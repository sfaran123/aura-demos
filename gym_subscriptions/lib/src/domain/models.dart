import 'l10n.dart';
// Domain models for gym subscriptions. Pure Dart: no Flutter imports, so the
// same classes can move into the existing AURA Flutter app or a backend.

enum PlanKind { recurring, term, punch }

extension PlanKindLabel on PlanKind {
  String get label => switch (this) {
        PlanKind.recurring => t('מתחדש כל חודש'),
        PlanKind.term => t('לתקופה'),
        PlanKind.punch => t('כרטיסייה'),
      };

  String get short => switch (this) {
        PlanKind.recurring => t('מתחדש'),
        PlanKind.term => t('לתקופה'),
        PlanKind.punch => t('כרטיסייה'),
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
    this.taxRate = 0,
    this.taxMethod,
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

  /// From the AURA server (the plan product's VAT): rate in %, and 1 when [price]
  /// is before VAT (else it includes VAT). Used to save the sale as the POS does.
  double taxRate;
  int? taxMethod;

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
        taxRate: taxRate,
        taxMethod: taxMethod,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'price': price,
        'months': months,
        'entries': entries,
        'validMonths': validMonths,
        'commitMonths': commitMonths,
        'cancelNoticeDays': cancelNoticeDays,
        'registrationFee': registrationFee,
        'weeklyLimit': weeklyLimit,
        'freezeDaysPerYear': freezeDaysPerYear,
        'maxInstallments': maxInstallments,
        'maxCheques': maxCheques,
        'autoRenew': autoRenew,
        'allowCash': allowCash,
        'allowCheques': allowCheques,
        'onlineSignup': onlineSignup,
        'active': active,
        'badge': badge,
        'prepayLastMonth': prepayLastMonth,
        if (taxRate != 0) 'taxRate': taxRate,
        if (taxMethod != null) 'taxMethod': taxMethod,
      };

  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) => SubscriptionPlan(
        id: j['id'],
        name: j['name'],
        kind: PlanKind.values.byName(j['kind']),
        price: (j['price'] as num).toDouble(),
        months: j['months'] ?? 1,
        entries: j['entries'] ?? 10,
        validMonths: j['validMonths'] ?? 3,
        commitMonths: j['commitMonths'] ?? 0,
        cancelNoticeDays: j['cancelNoticeDays'] ?? 30,
        registrationFee: (j['registrationFee'] as num? ?? 0).toDouble(),
        weeklyLimit: j['weeklyLimit'] ?? 0,
        freezeDaysPerYear: j['freezeDaysPerYear'] ?? 0,
        maxInstallments: j['maxInstallments'] ?? 1,
        maxCheques: j['maxCheques'] ?? 0,
        autoRenew: j['autoRenew'] ?? false,
        allowCash: j['allowCash'] ?? true,
        allowCheques: j['allowCheques'] ?? false,
        onlineSignup: j['onlineSignup'] ?? true,
        active: j['active'] ?? true,
        badge: j['badge'],
        prepayLastMonth: j['prepayLastMonth'] ?? false,
        taxRate: (j['taxRate'] as num? ?? 0).toDouble(),
        taxMethod: j['taxMethod'],
      );

  /// Short feature labels shown on plan cards.
  List<String> features() {
    final f = <String>[];
    switch (kind) {
      case PlanKind.recurring:
        f.add(commitMonths > 0 ? t('התחייבות {0} ח׳', [commitMonths]) : t('בלי התחייבות'));
        if (prepayLastMonth) f.add(t('חודש אחרון משולם מראש'));
      case PlanKind.term:
        f.add(t('{0} חודשים', [months]));
      case PlanKind.punch:
        f.add(t('{0} כניסות · תוקף {1} ח׳', [entries, validMonths]));
    }
    f.add(weeklyLimit > 0 ? t('{0} כניסות בשבוע', [weeklyLimit]) : t('כניסות ללא הגבלה'));
    if (registrationFee > 0) f.add(t('דמי רישום {0}', [money(registrationFee)]));
    if (freezeDaysPerYear > 0) f.add(t('הקפאה עד {0} יום', [freezeDaysPerYear]));
    if (maxInstallments > 1) f.add(t('עד {0} תשלומים', [maxInstallments]));
    return f;
  }

  /// Checks the definition before saving. Returns a message, or null if valid.
  String? validate() {
    if (name.trim().isEmpty) return t('צריך שם למסלול');
    if (price <= 0) return t('צריך מחיר גדול מ-0');
    if (kind == PlanKind.term && months <= 0) return t('צריך משך בחודשים');
    if (kind == PlanKind.punch && entries <= 0) return t('צריך מספר כניסות');
    if (kind == PlanKind.punch && validMonths <= 0) return t('צריך תוקף לכרטיסייה');
    if (registrationFee < 0) return t('דמי רישום לא יכולים להיות שליליים');
    if (maxInstallments < 1) return t('מספר תשלומים מינימלי הוא 1');
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

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'idNumber': idNumber,
        'savedCardLast4': savedCardLast4,
        'healthDeclared': healthDeclared,
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'],
        name: j['name'],
        phone: j['phone'],
        idNumber: j['idNumber'],
        savedCardLast4: j['savedCardLast4'],
        healthDeclared: j['healthDeclared'] ?? false,
      );
}

enum PayMethod { card, cash, cheque, bank, link }

extension PayMethodLabel on PayMethod {
  String get label => switch (this) {
        PayMethod.card => t('אשראי'),
        PayMethod.cash => t('מזומן'),
        PayMethod.cheque => t('שיקים'),
        PayMethod.bank => t('העברה'),
        PayMethod.link => t('לינק ללקוח'),
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
    ChequeDetails? cheque,
    TransferDetails? transfer,
    this.transactionId,
  })  : cheque = cheque ?? ChequeDetails(),
        transfer = transfer ?? TransferDetails();

  /// Card processor's transaction id, needed to refund a card payment.
  String? transactionId;

  final PayMethod method;
  double amount;
  CardSource cardSource;
  int installments;
  int cheques;

  /// Filled when [method] is a cheque: the cheques are consecutive, one a month.
  final ChequeDetails cheque;

  /// Filled when [method] is a bank transfer.
  final TransferDetails transfer;

  /// Basic details are missing for a cheque or a transfer.
  String? get detailsProblem => switch (method) {
        PayMethod.cheque => cheque.problem,
        PayMethod.bank => transfer.problem,
        _ => null,
      };

  /// One line for receipts and reports, empty when there is nothing to add.
  String get detailsText => switch (method) {
        PayMethod.cheque when cheque.isComplete => cheque.text(cheques),
        PayMethod.bank when transfer.isComplete => transfer.text,
        _ => '',
      };

  PaymentLine copy({double? amount}) => PaymentLine(
        method: method,
        amount: amount ?? this.amount,
        cardSource: cardSource,
        installments: installments,
        cheques: cheques,
        cheque: cheque,
        transfer: transfer,
        transactionId: transactionId,
      );

  Map<String, Object?> toJson() => {
        'method': method.name,
        'amount': amount,
        'cardSource': cardSource.name,
        'installments': installments,
        'cheques': cheques,
        if (method == PayMethod.cheque) 'cheque': cheque.toJson(),
        if (method == PayMethod.bank) 'transfer': transfer.toJson(),
        if (transactionId != null) 'transactionId': transactionId,
      };

  factory PaymentLine.fromJson(Map<String, dynamic> j) => PaymentLine(
        method: PayMethod.values.byName(j['method']),
        amount: (j['amount'] as num).toDouble(),
        cardSource: CardSource.values.byName(j['cardSource'] ?? 'saved'),
        installments: j['installments'] ?? 1,
        cheques: j['cheques'] ?? 1,
        cheque: j['cheque'] == null ? null : ChequeDetails.fromJson(j['cheque']),
        transfer: j['transfer'] == null ? null : TransferDetails.fromJson(j['transfer']),
        transactionId: j['transactionId'],
      );
}

String? _d(DateTime? d) => d?.toIso8601String();
DateTime? _pd(Object? s) => s == null ? null : DateTime.parse(s as String);

/// Israeli bank codes shown next to the number the staff types.
const Map<String, String> israeliBanks = {
  '4': 'יהב',
  '9': 'בנק הדואר',
  '10': 'לאומי',
  '11': 'דיסקונט',
  '12': 'הפועלים',
  '17': 'מרכנתיל',
  '20': 'מזרחי טפחות',
  '31': 'הבינלאומי',
  '46': 'מסד',
  '52': 'פאג"י',
  '54': 'ירושלים',
};

String bankName(String code) {
  final n = israeliBanks[int.tryParse(code)?.toString() ?? code];
  return n == null ? '' : t(n);
}

class ChequeDetails {
  ChequeDetails({this.number = '', this.bank = '', this.branch = '', this.account = '', this.firstDate});
  String number;
  String bank;
  String branch;
  String account;

  /// Date of the first cheque; the rest are a month apart. Null = today.
  DateTime? firstDate;

  bool get isComplete => problem == null;

  String? get problem {
    final missing = [
      if (!RegExp(r'^\d{3,10}$').hasMatch(number)) t('מספר שיק'),
      if (!RegExp(r'^\d{1,2}$').hasMatch(bank)) t('בנק'),
      if (!RegExp(r'^\d{3}$').hasMatch(branch)) t('סניף'),
      if (!RegExp(r'^\d{4,9}$').hasMatch(account)) t('חשבון'),
    ];
    return missing.isEmpty ? null : t('חסרים פרטי שיק: {0}', [missing.join(', ')]);
  }

  /// Number of the cheque at [i] (0-based); cheques in a book are consecutive.
  String numberAt(int i) {
    final n = int.tryParse(number);
    return n == null ? number : (n + i).toString().padLeft(number.length, '0');
  }

  String text(int count) {
    final b = bankName(bank);
    final nums = count > 1 ? '${numberAt(0)}–${numberAt(count - 1)}' : number;
    return t('שיק {0} · בנק {1}{2} · סניף {3} · חשבון {4}', [nums, bank, b.isEmpty ? '' : ' ($b)', branch, account]);
  }

  Map<String, Object?> toJson() =>
      {'number': number, 'bank': bank, 'branch': branch, 'account': account, 'firstDate': _d(firstDate)};

  factory ChequeDetails.fromJson(Map<String, dynamic> j) => ChequeDetails(
      number: j['number'] ?? '',
      bank: j['bank'] ?? '',
      branch: j['branch'] ?? '',
      account: j['account'] ?? '',
      firstDate: _pd(j['firstDate']));
}

class TransferDetails {
  TransferDetails({this.reference = '', this.bank = '', this.date});

  /// The bank's reference number (אסמכתא).
  String reference;
  String bank;
  DateTime? date;

  bool get isComplete => problem == null;

  String? get problem {
    final missing = [
      if (reference.trim().length < 3) t('אסמכתא'),
      if (!RegExp(r'^\d{1,2}$').hasMatch(bank)) t('בנק משלם'),
    ];
    return missing.isEmpty ? null : t('חסרים פרטי העברה: {0}', [missing.join(', ')]);
  }

  String get text {
    final b = bankName(bank);
    return t('העברה · אסמכתא {0} · בנק {1}{2}', [reference, bank, b.isEmpty ? '' : ' ($b)']);
  }

  Map<String, Object?> toJson() => {'reference': reference, 'bank': bank, 'date': _d(date)};

  factory TransferDetails.fromJson(Map<String, dynamic> j) =>
      TransferDetails(reference: j['reference'] ?? '', bank: j['bank'] ?? '', date: _pd(j['date']));
}

/// How a recurring plan is charged every month after the first payment.
enum RecurringMethod { savedCard, newCard, standingOrder, manual }

extension RecurringMethodLabel on RecurringMethod {
  String get label => switch (this) {
        RecurringMethod.savedCard => t('כרטיס שמור'),
        RecurringMethod.newCard => t('כרטיס חדש'),
        RecurringMethod.standingOrder => t('הוראת קבע בבנק'),
        RecurringMethod.manual => t('גבייה ידנית כל חודש'),
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
    this.serverRef,
  });

  final String id;
  final String subscriptionId;
  final String customerId;
  final DateTime dueDate;
  final double amount;
  final bool manual;

  /// From the AURA server: a failed month's key ("2026-10|12"), or the id of an
  /// unpaid membership invoice. Null for charges made in the app.
  final String? serverRef;
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

  Map<String, Object?> toJson() => {
        'id': id,
        'subscriptionId': subscriptionId,
        'customerId': customerId,
        'dueDate': _d(dueDate),
        'amount': amount,
        'manual': manual,
        'status': status.name,
        'paidWith': paidWith?.name,
        'paidAt': _d(paidAt),
        'attempts': attempts,
        'reminders': reminders,
        if (serverRef != null) 'serverRef': serverRef,
      };

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'],
        subscriptionId: j['subscriptionId'],
        customerId: j['customerId'],
        dueDate: _pd(j['dueDate'])!,
        amount: (j['amount'] as num).toDouble(),
        manual: j['manual'],
        status: ChargeStatus.values.byName(j['status']),
        paidWith: j['paidWith'] == null ? null : PayMethod.values.byName(j['paidWith']),
        paidAt: _pd(j['paidAt']),
        attempts: j['attempts'] ?? 0,
        reminders: j['reminders'] ?? 0,
        serverRef: j['serverRef'],
      );
}

enum SubStatus { active, pendingPayment, frozen, paymentFailed, cancelled, expired }

extension SubStatusLabel on SubStatus {
  String get label => switch (this) {
        SubStatus.active => t('פעיל'),
        SubStatus.pendingPayment => t('ממתין לתשלום'),
        SubStatus.frozen => t('מוקפא'),
        SubStatus.paymentFailed => t('חיוב נכשל'),
        SubStatus.cancelled => t('בוטל'),
        SubStatus.expired => t('הסתיים'),
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
    this.hasCardToken = false,
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

  /// Server memberships: a card is saved on the membership itself
  /// (subscriptions.zcredit_token), which the server charges each month.
  /// The web shows only "Saved" / "Unsaved"; there are no card digits.
  bool hasCardToken;

  Map<String, Object?> toJson() => {
        'id': id,
        'customerId': customerId,
        'planId': planId,
        'start': _d(start),
        'end': _d(end),
        'status': status.name,
        'discountPct': discountPct,
        'registrationWaived': registrationWaived,
        'monthlyAmount': monthlyAmount,
        'recurringMethod': recurringMethod?.name,
        'entriesLeft': entriesLeft,
        'frozenUntil': _d(frozenUntil),
        'freezeDaysUsed': freezeDaysUsed,
        'nextCharge': _d(nextCharge),
        'cancelEffective': _d(cancelEffective),
        'prepaidAmount': prepaidAmount,
        'joinedAt': _d(joinedAt),
        'cancelledAt': _d(cancelledAt),
        'hasCardToken': hasCardToken,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'],
        customerId: j['customerId'],
        planId: j['planId'],
        start: _pd(j['start'])!,
        end: _pd(j['end']),
        status: SubStatus.values.byName(j['status']),
        discountPct: j['discountPct'] ?? 0,
        registrationWaived: j['registrationWaived'] ?? false,
        monthlyAmount: (j['monthlyAmount'] as num?)?.toDouble(),
        recurringMethod: j['recurringMethod'] == null ? null : RecurringMethod.values.byName(j['recurringMethod']),
        entriesLeft: j['entriesLeft'],
        frozenUntil: _pd(j['frozenUntil']),
        freezeDaysUsed: j['freezeDaysUsed'] ?? 0,
        nextCharge: _pd(j['nextCharge']),
        cancelEffective: _pd(j['cancelEffective']),
        prepaidAmount: (j['prepaidAmount'] as num? ?? 0).toDouble(),
        joinedAt: _pd(j['joinedAt']),
        cancelledAt: _pd(j['cancelledAt']),
        hasCardToken: j['hasCardToken'] ?? false,
      );
}

enum ReceiptKind { subscription, collection, quickPay, link, credit }

/// A tax invoice-receipt covering every payment line of one action. A credit
/// note ([isCredit]) has negative lines and points to the document it credits.
class Receipt {
  Receipt({
    required this.number,
    required this.customerName,
    required this.description,
    required this.lines,
    required this.date,
    this.kind = ReceiptKind.subscription,
    this.customerId,
    this.subscriptionId,
    this.chargeId,
    this.creditOf,
    this.reason,
    this.credited = 0,
    this.allocationNumber,
    this.reference,
    this.saleId,
    this.docType,
    this.docTotal,
    this.vat,
    this.cancelled = false,
  });

  final ReceiptKind kind;
  final String? customerId;

  /// The membership or monthly charge this document paid for, if any.
  final String? subscriptionId;
  final String? chargeId;

  /// Credit notes: number of the credited document and why.
  final int? creditOf;
  final String? reason;

  /// Amount already credited on this document (positive).
  double credited;

  /// Tax Authority allocation number (Israel Invoice model), set by the backend.
  String? allocationNumber;

  /// The document number on the AURA server (e.g. "TIN-80011"); null for
  /// documents made in the app. Shown instead of [number] when set.
  final String? reference;

  /// The sale's id on the AURA server (its PDF is the web's document); null
  /// for documents made in the app only (the demo).
  final int? saleId;

  String get docNo => reference ?? '$number';

  /// Server documents only (null in the app): the web's document type (7 tax
  /// invoice, 27 tax invoice-receipt, 10 credit, 3 receipt, ...), the document's
  /// own total (an unpaid tax invoice has no payment lines), its VAT, and whether
  /// it was cancelled on the web (its credit note is a document of its own).
  final int? docType;
  final double? docTotal;
  final double? vat;
  final bool cancelled;

  /// A VAT document, as the web's accounting export: tax invoice, credit, invoice-receipt.
  bool get isTaxDocument => docType == 7 || docType == 10 || docType == 27;

  /// Where the receipt was sent: (channel, address, when).
  final List<(String, String, DateTime)> sent = [];

  final int number;
  String customerName;
  final String description;
  final List<PaymentLine> lines;
  final DateTime date;

  bool get isCredit => kind == ReceiptKind.credit;
  double get total => lines.fold(0, (a, l) => a + l.amount);
  double get collectedNow => lines.where(isCollected).fold(0, (a, l) => a + l.amount);

  /// The money of [l] is in: on a server document every payment line is a
  /// recorded payment; in the app, a transfer or link part waits for confirmation.
  bool isCollected(PaymentLine l) => reference != null || !l.method.isDeferred;

  /// What can still be credited on this document.
  double get creditable => isCredit ? 0 : ((total - credited) * 100).round() / 100;

  Map<String, Object?> toJson() => {
        'number': number,
        'kind': kind.name,
        'customerId': customerId,
        'customerName': customerName,
        'description': description,
        'date': _d(date),
        'lines': [for (final l in lines) l.toJson()],
        'subscriptionId': subscriptionId,
        'chargeId': chargeId,
        'creditOf': creditOf,
        'reason': reason,
        'credited': credited,
        'allocationNumber': allocationNumber,
        if (reference != null) 'reference': reference,
        if (docType != null) 'docType': docType,
        if (docTotal != null) 'docTotal': docTotal,
        if (vat != null) 'vat': vat,
        if (cancelled) 'cancelled': true,
        'sent': [
          for (final s in sent) {'channel': s.$1, 'to': s.$2, 'at': _d(s.$3)}
        ],
      };

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final r = Receipt(
      number: j['number'],
      kind: ReceiptKind.values.byName(j['kind']),
      customerId: j['customerId'],
      customerName: j['customerName'],
      description: j['description'],
      date: _pd(j['date'])!,
      lines: [for (final l in j['lines'] as List) PaymentLine.fromJson(l)],
      subscriptionId: j['subscriptionId'],
      chargeId: j['chargeId'],
      creditOf: j['creditOf'],
      reason: j['reason'],
      credited: (j['credited'] as num? ?? 0).toDouble(),
      allocationNumber: j['allocationNumber'],
      reference: j['reference'],
      docType: j['docType'],
      docTotal: (j['docTotal'] as num?)?.toDouble(),
      vat: (j['vat'] as num?)?.toDouble(),
      cancelled: j['cancelled'] == true,
    );
    for (final s in (j['sent'] as List? ?? const [])) {
      r.sent.add((s['channel'], s['to'], _pd(s['at'])!));
    }
    return r;
  }
}

class ShopItem {
  const ShopItem(this.id, this.name, this.price, {this.taxRate = 0, this.taxMethod});
  final String id;
  final String name;
  final double price;

  /// From the AURA server (products.tax_id / tax_method): VAT rate in %, and 1 when
  /// [price] is before VAT (else it includes VAT). Used to save the sale as the POS does.
  final double taxRate;
  final int? taxMethod;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        if (taxRate != 0) 'taxRate': taxRate,
        if (taxMethod != null) 'taxMethod': taxMethod,
      };
  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(j['id'], j['name'], (j['price'] as num).toDouble(),
      taxRate: (j['taxRate'] as num? ?? 0).toDouble(), taxMethod: j['taxMethod']);
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

  Map<String, Object?> toJson() => {
        'id': id,
        'sentTo': sentTo,
        'createdAt': _d(createdAt),
        'planId': planId,
        'customerId': customerId,
        'amount': amount,
        'stage': _stage.name,
        'timeline': {for (final e in timeline.entries) e.key.name: _d(e.value)},
      };

  factory SignupLink.fromJson(Map<String, dynamic> j) => SignupLink(
        id: j['id'],
        sentTo: j['sentTo'],
        createdAt: _pd(j['createdAt'])!,
        planId: j['planId'],
        customerId: j['customerId'],
        amount: (j['amount'] as num?)?.toDouble(),
        stage: LinkStage.values.byName(j['stage']),
        timeline: {
          for (final e in (j['timeline'] as Map).entries) LinkStage.values.byName(e.key): _pd(e.value)!,
        },
      );
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
        LinkStage.sent => t('נשלח'),
        LinkStage.opened => t('נפתח'),
        LinkStage.details => t('מילא פרטים'),
        LinkStage.signed => t('חתם'),
        LinkStage.paid => t('שילם'),
        LinkStage.failed => t('התשלום נכשל'),
      };
}
