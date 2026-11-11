// The card processor, as the backend should expose it to the app.
//
// The app never sees a card number: the card is typed into the processor's
// hosted field (see card_sheet.dart), which returns a token and the last four
// digits. Charges, recurring charges and refunds run on the server; the app
// only asks for them and shows the result. [MockPaymentGateway] approves
// everything, for the demo.

class CardToken {
  const CardToken(this.token, this.last4);
  final String token;
  final String last4;
}

class GatewayResult {
  const GatewayResult.ok(this.transactionId) : error = null;
  const GatewayResult.failed(this.error) : transactionId = null;
  final String? transactionId;
  final String? error;
  bool get ok => transactionId != null;
}

abstract class PaymentGateway {
  /// One charge, in [installments] if more than 1.
  Future<GatewayResult> charge({required CardToken card, required double amount, int installments = 1});

  /// Refunds all or part of an earlier charge.
  Future<GatewayResult> refund({required String transactionId, required double amount});
}

class MockPaymentGateway implements PaymentGateway {
  int _n = 0;

  @override
  Future<GatewayResult> charge({required CardToken card, required double amount, int installments = 1}) async =>
      GatewayResult.ok('MOCK-CH-${++_n}');

  @override
  Future<GatewayResult> refund({required String transactionId, required double amount}) async =>
      GatewayResult.ok('MOCK-RF-${++_n}');
}
