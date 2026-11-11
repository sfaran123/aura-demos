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

import 'server_sync_test.dart' show memberships, plans, serverApi, signedIn, today;
import 'support/fake_api.dart';

Map<String, dynamic> copy(Object? m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

/// Avi Cohen's punch card (membership 6) as the server returns it, changed by [edit].
Map<String, dynamic> avi([void Function(Map<String, dynamic> m)? edit]) {
  final m = copy((memberships['data'] as List)[1]);
  edit?.call(m);
  return m;
}

FakeApi api() {
  // The punch card plan allows 30 freeze days a year.
  final p = copy(plans);
  ((p['data'] as List)[1] as Map)['settings']['freeze_days_per_year'] = 30;
  final a = serverApi();
  a.responses['/gym/plans'] = p;
  a.postHandlers['/gym/memberships/6/freeze'] = (b) => {
        'data': avi((m) {
          m['status'] = 'frozen';
          m['frozen_until'] = '2026-11-24';
          m['freezes'] = [
            {'id': 1, 'start_date': '2026-11-11', 'end_date': '2026-11-24', 'reason': null}
          ];
          m['items'][0]['end_date'] = '2027-02-15';
        })
      };
  a.postHandlers['/gym/memberships/6/unfreeze'] = (b) => {'data': avi()};
  a.postHandlers['/gym/memberships/6/cancel'] = (b) => {
        'data': avi((m) {
          m['cancel_requested_at'] = '2026-11-11 10:00:00';
          m['items'][0]['end_date'] = '2026-12-11';
        }),
        'effective_date': '2026-12-11',
      };
  return a;
}

void main() {
  setUp(() => L10n.lang = AppLang.en);

  test('mapping: a scheduled cancellation of an "until cancelled" membership', () {
    final m = copy((memberships['data'] as List)[0]) // Dana, monthly, next charge 2026-12-01
      ..['cancel_requested_at'] = '2026-11-11 10:00:00'
      ..['items'][0]['end_date'] = '2026-12-01';
    final r = mapMemberships({
      'data': [m]
    }, customers: mapMembers({'data': []}), plans: mapPlans(plans), today: today);
    final s = r.subscriptions.single;
    expect(s.end, isNull, reason: 'still a monthly membership');
    expect(s.cancelEffective, DateTime(2026, 12, 1));
    expect(r.charges.where((c) => c.status == ChargeStatus.due), isEmpty,
        reason: 'no monthly charge on or after the cancellation date');
  });

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi a) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: a)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    return (store, a);
  }

  Future<void> openAvi(WidgetTester t) async {
    await t.tap(find.text('Avi Cohen').first);
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('freeze and end freeze go to the server', (t) async {
    final (store, a) = await boot(t, api());
    await openAvi(t);
    await tapKey(t, 'freeze');
    await tapKey(t, 'freeze-14');
    expect(a.posts.last.$1, '/gym/memberships/6/freeze');
    expect(a.posts.last.$2, {'days': 14});
    final s = store.subscriptions.firstWhere((x) => x.id == '6');
    expect(s.status, SubStatus.frozen);
    expect(s.frozenUntil, DateTime(2026, 11, 24));
    expect(s.freezeDaysUsed, 14);
    expect(s.end, DateTime(2027, 2, 15));
    expect(find.text('Membership frozen for 14 days'), findsOneWidget);

    await openAvi(t);
    await tapKey(t, 'unfreeze');
    expect(a.posts.last.$1, '/gym/memberships/6/unfreeze');
    expect(store.subscriptions.firstWhere((x) => x.id == '6').status, SubStatus.active);
  });

  testWidgets('cancel goes to the server and shows the date it set', (t) async {
    final (store, a) = await boot(t, api());
    await openAvi(t);
    await tapKey(t, 'cancelSub');
    await tapKey(t, 'confirmCancel');
    expect(a.posts.last.$1, '/gym/memberships/6/cancel');
    expect(a.posts.last.$2, isEmpty);
    final s = store.subscriptions.firstWhere((x) => x.id == '6');
    expect(s.cancelEffective, DateTime(2026, 12, 11));
    expect(find.text('Membership will be cancelled on 11/12/2026'), findsOneWidget);
  });

  testWidgets('a server error: nothing changes in the app, the message shows', (t) async {
    final a = api()..postErrors['/gym/memberships/6/freeze'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: Only 0 freeze days are left this year');
    final (store, _) = await boot(t, a);
    await openAvi(t);
    await tapKey(t, 'freeze');
    await tapKey(t, 'freeze-14');
    expect(find.textContaining('Only 0 freeze days are left'), findsOneWidget);
    final s = store.subscriptions.firstWhere((x) => x.id == '6');
    expect(s.status, SubStatus.active);
    expect(s.frozenUntil, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'the progress dialog closed');
  });
}
