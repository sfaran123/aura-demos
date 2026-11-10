// Domain models for gym subscriptions. Pure Dart: no Flutter imports, so the
// same classes can move into the existing AURA Flutter app or a backend.

enum PlanKind { recurring, term, punch }

extension PlanKindLabel on PlanKind {
  String get label => switch (this) {
        PlanKind.recurring => 'מתחדש כל חודש',
        PlanKind.term => 'לתקופה',
        PlanKind.punch => 'כרטיסייה',
      };

  String get short => switch (this) {
        PlanKind.recurring => 'מתחדש',
        PlanKind.term => 'לתקופה',
        PlanKind.punch => 'כרטיסייה',
      };
}

/// A subscription plan, stored in AURA as a product flagged as a subscription.
class SubscriptionPlan {
  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.kind,
    required this.price,
    this.months = 1,
    this.entries = 10,
    this.validMonths = 3,
    this.commitMonths = 0,
    this.cancelNoticeDays = 30,
    this.registrationFee = 0,
    this.weeklyLimit = 0,
    this.freezeDaysPerYear = 0,
    this.maxInstallments = 1,
    this.maxCheques = 0,
    this.autoRenew = false,
    this.allowCash = true,
    this.allowCheques = false,
    this.onlineSignup = true,
    this.active = true,
    this.badge,
    this.prepayLastMonth = false,
  });

  final String id;
  String name;
  PlanKind kind;

  /// Monthly price for [PlanKind.recurring]; total price otherwise.
  double price;

  /// Length of a [PlanKind.term] plan.
  int months;

  /// Entries and validity of a [PlanKind.punch] card.
  int entries;
  int validMonths;

  /// Minimum months for a recurring plan (0 = no commitment).
  int commitMonths;
  int cancelNoticeDays;

  double registrationFee;

  /// Entries allowed per week (0 = unlimited).
  int weeklyLimit;
  int freezeDaysPerYear;
  int maxInstallments;
  int maxCheques;

  /// Term plans: renew automatically at the end. Recurring plans always renew.
  bool autoRenew;
  bool allowCash;
  bool allowCheques;

  /// Shown to customers on the self sign-up link.
  bool onlineSignup;
  bool active;
  String? badge;

  /// Recurring plans: the customer pays the last month in advance when joining.
  /// Cancelling needs a month's notice, and the last month is not charged.
  bool prepayLastMonth;

  bool get isRecurring => kind == PlanKind.recurring;

  SubscriptionPlan copy({String? id}) => SubscriptionPlan(
        id: id ?? this.id,
        name: name,
        kind: kind,
        price: price,
        months: months,
        entries: entries,
        validMonths: validMonths,
        commitMonths: commitMonths,
        cancelNoticeDays: cancelNoticeDays,
        registrationFee: registrationFee,
        weeklyLimit: weeklyLimit,
        freezeDaysPerYear: freezeDaysPerYear,
        maxInstallments: maxInstallments,
        maxCheques: maxCheques,
        autoRenew: autoRenew,
        allowCash: allowCash,
        allowCheques: allowCheques,
        onlineSignup: onlineSignup,
        active: active,
        badge: badge,
        prepayLastMonth: prepayLastMonth,
      );

  /// Short feature labels shown on plan cards.
  List<String> features() {
    final f = <String>[];
    switch (kind) {
      case PlanKind.recurring:
        f.add(commitMonths > 0 ? 'התחייבות $commitMonths ח׳' : 'בלי התחייבות');
        if (prepayLastMonth) f.add('חודש אחרון משולם מראש');
      case PlanKind.term:
        f.add('$months חודשים');
      case PlanKind.punch:
        f.add('$entries כניסות · תוקף $validMonths ח׳');
    }
    f.add(weeklyLimit > 0 ? '$weeklyLimit כניסות בשבוע' : 'כניסות ללא הגבלה');
    if (registrationFee > 0) f.add('דמי רישום ${money(registrationFee)}');
    if (freezeDaysPerYear > 0) f.add('הקפאה עד $freezeDaysPerYear יום');
    if (maxInstallments > 1) f.add('עד $maxInstallments תשלומים');
    return f;
  }

  /// Checks the definition before saving. Returns a message, or null if valid.
  String? validate() {
    if (name.trim().isEmpty) return 'צריך שם למסלול';
    if (price <= 0) return 'צריך מחיר גדול מ-0';
    if (kind == PlanKind.term && months <= 0) return 'צריך משך בחודשים';
    if (kind == PlanKind.punch && entries <= 0) return 'צריך מספר כניסות';
    if (kind == PlanKind.punch && validMonths <= 0) return 'צריך תוקף לכרטיסייה';
    if (registrationFee < 0) return 'דמי רישום לא יכולים להיות שליליים';
    if (maxInstallments < 1) return 'מספר תשלומים מינימלי הוא 1';
    return null;
  }
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.idNumber,
    this.savedCardLast4,
    this.healthDeclared = false,
  });

  final String id;
  String name;
  String phone;
  String? idNumber;
  String? savedCardLast4;
  bool healthDeclared;

  bool get hasSavedCard => savedCardLast4 != null;
  String get initial => name.trim().isEmpty ? '?' : name.trim().substring(0, 1);
}

enum PayMethod { card, cash, cheque, bank, link }

extension PayMethodLabel on PayMethod {
  String get label => switch (this) {
        PayMethod.card => 'אשראי',
        PayMethod.cash => 'מזומן',
        PayMethod.cheque => 'שיקים',
        PayMethod.bank => 'העברה',
        PayMethod.link => 'לינק ללקוח',
      };

  /// Methods whose money is not confirmed at the counter.
  bool get isDeferred => this == PayMethod.link || this == PayMethod.bank;
}

enum CardSource { saved, newCard }

/// One part of a split payment.
class PaymentLine {
  PaymentLine({
    required this.method,
    required this.amount,
    this.cardSource = CardSource.saved,
    this.installments = 1,
    this.cheques = 1,
  });

  final PayMethod method;
  double amount;
  CardSource cardSource;
  int installments;
  int cheques;
}

/// How a recurring plan is charged every month after the first payment.
enum RecurringMethod { savedCard, newCard, standingOrder, manual }

extension RecurringMethodLabel on RecurringMethod {
  String get label => switch (this) {
        RecurringMethod.savedCard => 'כרטיס שמור',
        RecurringMethod.newCard => 'כרטיס חדש',
        RecurringMethod.standingOrder => 'הוראת קבע בבנק',
        RecurringMethod.manual => 'גבייה ידנית כל חודש',
      };

  /// Charged automatically, without staff action.
  bool get isAutomatic => this != RecurringMethod.manual;
}

/// [covered]: the last month, already paid in advance when the member joined.
enum ChargeStatus { due, paid, failed, covered }

/// One monthly charge of a recurring subscription. Automatic charges are run
/// by the card processor; manual ones appear in the "to collect" list until
/// staff mark them paid (cash, cheque, transfer or a payment link).
class Charge {
  Charge({
    required this.id,
    required this.subscriptionId,
    required this.customerId,
    required this.dueDate,
    required this.amount,
    required this.manual,
    this.status = ChargeStatus.due,
    this.paidWith,
    this.paidAt,
    this.attempts = 0,
    this.reminders = 0,
  });

  final String id;
  final String subscriptionId;
  final String customerId;
  final DateTime dueDate;
  final double amount;
  final bool manual;
  ChargeStatus status;
  PayMethod? paidWith;
  DateTime? paidAt;
  int attempts;
  int reminders;

  int daysOverdue(DateTime today) {
    final d = DateTime(today.year, today.month, today.day)
        .difference(DateTime(dueDate.year, dueDate.month, dueDate.day))
        .inDays;
    return d < 0 ? 0 : d;
  }

  bool isOpen() => status == ChargeStatus.due || status == ChargeStatus.failed;
}

enum SubStatus { active, pendingPayment, frozen, paymentFailed, cancelled, expired }

extension SubStatusLabel on SubStatus {
  String get label => switch (this) {
        SubStatus.active => 'פעיל',
        SubStatus.pendingPayment => 'ממתין לתשלום',
        SubStatus.frozen => 'מוקפא',
        SubStatus.paymentFailed => 'חיוב נכשל',
        SubStatus.cancelled => 'בוטל',
        SubStatus.expired => 'הסתיים',
      };
}

class Subscription {
  Subscription({
    required this.id,
    required this.customerId,
    required this.planId,
    required this.start,
    this.end,
    this.status = SubStatus.active,
    this.discountPct = 0,
    this.registrationWaived = false,
    this.monthlyAmount,
    this.recurringMethod,
    this.entriesLeft,
    this.frozenUntil,
    this.freezeDaysUsed = 0,
    this.nextCharge,
    this.cancelEffective,
    this.prepaidAmount = 0,
    DateTime? joinedAt,
    this.cancelledAt,
  }) : joinedAt = joinedAt ?? start;

  final String id;
  final String customerId;
  final String planId;
  DateTime start;
  DateTime? end;
  SubStatus status;
  int discountPct;
  bool registrationWaived;
  double? monthlyAmount;
  RecurringMethod? recurringMethod;
  int? entriesLeft;
  DateTime? frozenUntil;
  int freezeDaysUsed;
  DateTime? nextCharge;
  DateTime? cancelEffective;

  /// Last month paid in advance and held until the membership ends.
  double prepaidAmount;
  final DateTime joinedAt;
  DateTime? cancelledAt;
}

enum ReceiptKind { subscription, collection, quickPay, link }

/// A tax invoice-receipt covering every payment line of one action.
class Receipt {
  Receipt({
    required this.number,
    required this.customerName,
    required this.description,
    required this.lines,
    required this.date,
    this.kind = ReceiptKind.subscription,
  });

  final ReceiptKind kind;

  final int number;
  final String customerName;
  final String description;
  final List<PaymentLine> lines;
  final DateTime date;

  double get total => lines.fold(0, (a, l) => a + l.amount);
  double get collectedNow => lines.where((l) => !l.method.isDeferred).fold(0, (a, l) => a + l.amount);
}

class ShopItem {
  const ShopItem(this.id, this.name, this.price);
  final String id;
  final String name;
  final double price;
}

enum LinkStatus { waiting, paid }

/// Where the customer is in a link, in order.
enum LinkStage { sent, opened, details, signed, paid, failed }

class SignupLink {
  SignupLink({
    required this.id,
    required this.sentTo,
    required this.createdAt,
    this.planId,
    this.customerId,
    this.amount,
    LinkStage stage = LinkStage.sent,
    Map<LinkStage, DateTime>? timeline,
  })  : _stage = stage,
        timeline = timeline ?? {LinkStage.sent: createdAt};

  final String id;
  String sentTo;
  final DateTime createdAt;

  /// Null for an open registration link where the customer picks the plan.
  String? planId;
  String? customerId;
  double? amount;
  LinkStage _stage;
  final Map<LinkStage, DateTime> timeline;

  LinkStage get stage => _stage;

  /// Moves forward (never back, except to failed and from failed to paid).
  void advance(LinkStage s, DateTime at) {
    if (_stage == LinkStage.paid) return;
    if (s.index <= _stage.index && s != LinkStage.failed && _stage != LinkStage.failed) return;
    _stage = s;
    timeline.putIfAbsent(s, () => at);
    // Fill skipped steps so the timeline reads in order.
    for (final x in LinkStage.values) {
      if (x.index < s.index && x != LinkStage.failed && s != LinkStage.failed) timeline.putIfAbsent(x, () => at);
    }
  }

  LinkStatus get status => _stage == LinkStage.paid ? LinkStatus.paid : LinkStatus.waiting;

  String get url => 'fitclub.aura.link/${planId == null ? 'join' : 'pay'}/$id';
}

/// Money in shekels, no trailing ".0".
String money(double v) {
  final r = (v * 100).round() / 100;
  final whole = r.truncate();
  final frac = ((r - whole).abs() * 100).round();
  final digits = whole.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = r < 0 ? '-' : '';
  return frac == 0 ? '$sign$buf ₪' : '$sign$buf.${frac.toString().padLeft(2, '0')} ₪';
}

extension LinkStageLabel on LinkStage {
  String get label => switch (this) {
        LinkStage.sent => 'נשלח',
        LinkStage.opened => 'נפתח',
        LinkStage.details => 'מילא פרטים',
        LinkStage.signed => 'חתם',
        LinkStage.paid => 'שילם',
        LinkStage.failed => 'התשלום נכשל',
      };
}
