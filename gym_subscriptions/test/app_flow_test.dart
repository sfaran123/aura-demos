import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/state/reports.dart';
import 'package:aura_gym/src/state/gym_store.dart';

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

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
      try {
        await t.scrollUntilVisible(f, 250, scrollable: _vertical, maxScrolls: 40);
      } on StateError {
        await t.scrollUntilVisible(f, -250, scrollable: _vertical, maxScrolls: 60);
      }
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
      await t.scrollUntilVisible(f, 250, scrollable: _vertical);
    }
    return f;
  }

  testWidgets('home shows the main actions and what needs attention', (t) async {
    await boot(t);
    expect(find.text('מנוי חדש'), findsWidgets);
    expect(find.text('תשלום מהיר'), findsOneWidget);
    expect(find.text('לינק הרשמה'), findsOneWidget);
    expect(await seen(t, find.text('דורש טיפול')), findsOneWidget);
    await t.drag(find.byType(ListView).first, const Offset(0, -500));
    await t.pumpAndSettle();
    expect(find.textContaining(RegExp('גבייה ידנית|חיוב באשראי נכשל')), findsWidgets);
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
    expect(await seen(t, find.text('אלון ברק')), findsWidgets);
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


  testWidgets('every main screen has a ? that explains it', (t) async {
    await boot(t);
    for (final tab in ['navHome', 'navMembers', 'navCollect', 'navReports', 'navSettings']) {
      await tapKey(t, tab);
      await t.tap(find.byKey(const Key('help')).last);
      await t.pumpAndSettle();
      expect(find.text('למה זה עוזר'), findsOneWidget, reason: tab);
      expect(find.text('מה זה נותן לך'), findsOneWidget, reason: tab);
      await t.tap(find.byKey(const Key('helpClose')));
      await t.pumpAndSettle();
    }
    await tapKey(t, 'navReports');
    await tapKey(t, 'report-debts');
    await t.tap(find.byKey(const Key('help')).last);
    await t.pumpAndSettle();
    expect(find.text('כל החייבים לפי ותק החוב'), findsOneWidget);
  });

  testWidgets('business summary shows the whole business with a trend', (t) async {
    await boot(t);
    await tapKey(t, 'navReports');
    await tapKey(t, 'report-summary');
    expect(find.text('סיכום העסק'), findsWidgets);
    expect(await seen(t, find.text('מגמה – 6 חודשים')), findsOneWidget);
    for (final p in ['היום', '7 ימים', 'חודש קודם']) {
      await tap(t, find.text(p));
      expect(t.takeException(), isNull, reason: p);
    }
  });

  testWidgets('a debt is collected straight from the debts report', (t) async {
    await boot(t);
    await tapKey(t, 'navReports');
    await tapKey(t, 'report-debts');
    final open = store.charges.where((c) => c.isOpen() && c.daysOverdue(store.today) > 0 && c.manual).first;
    await tapKey(t, 'payRow-${open.id}');
    await t.tap(find.byKey(Key('collect-${open.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('collectWith-cash')));
    await t.pumpAndSettle();
    expect(open.status, ChargeStatus.paid);
    expect(store.receipts.last.lines.single.method, PayMethod.cash);
  });

  testWidgets('cheque payment needs number, bank, branch and account', (t) async {
    await boot(t);
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'plan-p4');
    await tapKey(t, 'toPayment');
    await tap(t, find.byTooltip('הסרה')); // the saved card is prefilled
    await tapKey(t, 'add-cheque');
    expect(await seen(t, find.textContaining('חסרים פרטי שיק')), findsWidgets);
    await t.enterText(find.byKey(const Key('chq-number-0')), '5001');
    await t.enterText(find.byKey(const Key('chq-bank-0')), '12');
    await t.enterText(find.byKey(const Key('chq-branch-0')), '614');
    await t.enterText(find.byKey(const Key('chq-account-0')), '338210');
    await t.pumpAndSettle();
    expect(find.textContaining('חסרים פרטי שיק'), findsNothing);
    expect(find.text('הפועלים'), findsOneWidget);
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    final line = store.receipts.last.lines.single;
    expect(line.method, PayMethod.cheque);
    expect(line.cheque.number, '5001');
    expect(line.cheque.branch, '614');
  });

  testWidgets('collecting a monthly payment by transfer asks for the reference', (t) async {
    await boot(t);
    await tapKey(t, 'navCollect');
    await tapKey(t, 'collect-ch1');
    await tapKey(t, 'collectWith-bank');
    await t.enterText(find.byKey(const Key('tr-ref-0')), '7788123');
    await t.enterText(find.byKey(const Key('tr-bank-0')), '10');
    await t.pumpAndSettle();
    await tapKey(t, 'detailsSave');
    final ch = store.charges.firstWhere((c) => c.id == 'ch1');
    expect(ch.status, ChargeStatus.paid);
    expect(store.receipts.last.lines.single.transfer.reference, '7788123');
  });

  testWidgets('receipt is sent by SMS after a quick payment', (t) async {
    await boot(t);
    await tapKey(t, 'tileQuickPay');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'item-water');
    await tapKey(t, 'itemsToPayment');
    await tapKey(t, 'add-cash');
    await tapKey(t, 'toSummary');
    await tapKey(t, 'confirm');
    expect(t.widget<TextField>(find.byKey(const Key('sendPhone'))).controller!.text, '052-7781024');
    await tapKey(t, 'sendSms');
    expect(store.receipts.last.sent.single.$1, 'SMS');
    await tapKey(t, 'viewReceipt');
    expect(find.byKey(const Key('receiptCard')), findsOneWidget);
  });

  testWidgets('a new plan can be created inside the new-membership flow', (t) async {
    await boot(t);
    await tapKey(t, 'tileNewSub');
    await tap(t, find.text('נועה לוי'));
    await tapKey(t, 'planStepNew');
    await t.enterText(find.byKey(const Key('pe-name')), 'בוקר בלבד');
    await t.enterText(find.byKey(const Key('pe-price')), '119');
    await t.pumpAndSettle();
    await tapKey(t, 'savePlan');
    final p = store.plans.last;
    expect(p.name, 'בוקר בלבד');
    expect(find.text('המשך לתשלום · 119 ₪'), findsOneWidget);
  });

  testWidgets('plans are reachable from home', (t) async {
    await boot(t);
    await tapKey(t, 'homePlans');
    expect(find.byKey(const Key('newPlan')), findsOneWidget);
  });

  testWidgets('business type sets the recommended reports, and reports can be turned off', (t) async {
    await boot(t);
    await tapKey(t, 'navSettings');
    await tapKey(t, 'businessType');
    await tapKey(t, 'bt-beauty');
    expect(store.settings.enabledReports.contains('frozen'), isFalse);
    await tapKey(t, 'navReports');
    expect(find.byKey(const Key('report-frozen')), findsNothing);
    await tapKey(t, 'pickReports');
    await tapKey(t, 'rep-revenue');
    expect(store.settings.enabledReports.contains('revenue'), isFalse);
    await tapKey(t, 'reportsAll');
    expect(store.settings.enabledReports.length, allReports.length);
  });


  testWidgets('the guide finds a topic and takes you there', (t) async {
    await boot(t);
    await tapKey(t, 'openGuide');
    expect(find.text('מה רוצים לעשות?'), findsOneWidget);
    await t.enterText(find.byKey(const Key('guideSearch')), 'שיק');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('guide-cheque')), findsOneWidget);
    expect(find.byKey(const Key('guide-freeze')), findsNothing);
    await t.enterText(find.byKey(const Key('guideSearch')), 'מזומן חודשי');
    await t.pumpAndSettle();
    await tapKey(t, 'guideGo-collectCash');
    expect(find.byKey(const Key('guideSearch')), findsNothing);
    expect(find.text('חוב פתוח עד היום'), findsOneWidget);
  });

  testWidgets('the ? sheet opens the full guide', (t) async {
    await boot(t);
    await tapKey(t, 'navMembers');
    await t.tap(find.byKey(const Key('help')).last);
    await t.pumpAndSettle();
    await tapKey(t, 'helpGuide');
    expect(find.byKey(const Key('guideSearch')), findsOneWidget);
  });


  testWidgets('sales list finds an invoice and resends it', (t) async {
    await boot(t);
    await tapKey(t, 'homeSales');
    expect(find.text('מכירות וחשבוניות'), findsOneWidget);
    final last = store.receipts.last;
    await t.enterText(find.byKey(const Key('salesSearch')), '${last.number}');
    await t.pumpAndSettle();
    await tapKey(t, 'sale-${last.number}');
    expect(find.byKey(const Key('receiptCard')), findsOneWidget);
    expect(find.textContaining('חשבונית מס קבלה'), findsWidgets);
  });

  testWidgets('price list: change a price and it is used at the desk', (t) async {
    await boot(t);
    await tapKey(t, 'homePrices');
    await tapKey(t, 'price-shake');
    await t.enterText(find.byKey(const Key('itemPrice')), '25');
    await tapKey(t, 'itemSave');
    expect(store.items.firstWhere((x) => x.id == 'shake').price, 25);
    await tapKey(t, 'newItem');
    await t.enterText(find.byKey(const Key('itemName')), 'חטיף חלבון');
    await t.enterText(find.byKey(const Key('itemPrice')), '12');
    await tapKey(t, 'itemSave');
    expect(store.items.any((x) => x.name == 'חטיף חלבון' && x.price == 12), isTrue);
  });

  testWidgets('quick-pay products are edited from the quick-pay screen', (t) async {
    await boot(t);
    await tapKey(t, 'tileQuickPay');
    await tapKey(t, 'walkIn');
    await tapKey(t, 'editPriceList');
    await tapKey(t, 'price-water');
    await t.enterText(find.byKey(const Key('itemPrice')), '10');
    await tapKey(t, 'itemSave');
    await t.tap(find.byType(BackButton).last);
    await t.pumpAndSettle();
    expect(find.text('10 ₪'), findsWidgets);
  });
}
