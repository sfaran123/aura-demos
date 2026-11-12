// PDFs made in the app: a report as it is on screen, and a receipt that has no
// document on the AURA server (the demo). A server sale is never redrawn here:
// its PDF is the web's own document (GET gym/sales/{id}/pdf).
//
// The app's fonts are used: Rubik for Hebrew and Latin, Cairo for any text with
// Arabic in it, so a PDF reads like the app, in Hebrew, Arabic or English.

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/checkout.dart' show fmtDate, round2;
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/gym_store.dart';
import '../state/reports.dart';
import 'receipt_view.dart' show carriesVat, docLabel;

pw.ThemeData? _theme;
late pw.Font _rubik, _rubikBold, _cairo, _cairoBold;

/// The app's fonts for PDFs, loaded once.
Future<pw.ThemeData> pdfTheme() async {
  if (_theme != null) return _theme!;
  Future<pw.Font> font(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  _rubik = await font('Rubik_400Regular');
  _rubikBold = await font('Rubik_700Bold');
  _cairo = await font('Cairo_400Regular');
  _cairoBold = await font('Cairo_700Bold');
  return _theme = pw.ThemeData.withFont(base: _rubik, bold: _rubikBold, fontFallback: [_cairo, _cairoBold]);
}

String _range(int from, int to) => '${String.fromCharCode(from)}-${String.fromCharCode(to)}';

/// Arabic letters and their presentation forms.
final _arabic =
    RegExp('[${_range(0x0600, 0x06FF)}${_range(0x0750, 0x077F)}${_range(0xFB50, 0xFDFF)}${_range(0xFE70, 0xFEFF)}]');

/// Arabic short vowels (tashkeel): U+064B to U+065F and U+0670.
final _tashkeel = RegExp('[${_range(0x064B, 0x065F)}${String.fromCharCode(0x0670)}]');

/// Text as the pdf package can draw it. Its right-to-left step (package bidi
/// 2.0.13) fails on some Arabic letter + short vowel pairs (e.g. alef with
/// hamza + damma: RangeError in Normalization._compose), so short vowels are
/// left out; Arabic reads the same without them.
String pdfSafe(String s) => s.replaceAll(_tashkeel, '');

/// A text in the PDF. Arabic is shaped into presentation forms after the font
/// is chosen, and Rubik has none ("Missing glyph"), so any text with Arabic in
/// it is set in Cairo, with Rubik as the fallback for Hebrew in the same line.
pw.Widget _text(String s, {pw.TextStyle? style}) {
  final text = pdfSafe(s);
  if (!_arabic.hasMatch(text)) return pw.Text(text, style: style);
  final bold = style?.fontWeight == pw.FontWeight.bold;
  return pw.Text(text,
      style: (style ?? const pw.TextStyle()).copyWith(
        font: bold ? _cairoBold : _cairo,
        fontNormal: _cairo,
        fontBold: _cairoBold,
        fontFallback: [bold ? _rubikBold : _rubik],
      ));
}

const _ink = PdfColor.fromInt(0xFF101A28);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFE5E7EB);
const _gold = PdfColor.fromInt(0xFFB8913A);

PdfColor _tone(Tone t) => switch (t) {
      Tone.ok => const PdfColor.fromInt(0xFF15803D),
      Tone.warn => const PdfColor.fromInt(0xFFB45309),
      Tone.bad => const PdfColor.fromInt(0xFFB91C1C),
      Tone.info => const PdfColor.fromInt(0xFF1D4ED8),
      Tone.plain => _ink,
    };

String _now() {
  final n = DateTime.now();
  return '${fmtDate(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

/// The business name as the app shows it (the AURA server's company name when signed in).
String businessNameOf(GymStore store) {
  final server = store.dashboard?.businessName ?? '';
  return server.isNotEmpty ? server : store.settings.businessName;
}

pw.Widget _header(String business, String title, String? sub) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _text(business, style: pw.TextStyle(fontSize: 11, color: _muted)),
        pw.SizedBox(height: 2),
        _text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
        if (sub != null && sub.isNotEmpty) _text(sub, style: const pw.TextStyle(fontSize: 11, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Container(height: 2, width: 48, color: _gold),
        pw.SizedBox(height: 12),
      ],
    );

pw.Widget _footer(pw.Context c) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _text(t('הופק {0}', [_now()]), style: const pw.TextStyle(fontSize: 8, color: _muted)),
        _text('${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    );

/// A report as on screen: its numbers, then every section with its rows.
Future<List<int>> reportPdf(ReportData data,
    {required String title, String? subtitle, String? period, required String business}) async {
  final doc = pw.Document(theme: await pdfTheme(), title: title, author: business, creator: 'AURA Gym');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 28),
    textDirection: L10n.lang.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
    footer: _footer,
    build: (c) => [
      _header(business, title, [if (period != null) period, if (subtitle != null) subtitle].join(' · ')),
      if (data.kpis.isNotEmpty)
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in data.kpis)
            pw.Container(
              width: 122,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _text(k.label, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
                pw.SizedBox(height: 2),
                _text(k.value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _tone(k.tone))),
                if (k.sub != null) _text(k.sub!, style: pw.TextStyle(fontSize: 8, color: _tone(k.subTone))),
              ]),
            ),
        ]),
      for (final s in data.sections) ...[
        pw.SizedBox(height: 14),
        _text(s.title, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 4),
        if (s.rows.isEmpty)
          _text(s.empty, style: const pw.TextStyle(fontSize: 10, color: _muted))
        else
          for (final r in s.rows)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    _text(r.title, style: const pw.TextStyle(fontSize: 10, color: _ink)),
                    if (r.subtitle != null && r.subtitle!.isNotEmpty)
                      _text(r.subtitle!, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ]),
                ),
                if (r.tag != null) ...[
                  pw.SizedBox(width: 6),
                  _text(r.tag!, style: pw.TextStyle(fontSize: 8.5, color: _tone(r.tone))),
                ],
                if (r.value != null) ...[
                  pw.SizedBox(width: 10),
                  _text(r.value!, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _tone(r.tone))),
                ],
              ]),
            ),
      ],
      if (data.note != null) ...[
        pw.SizedBox(height: 14),
        _text(data.note!, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      ],
    ],
  ));
  return doc.save();
}

/// A receipt made in the app only (no document on the AURA server), as the
/// receipt card shows it.
Future<List<int>> receiptPdf(Receipt r, GymStore store) async {
  final s = store.settings;
  final business = businessNameOf(store);
  final label = '${docLabel(r, s.docType)} ${r.docNo}';
  final vat = carriesVat(r, s.docType) ? round2(r.total * s.vatPct / (100 + s.vatPct)) : 0.0;
  pw.Widget line(String a, String b, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: _text(a, style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : null))),
          _text(b, style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : null)),
        ]),
      );
  final doc = pw.Document(theme: await pdfTheme(), title: label, author: business, creator: 'AURA Gym');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    textDirection: L10n.lang.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
    build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _header(business, label, s.businessId.isEmpty ? null : t('ח.פ / ע.מ {0}', [s.businessId])),
      _text('${fmtDate(r.date)} · ${r.customerName}', style: const pw.TextStyle(fontSize: 11, color: _muted)),
      if (r.allocationNumber != null)
        _text(t('מספר הקצאה {0}', [r.allocationNumber]), style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Divider(color: _line),
      _text(r.description, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      if (r.reason != null) _text(t('סיבה: {0}', [r.reason]), style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.SizedBox(height: 6),
      for (final l in r.lines) ...[
        line(l.method.label + (l.method == PayMethod.card && l.installments > 1 ? t(' · {0} תשלומים', [l.installments]) : ''),
            money(l.amount)),
        if (l.detailsText.isNotEmpty) _text(l.detailsText, style: const pw.TextStyle(fontSize: 9, color: _muted)),
      ],
      pw.Divider(color: _line),
      if (vat > 0) ...[
        line(t('לפני מע״מ'), money(round2(r.total - vat))),
        line(t('מע״מ {0}%', [s.vatPct.round()]), money(vat)),
      ],
      line(t('סה״כ'), money(r.total), bold: true),
      pw.Spacer(),
      _text(t('הופק {0}', [_now()]), style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ]),
  ));
  return doc.save();
}

/// A file name: letters, digits, '-' and '_' only.
String pdfFileName(String name) {
  final clean = name.trim().replaceAll(RegExp(r'[^\p{L}\p{N}\-_]+', unicode: true), '_').replaceAll(RegExp(r'_+'), '_');
  return '${clean.isEmpty ? 'document' : clean}.pdf';
}
