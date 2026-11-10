import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/state/reports.dart';
import 'package:aura_gym/src/state/gym_store.dart';

void main() {
  late GymStore store;

  Future<void> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    store = GymStore();
    await t.pumpWidget(AuraGymApp(store: store));
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
    }
    await t.ensureVisible(f.first);
    await t.pumpAndSettle();
    await t.tap(f.first);
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String k) => tap(t, find.byKey(Key(k)));

  /// Scrolls the current screen until [f] is built and on screen.
  Future<Finder> seen(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
    }
    return f;
  }

  testWidgets('home shows the main actions and what needs attention', (t) async {
    await boot(t);
    expect(find.text('מנוי חדש'), findsWidgets);
    expect(find.text('תשלום מהיר'), findsOneWidget);
    expect(find.text('לינק הרשמה'), findsOneWidget);
    expect(await seen(t, find.text('דורש טיפול')), findsOneWidget);
    expect(await seen(t, find.textContaining('גבייה ידנית')), findsWidgets);
  });

  testWidgets('existing customer with a saved card: subscription in 5 taps', (t) async {
    await boot(t);
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'plan-p5');
    await tapKey(t, 'toPayment');
    expect(find.byKey(const Key('payProblem')), findsNothing);
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    expect(find.textContaining('מנוי פעיל'), findsOneWidget);
    final sub = store.subscriptions.last;
    expect(sub.status, SubStatus.active);
    expect(store.receipts.last.total, 1790);
  });

  testWidgets('monthly plan split between cash and a new card, then manual collection', (t) async {
    await boot(t);
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('רים ח׳ורי'));
    await tapKey(t, 'plan-p1');
    await tapKey(t, 'toPayment');
    expect(find.byKey(const Key('payProblem')), findsOneWidget);
    await tapKey(t, 'add-cash');
    await t.enterText(find.byKey(const Key('amount-0')), '100');
    await t.pumpAndSettle();
    expect(find.text('נותרו 199 ₪ לשיוך'), findsOneWidget);
    await tapKey(t, 'add-card');
    await tapKey(t, 'fillTestCard');
    await tapKey(t, 'saveCard');
    expect(find.text('בחרו איך ייגבה התשלום החודשי'), findsOneWidget);
    await tap(t, find.text('גבייה ידנית כל חודש'));
    expect(find.byKey(const Key('payProblem')), findsNothing);
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    final sub = store.subscriptions.last;
    expect(sub.recurringMethod, RecurringMethod.manual);
    expect(store.receipts.last.lines.length, 2);
    expect(store.charges.last.manual, isTrue);
  });

  testWidgets('quick payment for a walk-in customer in cash', (t) async {
    await boot(t);
    await tapKey(t, 'tileQuickPay');
    await tapKey(t, 'walkIn');
    await tapKey(t, 'item-shake');
    await tapKey(t, 'item-shake');
    await tapKey(t, 'itemsToPayment');
    expect(find.text('44 ₪'), findsWidgets);
    await tapKey(t, 'add-cash');
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    expect(find.text('התשלום התקבל'), findsOneWidget);
    expect(store.receipts.last.customerName, 'לקוח מזדמן');
  });

  testWidgets('collect a manual monthly payment from the list', (t) async {
    await boot(t);
    await tapKey(t, 'navCollect');
    expect(find.text('אלון ברק'), findsWidgets);
    await tapKey(t, 'collect-ch1');
    await tapKey(t, 'collectWith-cash');
    expect(find.textContaining('הופקה'), findsOneWidget);
    expect(store.charges.firstWhere((c) => c.id == 'ch1').status, ChargeStatus.paid);
  });

  testWidgets('owner creates a new plan', (t) async {
    await boot(t);
    await tapKey(t, 'navSettings');
    await tapKey(t, 'openPlans');
    await tapKey(t, 'newPlan');
    await t.enterText(find.byKey(const Key('pe-name')), 'חודשי סטודנטים');
    await t.enterText(find.byKey(const Key('pe-price')), '129');
    await t.pumpAndSettle();
    await tapKey(t, 'savePlan');
    expect(store.plans.any((p) => p.name == 'חודשי סטודנטים' && p.price == 129), isTrue);
    expect(await seen(t, find.text('חודשי סטודנטים')), findsOneWidget);
  });

  testWidgets('customer signs up and pays through the link', (t) async {
    await boot(t);
    await tapKey(t, 'tileLink');
    await tap(t, find.text('איך הלקוח רואה'));
    await tapKey(t, 'linkPlan-p3');
    await t.enterText(find.byKey(const Key('lName')), 'אבי טל');
    await t.enterText(find.byKey(const Key('lPhone')), '0507778888');
    await t.pumpAndSettle();
    await tapKey(t, 'lHealth');
    await tapKey(t, 'lTerms');
    await tapKey(t, 'linkToPay');
    await tapKey(t, 'linkCard');
    await tapKey(t, 'fillTestCard');
    await tapKey(t, 'saveCard');
    await tapKey(t, 'linkPay');
    expect(find.byKey(const Key('linkDone')), findsOneWidget);
    expect(store.customers.any((c) => c.name == 'אבי טל' && c.hasSavedCard), isTrue);
    expect(store.links.first.status, LinkStatus.paid);
  });

  testWidgets('turning off manual monthly collection removes the option', (t) async {
    await boot(t);
    await tapKey(t, 'navSettings');
    await tapKey(t, 'allowManual');
    expect(store.settings.allowManualMonthly, isFalse);
    await tapKey(t, 'navHome');
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('רים ח׳ורי'));
    await tapKey(t, 'plan-p1');
    await tapKey(t, 'toPayment');
    expect(find.text('גבייה ידנית כל חודש'), findsNothing);
    expect(find.text('הוראת קבע בבנק'), findsOneWidget);
  });

  testWidgets('freeze a member from the members list', (t) async {
    await boot(t);
    await tapKey(t, 'navMembers');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'freeze');
    await tapKey(t, 'freeze-14');
    expect(store.subscriptions.firstWhere((s) => s.id == 's1').status, SubStatus.frozen);
  });

  testWidgets('every main screen works with a large system font (130%)', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await boot(t);
    for (final tab in ['navMembers', 'navCollect', 'navReports', 'navSettings', 'navHome']) {
      await tapKey(t, tab);
      expect(t.takeException(), isNull, reason: tab);
    }
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'plan-p4');
    await tapKey(t, 'toPayment');
    await tapKey(t, 'add-cheque');
    expect(t.takeException(), isNull);
    await tapKey(t, 'toSummary');
    expect(t.takeException(), isNull);
  });

  testWidgets('every report opens from the reports hub in two taps', (t) async {
    await boot(t);
    for (final r in allReports) {
      await tapKey(t, 'navReports');
      await tapKey(t, 'report-${r.id}');
      expect(t.takeException(), isNull, reason: r.id);
      expect(find.text(r.title), findsWidgets, reason: r.id);
      await t.tap(find.byType(BackButton).last);
      await t.pumpAndSettle();
    }
  });

  testWidgets('member filters cover every status', (t) async {
    await boot(t);
    await tapKey(t, 'navMembers');
    for (final f in ['active', 'pending', 'debt', 'failed', 'frozen', 'ending', 'cancelling', 'ended', 'all']) {
      await tapKey(t, 'memberFilter-$f');
      expect(t.takeException(), isNull, reason: f);
    }
    await tapKey(t, 'memberFilter-frozen');
    expect(find.text('מאיה גולן'), findsOneWidget);
    expect(find.text('נועה לוי'), findsNothing);
  });

  testWidgets('a sent link updates live until paid', (t) async {
    await boot(t);
    await tapKey(t, 'allLinks');
    for (final f in ['waiting', 'opened', 'signed', 'paid', 'failed', 'all']) {
      await tapKey(t, 'linkFilter-$f');
      expect(t.takeException(), isNull, reason: f);
    }
    final l = store.links.firstWhere((l) => l.stage == LinkStage.sent);
    await tapKey(t, 'link-${l.id}');
    await tapKey(t, 'simulateLink');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 2));
    }
    await t.pumpAndSettle();
    expect(l.stage, LinkStage.paid);
    store.stopSimulations();
  });

  for (final lang in [AppLang.ar, AppLang.en]) {
    testWidgets('the app works in ${lang.name}', (t) async {
      addTearDown(() => L10n.lang = AppLang.he);
      await boot(t);
      await tapKey(t, 'navSettings');
      await tapKey(t, 'lang-${lang.code}');
      expect(L10n.lang, lang);
      for (final tab in ['navHome', 'navMembers', 'navCollect', 'navReports', 'navSettings']) {
        await tapKey(t, tab);
        expect(t.takeException(), isNull, reason: '${lang.name} $tab');
      }
      await tapKey(t, 'navReports');
      await tapKey(t, 'report-manual');
      expect(t.takeException(), isNull);
      await t.tap(find.byType(BackButton).last);
      await t.pumpAndSettle();
      await tapKey(t, 'navHome');
      expect(find.text(lang == AppLang.en ? 'New membership' : 'اشتراك جديد'), findsWidgets);
      await tapKey(t, 'tileNewSub');
      await tap(t, find.text(lang == AppLang.en ? 'Noa Levi' : 'نوعا ليفي'));
      await tapKey(t, 'plan-p4');
      await tapKey(t, 'toPayment');
      await tapKey(t, 'add-cheque');
      await tapKey(t, 'toSummary');
      expect(t.takeException(), isNull);
    });
  }
}
