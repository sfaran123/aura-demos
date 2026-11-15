import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/checkout.dart';
import 'package:aura_gym/src/domain/card_entry.dart' show cardChargeText;
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today, products;
import 'support/fake_api.dart';

/// Z Credit's answer for an approved saved-card charge (the fake server's).
const zReceipt = '{"ReturnCode":0,"ReturnMessage":"OK","ReferenceNumber":"Z-778","ApprovalNumber":"0123456"}';

/// Answers like GymController::storeMembership (same format as GET gym/memberships).
Object? Function(Map<String, Object?>) membershipStore({int id = 77, bool duplicate = false}) => (body) {
      final recurring = body['plan_id'] == 10;
      final start = DateTime.parse(body['start_date'] as String);
      String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      return {
        // With card_charge_amount the server charged the saved card first.
        if (body['card_charge_amount'] != null)
          'card_charge': {
            'data': {'id': 3, 'status': 'approved', 'amount': body['card_charge_amount']},
            'receipt': zReceipt,
          },
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

  group('a new membership on the saved card', () {
    /// The server has a Z Credit terminal (card_tokens); it answers quick-payment charges too.
    FakeApi cardApi() => payingApi()
      ..responses['/gym/pos-settings'] = {
        'data': {...(posSettings['data'] as Map), 'card_tokens': true}
      }
      ..postHandlers['/gym/card-charges'] = ((b) => {
            'data': {'id': 9, 'status': 'approved', 'amount': b['amount'], 'payments': b['payments']},
            'receipt': zReceipt,
            'duplicate': false,
          })
      ..postHandlers['/gym/card-charges/link'] = ((b) => {'data': {'id': 9}, 'sale': {'id': 501}});

    bool canGoOn(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('toSummary'))).onPressed != null;

    /// Regular ([installments] 1) or installments, on the first card line.
    Future<void> chooseHow(WidgetTester t, int installments) async {
      if (installments <= 1) return tapKey(t, 'payRegular-0');
      await tapKey(t, 'payInstallments-0');
      await t.enterText(find.byKey(const Key('paymentsCount-0')), '$installments');
      await t.pumpAndSettle();
    }

    /// Home -> New membership -> [member] -> punch card -> card line.
    Future<void> toCardLine(WidgetTester t, {String member = 'Dana Levi'}) async {
      await tapKey(t, 'tileNewSub');
      await t.ensureVisible(find.text(member).first);
      await t.pumpAndSettle();
      await t.tap(find.text(member).first);
      await t.pumpAndSettle();
      await tapKey(t, 'plan-11');
      await tapKey(t, 'toPayment');
      await tapKey(t, 'add-card');
    }

    /// ... -> [saved] card, regular or [installments] (else the terminal) -> summary.
    Future<void> toSavedCardSummary(WidgetTester t, {bool saved = true, int installments = 1}) async {
      await toCardLine(t);
      expect(find.byKey(const Key('savedCardChip')), findsOneWidget);
      // A member with a saved card: the card line starts on the saved card.
      expect(find.textContaining('The saved card is charged 450'), findsOneWidget);
      // Regular or installments is asked, never assumed.
      expect(find.text('Choose: regular payment or installments'), findsOneWidget);
      expect(canGoOn(t), isFalse);
      if (saved) {
        await chooseHow(t, installments);
        expect(canGoOn(t), isTrue);
      }
      if (!saved) {
        final terminal = find.text('Payment terminal');
        await t.ensureVisible(terminal);
        await t.pumpAndSettle();
        await t.tap(terminal);
        await t.pumpAndSettle();
        expect(find.textContaining('The saved card is charged'), findsNothing);
      }
      await tapKey(t, 'toSummary');
    }

    testWidgets('the card is charged with the membership, then the sale carries the Z Credit answer', (t) async {
      final api = cardApi();
      await boot(t, api);
      await toSavedCardSummary(t);
      expect(find.textContaining('saved card 4815'), findsOneWidget);
      await tapKey(t, 'confirm');

      expect(paths(api), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/77/link-sale']);
      final sale = body(api, '/sales/store-v2');
      final m = body(api, '/gym/memberships');
      expect(m['card_charge_amount'], 450.0);
      expect(m['app_uuid'], sale['app_uuid'], reason: 'the sale app_uuid is the charge key');
      expect(sale['paid_by_ids'], '3');
      expect(sale['all_receipt'], zReceipt, reason: 'the card payment keeps Z Credit answer, as the web saves it');
      expect(sale['all_transaction_reference'], 'Z-778');
      expect(find.textContaining('TIN-9001'), findsOneWidget, reason: 'on the done screen');
    });

    testWidgets('the terminal, when the desk picks it: no card charge asked', (t) async {
      final api = cardApi();
      await boot(t, api);
      await toSavedCardSummary(t, saved: false);
      await tapKey(t, 'confirm');
      expect(paths(api), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/77/link-sale']);
      expect(body(api, '/gym/memberships').containsKey('card_charge_amount'), isFalse);
      expect(body(api, '/sales/store-v2')['all_receipt'], 'other_device');
    });

    testWidgets('declined: an alert, no membership, no tax invoice; the desk stays and can pick another method',
        (t) async {
      final api = cardApi()
        ..postErrors['/gym/memberships'] =
            AuraApiException(AuraErrorKind.server, 'HTTP 422: card_declined: Insufficient funds');
      await boot(t, api);
      await toSavedCardSummary(t);
      await tapKey(t, 'confirm');

      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget, reason: 'an alert the desk must close');
      expect(find.text('The card was not charged'), findsOneWidget);
      expect(find.textContaining('No membership was opened and no invoice was issued'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');
      expect(find.text('The card was not approved: Insufficient funds'), findsOneWidget, reason: 'also on the summary');
      expect(paths(api), ['/gym/memberships'], reason: 'no sale (no TIN), no link');

      // Not charged: the desk may go back and pay another way.
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('toSummary')), findsOneWidget);
    });

    testWidgets('no clear answer from Z Credit: an alert, nothing created', (t) async {
      final api = cardApi()
        ..postErrors['/gym/memberships'] = AuraApiException(AuraErrorKind.server, 'HTTP 409: charge_unknown');
      await boot(t, api);
      await toSavedCardSummary(t);
      await tapKey(t, 'confirm');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(find.textContaining('Check in Z Credit'), findsWidgets);
      expect(paths(api), ['/gym/memberships']);
    });

    testWidgets('charged, the sale fails: no way back, the retry saves it without charging again', (t) async {
      final api = cardApi()..postErrors['/sales/store-v2'] = AuraApiException(AuraErrorKind.server, 'HTTP 500');
      await boot(t, api);
      await toSavedCardSummary(t);
      await tapKey(t, 'confirm');
      expect(find.textContaining('the card will not be charged again'), findsOneWidget);

      // Back is blocked: the charge must end in a document.
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('confirm')), findsOneWidget);
      expect(find.text('The card was already charged. Finish here to save the document.'), findsOneWidget);

      api.postErrors.remove('/sales/store-v2');
      await tapKey(t, 'confirm');
      expect(paths(api).where((p) => p == '/gym/memberships').length, 1, reason: 'charged once, one membership');
      expect(body(api, '/sales/store-v2')['all_receipt'], zReceipt);
      expect(find.textContaining('TIN-9001'), findsOneWidget);
    });

    testWidgets('a monthly plan: the first payment is charged on the saved card too', (t) async {
      final api = cardApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
      final (store, _, _) = await boot(t, api);
      store.settings.registrationFeeProductId = '30';
      await tapKey(t, 'tileNewSub');
      await t.ensureVisible(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await tapKey(t, 'plan-10');
      await tapKey(t, 'toPayment');
      await tapKey(t, 'add-card');
      expect(find.byKey(const Key('savedCardChip')), findsOneWidget);
      expect(find.textContaining('The saved card is charged 498'), findsOneWidget,
          reason: 'first month + prepaid last month + sign-up fee');
      expect(find.byKey(const Key('payKind-0')), findsOneWidget, reason: 'asked for a monthly first payment too');
      await chooseHow(t, 1);
      final manual = find.text(RecurringMethod.manual.label);
      await t.scrollUntilVisible(manual, 200, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(manual);
      await t.pumpAndSettle();
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');

      expect(paths(api), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/78/link-sale']);
      final sale = body(api, '/sales/store-v2');
      expect(body(api, '/gym/memberships')['card_charge_amount'], 498.0);
      expect(sale['all_receipt'], zReceipt);
      expect(sale['all_transaction_reference'], 'Z-778');
    });

    testWidgets('"Add card" closed without saving: the payment step is blocked', (t) async {
      final api = cardApi();
      await boot(t, api);
      await toCardLine(t, member: 'Avi Cohen');
      expect(find.byKey(const Key('savedCardChip')), findsNothing, reason: 'Avi has no saved card');
      expect(find.byKey(const Key('payProblem')), findsNothing, reason: 'the terminal, until a card is asked for');

      await tapKey(t, 'addCardChip');
      Navigator.of(t.element(find.byKey(const Key('cardNumber')))).pop(); // closed, nothing saved
      await t.pumpAndSettle();

      expect(find.text("Save the member's card"), findsOneWidget, reason: 'blocked');
      expect(find.text('The card was not saved. Save a card, or pick the payment terminal.'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('toSummary'))).onPressed, isNull);

      // Only an explicit choice of the terminal unblocks it.
      final terminal = find.text('Payment terminal');
      await t.ensureVisible(terminal);
      await t.pumpAndSettle();
      await t.tap(terminal);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(const Key('toSummary'))).onPressed, isNotNull);
      expect(api.posts, isEmpty);
    });

    testWidgets('installments: the number is asked, the split shown, sent with the charge', (t) async {
      final api = cardApi();
      await boot(t, api);
      await toCardLine(t);
      await tapKey(t, 'payInstallments-0');
      expect(find.text('The number of installments must be 2 or more'), findsOneWidget, reason: 'no number yet');
      expect(canGoOn(t), isFalse);
      await t.enterText(find.byKey(const Key('paymentsCount-0')), '1');
      await t.pumpAndSettle();
      expect(canGoOn(t), isFalse, reason: '1 is not installments');
      await t.enterText(find.byKey(const Key('paymentsCount-0')), '4');
      await t.pumpAndSettle();
      expect(canGoOn(t), isTrue);
      // 450 in 4: 112.50 each (as the web splits it).
      expect(find.text('First payment 112.50 ₪, then 3 payments of 112.50 ₪'), findsOneWidget);
      expect(find.textContaining('The saved card is charged 450 ₪ in 4 installments'), findsOneWidget);
      await tapKey(t, 'toSummary');
      expect(find.textContaining('4 installments'), findsWidgets, reason: 'on the summary');
      await tapKey(t, 'confirm');

      final m = body(api, '/gym/memberships');
      expect(m['card_charge_amount'], 450.0);
      expect(m['card_charge_payments'], 4);
      expect(find.textContaining('TIN-9001'), findsOneWidget);
    });

    testWidgets('regular: sent as one payment', (t) async {
      final api = cardApi();
      await boot(t, api);
      await toSavedCardSummary(t);
      expect(find.textContaining('regular payment'), findsWidgets, reason: 'on the summary');
      await tapKey(t, 'confirm');
      expect(body(api, '/gym/memberships')['card_charge_payments'], 1);
    });

    testWidgets('quick payment on the saved card: asked, charged first, then the sale, then the link', (t) async {
      final api = cardApi();
      await boot(t, api);
      await tapKey(t, 'tileQuickPay');
      await t.ensureVisible(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await tapKey(t, 'item-21');
      await tapKey(t, 'item-20');
      await tapKey(t, 'itemsToPayment');
      await tapKey(t, 'add-card');
      expect(find.byKey(const Key('savedCardChip')), findsOneWidget, reason: 'quick payment: the saved card too');
      expect(canGoOn(t), isFalse, reason: 'regular or installments not chosen yet');
      await chooseHow(t, 2);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');

      expect(paths(api), ['/gym/card-charges', '/sales/store-v2', '/gym/card-charges/link']);
      final sale = body(api, '/sales/store-v2');
      final charge = body(api, '/gym/card-charges');
      expect(charge['customer_id'], 7);
      expect(charge['payments'], 2);
      expect(charge['amount'], sale['grand_total']);
      expect(charge['app_uuid'], sale['app_uuid']);
      expect(body(api, '/gym/card-charges/link'), {'app_uuid': sale['app_uuid']});
      expect(sale['all_receipt'], zReceipt);
      expect(find.textContaining('TIN-9001'), findsOneWidget);
    });

    testWidgets('quick payment declined: an alert, no sale', (t) async {
      final api = cardApi()
        ..postErrors['/gym/card-charges'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_declined: Do not honor');
      await boot(t, api);
      await tapKey(t, 'tileQuickPay');
      await t.ensureVisible(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await tapKey(t, 'item-21');
      await tapKey(t, 'itemsToPayment');
      await tapKey(t, 'add-card');
      await chooseHow(t, 1);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(find.textContaining('No invoice was issued'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');
      expect(paths(api), ['/gym/card-charges'], reason: 'no sale');
    });
  });

  test('desk texts for refused charges', () {
    expect(cardChargeText('HTTP 422: card_declined: Expired card'), 'The card was not approved: Expired card');
    expect(cardChargeText('HTTP 409: charge_unknown'), startsWith('No clear answer'));
    expect(cardChargeText('HTTP 409: already_charged'), startsWith('A card was already charged'));
    expect(cardChargeText('HTTP 500'), isNull);
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

  testWidgets('monthly plan on a picked start day: the months count from it', (t) async {
    final api = payingApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
    final (store, _, _) = await boot(t, api);
    store.settings.registrationFeeProductId = '30';
    await tapKey(t, 'tileNewSub');
    await t.ensureVisible(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await tapKey(t, 'plan-10');

    // The options are below the plans: built once scrolled to.
    await t.scrollUntilVisible(find.byKey(const Key('startOptions')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    final other = find.descendant(of: find.byKey(const Key('startOptions')), matching: find.text(StartOption.date.label));
    await t.ensureVisible(other);
    await t.pumpAndSettle();
    await t.tap(other);
    await t.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    expect(picker, findsOneWidget);
    // today is 11 Nov: the earliest start for a monthly plan is 12 Oct, so the picker opens on November.
    await t.tap(find.descendant(of: picker, matching: find.text('2')).first);
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: picker, matching: find.byType(TextButton)).last); // OK
    await t.pumpAndSettle();

    expect(find.descendant(of: find.byKey(const Key('startOptions')), matching: find.text(fmtDate(DateTime(2026, 11, 2)))),
        findsOneWidget);
    expect(find.byKey(const Key('nextChargeHint')), findsOneWidget);
    expect(find.textContaining(fmtDate(DateTime(2026, 12, 2))), findsOneWidget);

    await tapKey(t, 'toPayment');
    await tapKey(t, 'add-card');
    final manual = find.text(RecurringMethod.manual.label);
    await t.ensureVisible(manual);
    await t.pumpAndSettle();
    await t.tap(manual);
    await t.pumpAndSettle();
    await tapKey(t, 'toSummary');
    expect(find.textContaining(fmtDate(DateTime(2026, 11, 2)), findRichText: true), findsWidgets,
        reason: 'the summary shows the picked start');
    await tapKey(t, 'confirm');

    expect(body(api, '/gym/memberships')['start_date'], '2026-11-02');
  });

  testWidgets('the start can be changed on the summary, until the membership is opened', (t) async {
    final api = payingApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
    final (store, _, _) = await boot(t, api);
    store.settings.registrationFeeProductId = '30';
    await toSummary(t, '10', method: 'card');
    expect(find.text(fmtDate(DateTime(2026, 11, 11))), findsOneWidget, reason: 'today by default');
    expect(find.text(fmtDate(DateTime(2026, 12, 11))), findsOneWidget, reason: 'next monthly payment');

    await tapKey(t, 'changeStart');
    final picker = find.byType(DatePickerDialog);
    expect(picker, findsOneWidget);
    await t.tap(find.descendant(of: picker, matching: find.text('2')).first);
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: picker, matching: find.byType(TextButton)).last); // OK
    await t.pumpAndSettle();
    expect(find.text(fmtDate(DateTime(2026, 11, 2))), findsOneWidget);
    expect(find.text(fmtDate(DateTime(2026, 12, 2))), findsOneWidget);

    await tapKey(t, 'confirm');
    expect(body(api, '/gym/memberships')['start_date'], '2026-11-02');
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
    // The saved sale can be cancelled or refunded on the server, as the web (sale_credit_test.dart).
    await tapKey(t, 'viewReceipt');
    expect(find.byKey(const Key('receiptCard')), findsOneWidget);
    expect(find.byKey(const Key('creditReceipt'), skipOffstage: false), findsOneWidget);
  });
}
