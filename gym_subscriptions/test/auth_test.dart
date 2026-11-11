import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'support/fake_api.dart';

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(AuthController, FakeApi, MemoryAuthStorage)> boot(WidgetTester t, [MemoryAuthStorage? storage]) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final api = FakeApi();
    final st = storage ?? MemoryAuthStorage();
    final auth = AuthController(storage: st, api: api);
    await t.pumpWidget(AuraGymApp(store: GymStore(), auth: auth));
    await t.pumpAndSettle();
    return (auth, api, st);
  }

  Future<void> enter(WidgetTester t, String key, String text) async {
    await t.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)), text);
  }

  Future<void> press(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  test('domain normalization', () {
    expect(AuraConfig.normalizeDomain('auratech2'), 'auratech2.tech');
    expect(AuraConfig.normalizeDomain(' AuraTech2.tech '), 'auratech2.tech');
    expect(AuraConfig.normalizeDomain('https://auratech2.tech/'), 'auratech2.tech');
    expect(const AuraWorkspace(domain: 'auratech2.tech', company: 'aurademo1').api('/login').toString(),
        'https://aurademo1.auratech2.tech/api/login');
  });

  test('login response -> session -> json round trip', () {
    final s = AuraSession.fromLoginResponse({
      'token': 'x',
      'data': {'id': 7, 'name': 'n', 'role_id': 3, 'warehouse_id': '4', 'email': null},
    })!;
    expect(s.userId, '7');
    expect(s.roleId, '3');
    expect(s.warehouseId, 4);
    expect(s.email, '');
    expect(s.headers['token'], 'x');
    final back = AuraSession.fromJson(s.toJson())!;
    expect(back.token, 'x');
    expect(back.warehouseId, 4);
    expect(AuraSession.fromLoginResponse({'msg': 'invalid credentials'}), isNull);
  });

  testWidgets('domain -> login -> app -> sign out keeps the business', (t) async {
    final (auth, api, storage) = await boot(t);
    expect(find.text('Connect your business'), findsOneWidget);
    // Prefilled with auratech2 / aurademo1.
    expect(find.text('auratech2'), findsOneWidget);
    expect(find.text('aurademo1'), findsOneWidget);

    await press(t, 'authContinue');
    expect(api.calls.last, 'verify aurademo1@auratech2.tech');
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('authWorkspace')), findsOneWidget);

    // Empty fields are not sent.
    await press(t, 'authSignIn');
    expect(find.text('Required'), findsNWidgets(2));
    expect(api.calls.where((c) => c.startsWith('login')), isEmpty);

    // An email is refused like in the POS app.
    await enter(t, 'authUser', 'admin@x.com');
    await enter(t, 'authPassword', 'secret');
    await press(t, 'authSignIn');
    expect(find.text('No @ – a name, not an email'), findsOneWidget);

    await enter(t, 'authUser', 'admin');
    await enter(t, 'authPassword', 'wrong');
    await press(t, 'authSignIn');
    expect(find.text('Wrong username or password'), findsOneWidget);
    expect(auth.stage, AuthStage.login);

    await enter(t, 'authPassword', 'secret');
    await press(t, 'authSignIn');
    expect(api.calls, contains('login admin https://aurademo1.auratech2.tech/api/login'));
    expect(api.calls, contains('GET /gym/members'), reason: 'signing in loads the server data');
    expect(auth.stage, AuthStage.signedIn);
    expect(find.byKey(const Key('navHome')), findsOneWidget);
    expect(storage.data?['session']?['token'], 'tok123');
    expect(storage.data?['workspace'], {'domain': 'auratech2.tech', 'company': 'aurademo1'});

    // Settings shows the account; signing out returns to login, business kept.
    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('accountCard')), findsOneWidget);
    await press(t, 'signOut');
    await press(t, 'signOutConfirm');
    expect(auth.stage, AuthStage.login);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(storage.data?['session'], isNull);
    expect(storage.data?['workspace']?['company'], 'aurademo1');

    // "Change" goes back to the domain screen.
    await press(t, 'authChangeWorkspace');
    expect(find.text('Connect your business'), findsOneWidget);
    expect(storage.data?['workspace'], isNull);
  });

  testWidgets('unknown company and unreachable domain show a message', (t) async {
    final (auth, _, _) = await boot(t);
    await enter(t, 'authCompany', 'nosuch');
    await press(t, 'authContinue');
    expect(find.text('No business named "nosuch" on auratech2.tech'), findsOneWidget);
    expect(auth.stage, AuthStage.domain);

    await enter(t, 'authDomain', 'other.tech');
    await press(t, 'authContinue');
    expect(find.text("Can't reach other.tech. Check the internet connection and the domain."), findsOneWidget);
  });

  testWidgets('a saved session opens the app directly', (t) async {
    final storage = MemoryAuthStorage({
      'workspace': {'domain': 'auratech2.tech', 'company': 'aurademo1'},
      'session': {'token': 't', 'userName': 'admin'},
    });
    final (auth, _, _) = await boot(t, storage);
    expect(auth.stage, AuthStage.signedIn);
    expect(find.byKey(const Key('navHome')), findsOneWidget);
  });

  testWidgets('language switch on the sign-in screen', (t) async {
    await boot(t);
    await t.tap(find.byKey(const Key('authLang-he')));
    await t.pumpAndSettle();
    expect(find.text('חיבור לעסק'), findsOneWidget);
    await t.tap(find.byKey(const Key('authLang-ar')));
    await t.pumpAndSettle();
    expect(find.text('ربط المصلحة'), findsOneWidget);
  });
}
