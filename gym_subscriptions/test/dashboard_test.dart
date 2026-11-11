import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/dashboard.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/integration/repository.dart';
import 'package:aura_gym/src/integration/server_mapping.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

// Shaped like the real answer of GET /api/gym/dashboard.
final dashboard = {
  'data': {
    'business_name': 'Salams Ltd.',
    'active_members': 42,
    'revenue_today': 1234.5,
    'open_debt': 299.1,
    'debts': [
      {
        'kind': 'failed_charge',
        'id': 'failed-3',
        'subscription_id': 5,
        'sale_id': null,
        'reference_no': null,
        'customer_id': 7,
        'customer_name': 'Dana Levi',
        'description': 'Monthly',
        'amount': 179.1,
        'date': '2026-11-01 06:00:00',
        'message': 'declined',
      },
      {
        'kind': 'unpaid_invoice',
        'id': 'sale-500',
        'subscription_id': 5,
        'sale_id': 500,
        'reference_no': 'TIR-1001',
        'customer_id': 7,
        'customer_name': 'Dana Levi',
        'description': null,
        'amount': 120,
        'date': '2026-11-05 10:00:00',
        'message': null,
      },
    ],
    'expiring': [
      {'subscription_id': 6, 'customer_id': 8, 'customer_name': 'Avi Cohen', 'plan_name': '10 entries', 'end_date': '2026-11-20'},
    ],
    'expiring_days': 14,
    'recent_payments': [
      {
        'id': 91,
        'sale_id': 501,
        'reference_no': 'TIR-1002',
        'payment_reference': 'spr-1',
        'customer_name': 'Avi Cohen',
        'amount': 30,
        'paying_method': 'Cash',
        'created_at': '2026-11-11 09:30:00',
      },
      {
        'id': 90,
        'sale_id': 999,
        'reference_no': 'TIR-0999',
        'payment_reference': 'spr-0',
        'customer_name': null,
        'amount': 50,
        'paying_method': 'Gift Card',
        'created_at': '2026-11-10 18:00:00',
      },
    ],
    'documents_month': 17,
    'generated_at': '2026-11-11 10:00:00',
  }
};

void main() {
  setUp(() => L10n.lang = AppLang.en);

  test('mapping', () {
    final d = mapDashboard(dashboard)!;
    expect(d.businessName, 'Salams Ltd.');
    expect(d.activeMembers, 42);
    expect(d.revenueToday, 1234.5);
    expect(d.openDebt, 299.1);
    expect(d.debts.map((x) => x.kind), [DebtKind.failedCharge, DebtKind.unpaidInvoice]);
    expect(d.debts[1].reference, 'TIR-1001');
    expect(d.debts[1].saleId, '500');
    expect(d.expiring.single.endDate, DateTime(2026, 11, 20));
    expect(d.recentPayments.map((p) => p.method), [PayMethod.cash, PayMethod.cash]);
    expect(d.recentPayments[1].methodName, 'Gift Card');
    expect(d.documentsMonth, 17);
    expect(mapDashboard({'msg': 'x'}), isNull);
  });

  Future<(GymStore, FakeApi)> boot(WidgetTester t, {FakeApi? api, GymStore? store}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final a = api ?? (serverApi()..responses['/gym/dashboard'] = dashboard);
    final s = store ?? GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: s, auth: AuthController(storage: signedIn(), api: a)));
    await t.pumpAndSettle();
    return (s, a);
  }

  String text(WidgetTester t, String key) =>
      t.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))).map((w) => w.data).join(' | ');

  testWidgets('home shows the server numbers and lists', (t) async {
    final (store, api) = await boot(t);
    expect(api.calls, contains('GET /gym/dashboard?expiring_days=${store.settings.renewalReminderDaysBefore}'));

    expect(find.text(isolate('Salams Ltd.')), findsOneWidget);
    expect(text(t, 'kpiActive'), contains('42'));
    expect(text(t, 'kpiRevenue'), contains('1,234.50'));
    expect(text(t, 'kpiDebt'), contains('299.10'));
    expect(find.textContaining('17'), findsWidgets);

    // Needs attention: both debts and the membership ending soon.
    Future<void> see(String key) => t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
    await see('debt-failed-3');
    expect(find.byKey(const Key('debt-failed-3')), findsOneWidget);
    await see('debt-sale-500');
    expect(text(t, 'debt-sale-500'), contains('Invoice TIR-1001 unpaid'));
    await see('expiring-6');
    expect(find.byKey(const Key('expiring-6')), findsOneWidget);

    // Recent payments from the server, with its method name when the app has none.
    await see('payment-91');
    await see('payment-90');
    expect(text(t, 'payment-91'), allOf(contains('Avi Cohen'), contains('TIR-1002'), contains('Cash')));
    expect(text(t, 'payment-90'), allOf(contains('Walk-in customer'), contains('Gift Card')));

    // A payment of a synced sale opens its document.
    await t.tap(find.byKey(const Key('payment-91')));
    await t.pumpAndSettle();
    expect(find.textContaining('TIR-1002'), findsWidgets);
  });

  testWidgets('a server without the dashboard endpoint: home falls back to app numbers', (t) async {
    final api = serverApi()..errors['/gym/dashboard'] = AuraApiException(AuraErrorKind.server, 'HTTP 404');
    final (store, _) = await boot(t, api: api);
    expect(store.dashboard, isNull);
    expect(store.customers.any((c) => c.name == 'Dana Levi'), isTrue, reason: 'the rest of the sync still worked');
    expect(text(t, 'kpiActive'), contains('${store.activeCount}'));
  });

  test('the dashboard is saved with the data and restored on the next start', () async {
    final repo = MemoryGymRepository();
    final s1 = GymStore(repository: repo, clock: () => today);
    s1.applyServerData(
        customers: [], plans: [], subscriptions: [], charges: [], items: [], receipts: [], dashboardJson: dashboard);
    await s1.save();
    final s2 = GymStore(repository: repo, clock: () => today);
    expect(s2.dashboard?.businessName, 'Salams Ltd.');
    expect(s2.dashboard?.debts, hasLength(2));
    s2.resetDemo();
    expect(s2.dashboard, isNull);
  });
}
