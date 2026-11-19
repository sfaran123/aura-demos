// Several unpaid months in one payment, a debt paid with a new card (the saved
// card stays), and several saved cards per customer.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'desk_fixes_test.dart' show cardApi;
import 'server_sync_test.dart' show members, signedIn, today;
import 'support/fake_api.dart';

/// The fake server with a second failed month for Dana (membership 5).
FakeApi twoMonths() {
  final a = cardApi();
  final ms = jsonDecode(jsonEncode(a.responses['/gym/memberships'])) as Map<String, dynamic>;
  ((ms['data'] as List)[0] as Map)['failed_payments'] = [
    {
      'id': 4,
      'month_key': '2026-09|10',
      'amount': 179.1,
      'attempts': 1,
      'message': 'declined',
      'date': '2026-10-01 06:00:00'
    },
    {
      'id': 3,
      'month_key': '2026-10|10',
      'amount': 179.1,
      'attempts': 2,
      'message': 'declined',
      'date': '2026-11-01 06:00:00'
    },
  ];
  a.responses['/gym/memberships'] = ms;
  return a;
}

/// The fake server that lists two saved cards for Dana.
FakeApi twoCards([FakeApi? base]) {
  final a = base ?? cardApi();
  final ms = jsonDecode(jsonEncode(members)) as Map<String, dynamic>;
  ((ms['data'] as List)[1] as Map)['cards'] = [
    {'id': 11, 'last4': '4815', 'brand': 'Visa', 'expiry': '08/27', 'is_default': true},
    {'id': 12, 'last4': '2222', 'brand': 'Mastercard', 'expiry': '01/29', 'is_default': false},
  ];
  a.responses['/gym/members'] = ms;
  return a;
}

Map<String, Object?> _cards(List<Map<String, Object?>> cards) => {
      'data': {'cards': cards}
    };

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi a, {String tab = 'navCollect'}) async {
    t.view.physicalSize = Size(1080, tab == 'navMembers' ? 9000 : 2400);
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

  Future<void> typeCard(WidgetTester t, String number) async {
    await t.enterText(find.byKey(const Key('cardNumber')), number);
    await t.enterText(find.byKey(const Key('cardExpiry')), '12/30');
    await t.enterText(find.byKey(const Key('cardCvv')), '123');
    await t.pumpAndSettle();
  }

  Future<void> openCustomer(WidgetTester t) async {
    await tapKey(t, 'allCustomers');
    await tapKey(t, 'customer-7');
  }

  // Without the question "does the server make one document?" (no months in it).
  List<Map<String, Object?>> sent(FakeApi a, String path) => [
        for (final p in a.posts)
          if (p.$1 == path && !(p.$2['months'] is List && (p.$2['months'] as List).isEmpty)) p.$2
      ];
  List<String> paths(FakeApi a) => a.posts.map((p) => p.$1).toList();

  Map<String, Object?> document(Map<String, Object?> b) => {
        'document': {'id': 901, 'reference_no': 'TIN-901', 'grand_total': b['amount']}
      };

  /// Opens the two failed months of Dana from the collection list.
  Future<void> openBoth(WidgetTester t) async {
    await tapKey(t, 'debts-7');
    await tapKey(t, 'payAll-7');
  }

  group('several months in one payment', () {
    testWidgets('all months, cash: one request, one document with a line per month', (t) async {
      final a = twoMonths()..postHandlers['/gym/memberships/5/collect-months'] = document;
      await boot(t, a);
      await openBoth(t);
      expect(find.byKey(const Key('debt-failed-3')), findsOneWidget);
      expect(find.byKey(const Key('debt-failed-4')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(358.2));
      await tapKey(t, 'debtsMethod-cash');
      await tapKey(t, 'debtsPay');
      final body = sent(a, '/gym/memberships/5/collect-months').single;
      expect(body['method'], 'cash');
      expect(body['amount'], 358.2);
      expect((body['months'] as List).map((m) => (m as Map)['month_key']), ['2026-09|10', '2026-10|10']);
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
      expect(find.textContaining('TIN-901'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a server without the endpoint: each month is recorded on its own', (t) async {
      final a = twoMonths();
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-cash');
      await tapKey(t, 'debtsPay');
      // Said before anything is recorded: a document per month.
      expect(find.text('2 separate documents will be made'), findsOneWidget);
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
      await tapKey(t, 'manyDocumentsGo');
      expect(sent(a, '/gym/memberships/5/collect').map((b) => b['month_key']), ['2026-09|10', '2026-10|10']);
    });

    testWidgets('a server without the endpoint, and the desk wants one document: nothing is recorded', (t) async {
      final a = twoMonths();
      final (store, _) = await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-cash');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'manyDocumentsCancel');
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
      expect(store.openDebtsOf('7'), hasLength(2));
      expect(find.byKey(const Key('debtsPay')), findsOneWidget);
    });

    testWidgets('one month is unticked: the total follows and only the other is paid', (t) async {
      final a = twoMonths()..postHandlers['/gym/memberships/5/collect-months'] = document;
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debt-failed-4');
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(179.1));
      await tapKey(t, 'debtsMethod-cash');
      await tapKey(t, 'debtsPay');
      expect(sent(a, '/gym/memberships/5/collect-months'), isEmpty);
      expect(sent(a, '/gym/memberships/5/collect').single['month_key'], '2026-10|10');
    });

    testWidgets('select all clears and chooses everything', (t) async {
      await boot(t, twoMonths());
      await openBoth(t);
      await tapKey(t, 'debtsAll');
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(0));
      expect(t.widget<FilledButton>(find.byKey(const Key('debtsPay'))).onPressed, isNull);
      await tapKey(t, 'debtsAll');
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(358.2));
    });

    testWidgets('the saved card: charged ONCE for the total, then recorded with the answer', (t) async {
      final a = twoMonths()..postHandlers['/gym/memberships/5/collect-months'] = document;
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-card');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedPayments-3');
      final charge = sent(a, '/gym/card-charges').single;
      expect(charge['amount'], 358.2);
      expect(charge['payments'], 3);
      final p = paths(a);
      expect(p.indexOf('/gym/card-charges'), lessThan(p.lastIndexOf('/gym/memberships/5/collect-months')));
      final body = sent(a, '/gym/memberships/5/collect-months').single;
      expect(body['card_receipt'], contains('ZC-1'));
      expect(body['app_uuid'], charge['app_uuid']);
    });

    testWidgets('the card is not approved: nothing is recorded, every month stays open', (t) async {
      final a = twoMonths()
        ..postHandlers['/gym/memberships/5/collect-months'] = document
        ..postErrors['/gym/card-charges'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_declined: Refused');
      final (store, _) = await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-card');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedRegular');
      expect(find.textContaining('Refused'), findsOneWidget);
      expect(sent(a, '/gym/memberships/5/collect-months'), isEmpty);
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
      expect(store.openDebtsOf('7'), hasLength(2));
      expect(find.byKey(const Key('debtsPay')), findsOneWidget, reason: 'still open, to try again');
    });

    testWidgets('a server that answers 405 for collect-months: each month is recorded on its own', (t) async {
      final a = twoMonths()
        ..postErrors['/gym/memberships/5/collect-months'] =
            AuraApiException(AuraErrorKind.server, 'HTTP 405: The POST method is not supported');
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-card');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedPayments-4');
      // Asked before the card is charged.
      expect(sent(a, '/gym/card-charges'), isEmpty);
      await tapKey(t, 'manyDocumentsGo');
      expect(sent(a, '/gym/card-charges'), hasLength(1));
      expect(sent(a, '/gym/memberships/5/collect').map((b) => b['month_key']), ['2026-09|10', '2026-10|10']);
      expect(find.byKey(const Key('cardProblemDialog')), findsNothing);
    });

    testWidgets('charged but not recorded: an alert on top says so, and trying again does not charge twice', (t) async {
      final a = twoMonths()
        ..postErrors['/gym/memberships/5/collect-months'] = AuraApiException(AuraErrorKind.server, 'HTTP 500: boom');
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-card');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedRegular');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(find.text('Card charged, payment not recorded'), findsOneWidget);
      expect(find.textContaining('the card is not charged again'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');
      a.postErrors.remove('/gym/memberships/5/collect-months');
      a.postHandlers['/gym/memberships/5/collect-months'] = document;
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedRegular');
      expect(sent(a, '/gym/card-charges'), hasLength(1));
      expect(sent(a, '/gym/memberships/5/collect-months'), hasLength(2));
    });

    testWidgets('a refused card: the words of the card company in an alert on top', (t) async {
      final a = twoMonths()
        ..postErrors['/gym/card-charges'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_declined: Refused');
      await boot(t, a);
      await openBoth(t);
      await tapKey(t, 'debtsMethod-card');
      await tapKey(t, 'debtsPay');
      await tapKey(t, 'cardSavedPayments-6');
      await tapKey(t, 'manyDocumentsGo');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(find.text('The charge did not go through'), findsOneWidget);
      expect(find.textContaining('Refused'), findsOneWidget);
    });

    testWidgets('the customer page lists the unpaid months with the total', (t) async {
      await boot(t, twoMonths(), tab: 'navMembers');
      await openCustomer(t);
      expect(find.text('Unpaid months (2)'), findsOneWidget);
      expect(find.byKey(const Key('debt-failed-3')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(358.2));
    });

    testWidgets('the member pop-up opens the same list', (t) async {
      await boot(t, twoMonths(), tab: 'navMembers');
      await t.tap(find.text('Dana Levi').first);
      await t.pumpAndSettle();
      await tapKey(t, 'memberPayDebts');
      expect(find.byKey(const Key('debt-failed-3')), findsOneWidget);
      expect(find.byKey(const Key('debt-failed-4')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('debtsTotal'))).data, money(358.2));
    });
  });

  group('a debt paid with a new card', () {
    Map<String, Object?> newCardOk(Map<String, Object?> b) =>
        {'receipt': '{"HasError":false,"ReferenceNumber":"ZC-NEW"}', 'card_last4': '1111'};

    Future<void> toNewCard(WidgetTester t) async {
      await tapKey(t, 'collect-failed-3');
      await tapKey(t, 'collectWith-card');
      await tapKey(t, 'cardNew');
      await typeCard(t, '4111111111111111');
    }

    testWidgets('charged and recorded; the saved card is not charged and not changed; then saved on request',
        (t) async {
      final a = cardApi()
        ..postHandlers['/gym/card-charges/new-card'] = newCardOk
        ..postHandlers['/gym/card-charges/save-card'] = (b) => _cards([
              {'id': 11, 'last4': '4815', 'is_default': true},
              {'id': 12, 'last4': '1111', 'brand': 'Visa'},
            ]);
      final (store, _) = await boot(t, a);
      await toNewCard(t);
      await tapKey(t, 'newCardPay');
      final charge = sent(a, '/gym/card-charges/new-card').single;
      expect(charge['amount'], 179.1);
      expect(charge['card_number'], '4111111111111111');
      expect(sent(a, '/gym/card-charges'), isEmpty, reason: 'the saved card is not charged');
      final collect = sent(a, '/gym/memberships/5/collect').single;
      expect(collect['card_receipt'], contains('ZC-NEW'));
      expect(collect.values.join(' '), isNot(contains('4111111111111111')),
          reason: 'only the token side knows the card');
      // Asked whether to save the new card.
      expect(find.byKey(const Key('saveNewCardDialog')), findsOneWidget);
      expect(store.customer('7')!.savedCardLast4, '4815');
      await tapKey(t, 'saveNewCardYes');
      expect(sent(a, '/gym/card-charges/save-card').single['app_uuid'], charge['app_uuid']);
      expect(sent(a, '/gym/card-charges/save-card').single['make_default'], false,
          reason: 'the existing card stays the default');
      expect(find.byKey(const Key('cardSavedMessage')), findsOneWidget);
      // (The list itself comes back with the next sync; this fake server's members have no cards.)
      expect(store.customer('7')!.savedCardLast4, '4815');
    });

    testWidgets('"do not save": nothing more is sent', (t) async {
      final a = cardApi()..postHandlers['/gym/card-charges/new-card'] = newCardOk;
      final (store, _) = await boot(t, a);
      await toNewCard(t);
      await tapKey(t, 'newCardPay');
      await tapKey(t, 'saveNewCardNo');
      expect(sent(a, '/gym/card-charges/save-card'), isEmpty);
      expect(store.customer('7')!.savedCards, hasLength(1));
    });

    testWidgets('not approved: the error is shown, the debt stays open, another card can be tried', (t) async {
      final a = cardApi()
        ..postErrors['/gym/card-charges/new-card'] =
            AuraApiException(AuraErrorKind.server, 'HTTP 422: card_declined: Insufficient funds');
      final (store, _) = await boot(t, a);
      await toNewCard(t);
      await tapKey(t, 'newCardPay');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(find.textContaining('Insufficient funds'), findsWidgets);
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
      expect(store.toCollect.any((c) => c.id == 'failed-3'), isTrue);
      await tapKey(t, 'cardProblemOk');
      // Another card.
      a.postErrors.remove('/gym/card-charges/new-card');
      a.postHandlers['/gym/card-charges/new-card'] = newCardOk;
      await typeCard(t, '5555555555554444');
      await tapKey(t, 'newCardPay');
      expect(sent(a, '/gym/card-charges/new-card').last['card_number'], '5555555555554444');
      expect(sent(a, '/gym/memberships/5/collect'), hasLength(1));
    });

    testWidgets('a server without the endpoint says so and records nothing', (t) async {
      final a = cardApi();
      await boot(t, a);
      await toNewCard(t);
      await tapKey(t, 'newCardPay');
      expect(find.textContaining('not available on the server yet'), findsWidgets);
      expect(sent(a, '/gym/memberships/5/collect'), isEmpty);
    });

    testWidgets('a card that is not valid is stopped before anything is sent', (t) async {
      final a = cardApi()..postHandlers['/gym/card-charges/new-card'] = newCardOk;
      await boot(t, a);
      await tapKey(t, 'collect-failed-3');
      await tapKey(t, 'collectWith-card');
      await tapKey(t, 'cardNew');
      await typeCard(t, '1234');
      await tapKey(t, 'newCardPay');
      expect(find.byKey(const Key('cardProblemDialog')), findsOneWidget);
      expect(sent(a, '/gym/card-charges/new-card'), isEmpty);
    });
  });

  group('several saved cards', () {
    testWidgets('the customer page lists them; the default can be changed', (t) async {
      final a = twoCards()
        ..postHandlers['/gym/members/7/cards/12/default'] = (b) => _cards([
              {'id': 11, 'last4': '4815', 'brand': 'Visa', 'expiry': '08/27', 'is_default': false},
              {'id': 12, 'last4': '2222', 'brand': 'Mastercard', 'expiry': '01/29', 'is_default': true},
            ]);
      final (store, _) = await boot(t, a, tab: 'navMembers');
      await openCustomer(t);
      expect(find.text('Saved cards (2)'), findsOneWidget);
      expect(find.text('Visa •••• 4815'), findsOneWidget);
      expect(find.text('Expires 01/29'), findsOneWidget);
      expect(store.customer('7')!.defaultCard!.id, '11');
      await tapKey(t, 'cardMenu-12');
      await tapKey(t, 'cardDefault-12');
      expect(store.customer('7')!.defaultCard!.last4, '2222');
      expect(store.customer('7')!.savedCardLast4, '2222');
    });

    testWidgets('a card is removed after a confirmation', (t) async {
      final a = twoCards()
        ..postHandlers['/gym/members/7/cards/11/delete'] = (b) => _cards([
              {'id': 12, 'last4': '2222', 'brand': 'Mastercard', 'is_default': true},
            ]);
      final (store, _) = await boot(t, a, tab: 'navMembers');
      await openCustomer(t);
      await tapKey(t, 'cardMenu-11');
      await tapKey(t, 'cardRemove-11');
      expect(find.byKey(const Key('removeCardDialog')), findsOneWidget);
      expect(sent(a, '/gym/members/7/cards/11/delete'), isEmpty, reason: 'not before the confirmation');
      await tapKey(t, 'removeCardConfirm');
      expect(store.customer('7')!.savedCards.map((c) => c.last4), ['2222']);
    });

    testWidgets('another card is added next to the saved ones', (t) async {
      final a = twoCards()
        ..postHandlers['/gym/members/7/cards'] = (b) => _cards([
              {'id': 11, 'last4': '4815', 'is_default': true},
              {'id': 12, 'last4': '2222'},
              {'id': 13, 'last4': '1111', 'brand': 'Visa'},
            ]);
      final (store, _) = await boot(t, a, tab: 'navMembers');
      await openCustomer(t);
      await tapKey(t, 'customerAddCard');
      await typeCard(t, '4111111111111111');
      await tapKey(t, 'saveMemberCard');
      expect(sent(a, '/gym/members/7/cards').single['make_default'], false);
      expect(sent(a, '/gym/members/7/card'), isEmpty, reason: 'the saved card is not replaced');
      expect(store.customer('7')!.savedCards, hasLength(3));
      expect(store.customer('7')!.defaultCard!.last4, '4815');
    });

    testWidgets('a server that keeps one card says so; the saved card is not replaced', (t) async {
      final a = cardApi();
      final (store, _) = await boot(t, a, tab: 'navMembers');
      await openCustomer(t);
      expect(find.text('Saved cards (1)'), findsOneWidget);
      await tapKey(t, 'customerAddCard');
      await typeCard(t, '4111111111111111');
      await tapKey(t, 'saveMemberCard');
      expect(find.textContaining('keeps one card'), findsWidgets);
      expect(sent(a, '/gym/members/7/card'), isEmpty);
      expect(store.customer('7')!.savedCardLast4, '4815');
    });

    testWidgets('a debt is charged to the card that was picked', (t) async {
      final a = twoCards();
      await boot(t, a);
      await tapKey(t, 'collect-failed-3');
      await tapKey(t, 'collectWith-card');
      await tapKey(t, 'cardPick-12');
      await tapKey(t, 'cardSavedRegular');
      expect(sent(a, '/gym/card-charges').single['card_id'], 12);
      expect(find.textContaining('2222'), findsWidgets);
    });

    testWidgets('one saved card of an older server: no card id is sent', (t) async {
      final a = cardApi();
      await boot(t, a);
      await tapKey(t, 'collect-failed-3');
      await tapKey(t, 'collectWith-card');
      expect(find.byKey(const Key('cardPick-')), findsNothing);
      await tapKey(t, 'cardSavedRegular');
      expect(sent(a, '/gym/card-charges').single.containsKey('card_id'), isFalse);
    });

    test('in the demo: add, default, remove; the last card of a card-billed membership is known', () {
      final store = GymStore(clock: () => today);
      final c = store.upsertCustomer(Customer(id: 'x1', name: 'Test', phone: '050', savedCardLast4: '1234'));
      store.addCustomerCard(c, '4111111111111111', expiry: '12/30');
      expect(c.savedCards.map((x) => x.last4), ['1234', '1111']);
      expect(c.savedCards.last.brand, 'Visa');
      expect(c.defaultCard!.last4, '1234');
      store.setDefaultCustomerCard(c, c.savedCards.last);
      expect(c.savedCardLast4, '1111');
      store.removeCustomerCard(c, c.defaultCard!);
      expect(c.savedCards.map((x) => x.last4), ['1234']);
      expect(c.defaultCard!.isDefault, isTrue);
      store.removeCustomerCard(c, c.defaultCard!);
      expect(c.hasSavedCard, isFalse);
      // Saved and loaded again.
      store.addCustomerCard(c, '5555555555554444');
      store.addCustomerCard(c, '4111111111111111');
      final again = Customer.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(again.savedCards.map((x) => x.last4), ['4444', '1111']);
      expect(store.hasCardBilledMembership('x1'), isFalse);
    });
  });
}
