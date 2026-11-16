import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'help.dart';

import '../domain/checkout.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import '../state/gym_store.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'checkout/checkout_screens.dart' show methodIcon, PaymentDetailsFields;
import 'member_card.dart' show canUpdateMembershipCard, showMembershipCardSheet;
import 'members_screen.dart' show showMemberSheet;
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
    final overdueSum = store.openDebt;
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
        key: Key('charge-${c.id}'),
        onTap: () => showChargeDetails(context, c),
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
                onPressed: () => collect(context),
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

  Future<void> collect(BuildContext context) async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    // The row may leave the list while the server answers: the message still shows.
    final messenger = ScaffoldMessenger.of(context);
    void done(String text, {bool ok = true}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          backgroundColor: ok ? Aura.ok : Aura.warn,
          content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
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
              title: Text(x == PayMethod.card ? (sync != null ? t('אשראי') : t('אשראי (כרטיס שמור או חדש)')) : x.label),
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
      var reference = '';
      final amount = charge.amount;
      // A card: the member's saved card is charged now (regular or installments),
      // or the card was taken on the terminal and is only recorded here.
      if (m == PayMethod.card) {
        final cust = store.customer(charge.customerId);
        final saved = (store.posSettings?.cardTokens ?? false) && (cust?.hasSavedCard ?? false);
        final payments = await _askCardHow(context, saved ? cust!.savedCardLast4 : null, amount);
        if (payments == null || !context.mounted) return;
        if (payments > 0) {
          final ok = await runOnServer(
              context, () async => reference = await sync.collectWithSavedCard(charge, payments: payments));
          if (ok) {
            done(payments > 1
                ? t('הכרטיס חויב · {0} · {1} ב-{2} תשלומים', [reference, money(amount), payments])
                : t('הכרטיס חויב · {0} · {1}', [reference, money(amount)]));
          }
          return;
        }
      }
      // Recorded on the AURA server (document + payment); the list updates at once.
      final ok = await runOnServer(context, () async => reference = await sync.collectCharge(charge, m, line: line));
      if (ok) done(t('התקבל · {0} · {1} ב{2}', [reference, money(amount), m.label]));
      return;
    }
    final r = store.collect(charge, m, line: line);
    showDone(context, t('קבלה {0} הופקה · {1} ב{2}', [r.number, money(r.total), m.label]));
  }
}

/// How a card pays a collection: 0 = taken on the terminal (recorded only),
/// 1 = the saved card in one payment, 2+ = the saved card in installments.
/// Null when closed. [last4] is null when the member has no saved card to charge.
Future<int?> _askCardHow(BuildContext context, String? last4, double amount) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('איך לחייב את הכרטיס? · {0}', [money(amount)]),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (last4 != null) ...[
              FilledButton.icon(
                key: const Key('cardSavedRegular'),
                onPressed: () => Navigator.pop(ctx, 1),
                icon: const Icon(Icons.credit_card, size: 18),
                label: Text(t('כרטיס שמור •••• {0} · תשלום רגיל', [last4])),
              ),
              const SizedBox(height: 12),
              Text(t('כרטיס שמור •••• {0} · בתשלומים', [last4]),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final n in const [2, 3, 4, 6, 10, 12])
                  ActionChip(
                    key: Key('cardSavedPayments-$n'),
                    label: Text('$n × ${money(amount / n)}'),
                    onPressed: () => Navigator.pop(ctx, n),
                  ),
              ]),
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Note(t('ללקוח אין כרטיס שמור שאפשר לחייב מכאן. אפשר לשמור כרטיס מכרטיס המנוי.')),
              ),
            OutlinedButton.icon(
              key: const Key('cardTerminal'),
              onPressed: () => Navigator.pop(ctx, 0),
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: Text(t('חויב במסוף הסליקה (רישום בלבד)')),
            ),
          ]),
        ),
      ),
    );

/// Everything about one payment to collect: whose it is, on which membership,
/// what else is open, and what can be done about it.
Future<void> showChargeDetails(BuildContext context, Charge c) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ChargeDetails(charge: c),
    );

class _ChargeDetails extends StatelessWidget {
  const _ChargeDetails({required this.charge});
  final Charge charge;

  Future<void> _open(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) showDone(context, t('לא ניתן לפתוח במכשיר הזה'));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = charge;
    final cust = store.customer(c.customerId);
    final sub = store.subscriptions.where((s) => s.id == c.subscriptionId).firstOrNull;
    final plan = sub == null ? null : store.plan(sub.planId);
    // Paid meanwhile (from this sheet): nothing left to show.
    final open = store.charges.any((x) => x.id == c.id && x.isOpen());
    final others = store.charges
        .where((x) => x.customerId == c.customerId && x.isOpen() && x.id != c.id && !x.dueDate.isAfter(store.today))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final owed = round2(others.fold(open ? c.amount : 0.0, (a, x) => a + x.amount));
    final cardBilled = sub?.recurringMethod == RecurringMethod.savedCard;
    final failed = c.status == ChargeStatus.failed;
    final rows = <(String, String)>[
      (
        t('התשלום הזה'),
        failed
            ? '${money(c.amount)} · ${t('חיוב חודש {0}', [c.monthLabel])} · ${t('חיוב נכשל · {0} ניסיונות', [
                    c.attempts
                  ])}'
            : '${money(c.amount)} · ${t('מועד תשלום: {0}', [fmtDate(c.dueDate)])}'
      ),
      if (others.isNotEmpty)
        (t('סה"כ פתוח ללקוח'), '${money(owed)} · ${t('{0} תשלומים', [others.length + (open ? 1 : 0)])}'),
      if (plan != null) (t('מסלול'), plan.name),
      if (sub != null) (t('סטטוס'), sub.statusText),
      if (sub != null) (t('התחלה'), fmtDate(sub.start)),
      if (sub?.end != null && sub!.end!.year < 2100) (t('סיום'), fmtDate(sub.end!)),
      if (sub != null && plan != null && plan.isRecurring)
        (t('חיוב חודשי'), '${money(sub.monthlyAmount ?? plan.price)} · ${sub.recurringMethod?.label ?? '—'}'),
      if (sub?.nextCharge != null) (t('חיוב הבא'), fmtDate(sub!.nextCharge!)),
      if (sub != null && store.entriesLeft(sub) != null) (t('כניסות שנותרו'), '${store.entriesLeft(sub)}'),
      if (cardBilled) (t('כרטיס המנוי'), sub!.hasCardToken ? t('שמור') : t('לא שמור')),
      if (cust != null) (t('כרטיס אשראי'), cust.hasSavedCard ? '•••• ${cust.savedCardLast4}' : t('לא שמור')),
      if (sub?.cancelEffective != null) (t('ביטול נכנס לתוקף'), fmtDate(sub!.cancelEffective!)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(cust?.name ?? '', size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cust?.name ?? t('לקוח'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Text(cust?.phone ?? '', style: const TextStyle(color: Aura.muted)),
              ]),
            ),
            Pill(open ? (failed ? t('חיוב נכשל') : t('לגבייה')) : t('שולם'), tone: open ? PillTone.bad : PillTone.ok),
          ]),
          const SizedBox(height: 12),
          // What needs doing, said first.
          if (open && failed && cardBilled && !(sub?.hasCardToken ?? false))
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Note(t('אין כרטיס שמור במנוי: החיוב החודשי ימשיך להיכשל עד שיעודכן כרטיס.'), warn: true)),
          if (open && failed && cardBilled && (sub?.hasCardToken ?? false))
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Note(t('הכרטיס של המנוי נדחה. אפשר לחייב אותו שוב, לעדכן כרטיס, או לגבות באמצעי אחר.'))),
          if (cust != null && store.entryBlocked(cust.id))
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Note(t('הכניסה חסומה: יש תשלום באיחור מעבר לימי החסד.'), warn: true)),
          SummaryBox(rows: rows),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (open)
              FilledButton.icon(
                key: const Key('detailsCollect'),
                onPressed: () async {
                  await ChargeCard(charge: c).collect(context);
                },
                icon: const Icon(Icons.check, size: 18),
                label: Text(t('גבייה · {0}', [money(c.amount)])),
              ),
            if (sub != null && canUpdateMembershipCard(context, store, sub))
              OutlinedButton.icon(
                key: const Key('detailsMembershipCard'),
                onPressed: () => showMembershipCardSheet(context, sub),
                icon: const Icon(Icons.credit_card, size: 18),
                label: Text(t('עדכון כרטיס המנוי')),
              ),
            if (cust != null && whatsappNumber(cust.phone).isNotEmpty) ...[
              OutlinedButton.icon(
                key: const Key('detailsCall'),
                onPressed: () => _open(context, Uri(scheme: 'tel', path: cust.phone.replaceAll(RegExp(r'\D'), ''))),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text(t('חיוג')),
              ),
              OutlinedButton.icon(
                key: const Key('detailsWhatsapp'),
                onPressed: () => _open(context, Uri.parse('https://wa.me/${whatsappNumber(cust.phone)}')),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
              ),
            ],
            if (sub != null)
              OutlinedButton.icon(
                key: const Key('detailsMember'),
                onPressed: () {
                  Navigator.pop(context);
                  showMemberSheet(context, sub);
                },
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(t('כרטיס המנוי המלא')),
              ),
          ]),
          if (c.tries.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionLabel(t('ניסיונות חיוב')),
            for (final x in c.tries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    '${fmtDate(x.$1)} · ${x.$1.hour.toString().padLeft(2, '0')}:${x.$1.minute.toString().padLeft(2, '0')}'
                    '${x.$2.isEmpty ? '' : ' · ${x.$2}'}',
                    style: const TextStyle(fontSize: 13, color: Aura.muted)),
              ),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionLabel(t('תשלומים פתוחים נוספים ({0})', [others.length])),
            for (final x in others) ChargeCard(charge: x),
          ],
        ]),
      ),
    );
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
