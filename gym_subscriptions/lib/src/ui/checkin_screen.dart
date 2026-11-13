import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/visits.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'checkout/checkout_screens.dart';
import 'members_screen.dart' show showMemberSheet;
import 'theme.dart';
import 'widgets.dart';

/// The collection tab's place in the bottom bar.
const collectTab = 3;

/// A recorded visit, with what the desk should see about it.
typedef CheckInResult = ({Visit visit, Customer customer, EntryLevel level, String message});

Color _color(EntryLevel l) => switch (l) {
      EntryLevel.ok => Aura.ok,
      EntryLevel.warn => Aura.gold,
      EntryLevel.blocked => Aura.warn,
    };

Color _background(EntryLevel l) => switch (l) {
      EntryLevel.ok => Aura.okBg,
      EntryLevel.warn => Aura.goldBg,
      EntryLevel.blocked => Aura.warnBg,
    };

IconData _icon(EntryLevel l) => switch (l) {
      EntryLevel.ok => Icons.check_circle,
      EntryLevel.warn => Icons.error,
      EntryLevel.blocked => Icons.block,
    };

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Records that [c] came in: at once when nothing stops it; a member the rules
/// stop needs the desk's decision, and a second visit on the same day is asked
/// about first. Null when nothing was recorded.
Future<CheckInResult?> recordVisit(BuildContext context, Customer c) async {
  final store = StoreScope.read(context);
  final sync = SyncScope.maybeOf(context);
  // Several memberships can take the visit: the desk says which one.
  final open = store.entryChecks(c).where((x) => x.level != EntryLevel.blocked).toList();
  var check = store.entryCheck(c);
  if (open.length > 1) {
    final picked = await _pickMembership(context, c, open);
    if (picked == null || !context.mounted) return null;
    check = picked;
  }
  final sub = check.subscription;
  var force = false;
  if (check.level == EntryLevel.blocked) {
    final choice = await _showBlocked(context, c, check);
    if (!context.mounted) return null;
    switch (choice) {
      case _Blocked.fix when check.fix == EntryFix.collect:
        Navigator.of(context).popUntil((r) => r.isFirst);
        ShellTabs.of(context).value = collectTab;
        return null;
      case _Blocked.fix:
        startCheckout(context, CheckoutFlow.subscription, customer: c);
        return null;
      case _Blocked.oneTime:
        startCheckout(context, CheckoutFlow.quickPay, customer: c);
        return null;
      case _Blocked.card:
        showMemberSheet(context, check.subscription!);
        return null;
      case _Blocked.letIn:
        force = true;
      case null:
        return null;
    }
  } else if (check.alreadyToday) {
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('{0} כבר נרשם היום', [c.name])),
        content: Text(t('לרשום הגעה נוספת? בכרטיסייה תרד כניסה נוספת.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('חזרה'))),
          TextButton(
              key: const Key('checkinAgain'), onPressed: () => Navigator.pop(ctx, true), child: Text(t('לרשום שוב'))),
        ],
      ),
    );
    if (again != true || !context.mounted) return null;
  }
  if (sub == null) return null;
  late Visit visit;
  if (sync != null) {
    if (!await runOnServer(context, () async => visit = await sync.checkIn(sub, force: force))) return null;
  } else {
    visit = store.checkIn(sub);
  }
  final balance = store.visitBalance(sub);
  return (
    visit: visit,
    customer: c,
    level: force ? EntryLevel.warn : check.level,
    message: [if (check.message.isNotEmpty) check.message, if (balance.isNotEmpty) balance].join(' · '),
  );
}

/// Takes back a visit recorded by mistake. False when the server refused.
Future<bool> undoVisit(BuildContext context, Visit v) async {
  final sync = SyncScope.maybeOf(context);
  if (sync != null) return runOnServer(context, () => sync.undoVisit(v));
  StoreScope.read(context).undoVisit(v);
  return true;
}

/// Asks before a visit from a list is taken back (a slip of the finger there
/// would lose a real visit). True when the desk confirms.
Future<bool> confirmUndoVisit(BuildContext context, Visit v) async {
  final name = StoreScope.read(context).customer(v.customerId)?.name ?? '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('לבטל את ההגעה?')),
      content: Text(t('{0} · {1} בשעה {2}. כניסה שירדה מכרטיסייה תחזור.', [name, fmtDate(v.at), _time(v.at)])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('חזרה'))),
        TextButton(
          key: const Key('confirmUndoVisit'),
          style: TextButton.styleFrom(foregroundColor: Aura.warn),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('ביטול ההגעה')),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<EntryCheck?> _pickMembership(BuildContext context, Customer c, List<EntryCheck> open) {
  final store = StoreScope.read(context);
  return showModalBottomSheet<EntryCheck>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('על איזה מנוי לרשום את ההגעה של {0}?', [c.name]),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final x in open)
            ListTile(
              key: Key('checkinPick-${x.subscription!.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(x.level), color: _color(x.level)),
              title: Text(store.plan(x.subscription!.planId)?.name ?? ''),
              subtitle: Text([
                if (x.message.isNotEmpty) x.message,
                if (store.visitBalance(x.subscription!).isNotEmpty) store.visitBalance(x.subscription!),
              ].join(' · ')),
              onTap: () => Navigator.pop(ctx, x),
            ),
        ]),
      ),
    ),
  );
}

enum _Blocked { fix, letIn, oneTime, card }

Future<_Blocked?> _showBlocked(BuildContext context, Customer c, EntryCheck check) => showModalBottomSheet<_Blocked>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.block, color: Aura.warn, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(check.message,
                      key: const Key('checkinBlockedReason'),
                      style: const TextStyle(color: Aura.warn, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Text(t('ההגעה לא נרשמה.'), style: const TextStyle(color: Aura.muted)),
            const SizedBox(height: 14),
            if (check.fix != EntryFix.none)
              FilledButton.icon(
                key: const Key('checkinFix'),
                onPressed: () => Navigator.pop(ctx, _Blocked.fix),
                icon: Icon(check.fix == EntryFix.collect ? Icons.receipt_long : Icons.autorenew, size: 18),
                label: Text(check.fix == EntryFix.collect ? t('לגבייה') : t('חידוש / מנוי חדש')),
              ),
            if (check.subscription != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('checkinLetIn'),
                onPressed: () => Navigator.pop(ctx, _Blocked.letIn),
                child: Text(t('להכניס בכל זאת ולרשום הגעה')),
              ),
              // Unfreezing, replacing a card, cancelling: all on the member card.
              TextButton(
                key: const Key('checkinOpenCard'),
                onPressed: () => Navigator.pop(ctx, _Blocked.card),
                child: Text(t('לכרטיס המנוי')),
              ),
            ] else ...[
              // No membership to record on: a one-time entry is sold at the desk.
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('checkinOneTime'),
                onPressed: () => Navigator.pop(ctx, _Blocked.oneTime),
                icon: const Icon(Icons.point_of_sale, size: 18),
                label: Text(t('כניסה חד-פעמית בתשלום')),
              ),
            ],
          ]),
        ),
      ),
    );

/// The desk's check-in: find the member, one touch records the visit.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});
  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _search = TextEditingController();
  String q = '';
  CheckInResult? last;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _record(Customer c) async {
    final r = await recordVisit(context, c);
    if (r == null || !mounted) return;
    _search.clear();
    setState(() {
      q = '';
      last = r;
    });
  }

  Future<void> _undo(Visit v, {bool ask = false}) async {
    if (ask && !await confirmUndoVisit(context, v)) return;
    if (!mounted) return;
    final store = StoreScope.read(context);
    final name = store.customer(v.customerId)?.name ?? '';
    if (!await undoVisit(context, v) || !mounted) return;
    setState(() {
      if (last?.visit.id == v.id) last = null;
    });
    showDone(context, t('ההגעה של {0} בוטלה', [name]));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = store.visitsToday;
    final found = q.isEmpty ? const <Customer>[] : store.searchCustomers(q).take(30).toList();
    // The last one stays on the screen while its visit exists (it can be taken back).
    final shown = last != null && store.visits.any((v) => v.id == last!.visit.id) ? last : null;
    return Scaffold(
      appBar: AppBar(title: Text(t('הגעה'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        TextField(
          key: const Key('checkinSearch'),
          controller: _search,
          style: const TextStyle(fontSize: 18),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: t('שם, או ספרות אחרונות של הטלפון'),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() => q = '');
                    }),
          ),
          onChanged: (v) => setState(() => q = v.trim()),
          onSubmitted: (_) {
            if (found.length == 1) _record(found.single);
          },
        ),
        const SizedBox(height: 12),
        if (shown != null) ...[
          Panel(
            key: const Key('checkinResult'),
            color: _background(shown.level),
            borderColor: _background(shown.level),
            child: Row(children: [
              Icon(_icon(shown.level), color: _color(shown.level), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shown.customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                      [
                        t('הגעה נרשמה ב-{0}', [_time(shown.visit.at)]),
                        if (shown.message.isNotEmpty) shown.message
                      ].join(' · '),
                      key: const Key('checkinResultText'),
                      style: TextStyle(color: _color(shown.level), fontWeight: FontWeight.w600, height: 1.35)),
                ]),
              ),
              TextButton(
                key: const Key('checkinUndo'),
                onPressed: () => _undo(shown.visit),
                child: Text(t('ביטול')),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (q.isNotEmpty) ...[
          if (found.isEmpty) Note(t('לא נמצא לקוח כזה.')),
          for (final c in found) _CustomerRow(customer: c, onTap: () => _record(c)),
        ] else ...[
          SectionLabel(t('הגיעו היום ({0})', [today.length])),
          if (today.isEmpty)
            Note(t('עדיין אף אחד לא נרשם היום. מחפשים לקוח ונוגעים בו כדי לרשום הגעה.'),
                icon: Icons.how_to_reg_outlined),
          for (final v in today) VisitRow(visit: v, onUndo: () => _undo(v, ask: true)),
          if (today.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('נרשמה הגעה בטעות? לוחצים על "ביטול" בשורה שלה, וכניסה שירדה מכרטיסייה חוזרת.'),
                  style: const TextStyle(fontSize: 12, color: Aura.muted, height: 1.4)),
            ),
        ],
      ]),
    );
  }
}

/// A member in the search results: who, what they have, and whether they may come in.
class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final check = store.entryCheck(customer);
    final sub = check.subscription;
    final plan = sub == null ? null : store.plan(sub.planId);
    final balance = sub == null ? '' : store.visitBalance(sub);
    final status = [
      if (check.message.isNotEmpty) check.message,
      if (check.level != EntryLevel.blocked && balance.isNotEmpty) balance,
      if (check.alreadyToday) t('כבר נרשם היום'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        key: Key('checkin-${customer.id}'),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          Avatar(customer.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              Text([if (plan != null) plan.name, customer.phone].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              if (status.isNotEmpty)
                Text(status,
                    key: Key('checkinStatus-${customer.id}'),
                    style: TextStyle(fontSize: 13, color: _color(check.level), fontWeight: FontWeight.w600)),
            ]),
          ),
          Icon(_icon(check.level), color: _color(check.level), size: 30),
        ]),
      ),
    );
  }
}

/// One recorded visit: who and when, and the way to take it back.
class VisitRow extends StatelessWidget {
  const VisitRow({super.key, required this.visit, required this.onUndo, this.showName = true});
  final Visit visit;
  final VoidCallback onUndo;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = store.customer(visit.customerId);
    final sub = store.subscriptions.where((s) => s.id == visit.subscriptionId).firstOrNull;
    final plan = sub == null ? null : store.plan(sub.planId);
    final balance = sub == null ? '' : store.visitBalance(sub);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        key: Key('visit-${visit.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          if (showName) ...[Avatar(c?.name ?? '', size: 34), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(showName ? (c?.name ?? t('לקוח')) : '${fmtDate(visit.at)} · ${_time(visit.at)}',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              if (showName)
                Text(
                    [
                      _time(visit.at),
                      if (plan != null) plan.name,
                      if (balance.isNotEmpty) balance,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ]),
          ),
          TextButton(key: Key('undoVisit-${visit.id}'), onPressed: onUndo, child: Text(t('ביטול'))),
        ]),
      ),
    );
  }
}
