// Six months of demo history so the reports have something to show: members
// joining and leaving, monthly charges, counter sales, cheques and links.
// Deterministic (fixed seed), so screenshots and tests are stable.
// In the AURA app this file is not used: the data comes from the AURA API.

import 'dart:math';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import 'gym_store.dart';

const demoNames = [
  'אורי דהן', 'נטע שפירא', 'אחמד ג׳בארין', 'שירה אזולאי', 'יונתן פרץ', 'רנא אבו ריא', 'עדי ביטון', 'מיכל רוזן', //
  'עמית גבאי', 'הדר מלכה', 'סאמי חורי', 'טל אוחיון', 'ליאור כץ', 'נור עזאם', 'גיל ברגר', 'דנה וקנין', //
  'איתי אשכנזי', 'רותם סויסה', 'כרים נסאר', 'אביגיל חדד', 'עידו פרידמן', 'יאסמין חלבי', 'מתן אלמוג', 'קרן בן דוד', //
  'ראמי סלים', 'אופיר לנדאו', 'שני עמר', 'בשאר זועבי', 'מאור טייב', 'ליה שטרן', 'פאדי עבאס', 'נועם הרשקו', //
  'אלה גרינברג', 'יוסף קעדאן', 'רוני מימון', 'טליה בן עמי', 'מוחמד מסארווה', 'ענבל קורן', 'אסף יוסף', 'הילה נחום', //
  'סלים דיאב', 'אור לוין', 'מאיה בוזגלו', 'עלי מוסא', 'שחר אדלר', 'רעות חזן', 'ג׳ורג׳ חדאד', 'ספיר אליאס', //
];

void seedDemoHistory(GymStore s) {
  final r = Random(7);
  final td = s.today;
  final now = s.now;
  bool chance(double p) => r.nextDouble() < p;
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
  DateTime at(DateTime day, [int fromHour = 7, int toHour = 21]) =>
      day.add(Duration(hours: fromHour + r.nextInt(toHour - fromHour), minutes: r.nextInt(60)));

  final customers = <Customer>[];
  final newReceipts = <Receipt>[];
  var chargeNo = 0;

  Receipt rec(String customerId, String name, String desc, List<PaymentLine> lines, DateTime date, ReceiptKind kind) {
    final x = Receipt(
        number: 0, customerId: customerId, customerName: name, description: desc, lines: lines, date: date, kind: kind);
    newReceipts.add(x);
    return x;
  }

  PaymentLine cheques(double amount, int n, DateTime first) => PaymentLine(
        method: PayMethod.cheque,
        amount: amount,
        cheques: n,
        cheque: ChequeDetails(
          number: '${1000 + r.nextInt(8000)}',
          bank: pick(['10', '11', '12', '20', '31']),
          branch: '${100 + r.nextInt(800)}',
          account: '${100000 + r.nextInt(899999)}',
          firstDate: first,
        ),
      );

  PaymentLine transfer(double amount, DateTime date) => PaymentLine(
        method: PayMethod.bank,
        amount: amount,
        transfer:
            TransferDetails(reference: '${4000000 + r.nextInt(5000000)}', bank: pick(['10', '12', '20']), date: date),
      );

  // Plan mix: id -> weight.
  const mix = {'p1': 34, 'p2': 18, 'p3': 14, 'p7': 5, 'p4': 11, 'p5': 7, 'p6': 11};
  String pickPlan() {
    var x = r.nextInt(mix.values.reduce((a, b) => a + b));
    for (final e in mix.entries) {
      if (x < e.value) return e.key;
      x -= e.value;
    }
    return 'p1';
  }

  for (var i = 0; i < demoNames.length; i++) {
    final hasCard = chance(0.7);
    final c = Customer(
      id: 'dc$i',
      name: t(demoNames[i]),
      phone: '05${pick([0, 2, 3, 4, 8])}-${1000000 + r.nextInt(8999999)}',
      savedCardLast4: hasCard ? '${1000 + r.nextInt(8999)}' : null,
      healthDeclared: true,
    );
    customers.add(c);

    final join = td.subtract(Duration(days: 4 + r.nextInt(182)));
    final p = s.plan(pickPlan())!;
    final subId = 'ds$i';
    final viaLink = hasCard && chance(0.25);

    if (p.isRecurring) {
      final manual = !hasCard || chance(0.15);
      final method = manual ? RecurringMethod.manual : RecurringMethod.savedCard;
      final prepaid = p.prepayLastMonth ? p.price : 0.0;
      final first = p.price + p.registrationFee + prepaid;
      rec(
          c.id,
          c.name,
          p.name,
          [
            hasCard
                ? PaymentLine(method: PayMethod.card, amount: first)
                : (chance(0.3) ? transfer(first, join) : PaymentLine(method: PayMethod.cash, amount: first))
          ],
          at(join),
          viaLink ? ReceiptKind.link : ReceiptKind.subscription);

      DateTime? cancelledAt, cancelEffective;
      if (chance(0.14) && td.difference(join).inDays > 35) {
        cancelledAt = join.add(Duration(days: 30 + r.nextInt(td.difference(join).inDays - 30)));
        cancelEffective = cancelledAt.add(Duration(days: p.cancelNoticeDays));
      }
      final sub = Subscription(
        id: subId,
        customerId: c.id,
        planId: p.id,
        start: join,
        joinedAt: join,
        monthlyAmount: p.price,
        recurringMethod: method,
        prepaidAmount: prepaid,
        cancelledAt: cancelledAt,
        cancelEffective: cancelEffective,
      );

      // Monthly charges from the second month on.
      var due = addMonths(join, 1);
      while (!due.isAfter(td) && (cancelEffective == null || due.isBefore(cancelEffective))) {
        final isLast = addMonths(due, 1).isAfter(td);
        final ch = Charge(
            id: 'dch${chargeNo++}',
            subscriptionId: subId,
            customerId: c.id,
            dueDate: due,
            amount: p.price,
            manual: manual);
        if (isLast && manual && chance(0.4)) {
          ch.reminders = r.nextInt(3);
        } else if (isLast && !manual && chance(0.08)) {
          ch.status = ChargeStatus.failed;
          ch.attempts = 1 + r.nextInt(3);
          sub.status = SubStatus.paymentFailed;
        } else {
          final paidAt = manual ? due.add(Duration(days: r.nextInt(4))) : due;
          final m = manual ? pick([PayMethod.cash, PayMethod.cash, PayMethod.cash, PayMethod.bank]) : PayMethod.card;
          ch
            ..status = ChargeStatus.paid
            ..paidWith = m
            ..paidAt = paidAt;
          final dt = paidAt.isAfter(td) ? now : at(paidAt);
          rec(
              c.id,
              c.name,
              '${p.name} · ${due.month}/${due.year}',
              [m == PayMethod.bank ? transfer(p.price, paidAt) : PaymentLine(method: m, amount: p.price)],
              dt,
              ReceiptKind.collection);
        }
        s.charges.add(ch);
        due = addMonths(due, 1);
      }
      if (cancelEffective != null && !cancelEffective.isAfter(td)) {
        sub.status = SubStatus.cancelled;
      } else {
        sub.nextCharge = due;
        s.charges.add(Charge(
            id: 'dch${chargeNo++}',
            subscriptionId: subId,
            customerId: c.id,
            dueDate: due,
            amount: p.price,
            manual: manual));
        if (sub.status == SubStatus.active && cancelEffective == null && chance(0.06)) {
          sub
            ..status = SubStatus.frozen
            ..frozenUntil = td.add(Duration(days: 5 + r.nextInt(20)))
            ..freezeDaysUsed = 7 + r.nextInt(14);
        }
      }
      s.subscriptions.add(sub);
    } else {
      // Term plans and punch cards are paid up front.
      final total = p.price + p.registrationFee;
      final line = switch (r.nextInt(3)) {
        0 when p.allowCheques => cheques(total, min(3, p.maxCheques), join),
        1 when hasCard => PaymentLine(method: PayMethod.card, amount: total, installments: min(3, p.maxInstallments)),
        _ => hasCard
            ? PaymentLine(method: PayMethod.card, amount: total)
            : PaymentLine(method: PayMethod.cash, amount: total),
      };
      rec(c.id, c.name, p.name, [line], at(join), viaLink ? ReceiptKind.link : ReceiptKind.subscription);
      final end = endDate(p, join);
      final sub = Subscription(
        id: subId,
        customerId: c.id,
        planId: p.id,
        start: join,
        joinedAt: join,
        end: end,
        entriesLeft: p.kind == PlanKind.punch ? r.nextInt(p.entries + 1) : null,
      );
      if ((end != null && end.isBefore(td)) || sub.entriesLeft == 0) sub.status = SubStatus.expired;
      s.subscriptions.add(sub);
    }
  }

  // Counter sales, every day for six months.
  final weights = {'water': 5, 'shake': 6, 'towel': 2, 'locker': 1, 'day': 2, 'pt': 1};
  final pool = [
    for (final e in weights.entries)
      for (var k = 0; k < e.value; k++) e.key
  ];
  for (var d = 182; d >= 0; d--) {
    final day = td.subtract(Duration(days: d));
    final n = 1 + r.nextInt(day.weekday == DateTime.saturday ? 2 : 5);
    for (var k = 0; k < n; k++) {
      final when = at(day);
      if (when.isAfter(now)) continue;
      final ids = {pick(pool), if (chance(0.25)) pick(pool)};
      final items = [for (final id in ids) s.items.firstWhere((x) => x.id == id)];
      final amount = items.fold(0.0, (a, x) => a + x.price);
      final buyer = chance(0.6) ? customers[r.nextInt(customers.length)] : null;
      rec(
          buyer?.id ?? '',
          buyer?.name ?? t('לקוח מזדמן'),
          items.map((x) => x.name).join(', '),
          [PaymentLine(method: chance(0.55) ? PayMethod.cash : PayMethod.card, amount: amount)],
          when,
          ReceiptKind.quickPay);
    }
  }

  // Sign-up and payment links of the last 45 days.
  for (var k = 0; k < 18; k++) {
    final created = now.subtract(Duration(days: 1 + r.nextInt(45), hours: r.nextInt(10)));
    final p = s.plan(pick(['p1', 'p2', 'p3', 'p7']))!;
    final l = SignupLink(
        id: 'dl$k',
        sentTo: customers[r.nextInt(customers.length)].name,
        createdAt: created,
        planId: p.id,
        amount: p.price);
    final roll = r.nextDouble();
    final stage = roll < 0.5
        ? LinkStage.paid
        : roll < 0.62
            ? LinkStage.failed
            : roll < 0.78
                ? LinkStage.opened
                : roll < 0.88
                    ? LinkStage.signed
                    : LinkStage.sent;
    if (stage != LinkStage.sent) l.advance(stage, created.add(Duration(minutes: 5 + r.nextInt(120))));
    s.links.add(l);
  }

  s.customers.insertAll(0, customers);
  s.receipts.addAll(newReceipts.map((x) => Receipt(
        number: 0,
        customerId: x.customerId!.isEmpty ? null : x.customerId,
        customerName: x.customerName,
        description: x.description,
        lines: x.lines,
        date: x.date,
        kind: x.kind,
      )));
}
