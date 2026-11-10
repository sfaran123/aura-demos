import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/domain/checkout.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/domain/settings.dart';
import 'package:aura_gym/src/state/gym_store.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 10, 10, 0);
  GymStore newStore() => GymStore(clock: () => fixedNow);

  group('money and dates', () {
    test('money formats shekels with thousands separators', () {
      expect(money(1790), '1,790 ₪');
      expect(money(99.5), '99.50 ₪');
      expect(money(0), '0 ₪');
    });

    test('addMonths clamps to the last day of a short month', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });

    test('term end date is the day before the same date N months later', () {
      final p = SubscriptionPlan(id: 'x', name: 'x', kind: PlanKind.term, price: 540, months: 3);
      expect(endDate(p, DateTime(2026, 11, 10)), DateTime(2027, 2, 9));
    });

    test('recurring plans have no end date', () {
      final p = SubscriptionPlan(id: 'x', name: 'x', kind: PlanKind.recurring, price: 199);
      expect(endDate(p, DateTime(2026, 11, 10)), isNull);
    });

    test('start options', () {
      expect(startDate(StartOption.tomorrow, fixedNow), DateTime(2026, 11, 11));
      expect(startDate(StartOption.nextMonth, fixedNow), DateTime(2026, 12, 1));
      expect(startDate(StartOption.nextMonth, DateTime(2026, 12, 20)), DateTime(2027, 1, 1));
    });
  });

  group('pricing', () {
    final monthly = SubscriptionPlan(
        id: 'm', name: 'חודשי', kind: PlanKind.recurring, price: 199, registrationFee: 100);

    test('due now = first month + registration fee', () {
      expect(subscriptionDueNow(monthly), 299);
    });

    test('discount applies to the plan price, not the registration fee', () {
      expect(subscriptionDueNow(monthly, discountPct: 10), 279.1);
    });

    test('waiving the registration fee', () {
      expect(subscriptionDueNow(monthly, waiveRegistration: true), 199);
    });

    test('cart total adds items and a free amount', () {
      final store = newStore();
      expect(cartTotal({'shake': 2, 'towel': 1}, store.items, 15), 89);
    });
  });

  group('split payment validation', () {
    final term = SubscriptionPlan(
        id: 't', name: '3 חודשים', kind: PlanKind.term, price: 540, months: 3, maxInstallments: 3);
    final rec = SubscriptionPlan(id: 'r', name: 'חודשי', kind: PlanKind.recurring, price: 199);

    test('needs at least one line', () {
      expect(paymentProblem(due: 540, lines: [], newCardReady: false, plan: term), 'בחרו אמצעי תשלום');
    });

    test('reports what is left to assign', () {
      final p = paymentProblem(
          due: 540, lines: [PaymentLine(method: PayMethod.cash, amount: 200)], newCardReady: false, plan: term);
      expect(p, 'נותרו 340 ₪ לשיוך');
    });

    test('reports overpayment', () {
      final p = paymentProblem(
          due: 540, lines: [PaymentLine(method: PayMethod.cash, amount: 600)], newCardReady: false, plan: term);
      expect(p, 'הסכום גבוה ב-60 ₪ מהנדרש');
    });

    test('balanced split of cash and card passes', () {
      final p = paymentProblem(due: 540, lines: [
        PaymentLine(method: PayMethod.cash, amount: 200),
        PaymentLine(method: PayMethod.card, amount: 340, installments: 2),
      ], newCardReady: false, plan: term);
      expect(p, isNull);
    });

    test('a new card must be entered first', () {
      final p = paymentProblem(due: 540, lines: [
        PaymentLine(method: PayMethod.card, amount: 540, cardSource: CardSource.newCard),
      ], newCardReady: false, plan: term);
      expect(p, 'צריך להזין את הכרטיס החדש');
    });

    test('recurring plan needs a monthly method', () {
      final lines = [PaymentLine(method: PayMethod.cash, amount: 199)];
      expect(paymentProblem(due: 199, lines: lines, newCardReady: false, plan: rec), 'בחרו איך ייגבה התשלום החודשי');
      expect(
          paymentProblem(due: 199, lines: lines, newCardReady: false, plan: rec, recurring: RecurringMethod.manual),
          isNull);
    });

    test('new line takes the remaining amount', () {
      final l = newLine(PayMethod.card, 340, hasSavedCard: true);
      expect(l.amount, 340);
      expect(l.cardSource, CardSource.saved);
      expect(newLine(PayMethod.cash, -5, hasSavedCard: false).amount, 0);
    });

    test('deferred methods leave the subscription pending', () {
      expect(isPending([PaymentLine(method: PayMethod.cash, amount: 1)]), isFalse);
      expect(isPending([PaymentLine(method: PayMethod.link, amount: 1)]), isTrue);
    });
  });

  group('allowed methods', () {
    final s = BusinessSettings();
    final noCheque = SubscriptionPlan(id: 'a', name: 'a', kind: PlanKind.recurring, price: 1);

    test('plan rules restrict methods', () {
      expect(methodAllowed(PayMethod.cheque, s, plan: noCheque), isFalse);
      expect(methodAllowed(PayMethod.cash, s, plan: noCheque), isTrue);
    });

    test('walk-in cannot pay by link or cheque', () {
      expect(methodAllowed(PayMethod.link, s, walkIn: true), isFalse);
    });

    test('business can switch a method off', () {
      final s2 = BusinessSettings()..enabledMethods.remove(PayMethod.cash);
      expect(methodAllowed(PayMethod.cash, s2), isFalse);
    });

    test('recurring options follow settings', () {
      final s3 = BusinessSettings()..allowManualMonthly = false;
      expect(recurringOptions(hasSavedCard: false, s: s3), [RecurringMethod.newCard, RecurringMethod.standingOrder]);
      expect(recurringOptions(hasSavedCard: true, s: s).first, RecurringMethod.savedCard);
    });

    test('installments are capped by plan and business', () {
      final p = SubscriptionPlan(id: 'p', name: 'p', kind: PlanKind.term, price: 1, maxInstallments: 12);
      final s4 = BusinessSettings()..maxInstallments = 6;
      expect(maxInstallmentsFor(p, s4), 6);
      expect(maxInstallmentsFor(noCheque, s4), 1);
    });
  });

  group('validators', () {
    test('israeli id check digit', () {
      expect(isValidIsraeliId('123456782'), isTrue);
      expect(isValidIsraeliId('123456789'), isFalse);
      expect(isValidIsraeliId('12'), isFalse);
    });

    test('phone', () {
      expect(isValidPhone('052-1234567'), isTrue);
      expect(isValidPhone('0521234'), isFalse);
      expect(formatPhone('0521234567'), '052-1234567');
    });

    test('plan validation', () {
      final p = SubscriptionPlan(id: 'p', name: '', kind: PlanKind.term, price: 100);
      expect(p.validate(), 'צריך שם למסלול');
      p.name = 'x';
      p.months = 0;
      expect(p.validate(), 'צריך משך בחודשים');
    });
  });

  group('store', () {
    test('open a recurring subscription with cash now and manual monthly collection', () {
      final st = newStore();
      final c = st.addCustomer('שירן מזרחי', '0521112233');
      final plan = st.plan('p1')!;
      final res = st.openSubscription(
        customer: c,
        plan: plan,
        start: StartOption.today,
        discountPct: 0,
        waiveRegistration: false,
        lines: [PaymentLine(method: PayMethod.cash, amount: 299)],
        recurring: RecurringMethod.manual,
      );
      expect(res.sub.status, SubStatus.active);
      expect(res.receipt.total, 299);
      final ch = st.charges.where((x) => x.subscriptionId == res.sub.id).single;
      expect(ch.manual, isTrue);
      expect(ch.dueDate, DateTime(2026, 12, 10));
      expect(ch.amount, 199);
    });

    test('a link part leaves the subscription pending and creates a link', () {
      final st = newStore();
      final c = st.customer('c4')!;
      final res = st.openSubscription(
        customer: c,
        plan: st.plan('p4')!,
        start: StartOption.today,
        discountPct: 0,
        waiveRegistration: false,
        lines: [
          PaymentLine(method: PayMethod.cheque, amount: 340, cheques: 2),
          PaymentLine(method: PayMethod.link, amount: 300),
        ],
      );
      expect(res.sub.status, SubStatus.pendingPayment);
      expect(st.links.first.amount, 300);
      st.completeSignup(st.links.first,
          name: c.name, phone: c.phone, plan: st.plan('p4')!, cardLast4: '1111');
      expect(res.sub.status, SubStatus.active);
    });

    test('collecting a manual charge issues a receipt and schedules next month', () {
      final st = newStore();
      final ch = st.charges.firstWhere((x) => x.id == 'ch1');
      expect(st.toCollect.contains(ch), isTrue);
      final r = st.collect(ch, PayMethod.cash);
      expect(r.total, 149);
      expect(ch.status, ChargeStatus.paid);
      expect(st.toCollect.contains(ch), isFalse);
      final next = st.charges.last;
      expect(next.dueDate, addMonths(ch.dueDate, 1));
      expect(next.manual, isTrue);
    });

    test('failed card charge is in the collection list and blocks entry after grace', () {
      final st = newStore();
      expect(st.toCollect.any((c) => c.id == 'ch2'), isTrue);
      expect(st.entryBlocked('c6'), isTrue); // 9 days overdue > 7 grace days
      expect(st.entryBlocked('c5'), isFalse); // 3 days overdue
    });

    test('freeze extends the end date and respects the yearly allowance', () {
      final st = newStore();
      final s = st.subscriptions.firstWhere((x) => x.id == 's1');
      final end = s.end!;
      expect(st.freeze(s, 3), 'הקפאה מינימלית היא 7 ימים');
      expect(st.freeze(s, 61), 'נשארו 60 ימי הקפאה השנה');
      expect(st.freeze(s, 14), isNull);
      expect(s.status, SubStatus.frozen);
      expect(s.end, end.add(const Duration(days: 14)));
      st.unfreeze(s);
      expect(s.status, SubStatus.active);
      expect(s.end, end);
    });

    test('cancelling a committed plan waits for the commitment to end', () {
      final st = newStore();
      final plan = st.plan('p2')!;
      final sub = Subscription(id: 'z', customerId: 'c1', planId: 'p2', start: DateTime(2026, 9, 1));
      final d = cancelEffectiveDate(plan, sub, fixedNow);
      expect(d, DateTime(2027, 9, 1));
      final free = st.plan('p1')!;
      expect(cancelEffectiveDate(free, sub, fixedNow), DateTime(2026, 12, 10));
    });

    test('quick pay records revenue for today', () {
      final st = newStore();
      final before = st.todayRevenue;
      st.quickPay(description: 'שייק', lines: [PaymentLine(method: PayMethod.cash, amount: 22)]);
      expect(st.todayRevenue, before + 22);
    });

    test('saving a new plan adds it with a fresh id', () {
      final st = newStore();
      final n = st.plans.length;
      st.savePlan(SubscriptionPlan(id: '', name: 'סטודנטים', kind: PlanKind.recurring, price: 129));
      expect(st.plans.length, n + 1);
      expect(st.plans.last.id, isNot(''));
    });
  });
}
