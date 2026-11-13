import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/models.dart' show money;
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/server_mapping.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/state/reports.dart';

import 'dashboard_test.dart' show dashboard;
import 'server_sync_test.dart' show memberships, serverApi, signedIn, today;

Map<String, dynamic> copy(Object? m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

void main() {
  setUp(() => L10n.lang = AppLang.en);

  /// Signed in and synced with the server answers of server_sync_test + dashboard_test.
  /// Old Member's membership (9) was cancelled on the web on 3 Nov.
  Future<GymStore> synced(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final ms = copy(memberships);
    ((ms['data'] as List)[2] as Map)['cancelled_at'] = '2026-11-03 10:00:00';
    final api = serverApi()
      ..responses['/gym/memberships'] = ms
      ..responses['/gym/dashboard'] = dashboard;
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
    await t.pumpAndSettle();
    expect(store.dashboard, isNotNull);
    return store;
  }

  String kpi(ReportData d, String label) => d.kpis.firstWhere((k) => k.label == label).value;

  testWidgets('debts: the server list, same total as the home screen', (t) async {
    final s = await synced(t);
    final d = debtsReport(s, Period.month);
    expect(kpi(d, 'Open debt'), money(179.1));
    // Failed charge of 1 Nov = 10 days. The unpaid membership document is not a debt to collect.
    expect(kpi(d, 'Up to 7 days'), money(0));
    expect(kpi(d, '8–30 days'), money(179.1));
    expect(kpi(d, 'Over 30'), money(0));
    final rows = d.sections.single.rows;
    expect(rows.map((r) => r.subtitle), ['Card failed · due 01/11/2026']);
    expect(rows.first.chargeId, 'failed-3', reason: 'a failed charge can be collected from the report');
    // The hub card shows the same number.
    expect(allReports.firstWhere((r) => r.id == 'debts').headline!(s), money(179.1));
  });

  testWidgets('active: running memberships, members counted once (as the home screen)', (t) async {
    final s = await synced(t);
    final d = activeByPlanReport(s, Period.month);
    // Dana (charge failed, still running) and Avi (active); Old Member is cancelled.
    expect(kpi(d, 'Active members'), '2');
    expect(d.sections.single.rows.map((r) => r.title), containsAll(['Monthly', '10 entries']));
  });

  testWidgets('joins: a web cancellation counts on its date', (t) async {
    final s = await synced(t);
    final d = joinsReport(s, Period.month);
    expect(kpi(d, 'Cancelled'), '1');
    expect(d.sections[1].rows.single.title, 'Old Member');
    expect(kpi(d, 'Joined'), '1', reason: 'Avi joined on 1 Nov');
  });

  testWidgets('every report and hub card builds with server data, in every period', (t) async {
    final s = await synced(t);
    for (final r in allReports) {
      expect(r.headline?.call(s), isNotNull, reason: r.id);
      for (final p in r.periods ?? Period.values) {
        expect(r.build(s, p).kpis, isNotEmpty, reason: '${r.id} ${p.name}');
      }
    }
  });

  // ---- batch 2: money reports from GET gym/sales (TIR-1001 card 199 on 5 Nov, TIR-1002 cash 8 + cheque 22
  // due 15 Jan 2027 on 6 Nov, credit TIC-7 cash -8 on 7 Nov).
  testWidgets("revenue: all staff's documents, by method and source", (t) async {
    final s = await synced(t);
    final d = revenueReport(s, Period.month);
    expect(kpi(d, 'Collected'), money(221));
    expect(kpi(d, 'Receipts'), '3');
    final byMethod = {for (final r in d.sections[0].rows) r.title: r.value};
    expect(byMethod, {'Card': money(199), 'Cheques': money(22), 'Cash': money(0)});
  });

  testWidgets('daily: today is empty, the last 7 days have all three', (t) async {
    final s = await synced(t);
    expect(kpi(dailyReport(s, Period.today), 'Came in'), money(0));
    expect(kpi(dailyReport(s, Period.week), 'Came in'), money(221));
  });

  testWidgets('cheques and forecast', (t) async {
    final s = await synced(t);
    expect(kpi(chequesReport(s, Period.month), 'Future amount'), money(22));
    expect(chequesReport(s, Period.month).sections.first.rows.single.subtitle, startsWith('15/01/2027'));
    // Next 30 days: Dana's monthly charge on 1 Dec; the January cheque is later.
    final f = forecastReport(s, Period.month);
    expect(kpi(f, 'Automatic charge'), money(179.1));
    expect(kpi(f, 'Expected in 30 days'), money(179.1));
  });

  testWidgets('summary: same numbers as the home screen, no links', (t) async {
    final s = await synced(t);
    final d = summaryReport(s, Period.month);
    expect(kpi(d, 'Revenue'), money(221));
    expect(kpi(d, 'Active members'), '2');
    expect(kpi(d, 'Open debt'), money(179.1));
    // Collected 199 (membership payment) of 199 + 179.10 open in the period.
    expect(kpi(d, 'Collection rate'), '53%');
    expect(d.kpis.any((k) => k.label == 'Link conversion'), isFalse);
  });

  testWidgets('the links report is not in the hub while signed in', (t) async {
    final s = await synced(t);
    s.settings.enabledReports = {...s.settings.enabledReports, 'links', 'summary'};
    await t.tap(find.byKey(const Key('navReports')));
    await t.pumpAndSettle();
    expect(find.text('Links and conversion'), findsNothing);
  });

  testWidgets('control: not signed in, the links report is in the hub', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = GymStore(clock: () => today);
    s.settings.enabledReports = {'links'};
    await t.pumpWidget(AuraGymApp(store: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('navReports')));
    await t.pumpAndSettle();
    expect(find.text('Links and conversion'), findsOneWidget);
  });

  // ---- batch 3: accountant package from the server's documents
  test('accountant: VAT from the tax documents themselves, receipts carry none', () {
    Map<String, Object?> doc(int id, String ref, int type, double total, double tax,
            {List<Map<String, Object?>> pays = const [], String? alloc, bool cancelled = false}) =>
        {
          'id': id,
          'reference_no': ref,
          'type': type,
          'is_credit': type == 10,
          'is_tax_document': [7, 10, 27].contains(type),
          'is_cancelled': cancelled,
          'allocation_number': alloc,
          'created_at': '2026-11-0${id % 9 + 1} 10:00:00',
          'grand_total': total,
          'total_tax': tax,
          'customer_id': 7,
          'customer_name': 'Dana Levi',
          'products': [],
          'payments': pays,
        };
    final docs = mapGymSales({
      'data': [
        doc(1, 'TI-1', 7, 1180, 180), // unpaid tax invoice: counts by its own total
        doc(2, 'TIN-2', 27, 118, 18, cancelled: true, pays: [
          {'id': 1, 'amount': 118, 'paying_method': 'Credit Card', 'created_at': '2026-11-03 10:00:00'}
        ]),
        doc(3, 'TIC-3', 10, -59, -9, pays: [
          {'id': 2, 'amount': -59, 'paying_method': 'Cash', 'created_at': '2026-11-04 10:00:00'}
        ]),
        doc(4, 'R-4', 3, 1180, 0, pays: [
          {'id': 3, 'amount': 1180, 'paying_method': 'Cash', 'created_at': '2026-11-05 10:00:00'}
        ]),
        doc(5, 'TI-5', 7, 7080, 1080), // 6,000 before VAT, no allocation number
        doc(6, 'TI-6', 7, 7080, 1080, alloc: 'AL-1'),
      ]
    });
    final s = GymStore(seed: false, clock: () => today)
      ..applyServerData(
          customers: [],
          plans: [],
          subscriptions: [],
          charges: [],
          items: [],
          receipts: docs,
          dashboardJson: dashboard);
    final d = accountantReport(s, Period.month);

    expect(kpi(d, 'Sales incl. VAT'), money(1180 + 118 + 7080 + 7080));
    expect(kpi(d, 'Credits'), money(59));
    expect(kpi(d, 'Before VAT (net)'), money((15458 - 2358) - 50));
    expect(kpi(d, 'Output VAT to pay'), money(2358 - 9));
    expect(kpi(d, 'To check'), '1', reason: 'TI-5: over 5,000 before VAT, no allocation number');
    final checks = d.sections.firstWhere((x) => x.title == 'Checks before filing').rows;
    expect(checks.map((r) => r.title), contains('Tax Invoice TI-5'));
    final journal = d.sections.firstWhere((x) => x.title == 'Document journal').rows;
    expect(journal.map((r) => r.title).toList(), [
      'Tax Invoice TI-1',
      'Tax Invoice/Receipt TIN-2',
      'Tax Invoice Credit TIC-3',
      'Receipt R-4',
      'Tax Invoice TI-5',
      'Tax Invoice TI-6'
    ]);
    expect(journal[1].tag, 'Cancelled');
    expect(journal[0].subtitle, contains('VAT 180'), reason: 'control: a tax invoice shows its VAT');
    expect(journal[3].subtitle, isNot(contains('VAT')), reason: 'a receipt carries no VAT');
    expect(journal[5].subtitle, contains('AL-1'));
    final byMethod = {
      for (final r in d.sections.firstWhere((x) => x.title == 'Receipts by payment method').rows) r.title: r.value
    };
    expect(byMethod, {'Card': money(118), 'Cash': money(1180 - 59)});
  });
}
