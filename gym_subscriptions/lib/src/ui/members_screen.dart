import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'checkout/checkout_screens.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Filter { all, active, pending, debt, failed, frozen, ending, cancelling, ended }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'הכל',
        _Filter.active => 'פעילים',
        _Filter.pending => 'ממתינים לתשלום',
        _Filter.debt => 'חוב פתוח',
        _Filter.failed => 'חיוב נכשל',
        _Filter.frozen => 'מוקפאים',
        _Filter.ending => 'מסתיימים',
        _Filter.cancelling => 'בביטול',
        _Filter.ended => 'הסתיימו / בוטלו',
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
      appBar: AppBar(title: const Text('מנויים')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newSubFab',
        backgroundColor: Aura.goldLight,
        foregroundColor: Aura.ink,
        onPressed: () => startCheckout(context, CheckoutFlow.subscription),
        icon: const Icon(Icons.add),
        label: const Text('מנוי חדש'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'חיפוש לפי שם או טלפון'),
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
        if (subs.isEmpty) const Note('אין מנויים שמתאימים לסינון.'),
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
      PlanKind.recurring => 'חיוב הבא ${sub.nextCharge == null ? '—' : fmtDate(sub.nextCharge!)}',
      PlanKind.term => 'עד ${fmtDate(sub.end!)}',
      PlanKind.punch => 'נשארו ${sub.entriesLeft ?? 0} כניסות',
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
              Pill(sub.status.label, tone: toneFor(sub.status)),
              if (blocked)
                const Pill('כניסה חסומה', tone: PillTone.bad)
              else if (owes)
                const Pill('חוב פתוח', tone: PillTone.wait),
              if (sub.cancelEffective != null) Pill('מבוטל מ-${fmtDate(sub.cancelEffective!)}'),
            ]),
          ]),
        ),
        const ForwardChevron(),
      ]),
    );
  }
}

Future<void> showMemberSheet(BuildContext context, Subscription sub) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MemberSheet(sub: sub),
  );
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = store.customer(sub.customerId)!;
    final p = store.plan(sub.planId)!;
    final rows = <(String, String)>[
      ('טלפון', c.phone),
      ('מסלול', p.name),
      ('סטטוס', sub.status.label),
      ('התחלה', fmtDate(sub.start)),
      if (sub.end != null) ('סיום', fmtDate(sub.end!)),
      if (p.isRecurring)
        ('חיוב חודשי', '${money(sub.monthlyAmount ?? p.price)} · ${sub.recurringMethod?.label ?? '—'}'),
      if (sub.nextCharge != null && p.isRecurring) ('חיוב הבא', fmtDate(sub.nextCharge!)),
      if (sub.entriesLeft != null) ('כניסות שנותרו', '${sub.entriesLeft}'),
      if (p.commitMonths > 0) ('התחייבות עד', fmtDate(addMonths(sub.start, p.commitMonths))),
      if (sub.frozenUntil != null) ('מוקפא עד', fmtDate(sub.frozenUntil!)),
      ('ימי הקפאה שנותרו', '${freezeDaysLeft(p, sub)} מתוך ${p.freezeDaysPerYear}'),
      if (sub.cancelEffective != null) ('ביטול נכנס לתוקף', fmtDate(sub.cancelEffective!)),
      ('הצהרת בריאות', c.healthDeclared ? 'נחתמה' : 'חסרה'),
    ];
    final canFreeze = sub.status == SubStatus.active && freezeDaysLeft(p, sub) >= store.settings.freezeMinDays;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(c.name, size: 44),
            const SizedBox(width: 12),
            Expanded(child: Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            Pill(sub.status.label, tone: toneFor(sub.status)),
          ]),
          const SizedBox(height: 12),
          if (store.entryBlocked(c.id))
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Note('הכניסה חסומה: יש תשלום באיחור מעבר לימי החסד.', warn: true)),
          SummaryBox(rows: rows),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (canFreeze)
              OutlinedButton.icon(
                key: const Key('freeze'),
                onPressed: () => _freeze(context),
                icon: const Icon(Icons.ac_unit, size: 18),
                label: const Text('הקפאה'),
              ),
            if (sub.status == SubStatus.frozen)
              OutlinedButton.icon(
                onPressed: () {
                  store.unfreeze(sub);
                  Navigator.pop(context);
                  showDone(context, 'ההקפאה הסתיימה, המנוי פעיל');
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('סיום הקפאה'),
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                startCheckout(context, CheckoutFlow.subscription, customer: c);
              },
              icon: const Icon(Icons.autorenew, size: 18),
              label: const Text('חידוש / החלפת מסלול'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                startCheckout(context, CheckoutFlow.quickPay, customer: c);
              },
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: const Text('תשלום'),
            ),
            if (sub.cancelEffective == null && sub.status != SubStatus.cancelled)
              OutlinedButton.icon(
                key: const Key('cancelSub'),
                style: OutlinedButton.styleFrom(foregroundColor: Aura.warn),
                onPressed: () => _cancel(context),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('ביטול מנוי'),
              ),
          ]),
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
            const Text('כמה ימים להקפיא?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('נשארו $max ימים השנה. ההקפאה מאריכה את המנוי ודוחה את החיוב הבא.',
                style: const TextStyle(color: Aura.muted, fontSize: 13)),
            if (store.settings.freezeFeePerMonth > 0)
              Text('דמי הקפאה: ${money(store.settings.freezeFeePerMonth)} לחודש',
                  style: const TextStyle(color: Aura.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in opts)
                ActionChip(key: Key('freeze-$d'), label: Text('$d ימים'), onPressed: () => Navigator.pop(ctx, d)),
            ]),
          ]),
        ),
      ),
    );
    if (days == null || !context.mounted) return;
    final err = store.freeze(sub, days);
    Navigator.pop(context);
    showDone(context, err ?? 'המנוי הוקפא ל-$days ימים');
  }

  Future<void> _cancel(BuildContext context) async {
    final store = StoreScope.read(context);
    final p = store.plan(sub.planId)!;
    final when = cancelEffectiveDate(p, sub, store.today);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ביטול מנוי'),
        content: Text([
          'הביטול ייכנס לתוקף ב-${fmtDate(when)}.',
          if (p.commitMonths > 0) 'המסלול בהתחייבות ל-${p.commitMonths} חודשים, ולכן החיובים ממשיכים עד סוף ההתחייבות.',
          if (p.isRecurring) 'הודעה מראש: ${p.cancelNoticeDays} יום.',
          'אחרי התאריך הזה לא יהיו חיובים נוספים.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('חזרה')),
          TextButton(
            key: const Key('confirmCancel'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Aura.warn),
            child: const Text('ביטול המנוי'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    store.cancel(sub);
    Navigator.pop(context);
    showDone(context, 'המנוי יבוטל ב-${fmtDate(when)}');
  }
}
