// A member's saved card, as the web's customer page: added for a new member,
// or added / changed for an existing one. The server checks the card with
// Z Credit (gym/members/{id}/card → HomeController::checkCard) and keeps the
// token; the app keeps only the last four digits.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/card_entry.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'add_member_test.dart' show customerStore;
import 'new_membership_test.dart' as nm show posSettings;
import 'new_membership_test.dart' show payingApi;
import 'server_sync_test.dart' show memberships, serverApi, signedIn, today;
import 'support/fake_api.dart';

Map<String, Object?> posSettings({bool cardTokens = true}) => {
      'data': {'business_type': 0, 'decimal': 2, 'customer_id': 1, 'card_tokens': cardTokens}
    };

/// Answers like GymController::saveMemberCard.
Object? Function(Map<String, Object?>) cardSaved(int id) => (body) => {
      'data': {'id': id, 'has_saved_card': true, 'card_last4': '${body['card_number']}'.substring(12)}
    };

void main() {
  setUp(() => L10n.lang = AppLang.en);

  group('typing rules (the web customer page)', () {
    test('expiry is formatted as the web formats it', () {
      expect(formatExpiryInput('3'), '03/');
      expect(formatExpiryInput('1'), '1');
      expect(formatExpiryInput('12'), '12/');
      expect(formatExpiryInput('13'), '12/');
      expect(formatExpiryInput('00'), '01/');
      expect(formatExpiryInput('0928'), '09/28');
      expect(formatExpiryInput('12/2030'), '12/30');
      expect(formatExpiryInput(''), '');
    });

    test('card number is grouped by four, digits only', () {
      expect(formatCardNumberInput('4580000000001111'), '4580 0000 0000 1111');
      expect(formatCardNumberInput('4580-00'), '4580 00');
    });

    test('checks before anything is sent', () {
      expect(cardNumberError(''), isNotNull);
      expect(cardNumberError('1234567'), isNotNull);
      expect(cardNumberError('12345678'), isNull, reason: 'Isracard: 8 digits, no Luhn');
      expect(cardNumberError('4580 0000 0000 1112'), isNull, reason: 'no Luhn check, as the web');
      expect(cardNumberError('1' * 20), isNotNull);
      expect(cvvError('12'), isNotNull);
      expect(cvvError('123'), isNull);
      expect(cvvError('1234'), isNull);
      expect(expiryError('11/26', today), isNull, reason: 'valid through the end of the month');
      expect(expiryError('10/26', today), isNotNull);
      expect(expiryError('13/30', today), isNotNull);
      expect(expiryError('1230', today), isNotNull);
    });
  });

  Future<(GymStore, FakeApi)> boot(WidgetTester t, FakeApi api) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
    await t.pumpAndSettle();
    return (store, api);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> typeCard(WidgetTester t, {String number = '4580000000001111', String expiry = '0928', String cvv = '123'}) async {
    await t.enterText(find.byKey(const Key('cardNumber')), number);
    await t.enterText(find.byKey(const Key('cardExpiry')), expiry);
    await t.enterText(find.byKey(const Key('cardCvv')), cvv);
    await t.pumpAndSettle();
  }

  Future<void> openMember(WidgetTester t, String name) async {
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    await t.tap(find.text(name).first);
    await t.pumpAndSettle();
  }

  group('existing member', () {
    testWidgets('adds a card: sent to the server, the app keeps the last 4', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/gym/members/8/card'] = cardSaved(8);
      final (store, _) = await boot(t, api);
      await openMember(t, 'Avi Cohen');
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('Add card'), findsOneWidget);
      await tapKey(t, 'memberCard');
      await typeCard(t, number: '4580 0000 0000 1111', expiry: '0928');
      expect(find.text('4580 0000 0000 1111'), findsOneWidget);
      expect(find.text('09/28'), findsOneWidget);
      await tapKey(t, 'saveMemberCard');

      expect(api.posts.last.$1, '/gym/members/8/card');
      expect(api.posts.last.$2, {'card_number': '4580000000001111', 'cvv': '123', 'card_expiry_date': '09/28'});
      expect(store.customer('8')!.savedCardLast4, '1111');
      expect(find.text('Card saved · •••• 1111'), findsOneWidget);
      expect(find.byKey(const Key('saveMemberCard')), findsNothing, reason: 'the card sheet closed');
    });

    testWidgets('changes the saved card', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/gym/members/7/card'] = cardSaved(7);
      final (store, _) = await boot(t, api);
      await openMember(t, 'Dana Levi');
      expect(find.text('•••• 4815'), findsOneWidget);
      expect(find.text('Change card'), findsOneWidget);
      await tapKey(t, 'memberCard');
      expect(find.text('The saved card •••• 4815 will be replaced by the new card.'), findsOneWidget);
      await typeCard(t, number: '5326100000002222', expiry: '1230', cvv: '1234');
      await tapKey(t, 'saveMemberCard');
      expect(api.posts.last.$2, {'card_number': '5326100000002222', 'cvv': '1234', 'card_expiry_date': '12/30'});
      expect(store.customer('7')!.savedCardLast4, '2222');
    });

    testWidgets('a declined card keeps the sheet open and the old card', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postErrors['/gym/members/7/card'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_not_valid');
      final (store, _) = await boot(t, api);
      await openMember(t, 'Dana Levi');
      await tapKey(t, 'memberCard');
      await typeCard(t);
      await tapKey(t, 'saveMemberCard');
      expect(find.text('The card was not approved. Check the details and try again.'), findsOneWidget);
      expect(find.byKey(const Key('saveMemberCard')), findsOneWidget);
      expect(store.customer('7')!.savedCardLast4, '4815');
    });

    testWidgets('a wrong card is not sent', (t) async {
      final api = serverApi()..responses['/gym/pos-settings'] = posSettings();
      final (_, _) = await boot(t, api);
      await openMember(t, 'Avi Cohen');
      await tapKey(t, 'memberCard');
      await typeCard(t, expiry: '1025');
      await tapKey(t, 'saveMemberCard');
      expect(find.text('The card has expired'), findsOneWidget);
      expect(api.posts, isEmpty);
    });

    testWidgets('no Z Credit terminal on the server: no card button', (t) async {
      final api = serverApi()..responses['/gym/pos-settings'] = posSettings(cardTokens: false);
      await boot(t, api);
      await openMember(t, 'Avi Cohen');
      expect(find.byKey(const Key('memberCard')), findsNothing);
    });
  });

  group('new member', () {
    Future<void> openNewCustomer(WidgetTester t) async {
      await t.tap(find.byKey(const Key('tileNewSub')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('newCustomer')));
      await t.pumpAndSettle();
    }

    Future<void> fillMember(WidgetTester t) async {
      await t.enterText(find.byKey(const Key('ncName')), 'Noa Bar');
      await t.enterText(find.byKey(const Key('ncPhone')), '0541234567');
    }

    testWidgets('with a card: the member is created, then the card saved for them', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/customer/store'] = customerStore()
        ..postHandlers['/gym/members/321/card'] = cardSaved(321);
      final (store, _) = await boot(t, api);
      await openNewCustomer(t);
      await fillMember(t);
      await tapKey(t, 'ncAddCard');
      await typeCard(t);
      await tapKey(t, 'ncSave');

      expect(api.posts.map((p) => p.$1), ['/customer/store', '/gym/members/321/card']);
      expect(store.customer('321')!.savedCardLast4, '1111');
      expect(find.byKey(const Key('ncSave')), findsNothing, reason: 'the flow went on');
    });

    testWidgets('a wrong card stops before the member is created', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/customer/store'] = customerStore();
      await boot(t, api);
      await openNewCustomer(t);
      await fillMember(t);
      await tapKey(t, 'ncAddCard');
      await typeCard(t, cvv: '1');
      await tapKey(t, 'ncSave');
      expect(find.text('CVV needs 3 or 4 digits'), findsOneWidget);
      expect(api.posts, isEmpty);
    });

    testWidgets('card declined: the member is kept; retry, or go on without the card', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/customer/store'] = customerStore()
        ..postErrors['/gym/members/321/card'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_not_valid');
      final (store, _) = await boot(t, api);
      await openNewCustomer(t);
      await fillMember(t);
      await tapKey(t, 'ncAddCard');
      await typeCard(t);
      await tapKey(t, 'ncSave');
      expect(
          find.text(
              'The member was saved, but the card was not: The card was not approved. Check the details and try again.'),
          findsOneWidget);
      expect(store.customer('321'), isNotNull);
      expect(find.text('Try saving the card again'), findsOneWidget);

      // Retry: the member is not created again.
      await tapKey(t, 'ncSave');
      expect(api.posts.map((p) => p.$1), ['/customer/store', '/gym/members/321/card', '/gym/members/321/card']);

      await tapKey(t, 'ncSkipCard');
      expect(find.byKey(const Key('ncSave')), findsNothing, reason: 'went on without the card');
      expect(store.customer('321')!.hasSavedCard, isFalse);
    });

    testWidgets('an existing member with a saved card: the card is not replaced here', (t) async {
      final api = serverApi()
        ..responses['/gym/pos-settings'] = posSettings()
        ..postHandlers['/customer/store'] = customerStore();
      final (store, _) = await boot(t, api);
      await openNewCustomer(t);
      await t.enterText(find.byKey(const Key('ncName')), 'Dana again');
      await t.enterText(find.byKey(const Key('ncPhone')), '0501234567'); // Dana Levi, card 4815
      await tapKey(t, 'ncAddCard');
      await typeCard(t);
      await tapKey(t, 'ncSave');
      expect(api.posts, isEmpty);
      expect(store.customer('7')!.savedCardLast4, '4815');
      expect(find.textContaining('already has a saved card •••• 4815'), findsOneWidget);
    });
  });

  group('membership card (the web\'s "Update Credit Card Info")', () {
    /// Dana's monthly membership 5 (charged by card, a failed month) as the server returns it.
    Map<String, dynamic> dana([void Function(Map<String, dynamic> m)? edit]) {
      final m = (jsonDecode(jsonEncode((memberships['data'] as List)[0])) as Map).cast<String, dynamic>();
      edit?.call(m);
      return m;
    }

    final failedNov = {'month_key': '2026-11|10', 'year_month': '2026-11', 'label': 'November, 2026', 'amount': 179.1, 'product_id': 10, 'failed_count': 1};
    final failedOct = {'month_key': '2026-10|10', 'year_month': '2026-10', 'label': 'October, 2026', 'amount': 179.1, 'product_id': 10, 'failed_count': 2};

    FakeApi api({List<Map<String, Object?>>? failed}) => serverApi()
      ..responses['/gym/pos-settings'] = posSettings()
      ..postHandlers['/gym/memberships/5/card'] = ((b) => {
            'data': dana((m) => m['has_card_token'] = true),
            'failed_months': failed ?? [failedNov],
          })
      ..postHandlers['/gym/memberships/5/pay-failed-months'] = ((b) => {
            'data': dana((m) => m
              ..['has_card_token'] = true
              ..['status'] = 'active'
              ..['failed_payments'] = []),
            'document': {'reference_no': 'TIN-80020', 'grand_total': 179.1},
            'all_cleared': true,
            'remaining_months': [],
          });

    testWidgets('mapping: has_card_token', (t) async {
      final (store, _) = await boot(t, api()..responses['/gym/memberships'] = {
        'data': [dana((m) => m['has_card_token'] = true)]
      });
      expect(store.subscriptions.firstWhere((s) => s.id == '5').hasCardToken, isTrue);
    });

    testWidgets('new card saved on the membership, then a failed month charged to it', (t) async {
      final a = api();
      final (store, _) = await boot(t, a);
      await openMember(t, 'Dana Levi');
      expect(find.textContaining('has no saved card: the monthly charge will not happen'), findsOneWidget);
      expect(find.text('Membership card'), findsOneWidget);
      await tapKey(t, 'membershipCard');
      expect(find.text('Add a card to the membership'), findsOneWidget);
      expect(find.textContaining("The member's own saved card does not change."), findsOneWidget);
      await typeCard(t, number: '5326100000002222', expiry: '1230');
      await tapKey(t, 'saveMembershipCard');

      expect(a.posts.last.$1, '/gym/memberships/5/card');
      expect(a.posts.last.$2, {'card_number': '5326100000002222', 'cvv': '123', 'card_expiry_date': '12/30'});
      expect(store.subscriptions.firstWhere((s) => s.id == '5').hasCardToken, isTrue);
      expect(store.customer('7')!.savedCardLast4, '4815', reason: "the member's own card is not changed");

      // As the web's modal: the failed months, none chosen yet.
      expect(find.text('Months whose charge failed'), findsOneWidget);
      expect(find.text('11/2026'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('chargeFailedMonths'))).onPressed, isNull);
      await tapKey(t, 'failedMonth-2026-11|10');
      await tapKey(t, 'chargeFailedMonths');

      final pay = a.posts.lastWhere((p) => p.$1 == '/gym/memberships/5/pay-failed-months');
      expect(pay.$2, {
        'months': ['2026-11|10']
      });
      expect(find.textContaining('TIN-80020'), findsOneWidget);
      expect(find.byKey(const Key('chargeFailedMonths')), findsNothing, reason: 'all cleared: the sheet closed');
      expect(a.calls.where((c) => c == 'GET /gym/memberships').length, greaterThan(1), reason: 'synced after the charge');
    });

    testWidgets('a declined charge stays on the months with the bank\'s message', (t) async {
      final a = api(failed: [failedOct, failedNov])
        ..postErrors['/gym/memberships/5/pay-failed-months'] =
            AuraApiException(AuraErrorKind.server, 'HTTP 422: Declined by bank');
      await boot(t, a);
      await openMember(t, 'Dana Levi');
      await tapKey(t, 'membershipCard');
      await typeCard(t);
      await tapKey(t, 'saveMembershipCard');
      expect(find.text('10/2026'), findsOneWidget);
      await tapKey(t, 'failedMonth-2026-10|10');
      await tapKey(t, 'failedMonth-2026-11|10');
      await tapKey(t, 'chargeFailedMonths');
      expect(a.posts.last.$2, {
        'months': ['2026-10|10', '2026-11|10']
      });
      expect(find.text('The charge was not approved: Declined by bank'), findsOneWidget);
      expect(find.byKey(const Key('chargeFailedMonths')), findsOneWidget);
    });

    testWidgets('"Not now": the card is saved, the months stay to collect', (t) async {
      final a = api();
      await boot(t, a);
      await openMember(t, 'Dana Levi');
      await tapKey(t, 'membershipCard');
      await typeCard(t);
      await tapKey(t, 'saveMembershipCard');
      await tapKey(t, 'skipFailedMonths');
      expect(a.posts.where((p) => p.$1.endsWith('pay-failed-months')), isEmpty);
      expect(find.text('Membership card updated. The unpaid months stay on the to-collect list.'), findsOneWidget);
    });

    testWidgets('no failed months: saved and closed', (t) async {
      await boot(t, api(failed: []));
      await openMember(t, 'Dana Levi');
      await tapKey(t, 'membershipCard');
      await typeCard(t);
      await tapKey(t, 'saveMembershipCard');
      expect(find.text('Membership card updated'), findsOneWidget);
      expect(find.byKey(const Key('saveMembershipCard')), findsNothing);
    });

    testWidgets('a declined card is not saved', (t) async {
      final a = api()
        ..postErrors['/gym/memberships/5/card'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: card_not_valid');
      final (store, _) = await boot(t, a);
      await openMember(t, 'Dana Levi');
      await tapKey(t, 'membershipCard');
      await typeCard(t);
      await tapKey(t, 'saveMembershipCard');
      expect(find.text('The card was not approved. Check the details and try again.'), findsOneWidget);
      expect(store.subscriptions.firstWhere((s) => s.id == '5').hasCardToken, isFalse);
    });

    testWidgets('only a membership charged by card: not a punch card, not paid at the desk', (t) async {
      final a = api()
        ..responses['/gym/memberships'] = {
          'data': [
            dana((m) => m['auto_payment_type'] = 'manual'),
            (memberships['data'] as List)[1],
          ]
        };
      await boot(t, a);
      await openMember(t, 'Dana Levi');
      expect(find.text('Dana Levi'), findsWidgets);
      expect(find.byKey(const Key('freeze')).evaluate().isNotEmpty || find.byKey(const Key('cancelSub')).evaluate().isNotEmpty,
          isTrue,
          reason: 'the member sheet is open');
      expect(find.byKey(const Key('membershipCard')), findsNothing, reason: 'paid at the desk');
      expect(find.text('Membership card'), findsNothing);
    });

    testWidgets('a punch card (paid once) has no membership card', (t) async {
      await boot(t, api());
      await openMember(t, 'Avi Cohen');
      expect(find.byKey(const Key('cancelSub')), findsOneWidget, reason: "Avi's member sheet is open");
      expect(find.byKey(const Key('membershipCard')), findsNothing);
    });

    testWidgets('no Z Credit terminal: no membership card button', (t) async {
      await boot(t, api()..responses['/gym/pos-settings'] = posSettings(cardTokens: false));
      await openMember(t, 'Dana Levi');
      expect(find.byKey(const Key('membershipCard')), findsNothing);
    });
  });

  group('new membership, monthly by the saved card (charged by the server each month)', () {
    FakeApi cardApi() => payingApi()
      ..responses['/gym/pos-settings'] = {
        'data': {...(nm.posSettings['data'] as Map), 'card_tokens': true}
      };

    Future<GymStore> toPayment(WidgetTester t, FakeApi a, String member) async {
      final (store, _) = await boot(t, a);
      store.settings.registrationFeeProductId = '30';
      await tapKey(t, 'tileNewSub');
      await t.ensureVisible(find.text(member).first);
      await t.pumpAndSettle();
      await t.tap(find.text(member).first);
      await t.pumpAndSettle();
      await tapKey(t, 'plan-10');
      await tapKey(t, 'toPayment');
      // The monthly plan takes no cash: the first payment by card on the terminal.
      await tapKey(t, 'add-card');
      return store;
    }

    Map<String, Object?> sent(FakeApi a, String path) => a.posts.lastWhere((p) => p.$1 == path).$2;

    testWidgets('a member with a saved card: chosen for the next months, sent as credit_card', (t) async {
      final a = cardApi();
      await toPayment(t, a, 'Dana Levi');
      expect(find.text('Saved card •••• 4815'), findsOneWidget);
      expect(find.byKey(const Key('payProblem')), findsNothing, reason: 'the saved card is chosen');
      expect(find.text('Another card'), findsOneWidget);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(sent(a, '/gym/memberships')['recurring_method'], 'credit_card');
      expect(a.posts.map((p) => p.$1), ['/gym/memberships', '/sales/store-v2', '/gym/memberships/77/link-sale']);
    });

    testWidgets('no saved card: "New card" saves one for the member, then it is the monthly card', (t) async {
      final a = cardApi()..postHandlers['/gym/members/8/card'] = cardSaved(8);
      final store = await toPayment(t, a, 'Avi Cohen');
      expect(find.textContaining('Saved card'), findsNothing);
      expect(find.byKey(const Key('payProblem')), findsOneWidget, reason: 'the monthly method is not chosen yet');
      final newCard = find.text('New card');
      await t.ensureVisible(newCard);
      await t.pumpAndSettle();
      await t.tap(newCard);
      await t.pumpAndSettle();
      await typeCard(t);
      await tapKey(t, 'saveMemberCard');

      expect(a.posts.last.$1, '/gym/members/8/card');
      expect(store.customer('8')!.savedCardLast4, '1111');
      expect(find.text('Saved card •••• 1111'), findsOneWidget);
      expect(find.byKey(const Key('payProblem')), findsNothing);
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(sent(a, '/gym/memberships')['recurring_method'], 'credit_card');
    });

    testWidgets('"New card" closed without saving: nothing chosen', (t) async {
      final a = cardApi();
      await toPayment(t, a, 'Avi Cohen');
      final newCard = find.text('New card');
      await t.ensureVisible(newCard);
      await t.pumpAndSettle();
      await t.tap(newCard);
      await t.pumpAndSettle();
      // Closed as back / a swipe down does.
      Navigator.of(t.element(find.byKey(const Key('cardNumber')))).pop();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saveMemberCard')), findsNothing, reason: 'the card sheet closed');
      expect(find.byKey(const Key('payProblem')), findsOneWidget);
      expect(a.posts, isEmpty);
    });

    testWidgets('the server has no saved card for the member: a clear message, no sale', (t) async {
      final a = cardApi()
        ..postErrors['/gym/memberships'] = AuraApiException(AuraErrorKind.server, 'HTTP 422: member_has_no_card');
      await toPayment(t, a, 'Dana Levi');
      await tapKey(t, 'toSummary');
      await tapKey(t, 'confirm');
      expect(find.textContaining('The member has no saved card in the system.'), findsOneWidget);
      expect(a.posts.map((p) => p.$1), ['/gym/memberships']);
    });

    testWidgets('no Z Credit terminal: no card choices for the next months', (t) async {
      await toPayment(t, payingApi(), 'Dana Levi');
      expect(find.textContaining('Saved card'), findsNothing);
      expect(find.text('New card'), findsNothing);
    });
  });

  testWidgets('demo: the card is kept in the app', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    // The members list is sorted by name: the first one is on screen.
    final c = (store.subscriptions.map((s) => store.customer(s.customerId)!).toList()
          ..sort((a, b) => a.name.compareTo(b.name)))
        .first;
    await t.tap(find.text(c.name).first);
    await t.pumpAndSettle();
    await tapKey(t, 'memberCard');
    await typeCard(t, number: '4580000000009999');
    await tapKey(t, 'saveMemberCard');
    expect(c.savedCardLast4, '9999');
  });
}
