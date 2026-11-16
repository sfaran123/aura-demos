// Every way money comes in and goes back, end to end against the fake server:
// a new membership, a quick payment and a collection, each by cash, card,
// cheque(s), bank transfer and a split; then cancelling and refunding.
// What is checked each time: what is sent to the server, that the payments add
// up to the document, and what the desk is told.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'collect_test.dart' as col;
import 'new_membership_test.dart' as nm;
import 'sale_credit_test.dart' show options, creditPath, cancelPath, refundPath;
import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<GymStore> boot(WidgetTester t, FakeApi api) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
    await t.pumpAndSettle();
    return store;
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).first);
    await t.pumpAndSettle();
    await t.tap(find.text(text).first);
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.enterText(find.byKey(Key(key)), text);
    await t.pumpAndSettle();
  }

  Future<void> cheque(WidgetTester t, int i) async {
    await type(t, 'chq-number-$i', '5501');
    await type(t, 'chq-bank-$i', '12');
    await type(t, 'chq-branch-$i', '600');
    await type(t, 'chq-account-$i', '123456');
  }

  Future<void> transfer(WidgetTester t, int i) async {
    await type(t, 'tr-ref-$i', 'BR77');
    await type(t, 'tr-bank-$i', '12');
  }

  List<String> paths(FakeApi a) => [for (final p in a.posts) p.$1];
  Map<String, Object?> body(FakeApi a, String path) => a.posts.lastWhere((p) => p.$1 == path).$2;
  List<double> amounts(Map<String, Object?> sale) =>
      [for (final x in '${sale['paid_amount_data']}'.split(',')) double.parse(x)];

  /// The checks that hold for every saved sale: fully paid, and the payments add up.
  void addsUp(Map<String, Object?> sale, double total, String methods) {
    expect(sale['grand_total'], total);
    expect(sale['paid_amount'], total);
    expect(sale['payment_status'], 4, reason: 'paid in full');
    expect(sale['paid_by_ids'], methods);
    expect(amounts(sale).fold(0.0, (a, b) => a + b), closeTo(total, 0.001), reason: 'the payments add up');
    expect('${sale['paid_by_ids']}'.split(',').length, amounts(sale).length);
  }

  /// The server's data with cheques allowed on the 10-entry plan (up to 3).
  FakeApi chequesApi() {
    final a = nm.payingApi();
    final plans = (jsonDecode(jsonEncode(a.responses['/gym/plans'])) as Map).cast<String, dynamic>();
    for (final p in plans['data'] as List) {
      if ((p as Map)['id'] == 11) {
        (p['settings'] as Map)
          ..['allow_cheques'] = true
          ..['max_cheques'] = 3;
      }
    }
    return a..responses['/gym/plans'] = plans;
  }

  // ------------------------------------------------------------ new membership
  group('a new membership (10 entries, 450)', () {
    Future<FakeApi> toPayment(WidgetTester t, {FakeApi? api}) async {
      final a = api ?? nm.payingApi();
      await boot(t, a);
      await tapKey(t, 'tileNewSub');
      await tapText(t, 'Dana Levi');
      await tapKey(t, 'plan-11');
      await tapKey(t, 'toPayment');
      return a;
    }

    Future<Map<String, Object?>> pay(WidgetTester t, FakeApi a) async {
      expect(find.byKey(const Key('payProblem')), findsNothing, reason: 'the payment step is complete');
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(paths(a), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/77/link-sale']);
      expect(find.textContaining('TIN-9001'), findsOneWidget, reason: 'the document on the done screen');
      final sale = body(a, '/sales/store-v2');
      expect(sale['type'], 27, reason: 'a tax invoice-receipt');
      return sale;
    }

    testWidgets('cash', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cash');
      addsUp(await pay(t, a), 450, '1');
    });

    testWidgets('card on the terminal: recorded, nothing charged from the app', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-card');
      final sale = await pay(t, a);
      addsUp(sale, 450, '3');
      expect(sale['all_receipt'], 'other_device');
      expect(body(a, '/gym/memberships').containsKey('card_charge_amount'), isFalse);
    });

    testWidgets('a plan that does not take cheques: no cheque line can be added', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cheque');
      expect(find.byKey(const Key('chq-number-0')), findsNothing);
      expect(find.byKey(const Key('payProblem')), findsOneWidget);
      expect(a.posts, isEmpty);
    });

    testWidgets('one cheque: its details go with the sale', (t) async {
      final a = await toPayment(t, api: chequesApi());
      await tapKey(t, 'add-cheque');
      expect(find.byKey(const Key('payProblem')), findsOneWidget, reason: 'the cheque details are required');
      await tapText(t, 'One cheque');
      await cheque(t, 0);
      final sale = await pay(t, a);
      addsUp(sale, 450, '4');
      expect(sale['all_cheque_number'], '5501');
      expect(sale['all_cheque_bank_name'], '12');
      expect(sale['all_cheque_branch_name'], '600');
      expect(sale['all_cheque_account_number'], '123456');
      expect(sale['all_cheque_amount'], '450.0');
    });

    testWidgets('three cheques: consecutive numbers, a month apart, adding up', (t) async {
      final a = await toPayment(t, api: chequesApi());
      await tapKey(t, 'add-cheque');
      await tapText(t, '3 cheques');
      await cheque(t, 0);
      final sale = await pay(t, a);
      addsUp(sale, 450, '4,4,4');
      expect(sale['all_cheque_number'], '5501,5502,5503');
      expect(amounts(sale), [150.0, 150.0, 150.0]);
      final dates = '${sale['all_cheque_date']}'.split(RegExp(r'[|,]+')).where((x) => x.isNotEmpty).toList();
      expect(dates, hasLength(3));
      expect(dates.toSet(), hasLength(3), reason: 'one cheque a month');
    });

    testWidgets('bank transfer: the reference and the bank go with the sale', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-bank');
      expect(find.byKey(const Key('payProblem')), findsOneWidget, reason: 'the transfer details are required');
      await transfer(t, 0);
      final sale = await pay(t, a);
      addsUp(sale, 450, '6');
      expect(sale.values.map((v) => '$v'), contains('BR77'));
      expect(sale['all_deposit_amount'], '450.0');
    });

    testWidgets('split: part cash, the rest by card', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cash');
      await type(t, 'amount-0', '200');
      expect(find.byKey(const Key('payProblem')), findsOneWidget, reason: '250 is still missing');
      await tapKey(t, 'add-card');
      final sale = await pay(t, a);
      addsUp(sale, 450, '1,3');
      expect(amounts(sale), [200.0, 250.0]);
    });

    testWidgets('split three ways: cash, cheque and transfer', (t) async {
      final a = await toPayment(t, api: chequesApi());
      await tapKey(t, 'add-cash');
      await type(t, 'amount-0', '100');
      await tapKey(t, 'add-cheque');
      await type(t, 'amount-1', '150');
      await tapText(t, 'One cheque');
      await cheque(t, 1);
      await tapKey(t, 'add-bank');
      await transfer(t, 2);
      final sale = await pay(t, a);
      addsUp(sale, 450, '1,4,6');
      expect(amounts(sale), [100.0, 150.0, 200.0]);
    });

    testWidgets('paying too little or too much is stopped before anything is saved', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cash');
      await type(t, 'amount-0', '400');
      expect(find.byKey(const Key('payProblem')), findsOneWidget);
      await type(t, 'amount-0', '500');
      expect(find.byKey(const Key('payProblem')), findsOneWidget);
      expect(a.posts, isEmpty);
    });

    testWidgets('an exempt dealer: a receipt (type 3) with no VAT, by transfer', (t) async {
      final api = nm.payingApi()
        ..responses['/gym/pos-settings'] = {
          'data': {...(nm.posSettings['data'] as Map), 'business_type': 1}
        };
      final a = await toPayment(t, api: api);
      await tapKey(t, 'add-bank');
      await transfer(t, 0);
      expect(find.byKey(const Key('payProblem')), findsNothing);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      final sale = body(a, '/sales/store-v2');
      expect(sale['type'], 3, reason: 'a receipt, never a tax invoice');
      expect(sale['total_tax'], 0);
      addsUp(sale, 450, '6');
    });
  });

  // ------------------------------------------------------------- quick payment
  group('a quick payment, walk-in (2 shakes and a water, 53)', () {
    Future<FakeApi> toPayment(WidgetTester t) async {
      final a = nm.payingApi();
      await boot(t, a);
      await tapKey(t, 'tileQuickPay');
      await tapKey(t, 'walkIn');
      await tapKey(t, 'item-21');
      await tapKey(t, 'item-21');
      await tapKey(t, 'item-20');
      await tapKey(t, 'itemsToPayment');
      return a;
    }

    Future<Map<String, Object?>> pay(WidgetTester t, FakeApi a) async {
      expect(find.byKey(const Key('payProblem')), findsNothing);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(paths(a), ['/sales/store-v2'], reason: 'one sale, nothing else');
      expect(find.textContaining('TIN-9001'), findsOneWidget);
      return body(a, '/sales/store-v2');
    }

    testWidgets('cash', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cash');
      addsUp(await pay(t, a), 53, '1');
    });

    testWidgets('card on the terminal (a walk-in has no saved card)', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-card');
      expect(find.byKey(const Key('savedCardChip')), findsNothing);
      final sale = await pay(t, a);
      addsUp(sale, 53, '3');
      expect(sale['all_receipt'], 'other_device');
    });

    testWidgets('bank transfer', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-bank');
      await transfer(t, 0);
      final sale = await pay(t, a);
      addsUp(sale, 53, '6');
      expect(sale.values.map((v) => '$v'), contains('BR77'));
    });

    testWidgets('split: cash and card', (t) async {
      final a = await toPayment(t);
      await tapKey(t, 'add-cash');
      await type(t, 'amount-0', '20');
      await tapKey(t, 'add-card');
      final sale = await pay(t, a);
      addsUp(sale, 53, '1,3');
      expect(amounts(sale), [20.0, 33.0]);
    });
  });

  // ---------------------------------------------------------------- collection
  group('collecting a manual monthly payment', () {
    FakeApi manualDue() {
      final a = col.api();
      final m = ((a.responses['/gym/memberships'] as Map)['data'] as List)[0] as Map;
      m['failed_payments'] = <Object?>[];
      m['auto_payment_type'] = 'manual';
      ((m['items'] as List)[0] as Map)['next_payment_date'] = '2026-11-08';
      return a;
    }

    for (final method in ['cash', 'card', 'cheque', 'bank']) {
      testWidgets('by $method: recorded for the month that is due', (t) async {
        final a = manualDue();
        await boot(t, a);
        await t.tap(find.byKey(const Key('navCollect')));
        await t.pumpAndSettle();
        await tapKey(t, 'collect-next-5');
        await tapKey(t, 'collectWith-$method');
        if (method == 'card') await tapKey(t, 'cardTerminal');
        if (method == 'cheque') {
          await cheque(t, 0);
          await tapKey(t, 'detailsSave');
        }
        if (method == 'bank') {
          await transfer(t, 0);
          await tapKey(t, 'detailsSave');
        }
        final sent = body(a, '/gym/memberships/5/collect');
        expect(sent['method'], method);
        expect(sent['due_date'], '2026-11-08');
        if (method == 'cheque') expect(sent['cheque_number'], '5501');
        if (method == 'bank') expect(sent['transfer_reference'], 'BR77');
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'not left loading');
        expect(find.textContaining('Received · TIN-900'), findsOneWidget);
      });
    }

    testWidgets('a cheque without its details cannot be saved', (t) async {
      final a = manualDue();
      await boot(t, a);
      await t.tap(find.byKey(const Key('navCollect')));
      await t.pumpAndSettle();
      await tapKey(t, 'collect-next-5');
      await tapKey(t, 'collectWith-cheque');
      expect(t.widget<FilledButton>(find.byKey(const Key('detailsSave'))).onPressed, isNull);
      expect(a.posts, isEmpty);
    });
  });

  // ------------------------------------------------- cancelling and refunding
  group('cancelling and refunding a document', () {
    Future<void> openCredit(WidgetTester t, FakeApi api) async {
      await boot(t, api);
      await tapKey(t, 'homeSales');
      await tapKey(t, 'sale-500');
      await tapKey(t, 'creditReceipt');
    }

    Future<void> confirm(WidgetTester t) async {
      await type(t, 'creditReason', 'Customer asked');
      await tapKey(t, 'creditConfirm');
      await tapKey(t, 'creditConfirmYes');
    }

    for (final (method, chip) in [('cash', 'refund-cash'), ('bank', 'refund-bank'), ('card', 'refund-card')]) {
      testWidgets('a tax invoice-receipt, money back by $method: a credit and a minus receipt', (t) async {
        final api = serverApi()..responses[creditPath] = options();
        api.postHandlers[cancelPath] = (b) => {
              'data': {
                'sale': {'id': 500, 'reference_no': 'TIR-1001', 'cancelled': true},
                'document': {'id': 900, 'reference_no': 'TIC-90003', 'grand_total': -199},
                'receipt': {'id': 901, 'reference_no': 'R-50007', 'grand_total': -199},
              }
            };
        await openCredit(t, api);
        await tapKey(t, 'creditMode-cancel');
        expect(
            find.textContaining('A credit invoice is issued for the whole amount and a minus receipt'), findsWidgets);
        await tapKey(t, chip);
        await confirm(t);
        expect(body(api, cancelPath)['method'], method);
        expect(find.text('TIR-1001 cancelled · Credit invoice TIC-90003 · Minus receipt R-50007'), findsOneWidget);
      });
    }

    testWidgets('a tax invoice-receipt cancelled, but the server made no minus receipt: said clearly', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'reference_no': 'TIR-1001', 'cancelled': true},
              'document': {'id': 900, 'reference_no': 'TIC-90003'},
            }
          };
      await openCredit(t, api);
      await tapKey(t, 'creditMode-cancel');
      await tapKey(t, 'refund-cash');
      await confirm(t);
      expect(find.textContaining('Credit invoice TIC-90003'), findsOneWidget);
      expect(find.textContaining('the server did not return a minus receipt'), findsOneWidget);
      expect(find.byKey(const Key('cardProblemOk')), findsOneWidget, reason: 'stays until it is read');
    });

    testWidgets('an unpaid tax invoice: a credit only, no money to give back', (t) async {
      final o = options(methods: const [], card: null);
      (o['data'] as Map)['paid_amount'] = 0;
      final api = serverApi()..responses[creditPath] = o;
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'cancelled': true},
              'document': {'reference_no': 'TIC-90010'},
            }
          };
      await openCredit(t, api);
      expect(find.byKey(const Key('refund-cash')), findsNothing);
      await confirm(t);
      expect(body(api, cancelPath).containsKey('method'), isFalse);
      expect(find.text('TIR-1001 cancelled · Credit invoice TIC-90010'), findsOneWidget);
    });

    testWidgets('a receipt (exempt dealer): cancelled with a minus receipt', (t) async {
      final api = serverApi()..responses[creditPath] = options(mode: 'direct', methods: const [], card: null);
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'cancelled': true},
              'document': null,
              'receipt': 'R-50008',
            }
          };
      await openCredit(t, api);
      expect(find.text('The receipt is cancelled and a minus receipt is issued for the whole amount.'), findsWidgets);
      await confirm(t);
      expect(find.text('TIR-1001 cancelled · Minus receipt R-50008'), findsOneWidget);
    });

    testWidgets('a receipt cancelled, but the server made no minus receipt: said clearly', (t) async {
      final api = serverApi()..responses[creditPath] = options(mode: 'direct', methods: const [], card: null);
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'cancelled': true},
              'document': null,
            }
          };
      await openCredit(t, api);
      await confirm(t);
      expect(find.textContaining('the server did not return a minus receipt'), findsOneWidget);
      expect(find.textContaining('credit invoice'), findsNothing, reason: 'a receipt needs no credit invoice');
    });

    testWidgets('refund to the card, the whole amount: a credit and a minus receipt', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      api.postHandlers[refundPath] = (b) => {
            'data': {'sale_id': 500, 'amount': 199, 'tic': 'TIC-90004', 'receipt': 'R-50006'}
          };
      await openCredit(t, api);
      await tapKey(t, 'creditFull');
      await confirm(t);
      expect(body(api, refundPath)['amount'], 199.0);
      expect(find.text('${money(199)} refunded to the card · Credit invoice TIC-90004 · Minus receipt R-50006'),
          findsOneWidget);
    });

    testWidgets('refund to the card, but the server made no documents: said clearly', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      api.postHandlers[refundPath] = (b) => {
            'data': {'sale_id': 500, 'amount': 199}
          };
      await openCredit(t, api);
      await confirm(t);
      expect(find.textContaining('the server did not return a credit invoice'), findsOneWidget);
      expect(find.textContaining('the server did not return a minus receipt'), findsOneWidget);
    });

    testWidgets('a reason is required before anything is cancelled', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      await openCredit(t, api);
      expect(t.widget<FilledButton>(find.byKey(const Key('creditConfirm'))).onPressed, isNull);
      expect(api.posts, isEmpty);
    });
  });
}
