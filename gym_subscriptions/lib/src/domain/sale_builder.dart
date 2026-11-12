// A sale saved on the AURA server exactly as the AURA POS app saves one:
// POST /api/sales/store-v2 with the same body (pos-app order_object_view.dart
// sendSalesInfoWithMultiplePayments), the same line maths (cart_product.dart
// calculateProductPriceByTax) and the same totals (order_totals.dart
// OrderTotals.pos, without an order discount). The web is the reference for
// the maths; nothing here is new maths.

import 'dart:math';

import 'checkout.dart';
import 'models.dart';

/// GET gym/pos-settings: what the POS app reads from sales/get-data-for-pos.
class PosSettings {
  const PosSettings({
    required this.businessType,
    required this.decimal,
    this.customerId,
    this.warehouseId,
    this.billerId,
    this.productNumber,
    this.userId,
    this.cardTokens = false,
  });

  /// 1 = exempt dealer: receipts (type 3), no VAT.
  final int businessType;
  final int decimal;

  /// The POS default customer (a walk-in sale).
  final int? customerId;
  final int? warehouseId;
  final int? billerId;
  final Object? productNumber;
  final int? userId;

  /// A member's card can be saved on the server (POST gym/members/{id}/card):
  /// the Z Credit terminal is set in the web's general settings.
  final bool cardTokens;

  bool get noVat => businessType == 1;

  /// As the POS app: receipt for an exempt dealer, else tax invoice-receipt.
  int get invoiceType => noVat ? 3 : 27;

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  factory PosSettings.fromJson(Map j) => PosSettings(
        businessType: _int(j['business_type']) ?? 0,
        decimal: _int(j['decimal']) ?? 2,
        customerId: _int(j['customer_id']),
        warehouseId: _int(j['warehouse_id']),
        billerId: _int(j['biller_id']),
        productNumber: j['product_number'],
        userId: _int(j['user_id']),
        cardTokens: j['card_tokens'] == true,
      );
}

/// num.roundTo of the POS app (helpers/util.dart).
num _roundTo(num v, int decimals) {
  final factor = pow(10, decimals);
  return (v * factor).round() / factor;
}

/// One product line of the sale.
class SaleLine {
  SaleLine({
    required this.productId,
    required this.title,
    required this.basePrice,
    required this.qty,
    required this.taxRate,
    this.taxMethod,
    this.discountPct = 0,
  });

  /// A line whose price is given with VAT (a price the staff sees, such as the
  /// sign-up fee), as the POS app's price override: turned back into the
  /// product's price basis.
  factory SaleLine.gross({
    required int productId,
    required String title,
    required num grossPrice,
    required num qty,
    required num taxRate,
    int? taxMethod,
  }) =>
      SaleLine(
        productId: productId,
        title: title,
        basePrice: taxMethod == 1 && taxRate > 0 ? grossPrice / (1 + taxRate / 100) : grossPrice,
        qty: qty,
        taxRate: taxRate,
        taxMethod: taxMethod,
      );

  final int productId;
  final String title;

  /// The product's price (before VAT when [taxMethod] is 1, else with VAT).
  final num basePrice;
  final num qty;
  final num taxRate;
  final int? taxMethod;

  /// Line discount in percent, as the POS's percentage line discount.
  final num discountPct;

  /// Per-unit discount (Cart.selectedUpdateDiscountPercentage).
  num get discount => discountPct == 0 ? 0 : basePrice * discountPct / 100;
}

/// CartProduct.calculateProductPriceByTax, without extras or variants.
class LinePrice {
  const LinePrice(this.netUnitPrice, this.netUnitPriceWithTax, this.taxAmount, this.total, this.totalWithoutTax);
  final num netUnitPrice;
  final num netUnitPriceWithTax;
  final num taxAmount;
  final num total;
  final num totalWithoutTax;
}

LinePrice linePrice(SaleLine l, PosSettings pos) {
  final decimal = pos.decimal;
  final taxRate = l.taxRate;
  final netUnit = _roundTo(l.basePrice - l.discount, decimal);

  if (pos.noVat) {
    final total = _roundTo(netUnit * l.qty, decimal);
    return LinePrice(netUnit, netUnit, 0, total, total);
  }

  num netUnitPrice;
  final netUnitPriceWithTax = netUnit;
  num taxAmount;
  if (l.taxMethod == 1) {
    netUnitPrice = netUnit;
    taxAmount = _roundTo(netUnitPrice * l.qty * (taxRate / 100), decimal);
  } else {
    final subUnit = l.basePrice - l.discount;
    netUnitPrice = _roundTo((100 / (100 + taxRate)) * subUnit, decimal);
    taxAmount = _roundTo((subUnit - netUnitPrice) * l.qty, decimal);
  }
  final totalWithoutTax = _roundTo(netUnitPrice * l.qty, decimal);
  final total = _roundTo(netUnitPrice * l.qty + taxAmount, decimal);
  return LinePrice(_roundTo(netUnitPrice, decimal), netUnitPriceWithTax, taxAmount, total, totalWithoutTax);
}

/// OrderTotals.pos with no order discount.
({num linesTotal, num totalTax, num grandTotal}) saleTotals(List<SaleLine> lines, PosSettings pos) {
  num fixed(num v) => double.parse(v.toStringAsFixed(pos.decimal));
  final prices = [for (final l in lines) linePrice(l, pos)];
  final subtotal = fixed(prices.fold<num>(0, (s, p) => s + p.total));
  final lineTax = fixed(prices.fold<num>(0, (s, p) => s + (pos.noVat ? 0 : p.taxAmount)));
  final cents = (subtotal * 100 + 0.5).floor();
  return (linesTotal: fixed(subtotal), totalTax: fixed(lineTax), grandTotal: cents / 100);
}

String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One payments row, as the POS app's partial payment rows.
class _PayRow {
  _PayRow(this.amount, this.paidById);
  final num amount;
  final int paidById;
  String cheque = '';
  String chequeDate = '';
  String chequeBank = '';
  String chequeBranch = '';
  String chequeAccount = '';
  String chequeAmount = '';
  String receipt = '';
  String depositDate = '';
  String depositAmount = '';
  String depositBank = '';
  String depositSerial = '';
}

/// The payment lines as rows: one row per cheque (a month apart, consecutive
/// numbers; the last takes the rounding), the transfer as the web's Deposit,
/// a card as taken on another terminal (the POS manual card, receipt
/// "other_device").
List<_PayRow> _rows(List<PaymentLine> lines, DateTime today) {
  final rows = <_PayRow>[];
  for (final l in lines) {
    switch (l.method) {
      case PayMethod.cash:
        rows.add(_PayRow(round2(l.amount), 1));
      case PayMethod.card:
        rows.add(_PayRow(round2(l.amount), 3)..receipt = 'other_device');
      case PayMethod.cheque:
        final n = l.cheques < 1 ? 1 : l.cheques;
        final each = round2(l.amount / n);
        final first = dateOnly(l.cheque.firstDate ?? today);
        for (var i = 0; i < n; i++) {
          final amount = i == n - 1 ? round2(l.amount - each * (n - 1)) : each;
          rows.add(_PayRow(amount, 4)
            ..cheque = l.cheque.numberAt(i)
            ..chequeDate = _ymd(addMonths(first, i))
            ..chequeBank = l.cheque.bank
            ..chequeBranch = l.cheque.branch
            ..chequeAccount = l.cheque.account
            ..chequeAmount = '$amount');
        }
      case PayMethod.bank:
        rows.add(_PayRow(round2(l.amount), 6)
          ..depositDate = l.transfer.date == null ? '' : _day(l.transfer.date!)
          ..depositAmount = '${round2(l.amount)}'
          ..depositBank = l.transfer.bank
          ..depositSerial = l.transfer.reference);
      case PayMethod.link:
        throw ArgumentError('A payment link is not a payment at the desk');
    }
  }
  return rows;
}

/// The POST sales/store-v2 body. [customerId] null = the POS default customer.
Map<String, Object?> storeV2Body({
  required PosSettings pos,
  required List<SaleLine> lines,
  required List<PaymentLine> payments,
  required String appUuid,
  required DateTime now,
  int? customerId,
  String? note,
}) {
  final totals = saleTotals(lines, pos);
  final rows = _rows(payments, now);
  final paid = round2(rows.fold<double>(0, (s, r) => s + r.amount.toDouble()));
  if ((paid - totals.grandTotal).abs() > 0.001) {
    throw ArgumentError('Payments $paid do not match the total ${totals.grandTotal}');
  }
  String join(String Function(_PayRow r) f, [String sep = '|,']) => rows.map(f).join(sep);

  final invoiceType = pos.invoiceType;
  final productSale = <Map<String, Object?>>[];
  num totalDiscount = 0;
  num qty = 0;
  for (final l in lines) {
    final p = linePrice(l, pos);
    totalDiscount += l.discount * l.qty;
    qty += l.qty;
    productSale.add({
      'product_title': l.title,
      'product_id': l.productId,
      'sale_unit_id': '0',
      'sale_unit': '',
      'product_batch_id': null,
      'net_unit_price': p.netUnitPrice,
      'discount': l.discount * l.qty,
      'discount_type': l.discountPct == 0 ? 'flat' : 'percentage',
      'discount_amount': l.discountPct,
      'tax_rate': pos.noVat ? 0 : l.taxRate,
      'qty': l.qty,
      'tax': p.taxAmount,
      'is_new': true,
      'new_qty': l.qty,
      'total': p.total,
      'printer_id': '',
      'food_variant_price': 0,
      'food_variant_unit_price': 0,
      'extra_price': 0,
      'extra_name': null,
      'extra_qty': null,
      'extra_unit_price': null,
      'food_variant_value': null,
      'note': null,
    });
  }

  return {
    'user_id': pos.userId?.toString(),
    'customer_id': customerId ?? pos.customerId,
    'warehouse_id': pos.warehouseId,
    'biller_id': pos.billerId,
    'product_number': pos.productNumber,
    'sale_status': 1,
    'document_status': (invoiceType == 3 || invoiceType == 27) ? 2 : 1,
    'payment_status': 4,
    'item': qty,
    'total_qty': qty,
    'order_tax_rate': 0,
    'order_tax': 0,
    // Cart.totalsForSave (POS page)
    'total_tax': totals.totalTax,
    'order_discount_type': 'Flat',
    'order_discount_value': 0,
    'order_discount': 0,
    'tax_deduction': 0,
    'rounding_adjustment': null,
    'total_price': totals.linesTotal,
    'grand_total': totals.grandTotal,
    'total_discount': totalDiscount,
    'timestamp': now.toIso8601String(),
    'product_sale_data': productSale,
    'paid_amount_data': join((r) => '${r.amount}', ','),
    'payment_change_data': join((r) => '0', ','),
    'paid_by_ids': join((r) => '${r.paidById}', ','),
    'all_payment_complete': join((r) => '0', ','),
    'all_cheque_number': join((r) => r.cheque, ','),
    'all_cheque_date': join((r) => r.chequeDate),
    'all_cheque_bank_name': join((r) => r.chequeBank),
    'all_cheque_branch_name': join((r) => r.chequeBranch),
    'all_cheque_account_number': join((r) => r.chequeAccount),
    'all_cheque_amount': join((r) => r.chequeAmount),
    'all_bit_details': join((r) => ''),
    'all_receipt': join((r) => r.receipt),
    'all_cibus_order_reference': join((r) => ''),
    'all_cibus_application_code_number': join((r) => ''),
    'all_cibus_card_number': join((r) => ''),
    'all_cibus_company_card_number': join((r) => ''),
    'all_transaction_reference': join((r) => ''),
    'all_deposit_date': join((r) => r.depositDate),
    'all_deposit_amount': join((r) => r.depositAmount),
    'all_deposit_bank_reference': join((r) => r.depositBank),
    'all_depositor_name': join((r) => ''),
    'all_depositor_account_number': join((r) => ''),
    'all_depositor_bank_branch': join((r) => ''),
    'all_deposit_serial_number': join((r) => r.depositSerial),
    'sale_note': (note == null || note.isEmpty) ? null : note,
    'receipt': null,
    'paid_amount': totals.grandTotal,
    'total_paid': totals.grandTotal,
    'type': invoiceType,
    'table_id': null,
    'dispatched_product_ids': null,
    'dispatch_number': null,
    'employee_id': null,
    'sale_id': null,
    'is_draft': null,
    'sale_form': null,
    'selected_sales_input': null,
    'cancel_sale_id': null,
    'cibus': null,
    'app_uuid': appUuid,
    'printer_data': null,
    'number_of_seat': null,
    'tip_paid_by': 'Cash',
  };
}

int _productId(String id, String what) {
  final n = int.tryParse(id);
  if (n == null) throw ArgumentError('$what has no AURA product id ($id)');
  return n;
}

/// A new membership's sale: the plan (two units with the prepaid last month),
/// with the membership discount as a percentage line discount, plus the sign-up
/// fee as its own line (the product chosen in Settings, at the plan's fee, a
/// price with VAT).
List<SaleLine> membershipSaleLines({
  required SubscriptionPlan plan,
  required int discountPct,
  required bool waiveRegistration,
  bool? prepayLastMonth,
  ShopItem? feeProduct,
}) {
  final prepay = prepayLastMonth ?? (plan.isRecurring && plan.prepayLastMonth);
  final lines = [
    SaleLine(
      productId: _productId(plan.id, 'The plan'),
      title: plan.name,
      basePrice: plan.price,
      qty: prepay ? 2 : 1,
      taxRate: plan.taxRate,
      taxMethod: plan.taxMethod,
      discountPct: discountPct,
    ),
  ];
  if (!waiveRegistration && plan.registrationFee > 0) {
    if (feeProduct == null) throw StateError('No sign-up fee product');
    lines.add(SaleLine.gross(
      productId: _productId(feeProduct.id, 'The sign-up fee'),
      title: feeProduct.name,
      grossPrice: plan.registrationFee,
      qty: 1,
      taxRate: feeProduct.taxRate,
      taxMethod: feeProduct.taxMethod,
    ));
  }
  return lines;
}

/// A quick payment's sale: one line per product in the cart, at its price.
List<SaleLine> cartSaleLines(Map<String, int> cart, List<ShopItem> items) => [
      for (final e in cart.entries)
        if (e.value > 0)
          () {
            final i = items.firstWhere((x) => x.id == e.key);
            return SaleLine(
              productId: _productId(i.id, i.name),
              title: i.name,
              basePrice: i.price,
              qty: e.value,
              taxRate: i.taxRate,
              taxMethod: i.taxMethod,
            );
          }(),
    ];

/// A random (version 4) UUID for the sale's app_uuid, as the POS app's Uuid().v4().
String newAppUuid() {
  final r = Random.secure();
  final b = [for (var i = 0; i < 16; i++) r.nextInt(256)];
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
