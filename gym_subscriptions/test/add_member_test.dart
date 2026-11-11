import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

/// Answers like CustomerController::storeForApp: a new customer, or the
/// existing one when the phone number is already on the server.
Object? Function(Map<String, Object?>) customerStore({String? existingPhone}) => (body) => {
      'msg': body['phone_number'] == existingPhone ? 'Existing customer!' : 'Customer created successfully!',
      'if_existing': body['phone_number'] == existingPhone,
      'data': {
        'id': body['phone_number'] == existingPhone ? 55 : 321,
        'name': body['phone_number'] == existingPhone ? 'Moshe Server' : body['name'],
        'address': null,
        'phone_number': body['phone_number'],
        'tax_no': body['tax_no'],
        'company_name': null,
        'customer_group_id': 1,
        'email': null,
        'created_at': '2026-11-11T10:00:00.000000Z',
        'updated_at': '2026-11-11T10:00:00.000000Z',
      },
    };

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

  Future<void> openNewCustomer(WidgetTester t) async {
    await t.tap(find.byKey(const Key('tileNewSub')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('newCustomer')));
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, String name, String phone, [String id = '']) async {
    await t.enterText(find.byKey(const Key('ncName')), name);
    await t.enterText(find.byKey(const Key('ncPhone')), phone);
    if (id.isNotEmpty) await t.enterText(find.byKey(const Key('ncId')), id);
    await t.tap(find.byKey(const Key('ncSave')));
    await t.pumpAndSettle();
  }

  testWidgets('signed in: the member is created on the server and the flow goes on', (t) async {
    final api = serverApi()..postHandlers['/customer/store'] = customerStore();
    final (store, _, _) = await boot(t, api);
    await openNewCustomer(t);
    await fill(t, 'Noa Bar', '0541234567', '000000018');

    expect(api.posts.single.$1, '/customer/store');
    expect(api.posts.single.$2,
        {'name': 'Noa Bar', 'phone_number': '054-1234567', 'tax_no': '000000018', 'customer_group_id': 1});
    final c = store.customer('321');
    expect(c?.name, 'Noa Bar');
    expect(c?.idNumber, '000000018');
    expect(find.byKey(const Key('ncSave')), findsNothing, reason: 'the sheet closed');
    expect(find.byKey(const Key('newCustomer')), findsNothing, reason: 'the flow went on to the next step');
  });

  testWidgets('the phone is already on the server: that customer is selected, nothing created', (t) async {
    final api = serverApi()..postHandlers['/customer/store'] = customerStore(existingPhone: '058-1112223');
    final (store, _, _) = await boot(t, api);
    final before = store.customers.length;
    await openNewCustomer(t);
    await fill(t, 'Someone New', '058-1112223');
    expect(store.customer('55')?.name, 'Moshe Server');
    expect(store.customers.length, before + 1, reason: 'added to the app list (it was not synced: e.g. inactive)');
    expect(find.text('A customer with this phone already exists: Moshe Server. They were selected.'), findsOneWidget);
  });

  testWidgets('already in the synced list (same digits): picked in the app, no server call', (t) async {
    final api = serverApi()..postHandlers['/customer/store'] = customerStore();
    final (store, _, _) = await boot(t, api);
    await openNewCustomer(t);
    await fill(t, 'Dana again', '0501234567'); // Dana Levi is 050-1234567 on the server
    expect(api.posts, isEmpty);
    expect(store.customers.where((c) => c.name == 'Dana again'), isEmpty);
  });

  testWidgets('a server error keeps the sheet open with the message; nothing is added', (t) async {
    final api = serverApi()..errors['/customer/store'] = AuraApiException(AuraErrorKind.server, 'HTTP 500');
    final (store, _, _) = await boot(t, api);
    final before = store.customers.length;
    await openNewCustomer(t);
    await fill(t, 'Noa Bar', '0541234567');
    expect(find.text('Server error (HTTP 500)'), findsOneWidget);
    expect(find.byKey(const Key('ncSave')), findsOneWidget);
    expect(store.customers.length, before);

    // Retry works once the server answers.
    api.errors.clear();
    api.postHandlers['/customer/store'] = customerStore();
    await t.tap(find.byKey(const Key('ncSave')));
    await t.pumpAndSettle();
    expect(store.customer('321')?.name, 'Noa Bar');
  });

  testWidgets('"Access denied" (token not accepted) signs out with the expired message', (t) async {
    final api = serverApi()..errors['/customer/store'] = AuraApiException(AuraErrorKind.forbidden, 'Access denied');
    final (_, _, auth) = await boot(t, api);
    await openNewCustomer(t);
    await fill(t, 'Noa Bar', '0541234567');
    expect(auth.stage, AuthStage.login);
    expect(find.text('Your session has expired. Please sign in again.'), findsOneWidget);
  });
}
