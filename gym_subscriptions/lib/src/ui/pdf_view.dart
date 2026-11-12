// Shows a PDF and lets staff keep it: "Share / Save" opens the phone's share
// sheet (Files, Drive, WhatsApp, e-mail...), "Print / Save as PDF" the
// system print dialog, which also saves the file (on Android into Downloads).
// No storage permission and no fixed folder is needed, on Android or iOS.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../domain/l10n.dart';
import 'auth_screens.dart' show authErrorText;
import 'theme.dart';
import 'widgets.dart';

/// Opens a PDF screen; [load] makes or downloads the file.
Future<void> openPdf(BuildContext context,
        {required String title, required String fileName, required Future<List<int>> Function() load}) =>
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => PdfScreen(title: title, fileName: fileName, load: load)));

class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.title, required this.fileName, required this.load});
  final String title;
  final String fileName;
  final Future<List<int>> Function() load;

  /// The page view; tests replace it (it renders through the printing plugin).
  static Widget Function(Uint8List bytes, String fileName) preview = (bytes, fileName) => PdfPreview(
        build: (_) async => bytes,
        pdfFileName: fileName,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        scrollViewDecoration: const BoxDecoration(color: Aura.paper),
      );

  /// Sharing and printing; tests replace them.
  static Future<void> Function(Uint8List bytes, String fileName) share =
      (bytes, fileName) => Printing.sharePdf(bytes: bytes, filename: fileName);
  static Future<void> Function(Uint8List bytes, String fileName) print =
      (bytes, fileName) => Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  Uint8List? bytes;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      bytes = null;
      error = null;
    });
    try {
      final b = await widget.load();
      if (mounted) setState(() => bytes = Uint8List.fromList(b));
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _run(Future<void> Function(Uint8List, String) action) async {
    final b = bytes;
    if (b == null) return;
    try {
      await action(b, widget.fileName);
    } catch (e) {
      if (mounted) showDone(context, t('לא הצלחנו לפתוח את הקובץ: {0}', ['$e']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = bytes != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(
          key: const Key('pdfShare'),
          tooltip: t('שמירה / שיתוף'),
          icon: const Icon(Icons.ios_share),
          onPressed: ready ? () => _run(PdfScreen.share) : null,
        ),
        IconButton(
          key: const Key('pdfPrint'),
          tooltip: t('הדפסה / שמירה כ-PDF'),
          icon: const Icon(Icons.print_outlined),
          onPressed: ready ? () => _run(PdfScreen.print) : null,
        ),
      ]),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Note(t('לא הצלחנו להפיק את ה-PDF: {0}', [authErrorText(error!)]), warn: true),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('pdfRetry'),
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('נסו שוב')),
                  ),
                ]),
              ),
            )
          : !ready
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: PdfScreen.preview(bytes!, widget.fileName)),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('pdfShareButton'),
                            onPressed: () => _run(PdfScreen.share),
                            icon: const Icon(Icons.ios_share),
                            label: Text(t('שמירה / שיתוף')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('pdfPrintButton'),
                            onPressed: () => _run(PdfScreen.print),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(t('הדפסה / שמירה כ-PDF')),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
