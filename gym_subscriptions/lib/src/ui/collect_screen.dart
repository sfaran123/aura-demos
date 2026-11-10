import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'checkout/checkout_screens.dart' show methodIcon;
import 'theme.dart';
import 'widgets.dart';

/// Monthly charges that need staff action: manual collections (cash, cheque,
/// transfer) and automatic card charges that failed.
class CollectScreen extends StatelessWidget {
  const CollectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = store.toCollect;
    final s = store.settings;
    final overdueSum = store.openDebt;
    return Scaffold(
      appBar: AppBar(title: const Text('לגבייה')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Panel(
          color: overdueSum > 0 ? Aura.warnBg : Aura.okBg,
          borderColor: overdueSum > 0 ? Aura.warnBg : Aura.okBg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(overdueSum > 0 ? 'חוב פתוח עד היום' : 'אין חובות פתוחים',
                style: TextStyle(color: overdueSum > 0 ? Aura.warn : Aura.ok, fontSize: 13)),
            Text(money(overdueSum),
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: overdueSum > 0 ? Aura.warn : Aura.ok)),
            const SizedBox(height: 4),
            Text(
              'תזכורת ${s.manualReminderDaysBefore} ימים לפני מועד התשלום · '
              '${s.blockEntryWhenOverdue ? 'חסימת כניסה אחרי ${s.graceDays} ימי איחור' : 'בלי חסימת כניסה'}',
              style: const TextStyle(fontSize: 12, color: Aura.muted, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Note('כל התשלומים החודשיים נגבו. מנויים בגבייה ידנית יופיעו כאן כמה ימים לפני מועד התשלום.',
              icon: Icons.check_circle_outline),
        for (final c in list) _ChargeCard(charge: c),
        const SizedBox(height: 8),
        const Note(
            'מנוי חודשי בגבייה ידנית (מזומן, שיק או העברה) מופיע כאן כל חודש. לחיצה על "התקבל" מפיקה קבלה ופותחת את החודש הבא. חיוב באשראי שנכשל מופיע כאן אחרי הניסיון הראשון.'),
      ]),
    );
  }
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard({required this.charge});
  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = charge;
    final cust = store.customer(c.customerId)!;
    final sub = store.subscriptions.firstWhere((s) => s.id == c.subscriptionId);
    final plan = store.plan(sub.planId)!;
    final late = c.daysOverdue(store.today);
    final blocked = late > store.settings.graceDays && store.settings.blockEntryWhenOverdue;
    final (tone, status) = c.status == ChargeStatus.failed
        ? (PillTone.bad, 'חיוב נכשל · ${c.attempts} ניסיונות')
        : late > 0
            ? (PillTone.bad, 'באיחור $late ימים')
            : c.dueDate == store.today
                ? (PillTone.wait, 'היום')
                : (PillTone.info, 'ב-${fmtDate(c.dueDate)}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(cust.name, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cust.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${plan.name} · ${c.manual ? 'גבייה ידנית' : 'אשראי'} · ${cust.phone}',
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(status, tone: tone),
            if (c.reminders > 0) Pill('נשלחו ${c.reminders} תזכורות'),
            if (blocked) const Pill('כניסה חסומה', tone: PillTone.bad),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: Key('collect-${c.id}'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => _collect(context),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('התקבל'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () {
                  store.sendChargeLink(c);
                  showDone(context, 'לינק לתשלום ${money(c.amount)} נשלח ל${cust.name}');
                },
                icon: const Icon(Icons.link, size: 18),
                label: const Text('לינק'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'תזכורת',
              onPressed: () {
                store.remind(c);
                showDone(context, 'תזכורת נשלחה ל${cust.name}');
              },
              icon: const Icon(Icons.notifications_none),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _collect(BuildContext context) async {
    final store = StoreScope.read(context);
    final methods = [PayMethod.cash, PayMethod.card, PayMethod.cheque, PayMethod.bank]
        .where((m) => store.settings.enabledMethods.contains(m))
        .toList();
    final m = await showModalBottomSheet<PayMethod>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('איך שולמו ${money(charge.amount)}?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final x in methods)
            ListTile(
              key: Key('collectWith-${x.name}'),
              leading: Icon(methodIcon(x)),
              title: Text(x == PayMethod.card ? 'אשראי (כרטיס שמור או חדש)' : x.label),
              onTap: () => Navigator.pop(ctx, x),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (m == null || !context.mounted) return;
    final r = store.collect(charge, m);
    showDone(context, 'קבלה ${r.number} הופקה · ${money(r.total)} ב${m.label}');
  }
}
