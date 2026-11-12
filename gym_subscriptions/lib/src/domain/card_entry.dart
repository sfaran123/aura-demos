// A member's saved card, as the web's customer page keeps it: the card is typed
// once, the server checks it with Z Credit (a J2 check, nothing is charged) and
// keeps the token for later charges. The app keeps only the last four digits.
//
// The rules are the web's (customer create/edit "Payment Methods & Documents",
// HomeController::checkCard): card number, CVV and expiry MM/YY. There is no
// Luhn check: Israeli Isracard numbers (8-9 digits) do not follow it.

import 'l10n.dart';
import 'models.dart';

/// Only the digits of what was typed.
String cardDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

String? cardNumberError(String s) {
  final d = cardDigits(s);
  if (d.isEmpty) return t('צריך מספר כרטיס');
  if (d.length < 8 || d.length > 19) return t('מספר הכרטיס לא תקין');
  return null;
}

String? cvvError(String s) => RegExp(r'^\d{3,4}$').hasMatch(s.trim()) ? null : t('CVV צריך 3 או 4 ספרות');

/// [s] is "MM/YY"; a card is valid through the end of its expiry month.
String? expiryError(String s, DateTime today) {
  final m = RegExp(r'^(0[1-9]|1[0-2])/(\d{2})$').firstMatch(s.trim());
  if (m == null) return t('תוקף בפורמט MM/YY');
  final month = int.parse(m.group(1)!), year = 2000 + int.parse(m.group(2)!);
  if (year < today.year || (year == today.year && month < today.month)) return t('תוקף הכרטיס עבר');
  return null;
}

/// The expiry as it is typed, formatted as the web's card fields do: a first
/// digit above 1 becomes "0X/", the month is kept between 01 and 12, the slash
/// is added after the month and a 4-digit year keeps its last two digits.
String formatExpiryInput(String typed) {
  var value = cardDigits(typed);
  if (value.isEmpty) return '';
  if (value.length == 1 && int.parse(value) > 1) value = '0$value';
  var month = value.substring(0, value.length < 2 ? value.length : 2);
  if (month.length == 2) {
    final n = int.parse(month);
    if (n == 0) month = '01';
    if (n > 12) month = '12';
  }
  var year = value.length > 2 ? value.substring(2) : '';
  if (year.length == 4) year = year.substring(2);
  if (year.length > 2) year = year.substring(0, 2);
  if (value.length <= 2) return month.length == 2 ? '$month/' : month;
  return '$month/$year';
}

/// The card number grouped by four, for display while typing.
String formatCardNumberInput(String typed) {
  final d = cardDigits(typed);
  final out = StringBuffer();
  for (var i = 0; i < d.length && i < 19; i++) {
    if (i > 0 && i % 4 == 0) out.write(' ');
    out.write(d[i]);
  }
  return out.toString();
}

/// Why the server did not save a card.
enum CardSaveError {
  /// Z Credit did not approve the card.
  declined,

  /// The web's general settings have no Z Credit terminal.
  terminalMissing,

  /// Z Credit could not be reached.
  unreachable,

  /// The membership is not billed by card (paid at the desk, or a standing order).
  notCardBilled,

  /// Monthly by card, but the member has no saved card on the server.
  memberHasNoCard,
}

class CardSaveException implements Exception {
  const CardSaveException(this.error);
  final CardSaveError error;

  String get message => switch (error) {
        CardSaveError.declined => t('הכרטיס לא אושר. בדקו את הפרטים ונסו שוב.'),
        CardSaveError.terminalMissing => t('לא הוגדר מסוף Z Credit בהגדרות המערכת של AURA.'),
        CardSaveError.unreachable => t('אין חיבור לחברת האשראי. נסו שוב.'),
        CardSaveError.notCardBilled => t('המנוי לא מחויב בכרטיס אשראי, ולכן אין לו כרטיס לעדכן.'),
        CardSaveError.memberHasNoCard =>
          t('ללקוח אין כרטיס שמור במערכת. בחרו "כרטיס חדש" כדי לשמור כרטיס, או אמצעי אחר לחיוב החודשי.'),
      };

  @override
  String toString() => 'CardSaveException($error)';
}

/// A card charge the card company did not approve; [message] is its answer.
class CardChargeException implements Exception {
  const CardChargeException(this.message);
  final String message;

  @override
  String toString() => 'CardChargeException($message)';
}

/// Whether a membership's own card can be updated, as the web's subscription
/// "Update Credit Card Info": only one the server charges monthly by card. On a
/// membership paid at the desk the server would start charging the card, and
/// a standing order is paid by bank transfer.
bool membershipCardUpdatable(Subscription s) =>
    s.recurringMethod == RecurringMethod.savedCard && s.status != SubStatus.cancelled && s.status != SubStatus.expired;

/// A month the server failed to charge to the membership's card, as the web
/// lists them after a card update (retries of the same month are one row).
class FailedMonth {
  const FailedMonth({required this.monthKey, required this.month, required this.amount});

  /// The server's key ("2026-09|10": month and product).
  final String monthKey;

  /// The first day of the month.
  final DateTime month;
  final double amount;

  /// From the web's list: {month_key, year_month "2026-09", amount, ...}.
  static FailedMonth? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = '${j['month_key'] ?? ''}';
    final ym = RegExp(r'^(\d{4})-(\d{2})').firstMatch('${j['year_month'] ?? key}');
    if (key.isEmpty || ym == null) return null;
    final amount = j['amount'];
    return FailedMonth(
      monthKey: key,
      month: DateTime(int.parse(ym.group(1)!), int.parse(ym.group(2)!)),
      amount: amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0,
    );
  }
}
