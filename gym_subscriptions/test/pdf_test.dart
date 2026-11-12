// Invoices and reports as PDF files.
//  - A sale on the AURA server: the web's own document (GET gym/sales/{id}/pdf),
//    as the POS app shows it; never redrawn in the app.
//  - A receipt made in the app only (demo) and every report: drawn in the app,
//    with the app's fonts (Hebrew, Arabic, English).
// Sharing and printing go through the phone's share sheet and print dialog.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/state/reports.dart';
import 'package:aura_gym/src/ui/pdf_documents.dart';
import 'package:aura_gym/src/ui/pdf_view.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

final fakePdf = utf8.encode('%PDF-1.4 the web invoice');

bool isPdf(List<int> b) => b.length > 500 && utf8.decode(b.take(5).toList()) == '%PDF-';

void main() {
  final shared = <(String, int)>[];
  final printed = <(String, int)>[];

  setUp(() {
    L10n.lang = AppLang.en;
    shared.clear();
    printed.clear();
    // The page view and the share / print dialogs are the printing plugin's.
    PdfScreen.preview = (bytes, name) => Text('preview $name ${bytes.length}', key: const Key('pdfPreview'));
    PdfScreen.share = (bytes, name) async => shared.add((name, bytes.length));
    PdfScreen.print = (bytes, name) async => printed.add((name, bytes.length));
  });

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  /// PDF building is real async work (fonts, compression): let it finish.
  Future<void> settlePdf(WidgetTester t) async {
    for (var i = 0; i < 50 && find.byKey(const Key('pdfPreview')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  group('made in the app', () {
    for (final lang in AppLang.values) {
      testWidgets('every report is a PDF (${lang.name})', (t) async {
        L10n.lang = lang;
        final store = GymStore(clock: () => today);
        await t.runAsync(() async {
          for (final r in allReports) {
            final data = r.build(store, (r.periods ?? Period.values).first);
            final bytes = await reportPdf(data, title: r.title, subtitle: r.subtitle, period: 'P', business: 'AURA Gym');
            expect(isPdf(bytes), isTrue, reason: r.id);
          }
        });
      });
    }

    testWidgets('a receipt made in the app is a PDF', (t) async {
      final store = GymStore(clock: () => today);
      await t.runAsync(() async {
        for (final r in store.receipts.take(5)) {
          expect(isPdf(await receiptPdf(r, store)), isTrue);
        }
      });
    });

    test('file names keep letters and digits', () {
      expect(pdfFileName('Tax invoice-receipt TIN-80011'), 'Tax_invoice-receipt_TIN-80011.pdf');
      expect(pdfFileName('דוח מכירות · 11/2026'), 'דוח_מכירות_11_2026.pdf');
      expect(pdfFileName('  '), 'document.pdf');
    });
  });

  group('signed in: the web\'s document', () {
    Future<FakeApi> openSale(WidgetTester t, FakeApi api) async {
      phone(t);
      await t.pumpWidget(AuraGymApp(store: GymStore(clock: () => today), auth: AuthController(storage: signedIn(), api: api)));
      await t.pumpAndSettle();
      await tapKey(t, 'homeSales');
      await tapKey(t, 'sale-500');
      await tapKey(t, 'receiptPdf');
      await settlePdf(t);
      return api;
    }

    testWidgets('downloaded from the server in the app language, then shared or printed', (t) async {
      final api = await openSale(t, serverApi()..files['/gym/sales/500/pdf'] = fakePdf);
      expect(api.calls, contains('GET /gym/sales/500/pdf?lang=en'));
      expect(find.textContaining(RegExp('^preview .*_TIR-1001\\.pdf ${fakePdf.length}\$')), findsOneWidget,
          reason: 'the bytes as the server sent them, named by the document');

      await tapKey(t, 'pdfShareButton');
      expect(shared.single.$1, endsWith('_TIR-1001.pdf'));
      expect(shared.single.$2, fakePdf.length);
      await tapKey(t, 'pdfPrintButton');
      expect(printed.single, shared.single);
    });

    testWidgets('Hebrew: the server makes the Hebrew document', (t) async {
      L10n.lang = AppLang.he;
      final api = serverApi()..files['/gym/sales/500/pdf'] = fakePdf;
      phone(t);
      await t.pumpWidget(AuraGymApp(store: GymStore(clock: () => today), auth: AuthController(storage: signedIn(), api: api)));
      await t.pumpAndSettle();
      await tapKey(t, 'homeSales');
      await tapKey(t, 'sale-500');
      await tapKey(t, 'receiptPdf');
      await settlePdf(t);
      expect(api.calls, contains('GET /gym/sales/500/pdf?lang=he'));
    });

    testWidgets('the server fails: the message and "try again"', (t) async {
      final api = serverApi()..errors['/gym/sales/500/pdf'] = AuraApiException(AuraErrorKind.server, 'HTTP 500: pdf_failed');
      await openSale(t, api);
      expect(find.textContaining('Could not make the PDF'), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('pdfShare'))).onPressed, isNull, reason: 'nothing to share');

      api.errors.remove('/gym/sales/500/pdf');
      api.files['/gym/sales/500/pdf'] = fakePdf;
      await tapKey(t, 'pdfRetry');
      await settlePdf(t);
      expect(find.byKey(const Key('pdfPreview')), findsOneWidget);
    });
  });

  testWidgets('demo: a receipt is drawn in the app, nothing asked from a server', (t) async {
    phone(t);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store));
    await t.pumpAndSettle();
    await tapKey(t, 'homeSales');
    final last = store.receipts.last;
    await t.enterText(find.byKey(const Key('salesSearch')), '${last.number}');
    await t.pumpAndSettle();
    await tapKey(t, 'sale-${last.number}');
    await tapKey(t, 'receiptPdf');
    await settlePdf(t);
    expect(find.byKey(const Key('pdfPreview')), findsOneWidget);
    await tapKey(t, 'pdfShareButton');
    expect(shared.single.$1, endsWith('_${last.number}.pdf'));
    expect(shared.single.$2, greaterThan(500));
  });

  testWidgets('a report on screen: PDF of its period', (t) async {
    phone(t);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store));
    await t.pumpAndSettle();
    await tapKey(t, 'navReports');
    final r = allReports.firstWhere((x) => x.usesPeriod && store.settings.enabledReports.contains(x.id));
    await tapKey(t, 'report-${r.id}');
    await tapKey(t, 'reportPdf');
    await settlePdf(t);
    expect(find.byKey(const Key('pdfPreview')), findsOneWidget);
    await tapKey(t, 'pdfShare');
    // The report screen opens on its first period, or "this month".
    expect(shared.single.$1, pdfFileName('${r.title} ${(r.periods?.first ?? Period.month).label}'));
    expect(shared.single.$2, greaterThan(500));
  });
}
