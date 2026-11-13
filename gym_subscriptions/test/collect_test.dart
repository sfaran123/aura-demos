import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'dashboard_test.dart' show dashboard;
import 'server_sync_test.dart' show memberships, serverApi, signedIn, today;
import 'support/fake_api.dart';

Map<String, dynamic> copy(Object? m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

/// The server's data: Dana's failed October month (key "2026-10|10") and her unpaid
/// invoice TIR-1001 (sale 500); total open debt 299.10.
FakeApi api() {
  final ms = copy(memberships);
  ((ms['data'] as List)[0] as Map)['failed_payments'] = [
    {
      'id': 3,
      'month_key': '2026-10|10',
      'amount': 179.1,
      'attempts': 2,
      'message': 'declined',
      'date': '2026-11-01 06:00:00'
    }
  ];
  final a = serverApi()
    ..responses['/gym/memberships'] = ms
    ..responses['/gym/dashboard'] = dashboard;
  a.postHandlers['/gym/memberships/5/collect'] = (b) => {
        'data': (ms['data'] as List)[0],
        'document': {'id': 900, 'reference_no': 'TIN-900', 'grand_total': 179.1},
      };
  a.postHandlers['/gym/sales/500/payments'] = (b) => {
        'sale': {'id': 500, 'reference_no': 'TIR-1001', 'grand_total': 120, 'paid_amount': 120, 'payment_status': 4},
      };
  return a;
}

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi a) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: a)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navCollect')));
    await t.pumpAndSettle();
    return (store, a);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('the list: the server debts, no link or reminder buttons', (t) async {
    final (store, _) = await boot(t, api());
    expect(find.byKey(const Key('collect-failed-3')), findsOneWidget);
    // Only what the desk collects: a membership document with an open balance
    // (TIR-1001, 120) is not in the list and not in the total.
    expect(find.byKey(const Key('collect-sale-500')), findsNothing);
    expect(find.textContaining('TIR-1001'), findsNothing);
    expect(find.text(money(179.1)), findsWidgets, reason: 'header = the home screen\'s open debt');
    expect(find.text('Link'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    expect(store.charges.firstWhere((c) => c.id == 'failed-3').attempts, 2);
  });

  testWidgets('a failed month shows its dates, and opens the list of tries', (t) async {
    await boot(t, api());
    final dates = t.widget<Text>(find.byKey(const Key('dates-failed-3'))).data!;
    expect(dates, contains('Charge for'));
    expect(dates, contains('Failed on'));
    await tapKey(t, 'tries-failed-3');
    expect(find.text('Charge attempts'), findsOneWidget);
    expect(find.byKey(const Key('try-failed-3-0')), findsOneWidget);
  });

  testWidgets('old failed months are folded apart and not in the open debt; a member is one row', (t) async {
    final a = api();
    final row = ((a.responses['/gym/memberships'] as Map)['data'] as List)[0] as Map;
    row['failed_payments'] = <Object>[
      ...(row['failed_payments'] as List),
      {'id': 90, 'amount': 150.0, 'message': 'declined', 'date': '2026-01-01 06:00:00'},
      {'id': 91, 'amount': 150.0, 'message': 'declined', 'date': '2026-02-01 06:00:00'},
      {'id': 92, 'amount': 179.1, 'message': 'declined', 'date': '2026-09-01 06:00:00'},
    ];
    final dash = copy(a.responses['/gym/dashboard']);
    final data = dash['data'] as Map;
    (data['debts'] as List).add(
        {'kind': 'failed_charge', 'id': 'failed-90', 'amount': 150.0, 'customer_name': 'Dana', 'date': '2026-01-01'});
    data['open_debt'] = (data['open_debt'] as num) + 150.0;
    a.responses['/gym/dashboard'] = dash;
    final (store, _) = await boot(t, a);
    expect(store.toCollect.map((c) => c.id), containsAll(['failed-3', 'failed-92']));
    expect(store.oldDebts.map((c) => c.id), ['failed-91', 'failed-90']);
    expect(store.dashboard!.openDebt, 179.1, reason: 'the old debt is taken off the server total');
    expect(store.dashboard!.debts.any((d) => d.id == 'failed-90'), isFalse);
    // Two failed months in the window: one row for the member, opening the months.
    expect(find.byKey(const Key('collect-failed-3')), findsNothing);
    expect(
        find.text(
            '2 failed months · 09/2026 – 10/2026 · ${store.customers.firstWhere((c) => c.id == store.toCollect.first.customerId).phone}'),
        findsOneWidget);
    await tapKey(t, 'debts-${store.toCollect.first.customerId}');
    expect(find.byKey(const Key('collect-failed-3')), findsOneWidget);
    expect(find.byKey(const Key('collect-failed-92')), findsOneWidget);
    // The old ones: folded at the bottom with their own total.
    await t.scrollUntilVisible(find.byKey(const Key('oldDebts')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Old debts · 1 members · ${money(300)}'), findsOneWidget);
    expect(find.byKey(const Key('collect-failed-90')), findsNothing);
  });

  testWidgets('every member in manual collection is listed, also when the next payment is far ahead', (t) async {
    final a = api();
    final rows = (a.responses['/gym/memberships'] as Map)['data'] as List;
    final avi = rows[0] as Map;
    avi['auto_payment_type'] = 'manual';
    ((avi['items'] as List).first as Map)['next_payment_date'] = '2026-12-28';
    final (store, _) = await boot(t, a);
    expect(store.toCollect.any((c) => c.id == 'next-5'), isFalse, reason: 'not due yet: not counted as to collect now');
    expect(store.upcomingManual.map((c) => c.id), contains('next-5'));
    await t.scrollUntilVisible(find.byKey(const Key('collect-next-5')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Next payments in manual collection'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('dates-next-5'))).data, 'Due: 28/12/2026');
  });

  testWidgets('a failed month collected in cash: tax invoice-receipt on the server, then a sync', (t) async {
    final (_, a) = await boot(t, api());
    final getsBefore = a.calls.where((c) => c == 'GET /gym/memberships').length;
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-cash');
    expect(a.posts.last.$1, '/gym/memberships/5/collect');
    expect(a.posts.last.$2, {'method': 'cash', 'month_key': '2026-10|10'});
    expect(a.calls.where((c) => c == 'GET /gym/memberships').length, getsBefore + 1,
        reason: 'reloaded after collecting');
    expect(find.textContaining('Received · TIN-900'), findsOneWidget);
  });

  testWidgets('a failed month collected by transfer: reference and bank are sent', (t) async {
    final (_, a) = await boot(t, api());
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-bank');
    await t.enterText(find.byKey(const Key('tr-ref-0')), 'BR77');
    await t.enterText(find.byKey(const Key('tr-bank-0')), '12');
    await t.pumpAndSettle();
    await tapKey(t, 'detailsSave');
    expect(a.posts.last.$1, '/gym/memberships/5/collect');
    expect(a.posts.last.$2, {
      'method': 'bank',
      'transfer_reference': 'BR77',
      'transfer_bank': '12',
      'month_key': '2026-10|10',
    });
  });

  testWidgets('a cheque: number, bank, branch, account and date are sent', (t) async {
    final (_, a) = await boot(t, api());
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-cheque');
    await t.enterText(find.byKey(const Key('chq-number-0')), '5501');
    await t.enterText(find.byKey(const Key('chq-bank-0')), '12');
    await t.enterText(find.byKey(const Key('chq-branch-0')), '600');
    await t.enterText(find.byKey(const Key('chq-account-0')), '123456');
    await t.pumpAndSettle();
    await tapKey(t, 'detailsSave');
    final body = a.posts.last.$2;
    expect((body['method'], body['cheque_number'], body['cheque_bank'], body['cheque_branch'], body['cheque_account']),
        ('cheque', '5501', '12', '600', '123456'));
    expect(body['cheque_date'], isA<String>());
    expect(body['month_key'], '2026-10|10');
  });

  testWidgets('a server error: the charge stays open and the message shows', (t) async {
    final a = api()
      ..postErrors['/gym/memberships/5/collect'] =
          AuraApiException(AuraErrorKind.server, 'HTTP 409: This failed month is already collected or written off');
    final (store, _) = await boot(t, a);
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-cash');
    expect(find.textContaining('already collected'), findsOneWidget);
    expect(store.charges.firstWhere((c) => c.id == 'failed-3').isOpen(), isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a manual monthly payment is collected by its due date', (t) async {
    final a = api();
    final ms = copy(memberships);
    final m = (ms['data'] as List)[0] as Map;
    m['auto_payment_type'] = 'manual';
    m['status'] = 'active';
    m['failed_payments'] = [];
    m['items'][0]['next_payment_date'] = '2026-11-08';
    a.responses['/gym/memberships'] = ms;
    await boot(t, a);
    await tapKey(t, 'collect-next-5');
    await tapKey(t, 'collectWith-cash');
    expect(a.posts.last.$1, '/gym/memberships/5/collect');
    expect(a.posts.last.$2, {'method': 'cash', 'due_date': '2026-11-08'});
  });
}
