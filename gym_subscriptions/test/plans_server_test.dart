// Plans and prices managed from the app, saved on the AURA server: a plan is a
// subscription product with its settings (POST gym/plans, POST gym/plans/{id}).

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

import 'server_sync_test.dart' show plans, serverApi, signedIn, today;
import 'support/fake_api.dart';

/// Answers like GymController::storePlan / updatePlan (the gym/plans row format).
Object? Function(Map<String, Object?>) planSaved(int id, {int? taxMethod}) => (b) {
      final type = b['plan_type'];
      return {
        'data': {
          'id': id,
          'name': b['name'],
          'code': '12345678',
          'price': b['price'],
          'tax_id': 1,
          'tax_method': taxMethod ?? 2,
          'tax_rate': 18,
          'duration_months': type == 'fixed_term' ? b['months'] : (type == 'punch_card' ? b['valid_months'] : null),
          'settings_saved': true,
          'settings': {
            'plan_type': type,
            'entries_count': b['entries_count'],
            'registration_fee': b['registration_fee'],
            'commitment_months': b['commitment_months'],
            'cancellation_notice_days': b['cancellation_notice_days'],
            'weekly_entry_limit': b['weekly_entry_limit'],
            'freeze_days_per_year': b['freeze_days_per_year'],
            'max_installments': b['max_installments'],
            'max_cheques': b['max_cheques'],
            'allow_cash': b['allow_cash'],
            'allow_cheques': b['allow_cheques'],
            'auto_renew': b['auto_renew'],
            'online_signup': b['online_signup'],
            'prepay_last_month': b['prepay_last_month'],
            'badge': null,
            'active': b['active'],
          },
        }
      };
    };

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

  Future<void> field(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(Key('pe-$key')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(Key('pe-$key')), text);
    await t.pumpAndSettle();
  }

  test('mapping: "active" from the settings; true when the server has no such column yet', () {
    final body = jsonDecode(jsonEncode(plans)) as Map;
    ((body['data'] as List)[0] as Map)['settings']['active'] = false;
    final p = mapPlans(body);
    expect(p[0].active, isFalse);
    expect(p[1].active, isTrue);
  });

  test('the body the server takes, by plan type', () {
    final punch = SubscriptionPlan(id: '', name: ' 10 entries ', kind: PlanKind.punch, price: 450, entries: 10, validMonths: 4);
    expect(planBody(punch), containsPair('plan_type', 'punch_card'));
    expect(planBody(punch)['name'], '10 entries');
    expect(planBody(punch)['entries_count'], 10);
    expect(planBody(punch)['valid_months'], 4);
    expect(planBody(punch).containsKey('months'), isFalse);
    final term = SubscriptionPlan(id: '', name: 'Half', kind: PlanKind.term, price: 900, months: 6, prepayLastMonth: true);
    expect(planBody(term)['plan_type'], 'fixed_term');
    expect(planBody(term)['months'], 6);
    expect(planBody(term)['prepay_last_month'], isFalse, reason: 'monthly plans only');
  });

  testWidgets('a new plan is created on the server and listed with its server id', (t) async {
    final api = serverApi()..postHandlers['/gym/plans'] = planSaved(500);
    final store = await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'newPlan');
    await field(t, 'name', 'Students');
    await field(t, 'price', '149');
    await field(t, 'commit', '6');
    await tapKey(t, 'savePlan');

    expect(api.posts.single.$1, '/gym/plans');
    final b = api.posts.single.$2;
    expect(b['name'], 'Students');
    expect(b['price'], 149);
    expect(b['plan_type'], 'recurring');
    expect(b['commitment_months'], 6);
    expect(b['max_installments'], 1, reason: 'a monthly plan is paid month by month');
    expect(b['auto_renew'], isTrue);
    expect(b['active'], isTrue);
    final p = store.plan('500');
    expect(p?.name, 'Students');
    expect(p?.price, 149);
    expect(store.plans.where((x) => x.name == 'Students').length, 1, reason: 'no local copy besides the server one');
    expect(find.text('Plan "Students" saved'), findsOneWidget);
  });

  testWidgets('editing a plan: new price saved on the server', (t) async {
    final api = serverApi()..postHandlers['/gym/plans/10'] = planSaved(10);
    final store = await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'editPlan-10');
    await field(t, 'price', '219');
    await tapKey(t, 'savePlan');

    expect(api.posts.single.$1, '/gym/plans/10');
    expect(api.posts.single.$2['price'], 219);
    expect(api.posts.single.$2['registration_fee'], 100, reason: 'the rest as it was');
    expect(store.plan('10')!.price, 219);
  });

  testWidgets('a plan with memberships keeps its type', (t) async {
    final api = serverApi();
    await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'editPlan-10'); // Dana's monthly membership uses it
    expect(find.text('This plan has memberships, so its type is fixed.'), findsOneWidget);
    expect(t.widget<SegmentedButton<PlanKind>>(find.byKey(const Key('pe-kind'))).onSelectionChanged, isNull);
  });

  testWidgets('the server refuses: its message, the editor stays open, nothing changes', (t) async {
    final api = serverApi()
      ..postErrors['/gym/plans/10'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: The price must be at least 0.');
    final store = await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'editPlan-10');
    await field(t, 'price', '219');
    await tapKey(t, 'savePlan');
    expect(find.text('The price must be at least 0.'), findsOneWidget);
    expect(find.byKey(const Key('savePlan')), findsOneWidget);
    expect(store.plan('10')!.price, 199, reason: 'the store keeps the server copy');
  });

  testWidgets('no permission: the message, nothing saved', (t) async {
    final api = serverApi()
      ..postErrors['/gym/plans'] =
          AuraApiException(AuraErrorKind.forbidden, 'Sorry! You are not allowed to access this module');
    final store = await boot(t, api);
    final before = store.plans.length;
    await tapKey(t, 'homePlans');
    await tapKey(t, 'newPlan');
    await field(t, 'name', 'X');
    await field(t, 'price', '10');
    await tapKey(t, 'savePlan');
    expect(find.textContaining('not allowed'), findsOneWidget);
    expect(store.plans.length, before);
  });

  testWidgets('switched off: kept in the list, not offered for a new membership', (t) async {
    final api = serverApi()..postHandlers['/gym/plans/10'] = planSaved(10);
    final store = await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'editPlan-10');
    final active = find.text('Active plan');
    await t.ensureVisible(active);
    await t.pumpAndSettle();
    await t.tap(active);
    await t.pumpAndSettle();
    await tapKey(t, 'savePlan');
    expect(api.posts.single.$2['active'], isFalse);
    expect(store.plan('10')!.active, isFalse);
    expect(find.byKey(const Key('editPlan-10')), findsOneWidget, reason: 'still listed, can be switched on again');

    // Back to the home screen.
    Navigator.of(t.element(find.byKey(const Key('editPlan-10')))).popUntil((r) => r.isFirst);
    await t.pumpAndSettle();
    // The home list was scrolled down to "Plans": back up to the tiles.
    await t.scrollUntilVisible(find.byKey(const Key('tileNewSub')), -300, scrollable: find.byType(Scrollable).first);
    await tapKey(t, 'tileNewSub');
    await t.tap(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('plan-10')), findsNothing);
    expect(find.byKey(const Key('plan-11')), findsOneWidget);
  });

  testWidgets('a product priced before VAT: the price field says so', (t) async {
    final body = jsonDecode(jsonEncode(plans)) as Map;
    ((body['data'] as List)[0] as Map)['tax_method'] = 1;
    final api = serverApi()..responses['/gym/plans'] = body;
    await boot(t, api);
    await tapKey(t, 'homePlans');
    await tapKey(t, 'editPlan-10');
    expect(find.text('₪ before VAT'), findsOneWidget);
  });
}
