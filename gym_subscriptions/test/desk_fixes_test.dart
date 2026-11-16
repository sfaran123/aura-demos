// Collection by saved card, the details of a payment to collect, draft sales
// left out, any dates in reports, and the customer page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/server_mapping.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/state/reports.dart';

import 'collect_test.dart' show api;
import 'new_membership_test.dart' as nm;
import 'server_sync_test.dart' show signedIn, today;
import 'support/fake_api.dart';

/// The server's data with a Z Credit terminal (saved cards can be charged).
FakeApi cardApi() => api()
  ..responses['/gym/pos-settings'] = {
    'data': {...(nm.posSettings['data'] as Map), 'card_tokens': true}
  }
  ..postHandlers['/gym/card-charges'] = (b) => {'receipt': '{"HasError":false,"ReferenceNumber":"ZC-1"}'};

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi a, {String tab = 'navCollect'}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: a)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(tab)));
    await t.pumpAndSettle();
    return (store, a);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Map<String, Object?> sent(FakeApi a, String path) => a.posts.lastWhere((p) => p.$1 == path).$2;

  testWidgets('collect with the saved card, regular: charged first, then recorded with the answer', (t) async {
    final (store, a) = await boot(t, cardApi());
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-card');
    await tapKey(t, 'cardSavedRegular');
    final paths = a.posts.map((p) => p.$1).toList();
    expect(paths.indexOf('/gym/card-charges'), lessThan(paths.indexOf('/gym/memberships/5/collect')));
    expect(sent(a, '/gym/card-charges')['payments'], 1);
    expect(sent(a, '/gym/card-charges')['amount'], 179.1);
    final collect = sent(a, '/gym/memberships/5/collect');
    expect(collect['method'], 'card');
    expect(collect['card_receipt'], contains('ZC-1'));
    expect(collect['app_uuid'], sent(a, '/gym/card-charges')['app_uuid']);
    // The loading dialog is closed although the row left the list.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('collect with the saved card in installments: the number is sent', (t) async {
    final (_, a) = await boot(t, cardApi());
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-card');
    await tapKey(t, 'cardSavedPayments-3');
    expect(sent(a, '/gym/card-charges')['payments'], 3);
  });

  testWidgets('the card was taken on the terminal: recorded only, nothing charged', (t) async {
    final (_, a) = await boot(t, cardApi());
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-card');
    await tapKey(t, 'cardTerminal');
    expect(a.posts.any((p) => p.$1 == '/gym/card-charges'), isFalse);
    expect(sent(a, '/gym/memberships/5/collect').containsKey('card_receipt'), isFalse);
  });

  testWidgets('a declined card: nothing is recorded, the charge stays to collect', (t) async {
    final a = cardApi();
    a.postHandlers.remove('/gym/card-charges');
    final (store, _) = await boot(t, a);
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-card');
    await tapKey(t, 'cardSavedRegular');
    expect(a.posts.any((p) => p.$1 == '/gym/memberships/5/collect'), isFalse);
    expect(store.toCollect.any((c) => c.id == 'failed-3'), isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('touching a payment to collect opens its details and actions', (t) async {
    await boot(t, cardApi());
    await tapKey(t, 'charge-failed-3');
    expect(find.text('This payment'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.byKey(const Key('detailsCollect')), findsOneWidget);
    expect(find.byKey(const Key('detailsMember')), findsOneWidget);
  });

  test('draft sales are not sales and not payments', () {
    final sales = {
      'data': [
        {'id': 1, 'reference_no': 'TIR-1', 'grand_total': 100, 'sale_status': 1, 'created_at': '2026-11-10 10:00:00'},
        {'id': 2, 'reference_no': 'DR-2', 'grand_total': 50, 'sale_status': 3, 'created_at': '2026-11-10 11:00:00'},
        {'id': 3, 'reference_no': 'DR-3', 'grand_total': 70, 'is_draft': 1, 'created_at': '2026-11-10 12:00:00'},
      ]
    };
    expect(mapGymSales(sales).map((r) => r.reference), ['TIR-1']);
    expect(draftSaleIds(sales), {'2', '3'});
    final dash = mapDashboard({
      'data': {
        'open_debt': 0,
        'recent_payments': [
          {'id': 9, 'amount': 100, 'paying_method': 'Cash', 'sale_id': 1},
          {'id': 10, 'amount': 50, 'paying_method': 'Cash', 'sale_id': 2, 'sale_status': 3},
        ]
      }
    });
    expect(dash!.recentPayments.map((p) => p.id), ['9']);
  });

  test('a report for any dates', () {
    final store = GymStore(clock: () => today);
    customPeriodRange = (DateTime(2026, 10, 5), DateTime(2026, 10, 21));
    addTearDown(() => customPeriodRange = null);
    expect(Period.custom.range(today), (DateTime(2026, 10, 5), DateTime(2026, 10, 21)));
    expect(Period.custom.label, '05/10/2026 – 20/10/2026');
    expect(previousRange(Period.custom, today), (DateTime(2026, 9, 19), DateTime(2026, 10, 5)));
    for (final r in allReports.where((r) => r.usesPeriod)) {
      expect((r.periods ?? Period.values), contains(Period.custom), reason: r.id);
      expect(() => r.build(store, Period.custom), returnsNormally, reason: r.id);
    }
  });

  testWidgets('every customer is found, with the whole ledger; editing is saved on the server', (t) async {
    final a = cardApi();
    final (store, _) = await boot(t, a, tab: 'navMembers');
    await tapKey(t, 'allCustomers');
    await t.enterText(find.byKey(const Key('customerSearch')), 'dana');
    await t.pumpAndSettle();
    await tapKey(t, 'customer-7');
    expect(find.text('Payment history'), findsOneWidget);
    // A server without the endpoint says so and changes nothing.
    await tapKey(t, 'customerEdit');
    await t.enterText(find.byKey(const Key('editName')), 'Dana Cohen');
    await tapKey(t, 'editSave');
    expect(store.customer('7')!.name, 'Dana Levi');
    expect(find.textContaining('not available on the server yet'), findsOneWidget);
    // With the endpoint: saved.
    a.postHandlers['/gym/members/7'] = (b) => {'data': b};
    await tapKey(t, 'editSave');
    expect(sent(a, '/gym/members/7')['name'], 'Dana Cohen');
    expect(store.customer('7')!.name, 'Dana Cohen');
  });

  testWidgets('the sign-in screen shows the AURA mark', (t) async {
    await t.pumpWidget(
        AuraGymApp(store: GymStore(), auth: AuthController(storage: MemoryAuthStorage({}), api: FakeApi())));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('auraLogo')), findsOneWidget);
  });
}
