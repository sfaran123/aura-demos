import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/help.dart';
import 'help.dart';
import 'receipt_view.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'checkin_screen.dart';
import 'checkout/checkout_screens.dart';
import 'member_card.dart';
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

enum _Filter { all, active, pending, debt, failed, frozen, ending, cancelling, ended }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => t('הכל'),
        _Filter.active => t('פעילים'),
        _Filter.pending => t('ממתינים לתשלום'),
        _Filter.debt => t('חוב פתוח'),
        _Filter.failed => t('חיוב נכשל'),
        _Filter.frozen => t('מוקפאים'),
        _Filter.ending => t('מסתיימים'),
        _Filter.cancelling => t('בביטול'),
        _Filter.ended => t('הסתיימו / בוטלו'),
      };
}

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  String q = '';
  _Filter filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final ending = store.expiringSoon.map((s) => s.id).toSet();
    bool match(Subscription s, _Filter f) => switch (f) {
          _Filter.all => true,
          _Filter.active => s.status == SubStatus.active,
          _Filter.pending => s.status == SubStatus.pendingPayment,
          _Filter.debt => store.hasOverdue(s.id),
          _Filter.failed => s.status == SubStatus.paymentFailed,
          _Filter.frozen => s.status == SubStatus.frozen,
          _Filter.ending => ending.contains(s.id),
          _Filter.cancelling => s.cancelEffective != null && s.cancelEffective!.isAfter(store.today),
          _Filter.ended => s.status == SubStatus.cancelled || s.status == SubStatus.expired,
        };
    bool search(Subscription s) {
      if (q.isEmpty) return true;
      final c = store.customer(s.customerId)!;
      return c.name.contains(q) || c.phone.replaceAll('-', '').contains(q.replaceAll('-', ''));
    }

    final subs = store.subscriptions.where((s) => search(s) && match(s, filter)).toList()
      ..sort((a, b) => store.customer(a.customerId)!.name.compareTo(store.customer(b.customerId)!.name));

    return Scaffold(
      appBar: AppBar(title: Text(t('מנויים')), actions: [HelpButton.topic(HelpTopic.members)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newSubFab',
        backgroundColor: Aura.goldLight,
        foregroundColor: Aura.ink,
        onPressed: () => startCheckout(context, CheckoutFlow.subscription),
        icon: const Icon(Icons.add),
        label: Text(t('מנוי חדש')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        TextField(
          decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: t('חיפוש לפי שם או טלפון')),
          onChanged: (v) => setState(() => q = v.trim()),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in _Filter.values) ...[
              ChoiceChip(
                key: Key('memberFilter-${f.name}'),
                label: Text('${f.label} ${store.subscriptions.where((s) => search(s) && match(s, f)).length}'),
                selected: filter == f,
                labelStyle: TextStyle(color: filter == f ? Colors.white : Aura.ink),
                onSelected: (_) => setState(() => filter = f),
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        if (subs.isEmpty) Note(t('אין מנויים שמתאימים לסינון.')),
        for (final s in subs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MemberRow(sub: s),
          ),
      ]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = store.customer(sub.customerId)!;
    final p = store.plan(sub.planId)!;
    final blocked = store.entryBlocked(c.id);
    final owes = store.charges.any((x) => x.subscriptionId == sub.id && x.isOpen() && x.daysOverdue(store.today) > 0);
    final detail = switch (p.kind) {
      PlanKind.recurring => t('חיוב הבא {0}', [sub.nextCharge == null ? '—' : fmtDate(sub.nextCharge!)]),
      PlanKind.term => t('עד {0}', [fmtDate(sub.end!)]),
      PlanKind.punch => t('נשארו {0} כניסות', [store.entriesLeft(sub) ?? 0]),
    };
    return Panel(
      onTap: () => showMemberSheet(context, sub),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Avatar(c.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            Text('${p.name} · $detail', style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(sub.statusText, tone: toneFor(sub.status)),
              if (blocked)
                Pill(t('כניסה חסומה'), tone: PillTone.bad)
              else if (owes)
                Pill(t('חוב פתוח'), tone: PillTone.wait),
              if (sub.cancelEffective != null) Pill(t('מבוטל מ-{0}', [fmtDate(sub.cancelEffective!)])),
            ]),
          ]),
        ),
        const ForwardChevron(),
      ]),
    );
  }
}

/// Opens the phone's dialer or WhatsApp. Says so when the device cannot.
Future<void> _openExternal(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showDone(context, t('לא ניתן לפתוח במכשיר הזה'));
}

Future<void> showMemberSheet(BuildContext context, Subscription sub) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MemberSheet(sub: sub),
  );
}

/// Shows the membership as the store has it now: a server answer (card
/// update, failed months charged) replaces the membership object.
class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final current = store.subscriptions.where((x) => x.id == sub.id).firstOrNull ?? sub;
    return _MemberSheetBody(sub: current);
  }
}

class _MemberSheetBody extends StatelessWidget {
  const _MemberSheetBody({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cardBilled = sub.recurringMethod == RecurringMethod.savedCard;
    final running = sub.status != SubStatus.cancelled && sub.status != SubStatus.expired;
    final c = store.customer(sub.customerId)!;
    final p = store.plan(sub.planId)!;
    final rows = <(String, String)>[
      (t('טלפון'), c.phone),
      (t('מסלול'), p.name),
      (t('סטטוס'), sub.statusText),
      (t('התחלה'), fmtDate(sub.start)),
      if (sub.end != null) (t('סיום'), fmtDate(sub.end!)),
      if (p.isRecurring)
        (t('חיוב חודשי'), '${money(sub.monthlyAmount ?? p.price)} · ${sub.recurringMethod?.label ?? '—'}'),
      if (sub.nextCharge != null && p.isRecurring) (t('חיוב הבא'), fmtDate(sub.nextCharge!)),
      if (sub.entriesLeft != null) (t('כניסות שנותרו'), '${store.entriesLeft(sub)}'),
      if (p.weeklyLimit > 0) (t('כניסות השבוע'), t('{0} מתוך {1}', [store.visitsThisWeek(sub.id), p.weeklyLimit])),
      if (p.commitMonths > 0) (t('התחייבות עד'), fmtDate(addMonths(sub.start, p.commitMonths))),
      if (sub.frozenUntil != null) (t('מוקפא עד'), fmtDate(sub.frozenUntil!)),
      (t('ימי הקפאה שנותרו'), t('{0} מתוך {1}', [freezeDaysLeft(p, sub), p.freezeDaysPerYear])),
      if (sub.cancelEffective != null) (t('ביטול נכנס לתוקף'), fmtDate(sub.cancelEffective!)),
      (t('הצהרת בריאות'), c.healthDeclared ? t('נחתמה') : t('חסרה')),
      (t('כרטיס אשראי'), c.hasSavedCard ? '•••• ${c.savedCardLast4}' : t('לא שמור')),
      // The membership's own card (the web shows only "Saved" / "Unsaved").
      if (cardBilled) (t('כרטיס המנוי'), sub.hasCardToken ? t('שמור') : t('לא שמור')),
    ];
    final visits = store.visitsOf(sub.id);
    final canFreeze = sub.status == SubStatus.active && freezeDaysLeft(p, sub) >= store.settings.freezeMinDays;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(c.name, size: 44),
            const SizedBox(width: 12),
            Expanded(child: Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            Pill(sub.statusText, tone: toneFor(sub.status)),
          ]),
          const SizedBox(height: 12),
          if (store.entryBlocked(c.id))
            Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Note(t('הכניסה חסומה: יש תשלום באיחור מעבר לימי החסד.'), warn: true)),
          if (cardBilled && running && !sub.hasCardToken && SyncScope.maybeOf(context) != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Note(
                    t('המנוי מחויב בכרטיס אשראי, אבל אין בו כרטיס שמור: החיוב החודשי לא יתבצע עד שיעודכן כרטיס.'),
                    warn: true)),
          SummaryBox(rows: rows),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (running)
              FilledButton.icon(
                key: const Key('memberCheckin'),
                onPressed: () async {
                  final r = await recordVisit(context, c);
                  if (r == null || !context.mounted) return;
                  showDone(context, [t('הגעה נרשמה'), if (r.message.isNotEmpty) r.message].join(' · '));
                },
                icon: const Icon(Icons.how_to_reg, size: 18),
                label: Text(t('הגעה')),
              ),
            if (whatsappNumber(c.phone).isNotEmpty) ...[
              OutlinedButton.icon(
                key: const Key('callMember'),
                onPressed: () =>
                    _openExternal(context, Uri(scheme: 'tel', path: c.phone.replaceAll(RegExp(r'\D'), ''))),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text(t('חיוג')),
              ),
              OutlinedButton.icon(
                key: const Key('whatsappMember'),
                onPressed: () => _openExternal(context, Uri.parse('https://wa.me/${whatsappNumber(c.phone)}')),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
              ),
            ],
            if (canFreeze)
              OutlinedButton.icon(
                key: const Key('freeze'),
                onPressed: () => _freeze(context),
                icon: const Icon(Icons.ac_unit, size: 18),
                label: Text(t('הקפאה')),
              ),
            if (sub.status == SubStatus.frozen)
              OutlinedButton.icon(
                key: const Key('unfreeze'),
                onPressed: () async {
                  final sync = SyncScope.maybeOf(context);
                  if (sync != null) {
                    if (!await runOnServer(context, () => sync.unfreezeMembership(sub)) || !context.mounted) return;
                  } else {
                    store.unfreeze(sub);
                  }
                  Navigator.pop(context);
                  showDone(context, t('ההקפאה הסתיימה, המנוי פעיל'));
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(t('סיום הקפאה')),
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                startCheckout(context, CheckoutFlow.subscription, customer: c);
              },
              icon: const Icon(Icons.autorenew, size: 18),
              label: Text(t('חידוש / החלפת מסלול')),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                startCheckout(context, CheckoutFlow.quickPay, customer: c);
              },
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: Text(t('תשלום')),
            ),
            if (canSaveMemberCard(context, store))
              OutlinedButton.icon(
                key: const Key('memberCard'),
                onPressed: () => showMemberCardSheet(context, c),
                icon: const Icon(Icons.credit_card, size: 18),
                label: Text(c.hasSavedCard ? t('החלפת כרטיס') : t('הוספת כרטיס')),
              ),
            if (canUpdateMembershipCard(context, store, sub))
              OutlinedButton.icon(
                key: const Key('membershipCard'),
                onPressed: () => showMembershipCardSheet(context, sub),
                icon: const Icon(Icons.autorenew, size: 18),
                label: Text(t('עדכון כרטיס המנוי')),
              ),
            if (sub.cancelEffective == null && sub.status != SubStatus.cancelled)
              OutlinedButton.icon(
                key: const Key('cancelSub'),
                style: OutlinedButton.styleFrom(foregroundColor: Aura.warn),
                onPressed: () => _cancel(context),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(t('ביטול מנוי')),
              ),
          ]),
          if (visits.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionLabel(t('הגעות אחרונות ({0})', [visits.length])),
            for (final v in visits.take(10))
              VisitRow(
                visit: v,
                showName: false,
                onUndo: () async {
                  if (!await confirmUndoVisit(context, v) || !context.mounted) return;
                  if (await undoVisit(context, v) && context.mounted) showDone(context, t('ההגעה בוטלה'));
                },
              ),
          ],
          const SizedBox(height: 16),
          CustomerHistory(customerId: c.id),
        ]),
      ),
    );
  }

  Future<void> _freeze(BuildContext context) async {
    final store = StoreScope.read(context);
    final p = store.plan(sub.planId)!;
    final max = freezeDaysLeft(p, sub);
    final opts = [7, 14, 21, 30, 45, 60].where((d) => d >= store.settings.freezeMinDays && d <= max).toList();
    if (opts.isEmpty || opts.last != max) opts.add(max);
    final days = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('כמה ימים להקפיא?'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(t('נשארו {0} ימים השנה. ההקפאה מאריכה את המנוי ודוחה את החיוב הבא.', [max]),
                style: const TextStyle(color: Aura.muted, fontSize: 13)),
            if (store.settings.freezeFeePerMonth > 0)
              Text(t('דמי הקפאה: {0} לחודש', [money(store.settings.freezeFeePerMonth)]),
                  style: const TextStyle(color: Aura.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in opts)
                ActionChip(
                    key: Key('freeze-$d'), label: Text(t('{0} ימים', [d])), onPressed: () => Navigator.pop(ctx, d)),
            ]),
          ]),
        ),
      ),
    );
    if (days == null || !context.mounted) return;
    final sync = SyncScope.maybeOf(context);
    if (sync != null) {
      if (!await runOnServer(context, () => sync.freezeMembership(sub, days)) || !context.mounted) return;
      Navigator.pop(context);
      showDone(context, t('המנוי הוקפא ל-{0} ימים', [days]));
      return;
    }
    final err = store.freeze(sub, days);
    Navigator.pop(context);
    showDone(context, err ?? t('המנוי הוקפא ל-{0} ימים', [days]));
  }

  Future<void> _cancel(BuildContext context) async {
    final store = StoreScope.read(context);
    final p = store.plan(sub.planId)!;
    final when = cancelEffectiveDate(p, sub, store.today);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('ביטול מנוי')),
        content: Text([
          t('הביטול ייכנס לתוקף ב-{0}.', [fmtDate(when)]),
          if (p.commitMonths > 0)
            t('המסלול בהתחייבות ל-{0} חודשים, ולכן החיובים ממשיכים עד סוף ההתחייבות.', [p.commitMonths]),
          if (p.isRecurring) t('הודעה מראש: {0} יום.', [p.cancelNoticeDays]),
          t('אחרי התאריך הזה לא יהיו חיובים נוספים.'),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('חזרה'))),
          TextButton(
            key: const Key('confirmCancel'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Aura.warn),
            child: Text(t('ביטול המנוי')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final sync = SyncScope.maybeOf(context);
    if (sync != null) {
      // The server works out the date with the same rules; show the date it set.
      Subscription? saved;
      if (!await runOnServer(context, () async => saved = await sync.cancelMembership(sub)) || !context.mounted) return;
      Navigator.pop(context);
      showDone(context, t('המנוי יבוטל ב-{0}', [fmtDate(saved?.cancelEffective ?? when)]));
      return;
    }
    store.cancel(sub);
    Navigator.pop(context);
    showDone(context, t('המנוי יבוטל ב-{0}', [fmtDate(when)]));
  }
}
