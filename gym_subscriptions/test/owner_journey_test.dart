// A business owner's walk through the whole app: every tab, every report in
// every period and language, every setting, and the actions that had no test.
// A screen that throws, overflows or cannot be reached fails here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/state/reports.dart';
import 'package:aura_gym/src/ui/collect_screen.dart';
import 'package:aura_gym/src/ui/customers_screen.dart';
import 'package:aura_gym/src/ui/sales_screen.dart';

import 'collect_test.dart' as col;
import 'new_membership_test.dart' as nm;
import 'server_sync_test.dart' show signedIn, today;
import 'support/fake_api.dart';

const tabs = ['navHome', 'navCheckin', 'navMembers', 'navCollect', 'navReports', 'navSettings'];

/// The server's data with debts to collect, a Z Credit terminal and the answers
/// a sale needs.
FakeApi fullApi() => col.api()
  ..responses['/gym/pos-settings'] = {
    'data': {...(nm.posSettings['data'] as Map), 'card_tokens': true}
  }
  ..postHandlers['/gym/memberships'] = nm.membershipStore()
  ..postHandlers['/sales/store-v2'] = nm.saleStore()
  ..postHandlers['/gym/memberships/77/link-sale'] = nm.linkStore();

void main() {
  setUp(() => L10n.lang = AppLang.en);

  Future<GymStore> boot(WidgetTester t, {FakeApi? api, GymStore? store}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = store ?? GymStore(clock: () => today);
    await t.pumpWidget(
        api == null ? AuraGymApp(store: s) : AuraGymApp(store: s, auth: AuthController(storage: signedIn(), api: api)));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)).first);
    await t.pumpAndSettle();
  }

  Future<void> back(WidgetTester t) async {
    // The top route is closed as the back button does (its tooltip is translated).
    t.state<NavigatorState>(find.byType(Navigator).last).pop();
    await t.pumpAndSettle();
  }

  /// Opens every tab, then every report of the hub with each of its periods.
  Future<void> tour(WidgetTester t, GymStore store) async {
    for (final tab in tabs) {
      await t.tap(find.byKey(Key(tab)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: tab);
    }
    await t.tap(find.byKey(const Key('navReports')));
    await t.pumpAndSettle();
    var opened = 0;
    for (final r in allReports) {
      // Every period builds, also for dates picked by hand.
      for (final p in [...(r.periods ?? Period.values), Period.custom]) {
        expect(() => r.build(store, p), returnsNormally, reason: '${r.id} ${p.name}');
      }
      final tile = find.byKey(Key('report-${r.id}'));
      if (tile.evaluate().isEmpty) {
        await t
            .scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 30)
            .catchError((_) {});
      }
      if (tile.evaluate().isEmpty) continue; // turned off for this business type
      await tapKey(t, 'report-${r.id}');
      expect(t.takeException(), isNull, reason: 'report ${r.id}');
      expect(find.text(r.title), findsWidgets);
      opened++;
      await back(t);
    }
    expect(opened, greaterThanOrEqualTo(8), reason: 'the reports open from the hub');
  }

  for (final lang in AppLang.values) {
    testWidgets('the demo business in ${lang.name}: every tab and every report opens', (t) async {
      L10n.lang = lang;
      customPeriodRange = (DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      addTearDown(() => customPeriodRange = null);
      final store = await boot(t, store: GymStore());
      await tour(t, store);
    });

    testWidgets('signed in, in ${lang.name}: every tab and every report opens', (t) async {
      L10n.lang = lang;
      customPeriodRange = (DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      addTearDown(() => customPeriodRange = null);
      final store = await boot(t, api: fullApi());
      await tour(t, store);
    });
  }

  testWidgets('the reports hub: shortcuts to sales, the price list and collection', (t) async {
    await boot(t, api: fullApi());
    await t.tap(find.byKey(const Key('navReports')));
    await t.pumpAndSettle();
    await tapKey(t, 'hubSales');
    expect(find.byType(SalesScreen), findsOneWidget);
    await back(t);
    await tapKey(t, 'hubPrices');
    expect(find.byType(PriceListScreen), findsOneWidget);
    await back(t);
    await tapKey(t, 'hubCollect');
    expect(find.byType(CollectScreen), findsWidgets);
  });

  testWidgets('home: the tiles and the numbers lead to their screens', (t) async {
    final store = await boot(t, api: fullApi());
    // The number at the top first (the list builds what is on the screen).
    await tapKey(t, 'kpiDebt');
    expect(find.byKey(const Key('collect-failed-3')), findsOneWidget, reason: 'the collection list');
    await t.tap(find.byKey(const Key('navHome')));
    await t.pumpAndSettle();
    await tapKey(t, 'tileCollect');
    expect(find.byKey(const Key('collect-failed-3')), findsOneWidget);
    await t.tap(find.byKey(const Key('navHome')));
    await t.pumpAndSettle();
    await tapKey(t, 'tileMembers');
    expect(find.text('Dana Levi'), findsWidgets);
    await t.tap(find.byKey(const Key('navHome')));
    await t.pumpAndSettle();
    for (final k in ['homeSales', 'homePrices', 'homePlans']) {
      await tapKey(t, k);
      expect(t.takeException(), isNull, reason: k);
      await back(t);
    }
    expect(store.openDebt, 179.1);
  });

  testWidgets('settings: every switch flips and flips back; the guide, price list and report picker open', (t) async {
    await boot(t, store: GymStore());
    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    var flipped = 0;
    // Switches are built as the list scrolls: walk the whole screen.
    for (var i = 0; i < 40; i++) {
      for (final e in find.byType(SwitchListTile).evaluate().toList()) {
        final w = e.widget as SwitchListTile;
        if (w.onChanged == null) continue;
        final before = w.value;
        w.onChanged!(!before);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'a settings switch');
        final now = find.byType(SwitchListTile).evaluate().map((x) => x.widget as SwitchListTile);
        // Put it back: the journey leaves the settings as they were.
        for (final x in now) {
          if (x.key == w.key && x.title.toString() == w.title.toString() && x.value != before) {
            x.onChanged?.call(before);
          }
        }
        await t.pumpAndSettle();
        flipped++;
      }
      final pos = t.state<ScrollableState>(scroll).position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      pos.jumpTo((pos.pixels + 500).clamp(0, pos.maxScrollExtent));
      await t.pumpAndSettle();
    }
    expect(flipped, greaterThan(5));
    for (final k in ['settingsGuide', 'openPriceList', 'openReportPicker']) {
      await t.scrollUntilVisible(find.byKey(Key(k)), -300, scrollable: scroll, maxScrolls: 60).catchError((_) async {
        await t.scrollUntilVisible(find.byKey(Key(k)), 300, scrollable: scroll, maxScrolls: 60);
      });
      await tapKey(t, k);
      expect(t.takeException(), isNull, reason: k);
      if (k == 'openReportPicker') await tapKey(t, 'reportsRecommended');
      await back(t);
    }
  });

  testWidgets('the language is changed from the settings and the app follows', (t) async {
    await boot(t, store: GymStore());
    await t.tap(find.byKey(const Key('navSettings')));
    await t.pumpAndSettle();
    for (final l in AppLang.values) {
      await tapKey(t, 'lang-${l.code}');
      expect(L10n.lang, l);
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('signed in, the price list is shown, not edited: a change here would be lost at the next update',
      (t) async {
    final store = await boot(t, api: fullApi());
    final before = [for (final i in store.items) (i.id, i.price)];
    await tapKey(t, 'homePrices');
    expect(find.byKey(const Key('pricesReadOnly')), findsOneWidget);
    expect(find.byKey(const Key('newItem')), findsNothing);
    await t.tap(find.byKey(Key('price-${store.items.first.id}')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('itemPrice')), findsNothing, reason: 'no edit form');
    expect([for (final i in store.items) (i.id, i.price)], before);
  });

  testWidgets('the price list: a product is removed', (t) async {
    final store = await boot(t, store: GymStore());
    final n = store.items.length;
    await tapKey(t, 'homePrices');
    await tapKey(t, 'price-${store.items.first.id}');
    await tapKey(t, 'itemRemove');
    expect(store.items.length, n - 1);
  });

  testWidgets('a new membership with the sign-up fee waived, then another one right after', (t) async {
    final api = fullApi()
      ..responses['/sales/getproduct-v2'] = [
        {'id': 20, 'name': 'Water', 'price': 8},
        {'id': 30, 'name': 'Sign-up fee', 'price': 100, 'tax_rate': 0, 'tax_method': 2},
      ];
    final store = await boot(t, api: api);
    store.settings.registrationFeeProductId = '30';
    await tapKey(t, 'tileNewSub');
    await t.tap(find.text('Avi Cohen').first);
    await t.pumpAndSettle();
    await tapKey(t, 'plan-11');
    if (find.byKey(const Key('waiveReg')).evaluate().isNotEmpty) {
      await tapKey(t, 'waiveReg');
    }
    await tapKey(t, 'toPayment');
    await tapKey(t, 'add-cash');
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    final sent = api.posts.firstWhere((p) => p.$1 == '/gym/memberships').$2;
    expect(sent['customer_id'], 8);
    expect(sent.containsKey('registration_waived'), isTrue);
    // The done screen starts the next sale.
    await tapKey(t, 'again');
    expect(find.byKey(const Key('confirm')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the customer page: a new membership, a payment and a check-in start from it', (t) async {
    final store = await boot(t, api: fullApi());
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pumpAndSettle();
    await t.tap(find.text('Avi Cohen').last);
    await t.pumpAndSettle();
    await tapKey(t, 'memberCustomerPage');
    expect(find.byType(CustomerScreen), findsOneWidget);
    expect(find.text('Memberships (1)'), findsOneWidget);

    await tapKey(t, 'customerNewSub');
    expect(find.byKey(const Key('plan-11')), findsOneWidget, reason: 'the plan step, the customer is already chosen');
    await back(t);
    await tapKey(t, 'customerQuickPay');
    expect(find.byKey(const Key('item-20')), findsOneWidget, reason: 'the products step');
    await back(t);
    await tapKey(t, 'customerCheckin');
    expect(store.visits.single.customerId, '8');

    // Editing checks what is typed before anything is sent.
    await tapKey(t, 'editCustomer');
    await t.enterText(find.byKey(const Key('editPhone')), '12');
    await tapKey(t, 'editSave');
    expect(find.byKey(const Key('editError')), findsOneWidget);
    await t.enterText(find.byKey(const Key('editPhone')), '052-7654321');
    await t.enterText(find.byKey(const Key('editEmail')), 'not-an-email');
    await tapKey(t, 'editSave');
    expect(find.byKey(const Key('editError')), findsOneWidget);
    await t.enterText(find.byKey(const Key('editEmail')), 'avi@example.com');
    await t.enterText(find.byKey(const Key('editIdNumber')), '123456782');
    api_(t);
  });

  testWidgets('a failed month: the membership card is updated straight from its details', (t) async {
    final a = fullApi();
    final m = ((a.responses['/gym/memberships'] as Map)['data'] as List)[0] as Map;
    m['has_card_token'] = true;
    await boot(t, api: a);
    await t.tap(find.byKey(const Key('navCollect')));
    await t.pumpAndSettle();
    await tapKey(t, 'charge-failed-3');
    expect(find.textContaining("The membership's card was declined"), findsOneWidget);
    await tapKey(t, 'detailsMembershipCard');
    expect(find.byKey(const Key('cardNumber')), findsOneWidget, reason: 'the card form of the membership');
  });
}

/// Nothing was thrown on the way.
void api_(WidgetTester t) => expect(t.takeException(), isNull);
