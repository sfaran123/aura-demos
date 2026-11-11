import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
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
              'end_date': recurring ? d(DateTime(start.year + 100, start.month, start.day)) : d(DateTime(start.year, start.month + 3, start.day)),
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

  /// Home -> New membership -> Dana Levi (saved card) -> [planId] -> payment -> summary.
  Future<void> toSummary(WidgetTester t, String planId) async {
    await tapKey(t, 'tileNewSub');
    await t.ensureVisible(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Dana Levi').first);
    await t.pumpAndSettle();
    await tapKey(t, 'plan-$planId');
    await tapKey(t, 'toPayment');
    expect(find.byKey(const Key('payProblem')), findsNothing, reason: 'the saved card covers the amount');
    await tapKey(t, 'toSummary');
  }

  testWidgets('punch card: created on the server, payment recorded in the app as before', (t) async {
    final api = serverApi()..postHandlers['/gym/memberships'] = membershipStore();
    final (store, _, _) = await boot(t, api);
    await toSummary(t, '11');
    await tapKey(t, 'confirm');

    final post = api.posts.single;
    expect(post.$1, '/gym/memberships');
    expect(post.$2, {
      'customer_id': 7,
      'plan_id': 11,
      'start_date': '2026-11-11',
      'discount_percent': 0,
      'registration_waived': false,
    });
    final sub = store.subscriptions.firstWhere((s) => s.id == '77');
    expect(sub.entriesLeft, 10);
    expect(sub.customerId, '7');
    expect(store.subscriptions.where((s) => s.customerId == '7' && s.planId == '11'), hasLength(1),
        reason: 'no second, app-only membership');
    final r = store.receipts.last;
    expect(r.subscriptionId, '77', reason: 'the receipt belongs to the server membership');
    expect(r.total, 450);
    expect(r.reference, isNull, reason: 'the payment is still only in the app');
    expect(find.byKey(const Key('confirm')), findsNothing, reason: 'on the done screen');
  });

  testWidgets('monthly plan: recurring method sent, next charge from the server', (t) async {
    final api = serverApi()..postHandlers['/gym/memberships'] = membershipStore(id: 78);
    final (store, _, _) = await boot(t, api);
    await toSummary(t, '10');
    await tapKey(t, 'confirm');
    expect(api.posts.single.$2['recurring_method'], 'credit_card');
    final sub = store.subscriptions.firstWhere((s) => s.id == '78');
    expect(sub.monthlyAmount, 199);
    expect(sub.end, isNull);
    expect(store.charges.where((c) => c.subscriptionId == '78').map((c) => c.dueDate), [DateTime(2026, 12, 11)]);
  });

  testWidgets('a server error: nothing created, the message shows, retry works', (t) async {
    final api = serverApi()
      ..postErrors['/gym/memberships'] =
          AuraApiException(AuraErrorKind.server, 'HTTP 422: Plan not found (an active subscription product is needed)');
    final (store, _, _) = await boot(t, api);
    final subs = store.subscriptions.length, receipts = store.receipts.length;
    await toSummary(t, '11');
    await tapKey(t, 'confirm');
    expect(find.textContaining('Plan not found'), findsOneWidget);
    expect(find.byKey(const Key('confirm')), findsOneWidget, reason: 'still on the summary');
    expect(store.subscriptions.length, subs);
    expect(store.receipts.length, receipts);

    api.postErrors.clear();
    api.postHandlers['/gym/memberships'] = membershipStore();
    await tapKey(t, 'confirm');
    expect(store.subscriptions.any((s) => s.id == '77'), isTrue);
    expect(store.receipts.length, receipts + 1);
  });

  testWidgets('session expired while saving: back to login, nothing created', (t) async {
    final api = serverApi()..postErrors['/gym/memberships'] = AuraApiException(AuraErrorKind.sessionExpired);
    final (store, _, auth) = await boot(t, api);
    final receipts = store.receipts.length;
    await toSummary(t, '11');
    await tapKey(t, 'confirm');
    expect(auth.stage, AuthStage.login);
    expect(store.receipts.length, receipts);
  });

  // Not signed in (everything stays in the app) is covered by app_flow_test.dart:
  // 'existing customer with a saved card: subscription in 5 taps'.
}
