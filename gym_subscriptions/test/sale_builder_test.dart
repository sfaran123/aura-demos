// The sale maths must give what the AURA POS app gives (cart_product.dart
// calculateProductPriceByTax, order_totals.dart OrderTotals.pos). The expected
// numbers are worked by hand from those functions.

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/domain/sale_builder.dart';

const vat = PosSettings(businessType: 0, decimal: 2, customerId: 1, warehouseId: 2, billerId: 3, userId: 5);
const exempt = PosSettings(businessType: 1, decimal: 2, customerId: 1, warehouseId: 2, billerId: 3, userId: 5);

SaleLine line(num price, {num qty = 1, num rate = 18, int? method, num pct = 0}) =>
    SaleLine(productId: 1, title: 'x', basePrice: price, qty: qty, taxRate: rate, taxMethod: method, discountPct: pct);

void main() {
  test('price with VAT (tax_method 2): VAT taken out of the price', () {
    final p = linePrice(line(100), vat);
    expect(p.netUnitPrice, 84.75);
    expect(p.taxAmount, 15.25);
    expect(p.total, 100);
  });

  test('price before VAT (tax_method 1): VAT added', () {
    final p = linePrice(line(100, method: 1), vat);
    expect(p.netUnitPrice, 100);
    expect(p.taxAmount, 18);
    expect(p.total, 118);
  });

  test('10% line discount, two units', () {
    final l = line(199, qty: 2, pct: 10);
    expect(l.discount, closeTo(19.9, 1e-9));
    final p = linePrice(l, vat);
    expect(p.netUnitPrice, 151.78);
    expect(p.taxAmount, 54.64);
    expect(p.totalWithoutTax, 303.56);
    expect(p.total, 358.2);
  });

  test('exempt dealer: no VAT, receipt (type 3), tax_rate 0 on the line', () {
    final p = linePrice(line(100, method: 1), exempt);
    expect(p.taxAmount, 0);
    expect(p.total, 100);
    final body = storeV2Body(
      pos: exempt,
      lines: [line(100, method: 1)],
      payments: [PaymentLine(method: PayMethod.cash, amount: 100)],
      appUuid: 'u',
      now: DateTime(2026, 11, 11),
    );
    expect(body['type'], 3);
    expect(body['document_status'], 2);
    expect(body['total_tax'], 0);
    expect(((body['product_sale_data'] as List).single as Map)['tax_rate'], 0);
  });

  test('sign-up fee given with VAT: as the POS price override, a before-VAT product can be 1 agora off', () {
    SaleLine fee(num g, int m) => SaleLine.gross(productId: 30, title: 'fee', grossPrice: g, qty: 1, taxRate: 18, taxMethod: m);
    expect(linePrice(fee(100, 2), vat).total, 100, reason: 'price with VAT: exact');
    expect(linePrice(fee(150, 1), vat).total, 150);
    expect(linePrice(fee(100, 1), vat).total, 100.01, reason: 'net 84.75 + VAT 15.26, the POS rounding');
  });

  test('totals: lines, VAT, grand total in whole agorot', () {
    final t = saleTotals([line(100), line(100, method: 1), line(199, qty: 2, pct: 10)], vat);
    expect(t.linesTotal, 576.2);
    expect(t.totalTax, 87.89);
    expect(t.grandTotal, 576.2);
  });

  test('cheques: one row each, a month apart, consecutive numbers, the last takes the rounding', () {
    final cheque = PaymentLine(
      method: PayMethod.cheque,
      amount: 100,
      cheques: 3,
      cheque: ChequeDetails(number: '0098', bank: '12', branch: '345', account: '678901', firstDate: DateTime(2026, 11, 30)),
    );
    final body = storeV2Body(
        pos: vat, lines: [line(100)], payments: [cheque], appUuid: 'u', now: DateTime(2026, 11, 11), customerId: 7);
    expect(body['paid_by_ids'], '4,4,4');
    expect(body['paid_amount_data'], '33.33,33.33,33.34');
    expect(body['all_cheque_number'], '0098,0099,0100');
    expect(body['all_cheque_date'], '2026-11-30|,2026-12-30|,2027-01-30');
    expect(body['all_cheque_bank_name'], '12|,12|,12');
    expect(body['all_cheque_branch_name'], '345|,345|,345');
    expect(body['all_cheque_account_number'], '678901|,678901|,678901');
    expect(body['all_payment_complete'], '0,0,0');
    expect(body['customer_id'], 7);
  });

  test('split cash + transfer: the web Deposit fields (bank, serial number, dd-mm-yyyy)', () {
    final transfer = PaymentLine(
      method: PayMethod.bank,
      amount: 60,
      transfer: TransferDetails(reference: 'BR-77', bank: 'Leumi', date: DateTime(2026, 11, 10)),
    );
    final body = storeV2Body(
      pos: vat,
      lines: [line(100)],
      payments: [PaymentLine(method: PayMethod.cash, amount: 40), transfer],
      appUuid: 'u',
      now: DateTime(2026, 11, 11),
    );
    expect(body['paid_by_ids'], '1,6');
    expect(body['all_deposit_bank_reference'], '|,Leumi');
    expect(body['all_deposit_serial_number'], '|,BR-77');
    expect(body['all_deposit_date'], '|,10-11-2026');
    expect(body['all_deposit_amount'], '|,60.0');
    expect(body['customer_id'], 1, reason: 'walk-in: the POS default customer');
  });

  test('payments that do not add up to the total are refused', () {
    expect(
        () => storeV2Body(
              pos: vat,
              lines: [line(100)],
              payments: [PaymentLine(method: PayMethod.cash, amount: 90)],
              appUuid: 'u',
              now: DateTime(2026, 11, 11),
            ),
        throwsArgumentError);
  });

  test('app_uuid is a version 4 UUID', () {
    final u = newAppUuid();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(u), isTrue);
    expect(newAppUuid(), isNot(u));
  });
}
