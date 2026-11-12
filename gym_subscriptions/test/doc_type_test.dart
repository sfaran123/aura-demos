// The document a payment produces follows the AURA server's business type, as
// in the POS app: an exempt dealer (business_type 1) issues a receipt (קבלה,
// type 3) for sales and refunds alike, without VAT; any other business a tax
// invoice-receipt, and a tax credit note for a refund.

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/domain/sale_builder.dart';
import 'package:aura_gym/src/domain/settings.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/ui/receipt_view.dart';

const exempt = PosSettings(businessType: 1, decimal: 2);
const licensed = PosSettings(businessType: 0, decimal: 2);

Receipt doc({bool credit = false, int? serverType}) => Receipt(
      number: 1,
      customerName: 'x',
      description: 'x',
      lines: const [],
      date: DateTime(2026, 11, 12),
      kind: credit ? ReceiptKind.credit : ReceiptKind.quickPay,
      docType: serverType,
    );

void main() {
  test('exempt dealer on the server: receipts, no VAT, also for a refund', () {
    final store = GymStore()..posSettings = exempt;
    final type = store.settings.docType;
    expect(type, DocType.receipt);
    expect(exempt.invoiceType, 3);
    expect(docLabel(doc(), type), 'קבלה');
    expect(docLabel(doc(credit: true), type), 'קבלה');
    expect(carriesVat(doc(), type), isFalse);
  });

  test('licensed dealer on the server: tax invoice-receipt, tax credit note', () {
    final store = GymStore()
      ..settings.docType = DocType.receipt
      ..posSettings = licensed;
    final type = store.settings.docType;
    expect(type, DocType.taxInvoiceReceipt);
    expect(licensed.invoiceType, 27);
    expect(docLabel(doc(), type), 'חשבונית מס קבלה');
    expect(docLabel(doc(credit: true), type), 'חשבונית מס זיכוי');
    expect(carriesVat(doc(), type), isTrue);
  });

  test('server documents keep their own type and VAT', () {
    expect(docLabel(doc(serverType: 3), DocType.taxInvoiceReceipt), 'קבלה');
    expect(carriesVat(doc(serverType: 3), DocType.taxInvoiceReceipt), isFalse);
    expect(carriesVat(doc(serverType: 27), DocType.receipt), isTrue);
  });

  test('signing out keeps the last document type', () {
    final store = GymStore()..posSettings = exempt;
    store.posSettings = null;
    expect(store.settings.docType, DocType.receipt);
  });
}
