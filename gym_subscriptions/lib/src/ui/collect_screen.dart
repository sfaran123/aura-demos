import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'help.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import '../state/gym_store.dart';
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
    final upcoming = SyncScope.maybeOf(context) == null ? const <Charge>[] : store.upcomingManual;
    final old = store.oldDebts;
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
        // A member with several failed months is one row that opens the months.
        for (final g in _byCustomer(list))
          if (g.length == 1) ChargeCard(charge: g.single) else _CustomerDebts(charges: g),
        // Signed in: every member in manual collection is listed, also those whose
        // next payment is still ahead, with its date.
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionLabel(t('התשלומים הבאים בגבייה ידנית ({0})', [upcoming.length])),
          for (final c in upcoming) ChargeCard(charge: c),
        ],
        // Failed charges from before the window, or of memberships that are no
        // longer active: folded, and not part of the open debt above.
        if (old.isNotEmpty) ...[
          const SizedBox(height: 8),
          Panel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: const Key('oldDebts'),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(t('חובות ישנים · {0} לקוחות · {1}', [
                _byCustomer(old).length,
                money(old.fold(0.0, (a, c) => a + c.amount)),
              ])),
              subtitle: Text(
                  t('חיובים שנכשלו לפני יותר מ-{0} חודשים, או של מנוי שכבר לא פעיל. לא נספרים בחוב הפתוח.',
                      [GymStore.debtWindowMonths]),
                  style: const TextStyle(fontSize: 12, color: Aura.muted, height: 1.4)),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              children: [for (final g in _byCustomer(old)) _CustomerDebts(charges: g)],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Note(t(t(
            'מנוי חודשי בגבייה ידנית (מזומן, שיק או העברה) מופיע כאן כל חודש. לחיצה על "התקבל" מפיקה קבלה ופותחת את החודש הבא. חיוב באשראי שנכשל מופיע כאן אחרי הניסיון הראשון.'))),
      ]),
    );
  }
}

/// The charges in rows: the failed charges of one member together (at the place
/// of the first), every other charge on its own.
List<List<Charge>> _byCustomer(List<Charge> list) {
  final groups = <String, List<Charge>>{};
  final rows = <List<Charge>>[];
  for (final c in list) {
    if (c.status != ChargeStatus.failed) {
      rows.add([c]);
    } else if (groups[c.customerId] case final g?) {
      g.add(c);
    } else {
      rows.add(groups[c.customerId] = [c]);
    }
  }
  return rows;
}

/// One member's failed months: the number of months and the total; opens the months.
class _CustomerDebts extends StatelessWidget {
  const _CustomerDebts({required this.charges});
  final List<Charge> charges;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cust = store.customer(charges.first.customerId);
    final months = [...charges]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final total = charges.fold(0.0, (a, c) => a + c.amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: Key('debts-${charges.first.customerId}'),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Avatar(cust?.name ?? '', size: 36),
          title: Text(cust?.name ?? t('לקוח'), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              charges.length == 1
                  ? '${t('חיוב חודש {0}', [months.first.monthLabel])} · ${cust?.phone ?? ''}'
                  : '${t('{0} חודשים שנכשלו', [
                          charges.length
                        ])} · ${months.first.monthLabel} – ${months.last.monthLabel}'
                      ' · ${cust?.phone ?? ''}',
              style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
          trailing: Text(money(total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          children: [for (final c in months) ChargeCard(charge: c)],
        ),
      ),
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
                    '${plan.name} · ${invoice != null ? t('חשבונית {0}', [
                            invoice
                          ]) : c.manual ? t('גבייה ידנית') : t('אשראי')}'
                    ' · ${cust.phone}',
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                // The dates: which month, and when it failed or is due.
                Text(
                    c.status == ChargeStatus.failed
                        ? [
                            t('חיוב חודש {0}', [c.monthLabel]),
                            t('נכשל ב-{0}', [fmtDate(c.dueDate)]),
                            if (c.tries.length > 1) t('ניסיון אחרון: {0}', [fmtDate(c.tries.last.$1)]),
                          ].join(' · ')
                        : t('מועד תשלום: {0}', [fmtDate(c.dueDate)]),
                    key: Key('dates-${c.id}'),
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            // A failed month: the pill opens the list of tries.
            if (c.status == ChargeStatus.failed && c.tries.isNotEmpty)
              InkWell(
                key: Key('tries-${c.id}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showTries(context, c, cust.name),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Pill(status, tone: tone)),
                  const Icon(Icons.chevron_left, size: 18, color: Aura.muted),
                ]),
              )
            else
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

  /// The tries of a failed month: when each one was, and what the card company answered.
  static Future<void> _showTries(BuildContext context, Charge c, String name) {
    String two(int n) => n.toString().padLeft(2, '0');
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('ניסיונות חיוב'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            const SizedBox(height: 2),
            Text(
                '$name · ${t('חיוב חודש {0}', [c.monthLabel])} · ${money(c.amount)} · ${t('חיוב נכשל · {0} ניסיונות', [
                      c.attempts
                    ])}',
                style: const TextStyle(color: Aura.muted)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final (i, x) in c.tries.indexed)
                  ListTile(
                    key: Key('try-${c.id}-$i'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Aura.warnBg,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    title: Text('${fmtDate(x.$1)} · ${two(x.$1.hour)}:${two(x.$1.minute)}'),
                    subtitle: x.$2.isEmpty ? null : Text(x.$2),
                  ),
              ]),
            ),
          ]),
        ),
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
