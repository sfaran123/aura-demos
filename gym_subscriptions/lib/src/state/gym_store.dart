// In-memory store with sample data. In the AURA app this is replaced by an
// implementation that calls the AURA API; screens only talk to GymStore.

import '../domain/checkout.dart';
import '../domain/models.dart';
import '../domain/notifier.dart';
import '../domain/settings.dart';

class GymStore extends SimpleNotifier {
  GymStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _seed();
  }

  final DateTime Function() _clock;
  DateTime get now => _clock();
  DateTime get today => dateOnly(now);

  final BusinessSettings settings = BusinessSettings();
  final List<SubscriptionPlan> plans = [];
  final List<Customer> customers = [];
  final List<Subscription> subscriptions = [];
  final List<Charge> charges = [];
  final List<Receipt> receipts = [];
  final List<SignupLink> links = [];
  int _receiptNo = 30187;
  int _id = 100;
  String _next(String p) => '$p${_id++}';

  final List<ShopItem> items = const [
    ShopItem('water', 'בקבוק מים', 8),
    ShopItem('shake', 'שייק חלבון', 22),
    ShopItem('pt', 'אימון אישי', 180),
    ShopItem('towel', 'מגבת', 30),
    ShopItem('locker', 'לוקר חודשי', 40),
    ShopItem('day', 'כניסה חד-פעמית', 60),
  ];

  void touch() => notifyListeners();

  // ---------- lookups ----------
  SubscriptionPlan? plan(String id) => plans.where((p) => p.id == id).firstOrNull;
  Customer? customer(String id) => customers.where((c) => c.id == id).firstOrNull;
  List<SubscriptionPlan> get activePlans => plans.where((p) => p.active).toList();

  Subscription? currentSubscription(String customerId) {
    final list = subscriptions
        .where((s) => s.customerId == customerId && s.status != SubStatus.cancelled && s.status != SubStatus.expired)
        .toList();
    return list.isEmpty ? null : list.last;
  }

  List<Customer> searchCustomers(String q) {
    final t = q.trim();
    if (t.isEmpty) return customers.reversed.toList();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return customers
        .where(
            (c) => c.name.contains(t) || (digits.isNotEmpty && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
        .toList();
  }

  /// Open manual charges and failed automatic charges, oldest first.
  List<Charge> get toCollect {
    final l = charges
        .where((c) => c.isOpen() && (c.manual || c.status == ChargeStatus.failed))
        .where((c) => !c.dueDate.isAfter(today.add(Duration(days: settings.manualReminderDaysBefore))))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return l;
  }

  double get openDebt => round2(toCollect.where((c) => !c.dueDate.isAfter(today)).fold(0.0, (a, c) => a + c.amount));

  int get activeCount => subscriptions.where((s) => s.status == SubStatus.active).length;

  double get todayRevenue =>
      round2(receipts.where((r) => dateOnly(r.date) == today).fold(0.0, (a, r) => a + r.collectedNow));

  List<Subscription> get expiringSoon => subscriptions
      .where((s) =>
          s.status == SubStatus.active &&
          s.end != null &&
          !s.end!.isBefore(today) &&
          s.end!.difference(today).inDays <= settings.renewalReminderDaysBefore)
      .toList();

  /// Entry is blocked when a charge is overdue past the grace period.
  bool entryBlocked(String customerId) {
    if (!settings.blockEntryWhenOverdue) return false;
    return charges.any((c) => c.customerId == customerId && c.isOpen() && c.daysOverdue(today) > settings.graceDays);
  }

  // ---------- actions ----------
  Customer addCustomer(String name, String phone, {String? idNumber}) {
    final c = Customer(id: _next('c'), name: name.trim(), phone: formatPhone(phone), idNumber: idNumber);
    customers.add(c);
    notifyListeners();
    return c;
  }

  void savePlan(SubscriptionPlan p) {
    final i = plans.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      plans[i] = p;
    } else {
      plans.add(p.copy(id: _next('p')));
    }
    notifyListeners();
  }

  Receipt _receipt(String name, String desc, List<PaymentLine> lines) {
    final r = Receipt(
        number: ++_receiptNo,
        customerName: name,
        description: desc,
        lines: lines
            .map((l) => PaymentLine(
                method: l.method,
                amount: l.amount,
                cardSource: l.cardSource,
                installments: l.installments,
                cheques: l.cheques))
            .toList(),
        date: now);
    receipts.add(r);
    return r;
  }

  /// Opens a subscription and issues one receipt for all payment lines.
  ({Subscription sub, Receipt receipt}) openSubscription({
    required Customer customer,
    required SubscriptionPlan plan,
    required StartOption start,
    required int discountPct,
    required bool waiveRegistration,
    required List<PaymentLine> lines,
    RecurringMethod? recurring,
    String? newCardLast4,
  }) {
    final s0 = startDate(start, now);
    final pending = isPending(lines);
    if (newCardLast4 != null &&
        (lines.any((l) => l.method == PayMethod.card && l.cardSource == CardSource.newCard) ||
            recurring == RecurringMethod.newCard)) {
      customer.savedCardLast4 = newCardLast4;
    }
    final monthly = plan.isRecurring ? planPriceAfterDiscount(plan, discountPct) : null;
    final sub = Subscription(
      id: _next('s'),
      customerId: customer.id,
      planId: plan.id,
      start: s0,
      end: endDate(plan, s0),
      status: pending ? SubStatus.pendingPayment : SubStatus.active,
      discountPct: discountPct,
      registrationWaived: waiveRegistration,
      monthlyAmount: monthly,
      recurringMethod:
          plan.isRecurring ? (recurring == RecurringMethod.newCard ? RecurringMethod.savedCard : recurring) : null,
      entriesLeft: plan.kind == PlanKind.punch ? plan.entries : null,
      nextCharge: plan.isRecurring ? addMonths(s0, 1) : null,
    );
    subscriptions.add(sub);
    if (plan.isRecurring) {
      charges.add(Charge(
        id: _next('ch'),
        subscriptionId: sub.id,
        customerId: customer.id,
        dueDate: addMonths(s0, 1),
        amount: monthly!,
        manual: recurring == RecurringMethod.manual,
      ));
    }
    final r = _receipt(customer.name, plan.name, lines);
    if (lines.any((l) => l.method == PayMethod.link)) {
      final linkPart = lines.where((l) => l.method == PayMethod.link).fold(0.0, (a, l) => a + l.amount);
      links.insert(
          0,
          SignupLink(
              id: _next('l'),
              sentTo: customer.name,
              createdAt: now,
              planId: plan.id,
              customerId: customer.id,
              amount: round2(linkPart)));
    }
    notifyListeners();
    return (sub: sub, receipt: r);
  }

  Receipt quickPay({Customer? customer, required String description, required List<PaymentLine> lines}) {
    final r = _receipt(customer?.name ?? 'לקוח מזדמן', description, lines);
    notifyListeners();
    return r;
  }

  /// Marks a manual (or failed) monthly charge as collected and schedules the next one.
  Receipt collect(Charge c, PayMethod method) {
    c.status = ChargeStatus.paid;
    c.paidWith = method;
    c.paidAt = now;
    final sub = subscriptions.firstWhere((s) => s.id == c.subscriptionId);
    final cust = customer(c.customerId)!;
    if (sub.status == SubStatus.paymentFailed || sub.status == SubStatus.pendingPayment) {
      sub.status = SubStatus.active;
    }
    final next = addMonths(c.dueDate, 1);
    sub.nextCharge = next;
    if (sub.cancelEffective == null || next.isBefore(sub.cancelEffective!)) {
      charges.add(Charge(
          id: _next('ch'),
          subscriptionId: sub.id,
          customerId: cust.id,
          dueDate: next,
          amount: c.amount,
          manual: c.manual));
    }
    final r = _receipt(cust.name, '${plan(sub.planId)?.name ?? 'מנוי'} · חודש ${c.dueDate.month}/${c.dueDate.year}',
        [PaymentLine(method: method, amount: c.amount)]);
    notifyListeners();
    return r;
  }

  void remind(Charge c) {
    c.reminders++;
    notifyListeners();
  }

  /// Sends the customer a payment link for an open charge.
  SignupLink sendChargeLink(Charge c) {
    final cust = customer(c.customerId)!;
    final sub = subscriptions.firstWhere((s) => s.id == c.subscriptionId);
    final l = SignupLink(
        id: _next('l'), sentTo: cust.name, createdAt: now, planId: sub.planId, customerId: cust.id, amount: c.amount);
    links.insert(0, l);
    c.reminders++;
    notifyListeners();
    return l;
  }

  String? freeze(Subscription s, int days) {
    final p = plan(s.planId)!;
    if (days < settings.freezeMinDays) return 'הקפאה מינימלית היא ${settings.freezeMinDays} ימים';
    if (days > freezeDaysLeft(p, s)) return 'נשארו ${freezeDaysLeft(p, s)} ימי הקפאה השנה';
    s.status = SubStatus.frozen;
    s.frozenUntil = today.add(Duration(days: days));
    s.freezeDaysUsed += days;
    if (s.end != null) s.end = s.end!.add(Duration(days: days));
    if (s.nextCharge != null) s.nextCharge = s.nextCharge!.add(Duration(days: days));
    for (final c in charges.where((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(today))) {
      charges[charges.indexOf(c)] = Charge(
          id: c.id,
          subscriptionId: c.subscriptionId,
          customerId: c.customerId,
          dueDate: c.dueDate.add(Duration(days: days)),
          amount: c.amount,
          manual: c.manual);
    }
    notifyListeners();
    return null;
  }

  void unfreeze(Subscription s) {
    if (s.frozenUntil != null && s.frozenUntil!.isAfter(today)) {
      final unused = s.frozenUntil!.difference(today).inDays;
      s.freezeDaysUsed -= unused;
      if (s.end != null) s.end = s.end!.subtract(Duration(days: unused));
    }
    s.status = SubStatus.active;
    s.frozenUntil = null;
    notifyListeners();
  }

  DateTime cancel(Subscription s) {
    final p = plan(s.planId)!;
    final d = cancelEffectiveDate(p, s, today);
    s.cancelEffective = d;
    charges.removeWhere((c) => c.subscriptionId == s.id && c.isOpen() && c.dueDate.isAfter(d));
    notifyListeners();
    return d;
  }

  SignupLink sendSignupLink(String to) {
    final l = SignupLink(id: _next('l'), sentTo: to.trim().isEmpty ? 'לקוח חדש' : to.trim(), createdAt: now);
    links.insert(0, l);
    notifyListeners();
    return l;
  }

  /// Customer side of the link: registers, pays by card, subscription becomes active.
  Subscription completeSignup(SignupLink link,
      {required String name,
      required String phone,
      String? idNumber,
      required SubscriptionPlan plan,
      required String cardLast4,
      int installments = 1}) {
    Customer? c = link.customerId != null ? customer(link.customerId!) : null;
    c ??= customers
        .where((x) => x.phone.replaceAll(RegExp(r'\D'), '') == phone.replaceAll(RegExp(r'\D'), ''))
        .firstOrNull;
    c ??= addCustomer(name, phone, idNumber: idNumber);
    c.healthDeclared = true;
    c.savedCardLast4 = cardLast4;
    final existing = link.customerId != null
        ? subscriptions.where((s) => s.customerId == c!.id && s.status == SubStatus.pendingPayment).firstOrNull
        : null;
    final amount = link.amount ?? subscriptionDueNow(plan);
    link.status = LinkStatus.paid;
    if (existing != null) {
      existing.status = SubStatus.active;
      _receipt(c.name, '${plan.name} · יתרה בלינק', [
        PaymentLine(method: PayMethod.card, amount: amount, installments: installments, cardSource: CardSource.newCard)
      ]);
      notifyListeners();
      return existing;
    }
    final r = openSubscription(
      customer: c,
      plan: plan,
      start: StartOption.today,
      discountPct: 0,
      waiveRegistration: false,
      lines: [
        PaymentLine(method: PayMethod.card, amount: amount, installments: installments, cardSource: CardSource.newCard)
      ],
      recurring: plan.isRecurring ? RecurringMethod.savedCard : null,
      newCardLast4: cardLast4,
    );
    return r.sub;
  }

  // ---------- sample data ----------
  void _seed() {
    plans.addAll([
      SubscriptionPlan(
          id: 'p1',
          name: 'חודשי ללא הגבלה',
          kind: PlanKind.recurring,
          price: 199,
          registrationFee: 100,
          freezeDaysPerYear: 30,
          badge: 'הכי נמכר'),
      SubscriptionPlan(
          id: 'p2',
          name: 'חודשי בהתחייבות לשנה',
          kind: PlanKind.recurring,
          price: 169,
          commitMonths: 12,
          freezeDaysPerYear: 30),
      SubscriptionPlan(
          id: 'p3',
          name: 'פעמיים בשבוע',
          kind: PlanKind.recurring,
          price: 149,
          registrationFee: 100,
          weeklyLimit: 2,
          freezeDaysPerYear: 14),
      SubscriptionPlan(
          id: 'p4',
          name: '3 חודשים',
          kind: PlanKind.term,
          price: 540,
          months: 3,
          registrationFee: 100,
          freezeDaysPerYear: 14,
          maxInstallments: 3,
          maxCheques: 3,
          allowCheques: true),
      SubscriptionPlan(
          id: 'p5',
          name: 'שנתי',
          kind: PlanKind.term,
          price: 1790,
          months: 12,
          freezeDaysPerYear: 60,
          maxInstallments: 12,
          maxCheques: 12,
          allowCheques: true,
          autoRenew: true),
      SubscriptionPlan(
          id: 'p6',
          name: 'כרטיסייה 10 כניסות',
          kind: PlanKind.punch,
          price: 350,
          entries: 10,
          validMonths: 3,
          maxInstallments: 2),
    ]);
    final t = today;
    Customer c(String id, String n, String ph, [String? card]) {
      final x = Customer(id: id, name: n, phone: ph, savedCardLast4: card, healthDeclared: true);
      customers.add(x);
      return x;
    }

    c('c1', 'נועה לוי', '052-7781024', '4580');
    c('c2', 'מוחמד חסן', '054-6120933');
    c('c3', 'דני כהן', '050-3349182', '1123');
    c('c4', 'רים ח׳ורי', '058-4410276');
    c('c5', 'אלון ברק', '052-9917345');
    c('c6', 'סמאח עודה', '053-2288104');

    subscriptions.addAll([
      Subscription(id: 's1', customerId: 'c1', planId: 'p5', start: addMonths(t, -8), end: addMonths(t, 4)),
      Subscription(
          id: 's2',
          customerId: 'c3',
          planId: 'p1',
          start: addMonths(t, -3),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          nextCharge: t.add(const Duration(days: 9))),
      Subscription(
          id: 's3',
          customerId: 'c5',
          planId: 'p3',
          start: addMonths(t, -2),
          monthlyAmount: 149,
          recurringMethod: RecurringMethod.manual,
          nextCharge: t.subtract(const Duration(days: 3))),
      Subscription(
          id: 's4',
          customerId: 'c6',
          planId: 'p1',
          start: addMonths(t, -5),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          status: SubStatus.paymentFailed,
          nextCharge: t.subtract(const Duration(days: 9))),
      Subscription(
          id: 's5', customerId: 'c2', planId: 'p4', start: addMonths(t, -3), end: t.add(const Duration(days: 6))),
    ]);
    customers.firstWhere((x) => x.id == 'c6').savedCardLast4 = '7702';
    charges.addAll([
      Charge(
          id: 'ch1',
          subscriptionId: 's3',
          customerId: 'c5',
          dueDate: t.subtract(const Duration(days: 3)),
          amount: 149,
          manual: true,
          reminders: 1),
      Charge(
          id: 'ch2',
          subscriptionId: 's4',
          customerId: 'c6',
          dueDate: t.subtract(const Duration(days: 9)),
          amount: 199,
          manual: false,
          status: ChargeStatus.failed,
          attempts: 2),
      Charge(
          id: 'ch3',
          subscriptionId: 's2',
          customerId: 'c3',
          dueDate: t.add(const Duration(days: 9)),
          amount: 199,
          manual: false),
    ]);
    links.add(SignupLink(id: 'l1', sentTo: 'יוסי אברהם', createdAt: now.subtract(const Duration(hours: 5))));
    receipts.addAll([
      Receipt(
          number: 30180,
          customerName: 'שירן מזרחי',
          description: 'שנתי',
          lines: [PaymentLine(method: PayMethod.card, amount: 1790, installments: 6)],
          date: now.subtract(const Duration(hours: 3))),
      Receipt(
          number: 30181,
          customerName: 'לקוח מזדמן',
          description: 'כניסה חד-פעמית',
          lines: [PaymentLine(method: PayMethod.cash, amount: 60)],
          date: now.subtract(const Duration(hours: 1))),
    ]);
  }
}
