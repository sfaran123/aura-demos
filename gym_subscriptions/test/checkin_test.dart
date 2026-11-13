// Check-in: the desk records that a member came in.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/visits.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'package:aura_gym/src/integration/aura_api.dart';

import 'server_sync_test.dart' show members, memberships, serverApi, signedIn, today;
import 'support/fake_api.dart';

/// The server's data; Avi (member 8) has a 10-entry card with [entries] left.
/// [edit] changes Avi's membership row before the app loads it; [more] are extra membership rows.
FakeApi api({int entries = 7, void Function(Map row)? edit, List<Map<String, Object?>> more = const []}) {
  final ms = (jsonDecode(jsonEncode(memberships)) as Map).cast<String, dynamic>();
  final avi = (ms['data'] as List)[1] as Map;
  avi['entries_remaining'] = entries;
  edit?.call(avi);
  ms['data'] = [...(ms['data'] as List), ...more];
  return serverApi()..responses['/gym/memberships'] = ms;
}

/// A running monthly membership (plan 10, no entries) of Avi, next to his card.
final aviMonthly = <String, Object?>{
  'id': 20,
  'customer_id': 8,
  'customer_name': 'Avi Cohen',
  'status': 'active',
  'auto_payment_type': 'credit_card',
  'entries_remaining': null,
  'created_at': '2026-11-01 09:00:00',
  'items': [
    {
      'product_id': 10,
      'product_name': 'Monthly',
      'total': 199,
      'start_date': '2026-11-01',
      'end_date': '2126-11-01',
      'periods': 0,
      'period_unit': 'month',
      'next_payment_date': '2026-12-01',
      'payments_total': 1200,
      'payments_done': 1,
    }
  ],
  'failed_payments': [],
  'freezes': [],
};

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi a) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today.add(const Duration(hours: 9, minutes: 30)));
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: a)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navCheckin')));
    await t.pumpAndSettle();
    return (store, a);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> search(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const Key('checkinSearch')), text);
    await t.pumpAndSettle();
  }

  String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('one touch records the visit; a server without visits keeps it on the device', (t) async {
    final (store, a) = await boot(t, api());
    expect(find.text('Came in today (0)'), findsOneWidget);
    await search(t, 'Avi');
    expect(text(t, 'checkinStatus-8'), '7 entries left');
    await tapKey(t, 'checkin-8');
    // The server was asked first; it has no visits yet (404), so the visit is local.
    expect(a.posts.last.$1, '/gym/memberships/6/visits');
    expect(a.posts.last.$2, {'force': false});
    expect(store.visits.single.local, isTrue);
    expect(store.entriesLeft(store.subscriptions.firstWhere((s) => s.id == '6')), 6);
    expect(text(t, 'checkinResultText'), 'Checked in at 09:30 · 6 entries left');
    // The search is cleared for the next member, and the visit is in today's list.
    expect(find.text('Came in today (1)'), findsOneWidget);
    expect(find.byKey(Key('visit-${store.visits.single.id}')), findsOneWidget);
  });

  testWidgets('a visit recorded by mistake is taken back: the entry returns', (t) async {
    final (store, _) = await boot(t, api());
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    await tapKey(t, 'checkinUndo');
    expect(store.visits, isEmpty);
    expect(store.entriesLeft(store.subscriptions.firstWhere((s) => s.id == '6')), 7);
    expect(find.byKey(const Key('checkinResult')), findsNothing);
    expect(find.text('Came in today (0)'), findsOneWidget);
    // Also from today's list.
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    await tapKey(t, 'undoVisit-${store.visits.single.id}');
    // From a list it asks first: a slip of the finger does not lose a real visit.
    expect(find.text('Cancel the visit?'), findsOneWidget);
    expect(store.visits, hasLength(1));
    await tapKey(t, 'confirmUndoVisit');
    expect(store.visits, isEmpty);
  });

  testWidgets('the server records the visit and answers the entries left; the undo goes to the server', (t) async {
    final a = api();
    a.postHandlers['/gym/memberships/6/visits'] = (b) => {
          'data': {'id': 41, 'subscription_id': 6, 'customer_id': 8, 'created_at': '2026-11-11 09:31:00'},
          'entries_remaining': 6,
        };
    a.postHandlers['/gym/visits/41/cancel'] = (b) => {'entries_remaining': 7};
    final (store, _) = await boot(t, a);
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(store.visits.single.id, '41');
    expect(store.visits.single.local, isFalse);
    expect(text(t, 'checkinResultText'), 'Checked in at 09:31 · 6 entries left');
    await tapKey(t, 'checkinUndo');
    expect(a.posts.last.$1, '/gym/visits/41/cancel');
    expect(store.visits, isEmpty);
    expect(store.subscriptions.firstWhere((s) => s.id == '6').entriesLeft, 7);
  });

  testWidgets('a used-up card is not recorded unless the desk lets the member in', (t) async {
    final (store, a) = await boot(t, api(entries: 0));
    await search(t, 'Avi');
    expect(text(t, 'checkinStatus-8'), 'The punch card is used up');
    await tapKey(t, 'checkin-8');
    expect(text(t, 'checkinBlockedReason'), 'The punch card is used up');
    expect(store.visits, isEmpty);
    expect(a.posts.where((p) => p.$1.endsWith('/visits')), isEmpty);
    await tapKey(t, 'checkinLetIn');
    expect(a.posts.last.$2, {'force': true});
    expect(store.visits, hasLength(1));
  });

  testWidgets('the last entry is recorded with a warning; a second visit today is asked about', (t) async {
    final (store, _) = await boot(t, api(entries: 2));
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(store.visits, hasLength(1));
    await search(t, 'Avi');
    expect(text(t, 'checkinStatus-8'), 'Last entry on the card · 1 entry left · Already in today');
    await tapKey(t, 'checkin-8');
    expect(find.text('Avi Cohen is already checked in today'), findsOneWidget);
    expect(store.visits, hasLength(1), reason: 'nothing until the desk confirms');
    await tapKey(t, 'checkinAgain');
    expect(store.visits, hasLength(2));
    expect(store.entryCheck(store.customers.firstWhere((c) => c.id == '8')).level, EntryLevel.blocked);
  });

  testWidgets('found by the last digits of the phone and in any letter case; Enter records a single match', (t) async {
    final (store, _) = await boot(t, api());
    await search(t, '4321');
    expect(find.byKey(const Key('checkin-8')), findsOneWidget);
    expect(find.byKey(const Key('checkin-7')), findsNothing);
    await search(t, 'avi co');
    expect(find.byKey(const Key('checkin-8')), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(store.visits.single.customerId, '8');
    await search(t, 'zzz');
    expect(find.text('No such member.'), findsOneWidget);
  });

  testWidgets('a frozen membership is stopped; the member card (unfreeze) is one touch away', (t) async {
    final (store, _) = await boot(t, api(edit: (row) {
      row['status'] = 'frozen';
      row['frozen_until'] = '2026-11-20';
    }));
    await search(t, 'Avi');
    expect(text(t, 'checkinStatus-8'), 'The membership is frozen until 20/11/2026');
    await tapKey(t, 'checkin-8');
    expect(find.byKey(const Key('checkinFix')), findsNothing, reason: 'nothing to renew or collect');
    await tapKey(t, 'checkinOpenCard');
    expect(find.byKey(const Key('unfreeze'), skipOffstage: false), findsOneWidget);
    expect(store.visits, isEmpty);
  });

  testWidgets('a member without a membership: a new membership or a paid one-time entry, no visit', (t) async {
    final a = api();
    final ms = (jsonDecode(jsonEncode(members)) as Map).cast<String, dynamic>();
    (ms['data'] as List).add({'id': 12, 'name': 'Noa Bar', 'phone': '054-1112233', 'is_walk_in': false});
    a.responses['/gym/members'] = ms;
    final (store, _) = await boot(t, a);
    await search(t, 'Noa');
    expect(text(t, 'checkinStatus-12'), 'No membership');
    await tapKey(t, 'checkin-12');
    expect(find.byKey(const Key('checkinFix')), findsOneWidget);
    expect(find.byKey(const Key('checkinOneTime')), findsOneWidget);
    expect(find.byKey(const Key('checkinLetIn')), findsNothing, reason: 'no membership to record the visit on');
    expect(store.visits, isEmpty);
  });

  testWidgets('a membership that ended is stopped with its date', (t) async {
    final (store, _) =
        await boot(t, api(edit: (row) => ((row['items'] as List).first as Map)['end_date'] = '2026-11-05'));
    final check = store.entryCheck(store.customers.firstWhere((c) => c.id == '8'));
    expect(check.level, EntryLevel.blocked);
    expect(check.message, 'The membership ended on 05/11/2026');
    expect(check.fix, EntryFix.renew);
  });

  testWidgets('a membership ending this week is recorded with a warning', (t) async {
    final (store, _) =
        await boot(t, api(edit: (row) => ((row['items'] as List).first as Map)['end_date'] = '2026-11-15'));
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(store.visits, hasLength(1));
    expect(text(t, 'checkinResultText'), contains('The membership ends on 15/11/2026'));
  });

  testWidgets('two memberships: the desk picks which one takes the visit', (t) async {
    final (store, _) = await boot(t, api(more: [aviMonthly]));
    final avi = store.customers.firstWhere((c) => c.id == '8');
    expect(store.entryChecks(avi), hasLength(2));
    expect(store.entryCheck(avi).subscription!.id, '20', reason: 'the unlimited one first: no entry is spent');
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(find.text("Which membership is Avi Cohen's visit recorded on?"), findsOneWidget);
    expect(store.visits, isEmpty);
    await tapKey(t, 'checkinPick-6');
    expect(store.visits.single.subscriptionId, '6');
    expect(store.entriesLeft(store.subscriptions.firstWhere((s) => s.id == '6')), 6);
  });

  testWidgets('a used-up card next to a running monthly membership: the visit goes on the monthly one', (t) async {
    final (store, _) = await boot(t, api(entries: 0, more: [aviMonthly]));
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(store.visits.single.subscriptionId, '20');
  });

  testWidgets('a weekly limit: counted from Sunday, then stopped', (t) async {
    final (store, _) = await boot(t, api());
    final sub = store.subscriptions.firstWhere((s) => s.id == '6');
    final avi = store.customers.firstWhere((c) => c.id == '8');
    store.plan(sub.planId)!.weeklyLimit = 2;
    // 11 Nov 2026 is a Wednesday: the week started on Sunday the 8th.
    expect(store.weekStart, DateTime(2026, 11, 8));
    store.checkIn(sub, at: DateTime(2026, 11, 7, 10)); // last week: not counted
    store.checkIn(sub, at: DateTime(2026, 11, 8, 10));
    expect(store.entryCheck(avi).level, EntryLevel.ok);
    store.checkIn(sub, at: DateTime(2026, 11, 10, 10));
    expect(store.visitsThisWeek(sub.id), 2);
    expect(store.entryCheck(avi).level, EntryLevel.blocked);
    expect(store.entryCheck(avi).message, "All 2 of this week's visits are used");
  });

  testWidgets('the server refuses: nothing is recorded and the message shows', (t) async {
    final a = api();
    a.postErrors['/gym/memberships/6/visits'] = AuraApiException(AuraErrorKind.server, 'HTTP 500');
    final (store, _) = await boot(t, a);
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    expect(store.visits, isEmpty);
    expect(find.byKey(const Key('checkinResult')), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('the server refuses to take a visit back: it stays', (t) async {
    final a = api();
    a.postHandlers['/gym/memberships/6/visits'] = (b) => {
          'data': {'id': 41, 'created_at': '2026-11-11 09:31:00'},
          'entries_remaining': 6,
        };
    a.postErrors['/gym/visits/41/cancel'] = AuraApiException(AuraErrorKind.server, 'HTTP 500');
    final (store, _) = await boot(t, a);
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    await tapKey(t, 'checkinUndo');
    expect(store.visits, hasLength(1));
    expect(find.byKey(const Key('checkinResult')), findsOneWidget);
  });

  testWidgets("the server's visits are loaded; the ones kept on the device stay through a reload and a sign-out",
      (t) async {
    final a = api();
    a.responses['/gym/visits'] = {
      'data': [
        {'id': 70, 'subscription_id': 6, 'customer_id': 8, 'created_at': '2026-11-11 07:15:00'},
        {'id': 71, 'subscription_id': 6, 'customer_id': 8, 'created_at': '2026-11-03 18:00:00'},
      ]
    };
    final (store, _) = await boot(t, a);
    expect(a.calls, contains('GET /gym/visits?from=2026-09-12'));
    expect(find.text('Came in today (1)'), findsOneWidget);
    final sub = store.subscriptions.firstWhere((s) => s.id == '6');
    expect(store.entriesLeft(sub), 7, reason: "the server's visits are already in its number");
    final local = store.checkIn(sub);
    store.applyServerData(
        customers: [...store.customers],
        plans: [...store.plans],
        subscriptions: [...store.subscriptions],
        charges: [...store.charges],
        items: store.items,
        receipts: [...store.receipts],
        visits: [Visit(id: '70', subscriptionId: '6', customerId: '8', at: DateTime(2026, 11, 11, 7, 15))]);
    expect(store.visits.map((v) => v.id), [local.id, '70'],
        reason: 'the device visit stays, the server list is replaced');
    // Sign-out: the business's data leaves the device; the visits only this device has stay.
    store.clearServerData();
    expect(store.visits.single.id, local.id);
    // Another business signs in on this device: nothing of the old one stays.
    store.clearServerData(settings: true, owner: 'other.example');
    expect(store.visits, isEmpty);
  });

  testWidgets('the demo (not signed in): visits work without a server', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore();
    await t.pumpWidget(AuraGymApp(store: store));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navCheckin')));
    await t.pumpAndSettle();
    // Every demo member gets an answer, whatever their membership is.
    for (final c in store.customers) {
      final check = store.entryCheck(c);
      expect(check.level == EntryLevel.blocked || check.subscription != null, isTrue);
    }
    final cards = store.subscriptions.where((s) => s.entriesLeft != null).toList();
    final card = cards.firstWhere((s) =>
        s.entriesLeft! > 1 &&
        store.entryCheck(store.customer(s.customerId)!).subscription?.id == s.id &&
        store.entryCheck(store.customer(s.customerId)!).level != EntryLevel.blocked &&
        store.entryChecks(store.customer(s.customerId)!).where((x) => x.level != EntryLevel.blocked).length == 1);
    final before = store.entriesLeft(card)!;
    await search(t, store.customer(card.customerId)!.name);
    await tapKey(t, 'checkin-${card.customerId}');
    expect(store.entriesLeft(card), before - 1);
    await tapKey(t, 'checkinUndo');
    expect(store.entriesLeft(card), before);
  });

  testWidgets('the member card: check-in, the history, and taking a visit back', (t) async {
    final (store, _) = await boot(t, api());
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    await t.tap(find.text('Avi Cohen').last);
    await t.pumpAndSettle();
    await tapKey(t, 'memberCheckin');
    expect(store.visits, hasLength(1));
    expect(find.text('Last visits (1)', skipOffstage: false), findsOneWidget);
    await tapKey(t, 'undoVisit-${store.visits.single.id}');
    await tapKey(t, 'confirmUndoVisit');
    expect(store.visits, isEmpty);
    expect(find.text('Last visits (1)', skipOffstage: false), findsNothing);
  });

  testWidgets('the visits are kept on the device and shown on the member card', (t) async {
    final (store, _) = await boot(t, api());
    await search(t, 'Avi');
    await tapKey(t, 'checkin-8');
    final saved = (jsonDecode(jsonEncode(store.toJson()['visits'])) as List).single as Map;
    expect(Visit.fromJson(saved.cast<String, dynamic>()).subscriptionId, '6');
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    await t.tap(find.text('Avi Cohen').last);
    await t.pumpAndSettle();
    expect(find.text('Last visits (1)', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('memberCheckin'), skipOffstage: false), findsOneWidget);
  });
}
