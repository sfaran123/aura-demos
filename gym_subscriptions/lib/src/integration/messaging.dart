// Sending receipts, reminders and links to customers (SMS / WhatsApp / email).
// In the demo nothing leaves the phone; the backend implements [MessageSender]
// with the business's SMS / WhatsApp provider and a link to the receipt PDF.

abstract class MessageSender {
  Future<bool> send({required String channel, required String to, required String text, String? receiptPdfUrl});
}

class MockMessageSender implements MessageSender {
  final List<(String, String, String)> sent = [];

  @override
  Future<bool> send({required String channel, required String to, required String text, String? receiptPdfUrl}) async {
    sent.add((channel, to, text));
    return true;
  }
}
