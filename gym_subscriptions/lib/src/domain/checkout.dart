// Pricing, split-payment and date rules. Pure Dart and unit-tested.

import 'models.dart';
import 'settings.dart';

enum CheckoutFlow { subscription, quickPay }

enum StartOption { today, tomorrow, nextMonth }

extension StartOptionLabel on StartOption {
  String get label => switch (this) {
        StartOption.today => 'היום',
        StartOption.tomorrow => 'מחר',
        StartOption.nextMonth => '1 לחודש הבא',
      };
}

double round2(double v) => (v * 100).round() / 100;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds calendar months, clamping the day (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final y = d.year + ((d.month - 1 + months) ~/ 12);
  final m = (d.month - 1 + months) % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

DateTime startDate(StartOption o, DateTime now) {
  final t = dateOnly(now);
  return switch (o) {
    StartOption.today => t,
    StartOption.tomorrow => t.add(const Duration(days: 1)),
    StartOption.nextMonth => DateTime(t.year, t.month + 1, 1),
  };
}

/// End of a term plan, or punch-card expiry. Null for recurring plans.
DateTime? endDate(SubscriptionPlan p, DateTime start) => switch (p.kind) {
      PlanKind.recurring => null,
      PlanKind.term => addMonths(start, p.months).subtract(const Duration(days: 1)),
      PlanKind.punch => addMonths(start, p.validMonths).subtract(const Duration(days: 1)),
    };

/// Price after discount (monthly for recurring plans).
double planPriceAfterDiscount(SubscriptionPlan p, int discountPct) =>
    round2(p.price * (100 - discountPct) / 100);

/// What the customer pays today: the plan price (first month for recurring
/// plans) after discount, plus the registration fee unless waived.
double subscriptionDueNow(SubscriptionPlan p,
        {int discountPct = 0, bool waiveRegistration = false}) =>
    round2(planPriceAfterDiscount(p, discountPct) +
        (waiveRegistration ? 0 : p.registrationFee));

double cartTotal(Map<String, int> cart, List<ShopItem> items, double custom) {
  var t = custom;
  cart.forEach((id, q) {
    final item = items.where((i) => i.id == id);
    if (item.isNotEmpty) t += item.first.price * q;
  });
  return round2(t);
}

double linesTotal(List<PaymentLine> lines) =>
    round2(lines.fold(0, (a, l) => a + l.amount));

/// Payment methods the counter may use for this checkout.
bool methodAllowed(PayMethod m, BusinessSettings s,
    {SubscriptionPlan? plan, bool walkIn = false}) {
  if (!s.enabledMethods.contains(m)) return false;
  if (plan != null) {
    if (m == PayMethod.cash && !plan.allowCash) return false;
    if (m == PayMethod.cheque && !plan.allowCheques) return false;
  }
  if (walkIn && (m == PayMethod.link || m == PayMethod.cheque)) return false;
  return true;
}

int maxInstallmentsFor(SubscriptionPlan? plan, BusinessSettings s) {
  if (plan == null) return s.maxInstallments;
  if (plan.isRecurring) return 1;
  return plan.maxInstallments < s.maxInstallments
      ? plan.maxInstallments
      : s.maxInstallments;
}

int maxChequesFor(SubscriptionPlan? plan, BusinessSettings s) {
  if (plan == null) return s.maxCheques;
  final m = plan.maxCheques < s.maxCheques ? plan.maxCheques : s.maxCheques;
  return m < 1 ? 1 : m;
}

/// A new line takes whatever is still unassigned.
PaymentLine newLine(PayMethod m, double remaining,
    {required bool hasSavedCard, int defaultCheques = 1}) {
  final amount = remaining > 0 ? round2(remaining) : 0.0;
  return PaymentLine(
    method: m,
    amount: amount,
    cardSource: hasSavedCard ? CardSource.saved : CardSource.newCard,
    cheques: defaultCheques,
  );
}

/// Recurring methods offered for this customer and business.
List<RecurringMethod> recurringOptions(
    {required bool hasSavedCard, required BusinessSettings s}) {
  return [
    if (hasSavedCard) RecurringMethod.savedCard,
    RecurringMethod.newCard,
    if (s.allowStandingOrder) RecurringMethod.standingOrder,
    if (s.allowManualMonthly) RecurringMethod.manual,
  ];
}

/// Why the payment step cannot continue yet, or null when it can.
String? paymentProblem({
  required double due,
  required List<PaymentLine> lines,
  required bool newCardReady,
  SubscriptionPlan? plan,
  RecurringMethod? recurring,
}) {
  if (due <= 0) return 'אין סכום לתשלום';
  if (lines.isEmpty) return 'בחרו אמצעי תשלום';
  for (final l in lines) {
    if (l.amount <= 0) return 'יש אמצעי תשלום בלי סכום';
    if (l.method == PayMethod.card &&
        l.cardSource == CardSource.newCard &&
        !newCardReady) {
      return 'צריך להזין את הכרטיס החדש';
    }
  }
  final left = round2(due - linesTotal(lines));
  if (left > 0) return 'נותרו ${money(left)} לשיוך';
  if (left < 0) return 'הסכום גבוה ב-${money(-left)} מהנדרש';
  if (plan != null && plan.isRecurring) {
    if (recurring == null) return 'בחרו איך ייגבה התשלום החודשי';
    if (recurring == RecurringMethod.newCard && !newCardReady) {
      return 'צריך להזין את הכרטיס לחיוב החודשי';
    }
  }
  return null;
}

/// The subscription waits for money that is not confirmed at the counter.
bool isPending(List<PaymentLine> lines) =>
    lines.any((l) => l.method.isDeferred);

/// Israeli ID check digit (Luhn variant). Accepts 5–9 digits.
bool isValidIsraeliId(String raw) {
  var id = raw.replaceAll(RegExp(r'\D'), '');
  if (id.length < 5 || id.length > 9) return false;
  id = id.padLeft(9, '0');
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    var n = int.parse(id[i]) * ((i % 2) + 1);
    if (n > 9) n -= 9;
    sum += n;
  }
  return sum % 10 == 0;
}

/// Israeli mobile or landline.
bool isValidPhone(String raw) =>
    RegExp(r'^0(5\d|[2-489]|7\d)\d{7}$').hasMatch(raw.replaceAll(RegExp(r'\D'), ''));

String formatPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  return d.length == 10 ? '${d.substring(0, 3)}-${d.substring(3)}' : raw.trim();
}

/// Freeze: how many days are still allowed this year.
int freezeDaysLeft(SubscriptionPlan p, Subscription s) {
  final left = p.freezeDaysPerYear - s.freezeDaysUsed;
  return left < 0 ? 0 : left;
}

/// When a cancellation takes effect: after the notice period, and not before
/// the commitment ends.
DateTime cancelEffectiveDate(
    SubscriptionPlan p, Subscription s, DateTime today) {
  var d = dateOnly(today).add(Duration(days: p.cancelNoticeDays));
  if (p.isRecurring && p.commitMonths > 0) {
    final commitEnd = addMonths(s.start, p.commitMonths);
    if (commitEnd.isAfter(d)) d = commitEnd;
  }
  if (s.end != null && s.end!.isBefore(d)) d = s.end!;
  return d;
}

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
