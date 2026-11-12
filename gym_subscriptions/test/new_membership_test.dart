import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today, products;
import 'support/fake_api.dart';

/// Answers like GymController::storeMembership (same format as GET gym/memberships).
Object? Function(Map<String, Object?>) membershipStore({int id = 77, bool duplicate = false}) => (body) {
      final recurring = body['plan_id'] == 10;
      final start = DateTime.parse(body['start_date'] as String);
      String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      return {
        'duplicate': duplicate,
        'data': {
          'id': id,
          'reference_no': '1006',
          'customer_id': body['customer_id'],
          'customer_name': 'Dana Levi',
          'status': 'active',
          'is_cancelled': false,
          'auto_payment_type': body['recurring_method'] ?? 'credit_card',
          'has_card_token': false,
          'grand_total': recurring ? 199 : 450,
          'discount_percent': body['discount_percent'],
          'registration_fee': recurring ? 100 : 0,
          'prepaid_amount': recurring ? 199 : 0,
          'entries_remaining': recurring ? null : 10,
          'created_at': '2026-11-11 10:00:00',
          'items': [
            {
              'id': 900,
              'product_id': body['plan_id'],
              'product_name': recurring ? 'Monthly' : '10 entries',
              'total': recurring ? 199 : 450,
              'start_date': d(start),
              'end_date': recurring
                  ? d(DateTime(start.year + 100, start.month, start.day))
                  : d(DateTime(start.year, start.month + 3, start.day)),
              'periods': recurring ? 0 : 3,
              'period_unit': 'month',
              'next_payment_date': recurring ? d(DateTime(start.year, start.month + 1, start.day)) : null,
              'payments_total': recurring ? 1200 : 1,
              'payments_done': 0,
            }
          ],
          'sale': null,
          'failed_payments': [],
          'freezes': [],
          'frozen_until': null,
        },
      };
    };

/// GET gym/pos-settings of a VAT business (tax invoice-receipts, type 27).
final posSettings = {
  'data': {
    'business_type': 0,
    'decimal': 2,
    'customer_id': 1,
    'warehouse_id': 2,
    'biller_id': 3,
    'product_number': 4,
    'user_id': 5,
  }
};

/// Answers like sales/store-v2 ({data: sale, latestSaleInfo}).
Object? Function(Map<String, Object?>) saleStore({int id = 501, String ref = 'TIN-9001'}) => (body) => {
      'data': {'id': id, 'reference_no': ref, 'grand_total': body['grand_total']},
      'latestSaleInfo': null,
    };

/// Answers like GymController::linkSale.
Object? Function(Map<String, Object?>) linkStore({String ref = 'TIN-9001'}) => (body) => {
      'data': null,
      'duplicate': false,
      'sale': {'id': body['sale_id'] ?? 501, 'reference_no': ref},
    };

FakeApi payingApi() => serverApi()
  ..responses['/gym/pos-settings'] = posSettings
  ..responses['/sales/getproduct-v2'] = [
    ...products,
    {'id': 30, 'name': 'Sign-up fee', 'price': 100, 'tax_rate': 0, 'tax_method': 2},
  ]
  ..postHandlers['/gym/memberships'] = membershipStore()
  ..postHandlers['/sales/store-v2'] = saleStore()
  ..postHandlers['/gym/memberships/77/link-sale'] = linkStore()
  ..postHandlers['/gym/memberships/78/link-sale'] = linkStore();

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(GymStore, FakeApi, AuthController)> boot(WidgetTester t, FakeApi api) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    final auth = AuthController(storage: signedIn(), api: api);
    await t.pumpWidget(AuraGymApp(store: store, auth: auth));
    await t.pumpAndSettle();
    return (store, api, auth);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  /// Home -> New membership -> Dana Levi -> [planId] -> payment by [method]
  /// (and the monthly method, for a monthly plan) -> summary.
  Future<void> toSummary(WidgetTester t, String planId, {String method = 'cash'}) async {
    await tapKey(t, 'tileNewSub');
    await t.ensureVisible(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await tapKey(t, 'plan-$planId');
    await tapKey(t, 'toPayment');
    expect(find.byKey(const Key('payProblem')), findsOneWidget, reason: 'no saved-card line ready-made when signed in');
    await tapKey(t, 'add-$method');
    if (planId == '10') {
      expect(find.text(RecurringMethod.newCard.label), findsNothing, reason: 'no monthly card charge yet');
      final manual = find.text(RecurringMethod.manual.label);
      await t.ensureVisible(manual);
      await t.pumpAndSettle();
      await t.tap(manual);
      await t.pumpAndSettle();
    }
    expect(find.byKey(const Key('payProblem')), findsNothing);
    await tapKey(t, 'toSummary');
  }

  List<String> paths(FakeApi api) => [for (final p in api.posts) p.$1];
  Map<String, Object?> body(FakeApi api, String path) => api.posts.lastWhere((p) => p.$1 == path).$2;

  testWidgets('punch card by cash: membership, then the POS sale, then the link', (t) async {
    final api = payingApi();
    await boot(t, api);
    await toSummary(t, '11');
    await tapKey(t, 'confirm');

    expect(paths(api), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/77/link-sale']);
    expect(body(api, '/gym/memberships'), {
      'customer_id': 7,
      'plan_id': 11,
      'start_date': '2026-11-11',
      'discount_percent': 0,
      'registration_waived': false,
    });
    final sale = body(api, '/sales/store-v2');
    expect(sale['customer_id'], 7);
    expect(sale['user_id'], '5');
    expect(sale['warehouse_id'], 2);
    expect(sale['biller_id'], 3);
    expect(sale['type'], 27);
    expect(sale['document_status'], 2);
    expect(sale['payment_status'], 4);
    expect(sale['grand_total'], 450);
    expect(sale['paid_amount'], 450);
    expect(sale['paid_by_ids'], '1');
    expect(sale['paid_amount_data'], '450.0');
    expect((sale['app_uuid'] as String).length, 36);
    final line = (sale['product_sale_data'] as List).single as Map;
    expect(line['product_id'], 11);
    expect(line['qty'], 1);
    expect(line['net_unit_price'], 450);
    expect(line['total'], 450);
    expect(body(api, '/gym/memberships/77/link-sale'), {'sale_id': 501});

    expect(find.textContaining('TIN-9001'), findsOneWidget, reason: 'the server document on the done screen');
    expect(find.byKey(const Key('confirm')), findsNothing, reason: 'on the done screen');
  });

  testWidgets('monthly plan: card on the terminal, prepaid month and sign-up fee lines', (t) async {
    final api = payingApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
    final (store, _, _) = await boot(t, api);
    store.settings.registrationFeeProductId = '30';
    await toSummary(t, '10', method: 'card');
    expect(find.textContaining('on the payment terminal'), findsOneWidget);
    await tapKey(t, 'confirm');

    expect(body(api, '/gym/memberships')['recurring_method'], 'manual');
    final sale = body(api, '/sales/store-v2');
    final lines = [for (final l in sale['product_sale_data'] as List) l as Map];
    expect([for (final l in lines) (l['product_id'], l['qty'], l['total'])], [(10, 2, 398), (30, 1, 100)]);
    expect(sale['grand_total'], 498);
    expect(sale['paid_by_ids'], '3');
    expect(sale['all_receipt'], 'other_device');
    expect(body(api, '/gym/memberships/78/link-sale'), {'sale_id': 501});
  });

  testWidgets('no sign-up fee product: stops before anything is saved', (t) async {
    final api = payingApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
    await boot(t, api);
    await toSummary(t, '10', method: 'card');
    await tapKey(t, 'confirm');
    expect(find.textContaining('sign-up fee product'), findsOneWidget);
    expect(api.posts, isEmpty);
  });

  testWidgets('sale fails after the membership: retry does not open it twice, same app_uuid', (t) async {
    final api = payingApi()..postErrors['/sales/store-v2'] = AuraApiException(AuraErrorKind.timeout);
    await boot(t, api);
    await toSummary(t, '11');
    await tapKey(t, 'confirm');
    expect(find.byKey(const Key('confirm')), findsOneWidget, reason: 'still on the summary');
    expect(find.textContaining('payment was not saved'), findsOneWidget);
    final uuid = body(api, '/sales/store-v2')['app_uuid'];

    // The first save did reach the server: it answers 409 and the link finds the sale by app_uuid.
    api.postErrors['/sales/store-v2'] = AuraApiException(AuraErrorKind.server, 'HTTP 409: Duplicate sale ignored');
    await tapKey(t, 'confirm');
    expect(paths(api), [
      '/gym/memberships',
      '/sales/store-v2',
      '/sales/store-v2',
      '/gym/memberships/77/link-sale',
    ]);
    expect(body(api, '/sales/store-v2')['app_uuid'], uuid);
    expect(body(api, '/gym/memberships/77/link-sale'), {'app_uuid': uuid});
    expect(paths(api).where((p) => p == '/gym/memberships'), hasLength(1), reason: 'opened once');
    expect(find.byKey(const Key('confirm')), findsNothing);
  });

  testWidgets('a server error on the membership: nothing saved, the message shows, retry works', (t) async {
    final api = payingApi()
      ..postErrors['/gym/memberships'] =
          AuraApiException(AuraErrorKind.server, 'HTTP 422: Plan not found (an active subscription product is needed)');
    final (store, _, _) = await boot(t, api);
    final subs = store.subscriptions.length, receipts = store.receipts.length;
    await toSummary(t, '11');
    await tapKey(t, 'confirm');
    expect(find.textContaining('Plan not found'), findsOneWidget);
    expect(paths(api), ['/gym/memberships'], reason: 'no sale without a membership');
    expect(store.subscriptions.length, subs);
    expect(store.receipts.length, receipts);

    api.postErrors.clear();
    await tapKey(t, 'confirm');
    expect(find.byKey(const Key('confirm')), findsNothing, reason: 'on the done screen');
    expect(paths(api).last, '/gym/memberships/77/link-sale');
  });

  testWidgets('session expired while saving: back to login, nothing created', (t) async {
    final api = payingApi()..postErrors['/gym/memberships'] = AuraApiException(AuraErrorKind.sessionExpired);
    final (store, _, auth) = await boot(t, api);
    await toSummary(t, '11');
    await tapKey(t, 'confirm');
    expect(auth.stage, AuthStage.login);
    expect(store.receipts, isEmpty, reason: 'signed out: the business data leaves the device');
    expect(paths(api), ['/gym/memberships']);
  });

  testWidgets('exempt dealer: the sale is a receipt (type 3) without VAT, and the app says Receipt', (t) async {
    final api = payingApi()
      ..responses['/gym/pos-settings'] = {
        'data': {...(posSettings['data'] as Map), 'business_type': 1}
      };
    await boot(t, api);
    await tapKey(t, 'tileQuickPay');
    await tapKey(t, 'walkIn');
    await tapKey(t, 'item-21');
    await tapKey(t, 'itemsToPayment');
    await tapKey(t, 'add-cash');
    await tapKey(t, 'toSummary');
    expect(find.textContaining('Receipt'), findsWidgets);
    expect(find.textContaining('Tax invoice'), findsNothing);
    await tapKey(t, 'confirm');

    final sale = body(api, '/sales/store-v2');
    expect(sale['type'], 3, reason: 'a receipt, not a tax invoice-receipt (27)');
    expect([for (final l in sale['product_sale_data'] as List) (l as Map)['tax_rate']], everyElement(0));
    expect(find.textContaining('Tax invoice'), findsNothing);
    await tapKey(t, 'viewReceipt');
    expect(find.textContaining('VAT'), findsNothing);
  });

  testWidgets('quick payment, walk-in: one POS sale to the default customer, no free amount', (t) async {
    final api = payingApi();
    await boot(t, api);
    await tapKey(t, 'tileQuickPay');
    await tapKey(t, 'walkIn');
    expect(find.byKey(const Key('customAmount')), findsNothing);
    await tapKey(t, 'item-21');
    await tapKey(t, 'item-21');
    await tapKey(t, 'item-20');
    await tapKey(t, 'itemsToPayment');
    await tapKey(t, 'add-cash');
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');

    expect(paths(api), ['/sales/store-v2']);
    final sale = body(api, '/sales/store-v2');
    expect(sale['customer_id'], 1, reason: 'the POS default customer');
    expect(
        [for (final l in sale['product_sale_data'] as List) ((l as Map)['product_id'], l['qty'])], [(21, 2), (20, 1)]);
    expect(sale['grand_total'], 53);
    expect(find.textContaining('TIN-9001'), findsOneWidget);
    // The done screen offers sending the new document by SMS or email (the server sends it).
    api.postHandlers['/sales/send-invoice-by-sms'] = (_) => {'success': true, 'message': 'SMS sent successfully'};
    api.postHandlers['/sales/send-invoice-via-mail'] = (_) => true;
    expect(find.byKey(const Key('sendWhatsapp'), skipOffstage: false), findsNothing);
    await t.enterText(find.byKey(const Key('sendPhone')), '054-1112222');
    await tapKey(t, 'sendSms');
    expect(body(api, '/sales/send-invoice-by-sms'), {'id': 501, 'mobile': '0541112222', 'type': 'short'});
    await t.enterText(find.byKey(const Key('sendEmail')), 'guest@example.com');
    await tapKey(t, 'sendEmailGo');
    expect(body(api, '/sales/send-invoice-via-mail')['sale_id'], 501);
    expect(find.text('Sent by SMS · 054-1112222'), findsOneWidget);
    expect(find.text('Sent by Email · guest@example.com'), findsOneWidget);
    // Not connected to the server yet, so not offered: a credit note.
    await tapKey(t, 'viewReceipt');
    expect(find.byKey(const Key('receiptCard')), findsOneWidget);
    expect(find.byKey(const Key('creditReceipt'), skipOffstage: false), findsNothing);
  });
}
