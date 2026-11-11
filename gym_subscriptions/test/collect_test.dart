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
    {'id': 3, 'month_key': '2026-10|10', 'amount': 179.1, 'attempts': 2, 'message': 'declined', 'date': '2026-11-01 06:00:00'}
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
    expect(find.byKey(const Key('collect-sale-500')), findsOneWidget);
    expect(find.textContaining('Invoice TIR-1001'), findsOneWidget);
    expect(find.text(money(299.1)), findsOneWidget, reason: 'header = the home screen\'s open debt');
    expect(find.text('Link'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    expect(store.charges.firstWhere((c) => c.id == 'failed-3').attempts, 2);
  });

  testWidgets('a failed month collected in cash: tax invoice-receipt on the server, then a sync', (t) async {
    final (_, a) = await boot(t, api());
    final getsBefore = a.calls.where((c) => c == 'GET /gym/memberships').length;
    await tapKey(t, 'collect-failed-3');
    await tapKey(t, 'collectWith-cash');
    expect(a.posts.last.$1, '/gym/memberships/5/collect');
    expect(a.posts.last.$2, {'method': 'cash', 'month_key': '2026-10|10'});
    expect(a.calls.where((c) => c == 'GET /gym/memberships').length, getsBefore + 1, reason: 'reloaded after collecting');
    expect(find.textContaining('Received · TIN-900'), findsOneWidget);
  });

  testWidgets('an unpaid invoice collected by transfer: payment added to the invoice', (t) async {
    final (_, a) = await boot(t, api());
    await tapKey(t, 'collect-sale-500');
    await tapKey(t, 'collectWith-bank');
    await t.enterText(find.byKey(const Key('tr-ref-0')), 'BR77');
    await t.enterText(find.byKey(const Key('tr-bank-0')), '12');
    await t.pumpAndSettle();
    await tapKey(t, 'detailsSave');
    expect(a.posts.last.$1, '/gym/sales/500/payments');
    expect(a.posts.last.$2, {
      'method': 'bank',
      'transfer_reference': 'BR77',
      'transfer_bank': '12',
    });
    expect(find.textContaining('Received · TIR-1001'), findsOneWidget);
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
