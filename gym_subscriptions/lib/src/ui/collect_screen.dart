import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'help.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'checkout/checkout_screens.dart' show methodIcon, PaymentDetailsFields;
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

/// Monthly charges that need staff action: manual collections (cash, cheque,
/// transfer) and automatic card charges that failed.
class CollectScreen extends StatelessWidget {
  const CollectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = store.toCollect;
    final s = store.settings;
    // Signed in: the server's open debt, the same number as the home screen.
    final overdueSum = store.dashboard?.openDebt ?? store.openDebt;
    return Scaffold(
      appBar: AppBar(title: Text(t('לגבייה')), actions: [HelpButton.topic(HelpTopic.collect)]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Panel(
          color: overdueSum > 0 ? Aura.warnBg : Aura.okBg,
          borderColor: overdueSum > 0 ? Aura.warnBg : Aura.okBg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(overdueSum > 0 ? t('חוב פתוח עד היום') : t('אין חובות פתוחים'),
                style: TextStyle(color: overdueSum > 0 ? Aura.warn : Aura.ok, fontSize: 13)),
            Text(money(overdueSum),
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: overdueSum > 0 ? Aura.warn : Aura.ok)),
            const SizedBox(height: 4),
            Text(
              t('תזכורת {0} ימים לפני מועד התשלום · {1}', [
                s.manualReminderDaysBefore,
                s.blockEntryWhenOverdue ? t('חסימת כניסה אחרי {0} ימי איחור', [s.graceDays]) : t('בלי חסימת כניסה')
              ]),
              style: const TextStyle(fontSize: 12, color: Aura.muted, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Note(t('כל התשלומים החודשיים נגבו. מנויים בגבייה ידנית יופיעו כאן כמה ימים לפני מועד התשלום.'),
              icon: Icons.check_circle_outline),
        for (final c in list) ChargeCard(charge: c),
        const SizedBox(height: 8),
        Note(t(t(
            'מנוי חודשי בגבייה ידנית (מזומן, שיק או העברה) מופיע כאן כל חודש. לחיצה על "התקבל" מפיקה קבלה ופותחת את החודש הבא. חיוב באשראי שנכשל מופיע כאן אחרי הניסיון הראשון.'))),
      ]),
    );
  }
}

class ChargeCard extends StatelessWidget {
  const ChargeCard({super.key, required this.charge});
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
    // Signed in: payment links and reminders are not connected yet, so they are hidden.
    final signedIn = SyncScope.maybeOf(context) != null;
    // An unpaid membership invoice from the server: its document number.
    final invoice = c.id.startsWith('sale-')
        ? (store.dashboard?.debts.where((d) => d.id == c.id).firstOrNull?.reference ?? c.serverRef)
        : null;
    final (tone, status) = c.status == ChargeStatus.failed
        ? (PillTone.bad, t('חיוב נכשל · {0} ניסיונות', [c.attempts]))
        : late > 0
            ? (PillTone.bad, t('באיחור {0} ימים', [late]))
            : c.dueDate == store.today
                ? (PillTone.wait, t('היום'))
                : (PillTone.info, t('ב-{0}', [fmtDate(c.dueDate)]));
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
                Text(
                    '${plan.name} · ${invoice != null ? t('חשבונית {0}', [invoice]) : c.manual ? t('גבייה ידנית') : t('אשראי')}'
                    ' · ${cust.phone}',
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(status, tone: tone),
            if (c.reminders > 0) Pill(t('נשלחו {0} תזכורות', [c.reminders])),
            if (blocked) Pill(t('כניסה חסומה'), tone: PillTone.bad),
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
                label: Text(t('התקבל')),
              ),
            ),
            if (!signedIn) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () {
                    store.sendChargeLink(c);
                    showDone(context, t('לינק לתשלום {0} נשלח ל{1}', [money(c.amount), cust.name]));
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(t('לינק')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: t('תזכורת'),
                onPressed: () {
                  store.remind(c);
                  showDone(context, t('תזכורת נשלחה ל{0}', [cust.name]));
                },
                icon: const Icon(Icons.notifications_none),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Future<void> _collect(BuildContext context) async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    final methods = [PayMethod.cash, PayMethod.card, PayMethod.cheque, PayMethod.bank]
        .where((m) => store.settings.enabledMethods.contains(m))
        .toList();
    final m = await showModalBottomSheet<PayMethod>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('איך שולמו {0}?', [money(charge.amount)]),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final x in methods)
            ListTile(
              key: Key('collectWith-${x.name}'),
              leading: Icon(methodIcon(x)),
              // Signed in, a card is recorded as charged on the card terminal.
              title: Text(x == PayMethod.card
                  ? (sync != null ? t('אשראי (במסוף האשראי)') : t('אשראי (כרטיס שמור או חדש)'))
                  : x.label),
              onTap: () => Navigator.pop(ctx, x),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (m == null || !context.mounted) return;
    PaymentLine? line;
    if (m == PayMethod.cheque || m == PayMethod.bank) {
      line = await showPaymentDetailsSheet(context, PaymentLine(method: m, amount: charge.amount));
      if (line == null || !context.mounted) return;
    }
    if (sync != null) {
      // Signed in: recorded on the AURA server (document + payment), then everything reloads.
      var reference = '';
      final amount = charge.amount;
      final ok = await runOnServer(context, () async => reference = await sync.collectCharge(charge, m, line: line));
      if (!ok || !context.mounted) return;
      showDone(context, t('התקבל · {0} · {1} ב{2}', [reference, money(amount), m.label]));
      return;
    }
    final r = store.collect(charge, m, line: line);
    showDone(context, t('קבלה {0} הופקה · {1} ב{2}', [r.number, money(r.total), m.label]));
  }
}

/// Asks for cheque or transfer details before a monthly payment is marked paid.
Future<PaymentLine?> showPaymentDetailsSheet(BuildContext context, PaymentLine line) =>
    showModalBottomSheet<PaymentLine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('${line.method.label} · ${money(line.amount)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              PaymentDetailsFields(line: line, index: 0, onChanged: () => setState(() {})),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('detailsSave'),
                onPressed: line.detailsProblem == null ? () => Navigator.pop(ctx, line) : null,
                child: Text(t('אישור והפקת קבלה')),
              ),
            ]),
          ),
        ),
      ),
    );
