import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/integration/server_mapping.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'support/fake_api.dart';

final today = DateTime(2026, 11, 11);

// Shaped like the real answers of /api/gym/*, /api/sales/getproduct-v2 and /api/sales.
final members = {
  'data': [
    {'id': 1, 'name': 'Walk-in', 'phone': '000', 'is_walk_in': true},
    {
      'id': 7,
      'name': 'Dana Levi',
      'phone': '050-1234567',
      'email': null,
      'id_number': '123456782',
      'has_saved_card': true,
      'card_last4': '4815',
      'health_declaration_signed_at': '2026-10-01 10:00:00',
      'is_walk_in': false,
      'created_at': '2026-10-01 10:00:00',
    },
    {
      'id': 8,
      'name': 'Avi Cohen',
      'phone': '052-7654321',
      'id_number': null,
      'has_saved_card': false,
      'card_last4': null,
      'health_declaration_signed_at': null,
      'is_walk_in': false,
    },
  ]
};

final plans = {
  'data': [
    {
      'id': 10,
      'name': 'Monthly',
      'price': 199,
      'duration_months': null,
      'settings_saved': true,
      'settings': {
        'plan_type': 'recurring',
        'entries_count': null,
        'registration_fee': 100,
        'commitment_months': 12,
        'cancellation_notice_days': 30,
        'weekly_entry_limit': 0,
        'freeze_days_per_year': 30,
        'max_installments': 1,
        'max_cheques': 0,
        'allow_cash': false,
        'allow_cheques': false,
        'auto_renew': false,
        'online_signup': true,
        'prepay_last_month': true,
        'badge': 'Popular',
      },
    },
    {
      'id': 11,
      'name': '10 entries',
      'price': 450,
      'duration_months': 3,
      'settings_saved': true,
      'settings': {'plan_type': 'punch_card', 'entries_count': 10, 'max_installments': 3},
    },
  ]
};

final memberships = {
  'data': [
    {
      'id': 5,
      'customer_id': 7,
      'customer_name': 'Dana Levi',
      'status': 'payment_failed',
      'auto_payment_type': 'credit_card',
      'discount_percent': 10,
      'prepaid_amount': 199,
      'entries_remaining': null,
      'cancel_requested_at': null,
      'created_at': '2026-09-01 09:00:00',
      'items': [
        {
          'product_id': 10,
          'product_name': 'Monthly',
          'total': 179.1,
          'start_date': '2026-09-01',
          'end_date': '2126-09-01',
          'periods': 0,
          'period_unit': 'month',
          'next_payment_date': '2026-12-01',
          'payments_total': 1200,
          'payments_done': 2,
        }
      ],
      'failed_payments': [
        {'id': 3, 'amount': 179.1, 'message': 'declined', 'date': '2026-11-01 06:00:00'}
      ],
      'freezes': [
        {'id': 1, 'start_date': '2026-03-01', 'end_date': '2026-03-10', 'reason': null}
      ],
      'frozen_until': null,
    },
    {
      'id': 6,
      'customer_id': 8,
      'customer_name': 'Avi Cohen',
      'status': 'active',
      'auto_payment_type': 'credit_card',
      'entries_remaining': 7,
      'created_at': '2026-11-01 09:00:00',
      'items': [
        {
          'product_id': 11,
          'product_name': '10 entries',
          'total': 450,
          'start_date': '2026-11-01',
          'end_date': '2027-02-01',
          'periods': 3,
          'period_unit': 'month',
          'next_payment_date': null,
          'payments_total': 1,
          'payments_done': 1,
        }
      ],
      'failed_payments': [],
      'freezes': [],
    },
    {
      // Member and plan deactivated on the web.
      'id': 9,
      'customer_id': 99,
      'customer_name': 'Old Member',
      'customer_phone': '053-0000000',
      'status': 'cancelled',
      'auto_payment_type': 'bank_transfer',
      'items': [
        {
          'product_id': 12,
          'product_name': 'Old plan',
          'total': 150,
          'start_date': '2025-01-01',
          'end_date': '2025-06-01',
          'periods': 5,
          'next_payment_date': '2025-06-01',
          'payments_total': 5,
          'payments_done': 5,
        }
      ],
      'failed_payments': [],
      'freezes': [],
    },
    {'id': 13, 'customer_id': 7, 'status': 'active', 'items': []},
  ]
};

final products = [
  {'id': 10, 'name': 'Monthly', 'price': 199},
  {'id': 20, 'name': 'Water', 'price': 8},
  {'id': 21, 'name': 'Shake', 'price': '22.50'},
];

Map<String, Object?> salesPage(List<Map<String, Object?>> rows, int last) => {
      'data': {'sale_data': rows, 'last_page': last}
    };

final sales1 = salesPage([
  {
    'sale': {
      'id': 500,
      'reference_no': 'TIR-1001',
      'grand_total': 199,
      'created_at': '2026-11-05 10:00:00',
      'subscription_id': 5
    },
    'customer': {'id': 7, 'name': 'Dana Levi'},
    'product_sale': [
      {'product_id': 10}
    ],
    'payment': [
      {'amount': 199, 'paying_method': 'Credit Card'}
    ],
  }
], 2);

final sales2 = salesPage([
  {
    'sale': {'id': 501, 'reference_no': 'TIR-1002', 'grand_total': 30, 'created_at': '2026-11-06 12:00:00'},
    'customer': {'id': 8, 'name': 'Avi Cohen'},
    'product_sale': [
      {'product_id': 20},
      {'product_id': 21}
    ],
    'payment': [
      {'amount': 8, 'paying_method': 'Cash'},
      {'amount': 22, 'paying_method': 'Cheque'}
    ],
  },
  {
    'sale': {'id': 502, 'reference_no': 'TIC-7', 'grand_total': -8, 'created_at': '2026-11-07 12:00:00'},
    'customer': {'id': 8, 'name': 'Avi Cohen'},
    'product_sale': [
      {'product_id': 20}
    ],
    'payment': [
      {'amount': -8, 'paying_method': 'Cash'}
    ],
  },
], 2);

Map<String, Object?> gymSalesPage(List<Map<String, Object?>> docs, int page, int last) =>
    {'data': docs, 'from': '2026-06-01', 'page': page, 'last_page': last, 'total': docs.length};

/// Shaped like GET /api/gym/sales (all staff, six months): the same three documents
/// as sales1/sales2, in two pages, with a cheque due in January.
final gymSales1 = gymSalesPage([
  {
    'id': 500,
    'reference_no': 'TIR-1001',
    'type': 27,
    'is_credit': false,
    'created_at': '2026-11-05 10:00:00',
    'grand_total': 199,
    'customer_id': 7,
    'customer_name': 'Dana Levi',
    'subscription_id': 5,
    'products': [
      {'id': 10, 'name': 'Monthly'}
    ],
    'payments': [
      {'id': 1, 'amount': 199, 'paying_method': 'Credit Card', 'created_at': '2026-11-05 10:00:00'}
    ],
  }
], 1, 2);

final gymSales2 = gymSalesPage([
  {
    'id': 501,
    'reference_no': 'TIR-1002',
    'type': 27,
    'is_credit': false,
    'created_at': '2026-11-06 12:00:00',
    'grand_total': 30,
    'customer_id': 8,
    'customer_name': 'Avi Cohen',
    'subscription_id': null,
    'products': [
      {'id': 20, 'name': 'Water'},
      {'id': 21, 'name': 'Shake'}
    ],
    'payments': [
      {'id': 2, 'amount': 8, 'paying_method': 'Cash', 'created_at': '2026-11-06 12:00:00'},
      {
        'id': 3,
        'amount': 22,
        'paying_method': 'Cheque',
        'created_at': '2026-11-06 12:00:00',
        'cheque_number': '1001',
        'cheque_date': '2027-01-15',
        'cheque_bank': '12',
        'cheque_branch': '600',
      },
    ],
  },
  {
    'id': 502,
    'reference_no': 'TIC-7',
    'type': 10,
    'is_credit': true,
    'created_at': '2026-11-07 12:00:00',
    'grand_total': -8,
    'customer_id': 8,
    'customer_name': 'Avi Cohen',
    'subscription_id': null,
    'products': [
      {'id': 20, 'name': 'Water'}
    ],
    'payments': [
      {'id': 4, 'amount': -8, 'paying_method': 'Cash', 'created_at': '2026-11-07 12:00:00'}
    ],
  },
], 2, 2);

FakeApi serverApi() => FakeApi()
  ..responses.addAll({
    '/gym/members': members,
    '/gym/plans': plans,
    '/gym/memberships': memberships,
    '/sales/getproduct-v2': products,
    '/gym/sales?from=2026-06-01&page=1': gymSales1,
    '/gym/sales?from=2026-06-01&page=2': gymSales2,
    '/sales?page=1': sales1,
    '/sales?page=2': sales2,
  });

MemoryAuthStorage signedIn({int? warehouseId = 2}) => MemoryAuthStorage({
      'workspace': {'domain': 'auratech2.tech', 'company': 'aurademo1'},
      'session': {'token': 't', 'userName': 'admin', 'warehouseId': warehouseId},
    });

void main() {
  setUp(() => L10n.lang = AppLang.en);

  group('mapping', () {
    test('members: walk-in left out, saved card, health declaration', () {
      final c = mapMembers(members);
      expect(c.map((x) => x.name), ['Dana Levi', 'Avi Cohen']);
      expect(c[0].id, '7');
      expect(c[0].savedCardLast4, '4815');
      expect(c[0].idNumber, '123456782');
      expect(c[0].healthDeclared, isTrue);
      expect(c[1].savedCardLast4, isNull);
      expect(c[1].healthDeclared, isFalse);
    });

    test('plans: settings and plan types', () {
      final p = mapPlans(plans);
      expect(p[0].kind, PlanKind.recurring);
      expect(p[0].price, 199);
      expect(p[0].commitMonths, 12);
      expect(p[0].registrationFee, 100);
      expect(p[0].allowCash, isFalse);
      expect(p[0].prepayLastMonth, isTrue);
      expect(p[0].badge, 'Popular');
      expect(p[1].kind, PlanKind.punch);
      expect(p[1].entries, 10);
      expect(p[1].validMonths, 3);
      expect(p[1].maxInstallments, 3);
      expect(p[1].allowCash, isTrue, reason: 'missing setting -> default');
    });

    test('failed tries of one month are one charge: its date, the last amount, all the tries', () {
      final copy = jsonDecode(jsonEncode(memberships)) as Map<String, dynamic>;
      ((copy['data'] as List).first as Map)['failed_payments'] = [
        {'id': 3, 'amount': 179.1, 'message': 'declined', 'date': '2026-10-01 06:00:00'},
        {'id': 4, 'amount': 179.1, 'message': 'insufficient funds', 'date': '2026-10-04 06:00:00'},
        {'id': 5, 'amount': 179.1, 'message': 'declined', 'date': '2026-10-08 06:00:00'},
        {'id': 6, 'amount': 179.1, 'message': 'declined', 'date': '2026-11-01 06:00:00'},
      ];
      final m = mapMemberships(copy, customers: mapMembers(members), plans: mapPlans(plans), today: today);
      final failed = m.charges.where((c) => c.status == ChargeStatus.failed).toList();
      expect(failed.map((c) => c.id), ['failed-3', 'failed-6'], reason: 'October once, November once');
      final october = failed.first;
      expect(october.amount, 179.1, reason: 'the month, not the tries added up');
      expect(october.attempts, 3);
      expect(october.dueDate, DateTime(2026, 10, 1));
      expect(october.monthLabel, '10/2026');
      expect(october.tries.map((x) => x.$2), ['declined', 'insufficient funds', 'declined']);
      expect(october.tries.last.$1, DateTime(2026, 10, 8, 6));
      expect(Charge.fromJson(october.toJson().cast<String, dynamic>()).tries.length, 3, reason: 'kept on the device');
    });

    test('a membership status the app does not know is shown as the server wrote it', () {
      final copy = jsonDecode(jsonEncode(memberships)) as Map<String, dynamic>;
      ((copy['data'] as List).first as Map)['status'] = 'on_hold';
      final m = mapMemberships(copy, customers: mapMembers(members), plans: mapPlans(plans), today: today);
      expect(m.subscriptions.first.serverStatus, 'on_hold');
      expect(m.subscriptions.first.statusText, 'on_hold');
      final known = mapMemberships(memberships, customers: mapMembers(members), plans: mapPlans(plans), today: today);
      expect(known.subscriptions.first.serverStatus, isNull);
      expect(Subscription.fromJson(m.subscriptions.first.toJson()).serverStatus, 'on_hold',
          reason: 'kept on the device');
    });

    test('memberships: statuses, charges, stand-ins for deactivated member/plan', () {
      final c = mapMembers(members), p = mapPlans(plans);
      final m = mapMemberships(memberships, customers: c, plans: p, today: today);
      expect(m.subscriptions.map((s) => s.id), ['5', '6', '9'], reason: 'a membership without products is skipped');

      final dana = m.subscriptions[0];
      expect(dana.status, SubStatus.paymentFailed);
      expect(dana.end, isNull, reason: 'periods 0 = until cancelled');
      expect(dana.monthlyAmount, 179.1);
      expect(dana.recurringMethod, RecurringMethod.savedCard);
      expect(dana.discountPct, 10);
      expect(dana.freezeDaysUsed, 10);
      expect(dana.prepaidAmount, 199);

      final avi = m.subscriptions[1];
      expect(avi.entriesLeft, 7);
      expect(avi.monthlyAmount, isNull, reason: 'paid once');
      expect(avi.recurringMethod, isNull);
      expect(avi.end, DateTime(2027, 2, 1));

      final old = m.subscriptions[2];
      expect(old.status, SubStatus.cancelled);
      expect(c.firstWhere((x) => x.id == '99').name, 'Old Member');
      expect(p.firstWhere((x) => x.id == '12').active, isFalse);

      final failed = m.charges.where((x) => x.status == ChargeStatus.failed).toList();
      expect(failed, hasLength(1));
      expect(failed[0].subscriptionId, '5');
      expect(failed[0].dueDate, DateTime(2026, 11, 1));
      expect(failed[0].amount, 179.1);
      final next = m.charges.where((x) => x.status == ChargeStatus.due).toList();
      expect(next.map((x) => x.subscriptionId), ['5'], reason: 'only running monthly memberships');
      expect(next[0].dueDate, DateTime(2026, 12, 1));
    });

    test('products: plans left out; sales: reference, payment methods, credit', () {
      final items = mapProducts(products, planIds: {'10'});
      expect(items.map((x) => x.name), ['Water', 'Shake']);
      expect(items[1].price, 22.5);

      final r = mapSales(sales2, names: {'20': 'Water', '21': 'Shake'});
      expect(r[0].docNo, 'TIR-1002');
      expect(r[0].description, 'Water, Shake');
      expect(r[0].lines.map((l) => l.method), [PayMethod.cash, PayMethod.cheque]);
      expect(r[0].total, 30);
      expect(r[0].kind, ReceiptKind.quickPay);
      expect(r[1].kind, ReceiptKind.credit);
      expect(mapSales(sales1, names: {})[0].kind, ReceiptKind.subscription);
    });
  });

  Future<(AuthController, FakeApi, GymStore)> boot(WidgetTester t, {FakeApi? api, MemoryAuthStorage? storage}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final a = api ?? serverApi();
    final auth = AuthController(storage: storage ?? signedIn(), api: a);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: auth));
    await t.pumpAndSettle();
    return (auth, a, store);
  }

  testWidgets('signed in: the server data replaces the demo data', (t) async {
    final (_, api, store) = await boot(t);
    expect(api.calls, containsAll(['GET /gym/members', 'GET /gym/plans', 'GET /gym/memberships']));
    expect(api.calls, contains('GET /sales/getproduct-v2?warehouse_id=2'));
    // Six months of sales (from 1 Jun for 11 Nov), all pages, from the gym endpoint.
    expect(api.calls, containsAll(['GET /gym/sales?from=2026-06-01&page=1', 'GET /gym/sales?from=2026-06-01&page=2']));
    expect(api.calls, isNot(contains('GET /gym/sales?from=2026-06-01&page=3')));
    expect(api.calls.where((c) => c.startsWith('GET /sales?')), isEmpty, reason: 'the old list is not needed');

    expect(store.customers.map((c) => c.name), containsAll(['Dana Levi', 'Avi Cohen', 'Old Member']));
    expect(store.customers, hasLength(3));
    expect(store.plans.map((p) => p.name), ['Monthly', '10 entries', 'Old plan']);
    expect(store.items.map((i) => i.name), ['Water', 'Shake']);
    expect(store.receipts.map((r) => r.docNo), ['TIR-1001', 'TIR-1002', 'TIC-7']);
    expect(store.receipts.map((r) => r.kind), [ReceiptKind.subscription, ReceiptKind.quickPay, ReceiptKind.credit]);
    final chq = store.receipts[1].lines.last;
    expect((chq.method, chq.cheque.number, chq.cheque.firstDate), (PayMethod.cheque, '1001', DateTime(2027, 1, 15)));
    expect(store.toCollect.map((c) => c.id), ['failed-3']);

    // Members screen shows them.
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    expect(find.text('Dana Levi'), findsWidgets);

    // Settings: synced.
    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    expect(find.text('Synced at 00:00').evaluate().isNotEmpty || find.textContaining('Synced at').evaluate().isNotEmpty,
        isTrue);
  });

  testWidgets('no warehouse on the user: the POS default warehouse is used', (t) async {
    final api = serverApi()
      ..responses['/sales/get-data-for-pos'] = {
        'data': {
          'pos_setting': {'warehouse_id': 4}
        }
      };
    await boot(t, api: api, storage: signedIn(warehouseId: null));
    expect(api.calls, contains('GET /sales/get-data-for-pos'));
    expect(api.calls, contains('GET /sales/getproduct-v2?warehouse_id=4'));
  });

  testWidgets('a rejected token signs out with a message', (t) async {
    final api = serverApi()..errors['/gym/members'] = AuraApiException(AuraErrorKind.sessionExpired);
    final (auth, _, _) = await boot(t, api: api);
    expect(auth.stage, AuthStage.login);
    expect(find.text('Your session has expired. Please sign in again.'), findsOneWidget);
    expect(auth.workspace?.company, 'aurademo1', reason: 'the business is kept');
  });

  testWidgets('a failed first load: the error with "Try again", never the demo data', (t) async {
    final api = serverApi()..errors['/gym/plans'] = AuraApiException(AuraErrorKind.forbidden, 'No access');
    final (auth, _, store) = await boot(t, api: api);
    expect(auth.stage, AuthStage.signedIn);
    expect(store.customers, isEmpty, reason: 'the demo members are gone, nothing came from the server');
    expect(find.byKey(const Key('navHome')), findsNothing, reason: 'the app does not open on no data');
    expect(find.text("You don't have permission (No access)"), findsOneWidget);

    api.errors.clear();
    await t.tap(find.byKey(const Key('firstSyncRetry')));
    await t.pumpAndSettle();
    expect(store.customers.any((c) => c.name == 'Dana Levi'), isTrue);
    expect(find.byKey(const Key('navHome')), findsOneWidget);
  });

  testWidgets('a failed first load: sign out from the error screen', (t) async {
    final api = serverApi()..errors['/gym/plans'] = AuraApiException(AuraErrorKind.unreachable);
    final (auth, _, _) = await boot(t, api: api);
    await t.tap(find.byKey(const Key('firstSyncSignOut')));
    await t.pumpAndSettle();
    expect(auth.stage, AuthStage.login);
  });

  testWidgets('a later sync that fails keeps the data and shows the error; Sync retries', (t) async {
    final api = serverApi();
    final (_, _, store) = await boot(t, api: api);
    api.errors['/gym/plans'] = AuraApiException(AuraErrorKind.forbidden, 'No access');

    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();
    expect(find.text("You don't have permission (No access)"), findsOneWidget);
    expect(store.customers.any((c) => c.name == 'Dana Levi'), isTrue, reason: 'the loaded data stays');

    api.errors.clear();
    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();
    expect(find.textContaining('Synced at'), findsOneWidget);
  });

  testWidgets('a server error on the sales list is shown, not replaced by another list', (t) async {
    final api = serverApi()..errors['/gym/sales'] = AuraApiException(AuraErrorKind.server, 'HTTP 500');
    await boot(t, api: api);
    expect(api.calls, isNot(contains('GET /sales?page=1')), reason: 'only a missing endpoint (404) falls back');
    expect(find.byKey(const Key('firstSyncError')), findsOneWidget);
  });

  testWidgets('a failed update: a banner on the home screen with the last update; Sync clears it', (t) async {
    final api = serverApi();
    final (_, _, store) = await boot(t, api: api);
    expect(store.lastSynced, isNotNull);
    expect(store.toJson()['lastSynced'], isNotNull, reason: 'kept between runs');
    expect(find.byKey(const Key('syncBanner')), findsNothing);

    api.errors['/gym/members'] = AuraApiException(AuraErrorKind.unreachable);
    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navHome')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('syncBanner')), findsOneWidget);
    expect(find.textContaining('The data is not up to date'), findsOneWidget);
    expect(find.text('No connection to the internet or the server. Check the connection and try again.'), findsWidgets);

    api.errors.clear();
    await t.tap(find.byKey(const Key('syncBannerRetry')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('syncBanner')), findsNothing);
  });

  testWidgets('the data is loaded again when the app comes back to the front, and every few minutes', (t) async {
    final (_, api, _) = await boot(t);
    int pulls() => api.calls.where((c) => c == 'GET /gym/members').length;
    final first = pulls();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(pulls(), first + 1);
    await t.pump(const Duration(minutes: 5, seconds: 1));
    await t.pumpAndSettle();
    expect(pulls(), first + 2);
  });

  testWidgets('member card: call and WhatsApp buttons', (t) async {
    await boot(t);
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    await t.tap(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('callMember')), findsOneWidget);
    expect(find.byKey(const Key('whatsappMember')), findsOneWidget);
  });

  testWidgets('sign-out removes the business data from the device; the settings stay', (t) async {
    final (auth, _, store) = await boot(t);
    expect(store.customers, isNotEmpty);
    store.settings.accountantEmail = 'acc@example.com';
    await auth.signOut();
    await t.pumpAndSettle();
    expect(store.customers, isEmpty);
    expect(store.receipts, isEmpty);
    expect(store.subscriptions, isEmpty);
    expect(store.serverLoaded, isFalse);
    expect(store.toJson()['customers'], isEmpty, reason: 'what is saved on the device is empty too');
    expect(store.settings.accountantEmail, 'acc@example.com');
  });

  testWidgets('data and settings of another business on the device are dropped at sign-in', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today)
      ..serverOwner = 'othergym.auratech2.tech'
      ..serverLoaded = true;
    store.settings.accountantEmail = 'other@example.com';
    final other = store.customers.first.name;
    final auth = AuthController(storage: signedIn(), api: serverApi());
    await t.pumpWidget(AuraGymApp(store: store, auth: auth));
    await t.pumpAndSettle();
    expect(store.serverOwner, 'aurademo1.auratech2.tech');
    expect(store.customers.any((c) => c.name == other), isFalse);
    expect(store.customers.any((c) => c.name == 'Dana Levi'), isTrue);
    expect(store.settings.accountantEmail, isNot('other@example.com'));
  });

  testWidgets('signed in: no demo or not-yet-connected actions', (t) async {
    await boot(t);
    expect(find.byKey(const Key('tileLink')), findsNothing);
    expect(find.byKey(const Key('tileMembers')), findsOneWidget);
    await t.tap(find.byKey(const Key('tileMembers')));
    await t.pumpAndSettle();
    expect(find.text('Search by name or phone'), findsOneWidget);

    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('signOut')), 400, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('resetDemo'), skipOffstage: false), findsNothing);
  });

  testWidgets('a server without gym/sales: the POS app sales list is used', (t) async {
    final api = serverApi()..errors['/gym/sales'] = AuraApiException(AuraErrorKind.server, 'HTTP 404');
    final (_, _, store) = await boot(t, api: api);
    expect(api.calls, containsAll(['GET /sales?page=1', 'GET /sales?page=2']));
    expect(store.receipts.map((r) => r.docNo), ['TIR-1001', 'TIR-1002', 'TIC-7']);
  });
}
