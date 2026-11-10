// In-memory store with sample data. In the AURA app this is replaced by an
// implementation that calls the AURA API; screens only talk to GymStore.

import 'dart:async';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/notifier.dart';
import '../domain/settings.dart';
import 'demo_data.dart';

class GymStore extends SimpleNotifier {
  GymStore({DateTime Function()? clock, bool seed = true}) : _clock = clock ?? DateTime.now {
    if (seed) _seed();
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

  List<ShopItem> items = [
    ShopItem('water', t('בקבוק מים'), 8),
    ShopItem('shake', t('שייק חלבון'), 22),
    ShopItem('pt', t('אימון אישי'), 180),
    ShopItem('towel', t('מגבת'), 30),
    ShopItem('locker', t('לוקר חודשי'), 40),
    ShopItem('day', t('כניסה חד-פעמית'), 60),
  ];

  void touch() => notifyListeners();

  /// Adds a product to the price list, or updates the one with the same id.
  void saveItem(ShopItem item) {
    final i = items.indexWhere((x) => x.id == item.id);
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(ShopItem(item.id.isEmpty ? _next('item') : item.id, item.name, item.price));
    }
    notifyListeners();
  }

  void removeItem(String id) {
    items.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  AppLang get language => L10n.lang;

  void setLanguage(AppLang l) {
    L10n.lang = l;
    for (final c in customers) {
      c.name = retranslate(c.name);
    }
    for (final p in plans) {
      p.name = retranslate(p.name);
      if (p.badge != null) p.badge = retranslate(p.badge!);
    }
    for (final l in links) {
      l.sentTo = retranslate(l.sentTo);
    }
    for (final r in receipts) {
      r.customerName = retranslate(r.customerName);
    }
    items = [for (final i in items) ShopItem(i.id, retranslate(i.name), i.price)];
    notifyListeners();
  }

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

  bool hasOverdue(String subscriptionId) =>
      charges.any((c) => c.subscriptionId == subscriptionId && c.isOpen() && c.daysOverdue(today) > 0);

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

  /// Saves a plan and returns the stored copy (new plans get an id).
  SubscriptionPlan savePlan(SubscriptionPlan p) {
    if (!p.isRecurring) p.prepayLastMonth = false;
    final i = plans.indexWhere((x) => x.id == p.id);
    late SubscriptionPlan saved;
    if (i >= 0) {
      plans[i] = saved = p;
    } else {
      plans.add(saved = p.copy(id: _next('p')));
    }
    notifyListeners();
    return saved;
  }

  Receipt _receipt(String name, String desc, List<PaymentLine> lines, ReceiptKind kind,
      {DateTime? at, String? customerId}) {
    final r = Receipt(
        number: ++_receiptNo,
        customerId: customerId,
        customerName: name,
        description: desc,
        kind: kind,
        lines: lines
            .map((l) => PaymentLine(
                method: l.method,
                amount: l.amount,
                cardSource: l.cardSource,
                installments: l.installments,
                cheques: l.cheques,
                cheque: l.cheque,
                transfer: l.transfer))
            .toList(),
        date: at ?? now);
    receipts.add(r);
    return r;
  }

  /// Schedules the monthly charge due on [due], unless the membership has
  /// ended by then. The last charge of a prepaid membership is already covered.
  void _schedule(Subscription sub, DateTime due, double amount, bool manual) {
    final end = sub.cancelEffective;
    if (end != null && !due.isBefore(end)) return;
    final covered = end != null && sub.prepaidAmount > 0 && !addMonths(due, 1).isBefore(end) && !_hasCovered(sub.id);
    charges.add(Charge(
      id: _next('ch'),
      subscriptionId: sub.id,
      customerId: sub.customerId,
      dueDate: due,
      amount: amount,
      manual: manual,
      status: covered ? ChargeStatus.covered : ChargeStatus.due,
    ));
    if (covered) sub.prepaidAmount = 0;
  }

  bool _hasCovered(String subId) => charges.any((c) => c.subscriptionId == subId && c.status == ChargeStatus.covered);

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
      prepaidAmount: plan.isRecurring && plan.prepayLastMonth ? monthly! : 0,
      joinedAt: now,
    );
    subscriptions.add(sub);
    if (plan.isRecurring) _schedule(sub, addMonths(s0, 1), monthly!, recurring == RecurringMethod.manual);
    final r = _receipt(customer.name, plan.name, lines, ReceiptKind.subscription, customerId: customer.id);
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
    final r =
        _receipt(customer?.name ?? t('לקוח מזדמן'), description, lines, ReceiptKind.quickPay, customerId: customer?.id);
    notifyListeners();
    return r;
  }

  /// Marks a manual (or failed) monthly charge as collected and schedules the next one.
  /// Marks a monthly charge as paid. [line] carries cheque or transfer details.
  Receipt collect(Charge c, PayMethod method, {PaymentLine? line}) {
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
    final hasLater = charges.any((x) => x.subscriptionId == sub.id && x.dueDate.isAfter(c.dueDate));
    if (!hasLater) _schedule(sub, next, c.amount, c.manual);
    final r = _receipt(cust.name, '${plan(sub.planId)?.name ?? t('מנוי')} · ${c.dueDate.month}/${c.dueDate.year}',
        [line ?? PaymentLine(method: method, amount: c.amount)], ReceiptKind.collection,
        customerId: cust.id);
    notifyListeners();
    return r;
  }

  /// Records that a receipt was sent. In the AURA app this calls the SMS /
  /// WhatsApp / email provider with a link to the receipt PDF.
  void sendReceipt(Receipt r, Channel channel, String to) {
    r.sent.add((channel.label, to, now));
    notifyListeners();
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
    if (days < settings.freezeMinDays) return t('הקפאה מינימלית היא {0} ימים', [settings.freezeMinDays]);
    if (days > freezeDaysLeft(p, s)) return t('נשארו {0} ימי הקפאה השנה', [freezeDaysLeft(p, s)]);
    s.status = SubStatus.frozen;
    s.frozenUntil = today.add(Duration(days: days));
    s.freezeDaysUsed += days;
    if (s.end != null) s.end = s.end!.add(Duration(days: days));
    if (s.nextCharge != null) s.nextCharge = s.nextCharge!.add(Duration(days: days));
    for (final c
        in charges.where((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(today)).toList()) {
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

  /// Schedules the cancellation. For a prepaid membership, the last month's
  /// charge is marked as already paid.
  DateTime cancel(Subscription s) {
    final p = plan(s.planId)!;
    var d = cancelEffectiveDate(p, s, today);
    if (s.prepaidAmount > 0) {
      // The month paid in advance is always the last month of the membership.
      final open = charges
          .where((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(today) && c.dueDate.isBefore(d))
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      if (open.isNotEmpty) {
        open.last.status = ChargeStatus.covered;
      } else {
        final nd = s.nextCharge ?? addMonths(s.start, 1);
        final end = addMonths(nd, 1);
        if (end.isAfter(d)) d = end;
        final existing = charges.where((c) => c.subscriptionId == s.id && c.dueDate == nd).firstOrNull;
        if (existing != null) {
          existing.status = ChargeStatus.covered;
        } else {
          charges.add(Charge(
              id: _next('ch'),
              subscriptionId: s.id,
              customerId: s.customerId,
              dueDate: nd,
              amount: s.monthlyAmount ?? p.price,
              manual: s.recurringMethod == RecurringMethod.manual,
              status: ChargeStatus.covered));
        }
      }
      s.prepaidAmount = 0;
    }
    s.cancelEffective = d;
    s.cancelledAt = now;
    charges.removeWhere((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(d));
    notifyListeners();
    return d;
  }

  // ---------- links ----------
  SignupLink sendSignupLink(String to) {
    final l = SignupLink(id: _next('l'), sentTo: to.trim().isEmpty ? t('לקוח חדש') : to.trim(), createdAt: now);
    links.insert(0, l);
    notifyListeners();
    return l;
  }

  void linkStage(SignupLink l, LinkStage s) {
    l.advance(s, now);
    notifyListeners();
  }

  final Map<String, Timer> _sims = {};

  /// Demo: plays the customer's side of a link, one step every [step], so the
  /// owner sees the stages change live. In production the stages come from the
  /// link page and the card processor's webhook.
  void simulateLink(SignupLink l, {Duration step = const Duration(seconds: 2)}) {
    _sims[l.id]?.cancel();
    _sims[l.id] = Timer.periodic(step, (timer) {
      final next = switch (l.stage) {
        LinkStage.sent => LinkStage.opened,
        LinkStage.opened => LinkStage.details,
        LinkStage.details => LinkStage.signed,
        LinkStage.signed || LinkStage.failed => LinkStage.paid,
        LinkStage.paid => null,
      };
      if (next == null) {
        timer.cancel();
        _sims.remove(l.id);
        return;
      }
      if (next == LinkStage.paid) {
        final plan = l.planId != null ? this.plan(l.planId!)! : activePlans.firstWhere((p) => p.onlineSignup);
        final c = l.customerId != null ? customer(l.customerId!)! : null;
        completeSignup(l,
            name: c?.name ?? (RegExp(r'\d').hasMatch(l.sentTo) ? t('לקוח מהלינק') : l.sentTo),
            phone: c?.phone ?? (isValidPhone(l.sentTo) ? l.sentTo : '050-0000000'),
            plan: plan,
            cardLast4: '4242');
        timer.cancel();
        _sims.remove(l.id);
      } else {
        linkStage(l, next);
      }
    });
  }

  bool isSimulating(SignupLink l) => _sims.containsKey(l.id);

  void stopSimulations() {
    for (final t in _sims.values) {
      t.cancel();
    }
    _sims.clear();
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
    final amount = link.amount ?? subscriptionDueNow(plan, prepayLastMonth: plan.isRecurring && plan.prepayLastMonth);
    link.customerId ??= c.id;
    link.planId ??= plan.id;
    link.advance(LinkStage.paid, now);
    final line =
        PaymentLine(method: PayMethod.card, amount: amount, installments: installments, cardSource: CardSource.newCard);
    if (existing != null) {
      existing.status = SubStatus.active;
      _receipt(c.name, t('{0} · לינק', [plan.name]), [line], ReceiptKind.link, customerId: c.id);
      notifyListeners();
      return existing;
    }
    final charge = link.customerId != null && link.amount != null
        ? charges.where((x) => x.customerId == c!.id && x.isOpen()).firstOrNull
        : null;
    if (charge != null) {
      collect(charge, PayMethod.card);
      return subscriptions.firstWhere((s) => s.id == charge.subscriptionId);
    }
    final r = openSubscription(
      customer: c,
      plan: plan,
      start: StartOption.today,
      discountPct: 0,
      waiveRegistration: false,
      lines: [line],
      recurring: plan.isRecurring ? RecurringMethod.savedCard : null,
      newCardLast4: cardLast4,
    );
    receipts.remove(r.receipt);
    receipts.add(Receipt(
        number: r.receipt.number,
        customerName: r.receipt.customerName,
        description: r.receipt.description,
        lines: r.receipt.lines,
        date: r.receipt.date,
        customerId: r.receipt.customerId,
        kind: ReceiptKind.link));
    return r.sub;
  }

  // ---------- sample data ----------
  void _seed() {
    plans.addAll([
      SubscriptionPlan(
          id: 'p1',
          name: t('חודשי ללא הגבלה'),
          kind: PlanKind.recurring,
          price: 199,
          registrationFee: 100,
          freezeDaysPerYear: 30,
          badge: t('הכי נמכר')),
      SubscriptionPlan(
          id: 'p2',
          name: t('חודשי בהתחייבות לשנה'),
          kind: PlanKind.recurring,
          price: 169,
          commitMonths: 12,
          freezeDaysPerYear: 30),
      SubscriptionPlan(
          id: 'p3',
          name: t('פעמיים בשבוע'),
          kind: PlanKind.recurring,
          price: 149,
          registrationFee: 100,
          weeklyLimit: 2,
          freezeDaysPerYear: 14),
      SubscriptionPlan(
          id: 'p7',
          name: t('חודשי + חודש אחרון מראש'),
          kind: PlanKind.recurring,
          price: 179,
          freezeDaysPerYear: 30,
          prepayLastMonth: true),
      SubscriptionPlan(
          id: 'p4',
          name: t('3 חודשים'),
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
          name: t('שנתי'),
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
          name: t('כרטיסייה 10 כניסות'),
          kind: PlanKind.punch,
          price: 350,
          entries: 10,
          validMonths: 3,
          maxInstallments: 2),
    ]);
    final td = today;
    Customer c(String id, String n, String ph, [String? card]) {
      final x = Customer(id: id, name: n, phone: ph, savedCardLast4: card, healthDeclared: true);
      customers.add(x);
      return x;
    }

    c('c7', t('יעל אורן'), '052-4417730', '9031');
    c('c8', t('חאלד מנסור'), '054-3302871');
    c('c9', t('מאיה גולן'), '050-7719264', '5512');
    c('c10', t('עומר שלו'), '052-6620043', '3381');
    c('c11', t('לינה סעד'), '058-2201937');
    c('c1', t('נועה לוי'), '052-7781024', '4580');
    c('c2', t('מוחמד חסן'), '054-6120933');
    c('c3', t('דני כהן'), '050-3349182', '1123');
    c('c4', t('רים ח׳ורי'), '058-4410276');
    c('c5', t('אלון ברק'), '052-9917345');
    c('c6', t('סמאח עודה'), '053-2288104', '7702');

    DateTime ago(int days) => td.subtract(Duration(days: days));
    subscriptions.addAll([
      Subscription(id: 's1', customerId: 'c1', planId: 'p5', start: addMonths(td, -8), end: addMonths(td, 4)),
      Subscription(
          id: 's2',
          customerId: 'c3',
          planId: 'p1',
          start: addMonths(td, -3),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          nextCharge: td.add(const Duration(days: 9))),
      Subscription(
          id: 's3',
          customerId: 'c5',
          planId: 'p3',
          start: addMonths(td, -2),
          monthlyAmount: 149,
          recurringMethod: RecurringMethod.manual,
          nextCharge: ago(3)),
      Subscription(
          id: 's4',
          customerId: 'c6',
          planId: 'p1',
          start: addMonths(td, -5),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          status: SubStatus.paymentFailed,
          nextCharge: ago(9)),
      Subscription(
          id: 's5', customerId: 'c2', planId: 'p4', start: addMonths(td, -3), end: td.add(const Duration(days: 6))),
      Subscription(
          id: 's6',
          customerId: 'c7',
          planId: 'p7',
          start: ago(18),
          joinedAt: ago(18),
          monthlyAmount: 179,
          recurringMethod: RecurringMethod.savedCard,
          prepaidAmount: 179,
          nextCharge: addMonths(ago(18), 1)),
      Subscription(
          id: 's7',
          customerId: 'c8',
          planId: 'p1',
          start: ago(25),
          joinedAt: ago(25),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.manual,
          nextCharge: addMonths(ago(25), 1)),
      Subscription(
          id: 's8',
          customerId: 'c9',
          planId: 'p2',
          start: addMonths(td, -4),
          monthlyAmount: 169,
          recurringMethod: RecurringMethod.savedCard,
          status: SubStatus.frozen,
          frozenUntil: td.add(const Duration(days: 12)),
          freezeDaysUsed: 21,
          nextCharge: td.add(const Duration(days: 15))),
      Subscription(
          id: 's9',
          customerId: 'c10',
          planId: 'p1',
          start: addMonths(td, -6),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          nextCharge: td.add(const Duration(days: 4)),
          cancelEffective: td.add(const Duration(days: 20)),
          cancelledAt: ago(10)),
      Subscription(
          id: 's10',
          customerId: 'c11',
          planId: 'p4',
          start: ago(12),
          joinedAt: ago(12),
          end: endDate(plan('p4')!, ago(12))),
    ]);
    charges.addAll([
      Charge(
          id: 'ch1', subscriptionId: 's3', customerId: 'c5', dueDate: ago(3), amount: 149, manual: true, reminders: 1),
      Charge(
          id: 'ch2',
          subscriptionId: 's4',
          customerId: 'c6',
          dueDate: ago(9),
          amount: 199,
          manual: false,
          status: ChargeStatus.failed,
          attempts: 2),
      Charge(
          id: 'ch3',
          subscriptionId: 's2',
          customerId: 'c3',
          dueDate: td.add(const Duration(days: 9)),
          amount: 199,
          manual: false),
      Charge(
          id: 'ch4',
          subscriptionId: 's6',
          customerId: 'c7',
          dueDate: addMonths(ago(18), 1),
          amount: 179,
          manual: false),
      Charge(
          id: 'ch5', subscriptionId: 's7', customerId: 'c8', dueDate: addMonths(ago(25), 1), amount: 199, manual: true),
      Charge(
          id: 'ch6',
          subscriptionId: 's8',
          customerId: 'c9',
          dueDate: td.add(const Duration(days: 15)),
          amount: 169,
          manual: false),
      Charge(
          id: 'ch7',
          subscriptionId: 's9',
          customerId: 'c10',
          dueDate: td.add(const Duration(days: 4)),
          amount: 199,
          manual: false),
      Charge(
          id: 'ch8',
          subscriptionId: 's3',
          customerId: 'c5',
          dueDate: addMonths(ago(3), -1),
          amount: 149,
          manual: true,
          status: ChargeStatus.paid,
          paidWith: PayMethod.cash,
          paidAt: addMonths(ago(3), -1)),
    ]);

    final l1 = SignupLink(id: 'l1', sentTo: t('יוסי אברהם'), createdAt: now.subtract(const Duration(hours: 5)));
    final l2 = SignupLink(id: 'l2', sentTo: '054-7781200', createdAt: now.subtract(const Duration(hours: 2)))
      ..advance(LinkStage.opened, now.subtract(const Duration(minutes: 50)));
    final l3 = SignupLink(id: 'l3', sentTo: t('רונית ש.'), createdAt: now.subtract(const Duration(hours: 1)))
      ..advance(LinkStage.opened, now.subtract(const Duration(minutes: 40)))
      ..advance(LinkStage.details, now.subtract(const Duration(minutes: 38)))
      ..advance(LinkStage.signed, now.subtract(const Duration(minutes: 37)))
      ..advance(LinkStage.failed, now.subtract(const Duration(minutes: 36)));
    final l4 =
        SignupLink(id: 'l4', sentTo: t('יעל אורן'), createdAt: ago(18), planId: 'p7', customerId: 'c7', amount: 358)
          ..advance(LinkStage.paid, ago(18));
    links.addAll([l1, l2, l3, l4]);

    final pc = PaymentLine.new;
    Receipt rec(int no, String name, String desc, List<PaymentLine> l, DateTime at, ReceiptKind k) =>
        Receipt(number: no, customerName: name, description: desc, lines: l, date: at, kind: k);
    receipts.addAll([
      rec(30160, t('חאלד מנסור'), t('חודשי ללא הגבלה'), [pc(method: PayMethod.cash, amount: 299)], ago(25),
          ReceiptKind.subscription),
      rec(30163, t('יעל אורן'), t('חודשי + חודש אחרון מראש'), [pc(method: PayMethod.card, amount: 358)], ago(18),
          ReceiptKind.link),
      rec(
          30166,
          t('לינה סעד'),
          t('3 חודשים'),
          [
            pc(
                method: PayMethod.cheque,
                amount: 640,
                cheques: 3,
                cheque: ChequeDetails(number: '0041', bank: '12', branch: '614', account: '338210', firstDate: ago(12)))
          ],
          ago(12),
          ReceiptKind.subscription),
      rec(30170, t('אלון ברק'), t('פעמיים בשבוע · {0}/{1}', [addMonths(ago(3), -1).month, addMonths(ago(3), -1).year]),
          [pc(method: PayMethod.cash, amount: 149)], addMonths(ago(3), -1), ReceiptKind.collection),
      rec(30174, t('דני כהן'), t('אימון אישי'), [pc(method: PayMethod.card, amount: 180)], ago(6),
          ReceiptKind.quickPay),
      rec(30177, t('נועה לוי'), t('שייק חלבון, מגבת'), [pc(method: PayMethod.cash, amount: 52)], ago(2),
          ReceiptKind.quickPay),
      rec(30180, t('שירן מזרחי'), t('שנתי'), [pc(method: PayMethod.card, amount: 1790, installments: 6)],
          now.subtract(const Duration(hours: 3)), ReceiptKind.subscription),
      rec(30181, t('לקוח מזדמן'), t('כניסה חד-פעמית'), [pc(method: PayMethod.cash, amount: 60)],
          now.subtract(const Duration(hours: 1)), ReceiptKind.quickPay),
    ]);
    seedDemoHistory(this);
    // Number every receipt in date order, as a real receipt book would be.
    receipts.sort((a, b) => a.date.compareTo(b.date));
    final numbered = [
      for (var i = 0; i < receipts.length; i++)
        Receipt(
          number: 28001 + i,
          customerId:
              receipts[i].customerId ?? customers.where((c) => c.name == receipts[i].customerName).firstOrNull?.id,
          customerName: receipts[i].customerName,
          description: receipts[i].description,
          lines: receipts[i].lines,
          date: receipts[i].date,
          kind: receipts[i].kind,
        )
    ];
    receipts
      ..clear()
      ..addAll(numbered);
    _receiptNo = 28000 + receipts.length;
  }
}
