// Sending a sale's document to the customer by SMS or email, signed in: the
// AURA server sends it (the same endpoints the POS app calls).

import 'l10n.dart';

/// The server's / SMS provider's reason a send failed, safe to show.
class ReceiptSendException implements Exception {
  const ReceiptSendException(this.message);
  final String message;

  @override
  String toString() => 'ReceiptSendException($message)';
}

/// The local form the web expects ("0501234567"); it drops the first digit
/// itself. As the POS app: any country code goes, a single leading 0 stays.
String localPhoneNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  for (final code in ['972', '971']) {
    if (digits.startsWith(code)) {
      digits = digits.substring(code.length);
      break;
    }
  }
  return digits.startsWith('0') ? digits : '0$digits';
}

const _sent = 'SMS sent successfully';

/// The answer of POST sales/send-invoice-by-sms. The web's current code answers
/// JSON {success, message}; older servers answer plain text ("SMS sent
/// successfully", SMS4Free's "Succeeded", or the provider's error), and JSON
/// {message} when SMS is not set up for the branch.
({bool ok, String message}) smsAnswer(Object? body) {
  if (body is Map) {
    final message = '${body['message'] ?? ''}'.trim();
    final ok = body['success'] == true || (body['success'] == null && message.startsWith(_sent));
    return (ok: ok, message: ok ? message : _failure(message));
  }
  var text = body is String ? body.trim() : '';
  // Anything a debug toolbar appends after the reply is dropped.
  final html = text.indexOf('<');
  if (html > 0) text = text.substring(0, html).trim();
  final ok = text.startsWith(_sent) || text == 'Succeeded' || text == 'true';
  return (ok: ok, message: ok ? text : _failure(text));
}

String _failure(String message) {
  if (message.isEmpty || message.startsWith('<')) return t('ה-SMS לא נשלח. נסו שוב.');
  // The web's text when the branch has no SMS4Free account.
  if (message.contains('SMS setting') || message.contains('הגדרות ה-SMS')) return t('שליחת SMS לא מוגדרת לסניף במערכת AURA (הגדרות הסניף).');
  return message;
}
