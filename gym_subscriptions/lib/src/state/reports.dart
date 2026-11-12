// Reports for the gym owner. Each report is computed from the store into a
// neutral structure (KPIs + sections of rows) that one screen renders.

import '../domain/checkout.dart';
import '../domain/dashboard.dart';
import '../domain/doc_types.dart';
import '../domain/help.dart';
import '../domain/models.dart';
import '../domain/settings.dart';
import 'gym_store.dart';
import '../domain/l10n.dart';

enum Period { today, week, month, lastMonth }

extension PeriodLabel on Period {
  String get label => switch (this) {
        Period.today => t('היום'),
        Period.week => t('7 ימים'),
        Period.month => t('החודש'),
        Period.lastMonth => t('חודש קודם'),
      };

  /// [from, to) for this period.
  (DateTime, DateTime) range(DateTime today) => switch (this) {
        Period.today => (today, today.add(const Duration(days: 1))),
        Period.week => (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
        Period.month => (DateTime(today.year, today.month, 1), DateTime(today.year, today.month + 1, 1)),
        Period.lastMonth => (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 1)),
      };
}

enum Tone { ok, warn, bad, info, plain }

class Kpi {
  const Kpi(this.label, this.value, {this.tone = Tone.plain, this.sub, this.subTone = Tone.plain});
  final String label;
  final String value;
  final Tone tone;

  /// Small line under the value, e.g. the change from the previous period.
  final String? sub;
  final Tone subTone;
}

class ReportRow {
  const ReportRow(this.title, {this.subtitle, this.value, this.tag, this.tone = Tone.plain, this.bar, this.chargeId});
  final String title;
  final String? subtitle;
  final String? value;
  final String? tag;
  final Tone tone;

  /// 0..1: draws a bar under the row (share of the largest row).
  final double? bar;

  /// An open charge behind this row: the report offers to collect it.
  final String? chargeId;
}

class ReportSection {
  ReportSection(this.title, this.rows, {String? empty}) : empty = empty ?? t('אין נתונים');
  final String title;
  final List<ReportRow> rows;
  final String empty;
}

class ReportData {
  const ReportData({required this.kpis, required this.sections, this.note});
  final List<Kpi> kpis;
  final List<ReportSection> sections;
  final String? note;

  /// Comma-separated copy of every row, for pasting into Excel.
  String toCsv(String title) {
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final b = StringBuffer('${q(title)}\n');
    for (final k in kpis) {
      b.writeln('${q(k.label)},${q(k.value)}');
    }
    for (final s in sections) {
      b.writeln();
      b.writeln(q(s.title));
      for (final r in s.rows) {
        b.writeln([r.title, r.subtitle, r.tag, r.value].map(q).join(','));
      }
    }
    return b.toString();
  }
}

enum ReportGroup { overview, accounting, money, collection, members, links }

extension ReportGroupLabel on ReportGroup {
  String get label => switch (this) {
        ReportGroup.overview => t('סיכום'),
        ReportGroup.accounting => t('הנהלת חשבונות'),
        ReportGroup.money => t('כספים'),
        ReportGroup.collection => t('גבייה וחובות'),
        ReportGroup.members => t('מנויים'),
        ReportGroup.links => t('לינקים'),
      };
}

/// One report in the reports hub.
class ReportDef {
  const ReportDef(this.id, this.group, this.title, this.subtitle, this.build,
      {this.usesPeriod = false, this.headline, this.periods});
  final String id;
  final ReportGroup group;
  final String title;
  final String subtitle;
  final bool usesPeriod;

  /// Periods offered for this report (all of them when null).
  final List<Period>? periods;
  final ReportData Function(GymStore s, Period p) build;

  /// The number shown on the report's card in the hub.
  final String Function(GymStore s)? headline;

  HelpContent get help => reportHelp(id, title);
}

bool _inRange(DateTime d, (DateTime, DateTime) r) => !d.isBefore(r.$1) && d.isBefore(r.$2);

/// Signed in and synced: the data is the AURA server's.
bool _fromServer(GymStore s) => s.dashboard != null;

/// Memberships counted as active. From the server: running, i.e. not cancelled
/// and not ended (the home screen's definition). In the app alone: active or frozen.
List<Subscription> _live(GymStore s) => _fromServer(s)
    ? s.subscriptions.where((x) => x.status != SubStatus.cancelled && x.status != SubStatus.expired).toList()
    : s.subscriptions.where((x) => x.status == SubStatus.active || x.status == SubStatus.frozen).toList();
double _sum(Iterable<double> v) => round2(v.fold(0.0, (a, b) => a + b));
String _name(GymStore s, String customerId) => s.customer(customerId)?.name ?? '—';
String _plan(GymStore s, String planId) => s.plan(planId)?.name ?? '—';

String _receiptKind(ReceiptKind k) => switch (k) {
      ReceiptKind.subscription => t('מנויים חדשים'),
      ReceiptKind.collection => t('גבייה חודשית'),
      ReceiptKind.quickPay => t('תשלום מהיר'),
      ReceiptKind.link => t('תשלום בלינק'),
      ReceiptKind.credit => t('זיכויים'),
    };

// ------------------------------------------------------------------ summary
/// The period just before [p], of the same length (month to date compares with
/// the same days of last month).
(DateTime, DateTime) previousRange(Period p, DateTime today) {
  final r = p.range(today);
  return switch (p) {
    Period.today => (today.subtract(const Duration(days: 1)), today),
    Period.week => (r.$1.subtract(const Duration(days: 7)), r.$1),
    Period.month => (
        DateTime(today.year, today.month - 1, 1),
        DateTime(today.year, today.month - 1, 1).add(Duration(days: today.day))
      ),
    Period.lastMonth => (DateTime(today.year, today.month - 2, 1), DateTime(today.year, today.month - 1, 1)),
  };
}

String _delta(double now, double before) {
  if (before == 0) return now == 0 ? '—' : t('חדש');
  final pct = ((now - before) / before * 100).round();
  return pct >= 0 ? '+$pct%' : '−${-pct}%';
}

Tone _deltaTone(double now, double before, {bool upIsGood = true}) {
  if (now == before) return Tone.plain;
  return (now > before) == upIsGood ? Tone.ok : Tone.bad;
}

double _revenueIn(GymStore s, (DateTime, DateTime) r) =>
    _sum(s.receipts.where((x) => _inRange(x.date, r)).map((x) => x.collectedNow));

ReportData summaryReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final prev = previousRange(p, s.today);
  final cut = r.$2.isAfter(s.now) ? (r.$1, s.today.add(const Duration(days: 1))) : r;

  final revenue = _revenueIn(s, r), revenuePrev = _revenueIn(s, prev);
  final receipts = s.receipts.where((x) => _inRange(x.date, r)).toList();
  final joins = s.subscriptions.where((x) => _inRange(x.joinedAt, r)).length;
  final joinsPrev = s.subscriptions.where((x) => _inRange(x.joinedAt, prev)).length;
  final cancels = s.subscriptions.where((x) => x.cancelledAt != null && _inRange(x.cancelledAt!, r)).length;
  final cancelsPrev = s.subscriptions.where((x) => x.cancelledAt != null && _inRange(x.cancelledAt!, prev)).length;
  final dash = s.dashboard;
  final live = _live(s);
  // From the server, members are counted once (as the home screen).
  final liveCount = dash != null ? live.map((x) => x.customerId).toSet().length : live.length;

  // Monthly charges that fell due in the period (up to today) and how many were collected.
  // From the server: collected = membership payments in the period; open = the
  // server's debts (failed charges, unpaid membership invoices) dated in the period.
  final double dueSum, paidSum, openSum, failedSum;
  if (dash != null) {
    final debts = dash.debts.where((d) => d.date != null && _inRange(d.date!, cut)).toList();
    paidSum = _sum(s.receipts
        .where((x) => x.kind == ReceiptKind.subscription && _inRange(x.date, cut))
        .map((x) => x.collectedNow));
    openSum = _sum(debts.map((d) => d.amount));
    failedSum = _sum(debts.where((d) => d.kind == DebtKind.failedCharge).map((d) => d.amount));
    dueSum = round2(paidSum + openSum);
  } else {
    final due = s.charges.where((c) => c.status != ChargeStatus.covered && _inRange(c.dueDate, cut)).toList();
    dueSum = _sum(due.map((c) => c.amount));
    paidSum = _sum(due.where((c) => c.status == ChargeStatus.paid).map((c) => c.amount));
    openSum = _sum(due.where((c) => c.isOpen()).map((c) => c.amount));
    failedSum = _sum(due.where((c) => c.status == ChargeStatus.failed).map((c) => c.amount));
  }
  final rate = dueSum == 0 ? 100 : (paidSum / dueSum * 100).round();

  final sent = s.links.where((l) => _inRange(l.createdAt, r)).toList();
  final linkPaid = sent.where((l) => l.stage == LinkStage.paid).length;

  // Six-month trend.
  final months = [for (var i = 5; i >= 0; i--) DateTime(s.today.year, s.today.month - i, 1)];
  final trend = [
    for (final m in months)
      (
        m,
        _revenueIn(s, (m, DateTime(m.year, m.month + 1, 1))),
        s.subscriptions.where((x) => _inRange(x.joinedAt, (m, DateTime(m.year, m.month + 1, 1)))).length,
        s.subscriptions
            .where((x) => x.cancelledAt != null && _inRange(x.cancelledAt!, (m, DateTime(m.year, m.month + 1, 1))))
            .length,
      )
  ];
  final maxTrend = trend.fold(0.0, (a, x) => x.$2 > a ? x.$2 : a);

  final byKind = <ReceiptKind, double>{};
  final byMethod = <PayMethod, double>{};
  for (final x in receipts) {
    byKind[x.kind] = round2((byKind[x.kind] ?? 0) + x.collectedNow);
    for (final l in x.lines.where(x.isCollected)) {
      byMethod[l.method] = round2((byMethod[l.method] ?? 0) + l.amount);
    }
  }

  // Best sellers at the counter.
  final sold = <String, int>{};
  final soldSum = <String, double>{};
  for (final x in receipts.where((x) => x.kind == ReceiptKind.quickPay)) {
    final parts = x.description.split(', ');
    for (final part in parts) {
      sold[part] = (sold[part] ?? 0) + 1;
      soldSum[part] = round2((soldSum[part] ?? 0) + x.collectedNow / parts.length);
    }
  }
  final top = sold.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final maxSold = top.isEmpty ? 1 : top.first.value;

  final overdue = s.charges.where((c) => c.isOpen() && c.daysOverdue(s.today) > 0).toList();
  // Open debt: from the server, the home screen's list and total.
  final debtSum = dash != null ? dash.openDebt : _sum(overdue.map((c) => c.amount));
  final debtCustomers = dash != null
      ? dash.debts.map((d) => d.customerId ?? d.customerName).toSet().length
      : overdue.map((c) => c.customerId).toSet().length;
  final failed = s.charges.where((c) => c.status == ChargeStatus.failed).length;
  final blocked = s.customers.where((c) => s.entryBlocked(c.id)).length;
  final waitingLinks = s.links.where((l) => l.stage != LinkStage.paid && l.stage != LinkStage.failed).length;
  final ending = s.subscriptions
      .where((x) =>
          x.status == SubStatus.active &&
          x.end != null &&
          !x.end!.isBefore(s.today) &&
          x.end!.difference(s.today).inDays <= 30)
      .length;
  final cancelling =
      s.subscriptions.where((x) => x.cancelEffective != null && x.cancelEffective!.isAfter(s.today)).length;

  Tone n(int v) => v > 0 ? Tone.warn : Tone.ok;
  return ReportData(kpis: [
    Kpi(t('הכנסות'), money(revenue),
        tone: Tone.ok,
        sub: t('{0} מול התקופה הקודמת', [_delta(revenue, revenuePrev)]),
        subTone: _deltaTone(revenue, revenuePrev)),
    Kpi(t('מנויים פעילים'), '$liveCount',
        sub: t('{0} מוקפאים', [live.where((x) => x.status == SubStatus.frozen).length])),
    Kpi(t('הצטרפו'), '$joins',
        tone: Tone.ok,
        sub: t('{0} בתקופה הקודמת', [joinsPrev]),
        subTone: _deltaTone(joins.toDouble(), joinsPrev.toDouble())),
    Kpi(t('ביטלו'), '$cancels',
        tone: cancels > 0 ? Tone.warn : Tone.plain,
        sub: t('{0} בתקופה הקודמת', [cancelsPrev]),
        subTone: _deltaTone(cancels.toDouble(), cancelsPrev.toDouble(), upIsGood: false)),
    Kpi(t('אחוז גבייה'), '$rate%',
        tone: rate >= 90 ? Tone.ok : (rate >= 75 ? Tone.warn : Tone.bad),
        sub: t('{0} מתוך {1}', [money(paidSum), money(dueSum)])),
    Kpi(t('חוב פתוח'), money(debtSum),
        tone: debtSum <= 0 ? Tone.ok : Tone.bad, sub: t('{0} לקוחות', [debtCustomers])),
    Kpi(t('קבלות'), '${receipts.length}',
        sub: t('ממוצע {0}', [money(receipts.isEmpty ? 0 : revenue / receipts.length)])),
    // Sign-up links are not on the server yet: left out while signed in.
    if (dash == null)
      Kpi(t('המרת לינקים'), sent.isEmpty ? '—' : '${(linkPaid / sent.length * 100).round()}%',
          tone: Tone.info, sub: t('{0} מתוך {1} שילמו', [linkPaid, sent.length])),
  ], sections: [
    ReportSection(t('דורש טיפול עכשיו'), [
      ReportRow(t('לקוחות באיחור'),
          value: '$debtCustomers', tone: n(debtCustomers), tag: debtSum <= 0 ? null : money(debtSum)),
      ReportRow(t('חיובי אשראי שנכשלו'), value: '$failed', tone: failed > 0 ? Tone.bad : Tone.ok),
      ReportRow(t('כניסה חסומה'), value: '$blocked', tone: blocked > 0 ? Tone.bad : Tone.ok),
      ReportRow(t('מסתיימים ב-30 יום – להציע חידוש'), value: '$ending', tone: n(ending)),
      ReportRow(t('בתהליך ביטול'), value: '$cancelling', tone: n(cancelling)),
      if (dash == null) ReportRow(t('לינקים שעוד לא שולמו'), value: '$waitingLinks', tone: n(waitingLinks)),
    ]),
    ReportSection(t('מגמה – 6 חודשים'), [
      for (final m in trend.reversed)
        ReportRow('${m.$1.month.toString().padLeft(2, '0')}/${m.$1.year}',
            subtitle: t('+{0} הצטרפו · {1} ביטלו', [m.$3, m.$4]),
            value: money(m.$2),
            bar: maxTrend == 0 ? 0 : m.$2 / maxTrend,
            tone: m.$1.month == s.today.month && m.$1.year == s.today.year ? Tone.info : Tone.plain),
    ]),
    ReportSection(t('גבייה חודשית בתקופה'), [
      ReportRow(t('היה לגבות'), value: money(dueSum)),
      ReportRow(t('נגבה'), value: money(paidSum), tone: Tone.ok, bar: dueSum == 0 ? 0 : paidSum / dueSum),
      ReportRow(t('פתוח'), value: money(openSum), tone: openSum > 0 ? Tone.warn : Tone.ok),
      ReportRow(t('מתוכו חיובים שנכשלו'), value: money(failedSum), tone: failedSum > 0 ? Tone.bad : Tone.ok),
    ]),
    ReportSection(t('מאיפה הגיע הכסף'), [
      for (final e in byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(_receiptKind(e.key),
            value: money(e.value),
            tag: revenue == 0 ? null : '${(e.value / revenue * 100).round()}%',
            bar: revenue == 0 ? 0 : e.value / revenue),
    ]),
    ReportSection(t('לפי אמצעי תשלום'), [
      for (final e in byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(e.key.label,
            value: money(e.value),
            tag: revenue == 0 ? null : '${(e.value / revenue * 100).round()}%',
            bar: revenue == 0 ? 0 : e.value / revenue),
    ]),
    ReportSection(t('הנמכרים ביותר בקבלה'), [
      for (final e in top.take(6))
        ReportRow(e.key,
            subtitle: money(soldSum[e.key] ?? 0), value: t('{0} פעמים', [e.value]), bar: e.value / maxSold),
    ]),
  ], note: t('השוואה לתקופה באורך זהה שלפניה. "החודש" מושווה לאותם ימים בחודש הקודם.'));
}

// ------------------------------------------------------------------ accounting
/// Net and VAT of an amount that includes VAT.
(double, double) splitVat(double gross, double vatPct) {
  final vat = round2(gross * vatPct / (100 + vatPct));
  return (round2(gross - vat), vat);
}

/// Invoices above this amount before VAT, to a business customer, need a Tax
/// Authority allocation number (Israel Invoice model, from 1 June 2026).
const allocationThreshold = 5000.0;

/// Accountant package from the server's documents. VAT comes from the tax
/// documents themselves (types 7, 27 and credit 10, as the web's accounting
/// export), with each document's own total and VAT; receipts and other
/// documents carry no VAT. Numbering is done by the server per document type.
ReportData _serverAccountantReport(GymStore s, (DateTime, DateTime) r) {
  final docs = s.receipts.where((x) => _inRange(x.date, r)).toList()..sort((a, b) => a.date.compareTo(b.date));
  final tax = docs.where((x) => x.isTaxDocument).toList();
  final sales = tax.where((x) => !x.isCredit).toList();
  final credits = tax.where((x) => x.isCredit).toList();
  double docTotal(Receipt x) => x.docTotal ?? x.total;
  final gross = _sum(sales.map(docTotal));
  final vat = _sum(sales.map((x) => x.vat ?? 0));
  final creditGross = _sum(credits.map((x) => docTotal(x).abs()));
  final cVat = _sum(credits.map((x) => (x.vat ?? 0).abs()));
  final net = round2(gross - vat), cNet = round2(creditGross - cVat);
  final big = sales.where((x) => docTotal(x) - (x.vat ?? 0) > allocationThreshold && x.allocationNumber == null).toList();

  final byMethod = <PayMethod, double>{};
  for (final x in docs) {
    for (final l in x.lines) {
      byMethod[l.method] = round2((byMethod[l.method] ?? 0) + l.amount);
    }
  }
  final cheques = [
    for (final x in docs)
      for (final l in x.lines.where((l) => l.method == PayMethod.cheque && l.amount > 0))
        (
          x,
          dateOnly(l.cheque.firstDate ?? x.date),
          l.amount,
          l.cheque.number.isEmpty ? '' : t('שיק {0} · בנק {1} · סניף {2}', [l.cheque.number, l.cheque.bank, l.cheque.branch]),
        )
  ];
  String label(Receipt x) => '${serverDocTypeLabel(x.docType ?? 0)} ${x.docNo}';

  return ReportData(
      kpis: [
        Kpi(t('מחזור כולל מע״מ'), money(gross), tone: Tone.ok, sub: t('{0} מסמכים', [sales.length])),
        Kpi(t('זיכויים'), money(creditGross),
            tone: creditGross > 0 ? Tone.warn : Tone.plain, sub: t('{0} מסמכים', [credits.length])),
        Kpi(t('לפני מע״מ (נטו)'), money(round2(net - cNet))),
        Kpi(t('מע״מ עסקאות לתשלום'), money(round2(vat - cVat)), tone: Tone.info, sub: t('לפי המסמכים')),
        Kpi(t('טווח מספרים'), '—', sub: t('מספור בשרת, לפי סוג מסמך')),
        Kpi(t('לבדיקה'), '${big.length}',
            tone: big.isEmpty ? Tone.ok : Tone.warn, sub: t('מספרי הקצאה ותקבולים ממתינים')),
      ],
      sections: [
        ReportSection(t('סיכום מע״מ לתקופה'), [
          ReportRow(t('עסקאות חייבות לפני מע״מ'), value: money(net)),
          ReportRow(t('מע״מ על עסקאות'), value: money(vat)),
          ReportRow(t('זיכויים לפני מע״מ'), value: money(-cNet), tone: cNet > 0 ? Tone.warn : Tone.plain),
          ReportRow(t('מע״מ על זיכויים'), value: money(-cVat), tone: cVat > 0 ? Tone.warn : Tone.plain),
          ReportRow(t('סה״כ מע״מ עסקאות לדיווח'), value: money(round2(vat - cVat)), tone: Tone.info),
        ]),
        ReportSection(t('תקבולים לפי אמצעי תשלום'), [
          for (final m in PayMethod.values)
            if (byMethod[m] != null) ReportRow(m.label, value: money(byMethod[m]!)),
        ]),
        ReportSection(t('בדיקות לפני הגשה'), [
          ReportRow(t('מספור רציף של מסמכים'), subtitle: t('מספור בשרת, לפי סוג מסמך')),
          ReportRow(t('חשבוניות מעל {0} לפני מע״מ בלי מספר הקצאה', [money(allocationThreshold)]),
              subtitle: t('נדרש מספר הקצאה אם הלקוח הוא עסק (חשבוניות ישראל)'),
              value: '${big.length}',
              tone: big.isEmpty ? Tone.ok : Tone.warn),
          for (final x in big)
            ReportRow(label(x),
                subtitle: '${fmtDate(x.date)} · ${x.customerName}', value: money(docTotal(x)), tone: Tone.warn),
        ]),
        ReportSection(t('יומן מסמכים'), [
          for (final x in docs)
            ReportRow(label(x),
                subtitle: [
                  fmtDate(x.date),
                  x.customerName,
                  if (x.lines.isNotEmpty) x.lines.map((l) => l.method.label).join(' + '),
                  if (x.isTaxDocument && (x.vat ?? 0) != 0) t('מע״מ {0}', [money(x.vat!)]),
                  if (x.allocationNumber != null) t('מספר הקצאה {0}', [x.allocationNumber]),
                ].join(' · '),
                value: money(docTotal(x)),
                tag: x.cancelled ? t('בוטל') : null,
                tone: x.isCredit || x.cancelled ? Tone.bad : Tone.plain),
        ]),
        ReportSection(t('שיקים שהתקבלו'), [
          for (final c in cheques)
            ReportRow(c.$1.customerName,
                subtitle: [fmtDate(c.$2), if (c.$4.isNotEmpty) c.$4, c.$1.docNo].join(' · '), value: money(c.$3)),
        ]),
      ],
      note: t(
          'הדוח מוכן להעברה לרואה החשבון (העתקה לאקסל). קובץ במבנה אחיד לרשות המסים ובקשת מספרי הקצאה מופקים בצד השרת, אחרי החיבור למערכת.'));
}

ReportData accountantReport(GymStore s, Period p) {
  final r = (p == Period.lastMonth ? Period.lastMonth : Period.month).range(s.today);
  if (_fromServer(s)) return _serverAccountantReport(s, r);
  final vatPct = s.settings.docType == DocType.taxInvoiceReceipt ? s.settings.vatPct : 0.0;
  final docs = s.receipts.where((x) => _inRange(x.date, r)).toList()..sort((a, b) => a.number.compareTo(b.number));
  final sales = docs.where((x) => !x.isCredit).toList();
  final credits = docs.where((x) => x.isCredit).toList();
  final gross = _sum(sales.map((x) => x.total));
  final creditGross = _sum(credits.map((x) => -x.total));
  final (net, vat) = splitVat(gross, vatPct);
  final (cNet, cVat) = splitVat(creditGross, vatPct);
  // Server documents (reference set) are numbered by the server, per document type.
  final numbers = docs.where((x) => x.reference == null).map((x) => x.number).toList();
  final gaps = <int>[];
  for (var i = 1; i < numbers.length; i++) {
    for (var n = numbers[i - 1] + 1; n < numbers[i]; n++) {
      gaps.add(n);
    }
  }
  final big =
      sales.where((x) => splitVat(x.total, vatPct).$1 > allocationThreshold && x.allocationNumber == null).toList();
  final pending = sales.where((x) => x.lines.any((l) => !x.isCollected(l))).toList();

  final byMethod = <PayMethod, double>{};
  for (final x in docs) {
    for (final l in x.lines) {
      byMethod[l.method] = round2((byMethod[l.method] ?? 0) + l.amount);
    }
  }
  final cheques = [
    for (final x in sales)
      for (final l in x.lines.where((l) => l.method == PayMethod.cheque))
        for (var i = 0; i < l.cheques; i++)
          (
            x,
            addMonths(dateOnly(l.cheque.firstDate ?? x.date), i),
            round2(l.amount / l.cheques),
            l.cheque.number.isEmpty
                ? ''
                : t('שיק {0} · בנק {1} · סניף {2}', [l.cheque.numberAt(i), l.cheque.bank, l.cheque.branch]),
          )
  ];
  String label(Receipt x) =>
      x.isCredit ? s.settings.docType.creditName : s.settings.docType.docName;

  return ReportData(
      kpis: [
        Kpi(t('מחזור כולל מע״מ'), money(gross), tone: Tone.ok, sub: t('{0} מסמכים', [sales.length])),
        Kpi(t('זיכויים'), money(creditGross),
            tone: creditGross > 0 ? Tone.warn : Tone.plain, sub: t('{0} מסמכים', [credits.length])),
        Kpi(t('לפני מע״מ (נטו)'), money(round2(net - cNet))),
        Kpi(t('מע״מ עסקאות לתשלום'), money(round2(vat - cVat)), tone: Tone.info, sub: t('מע״מ {0}%', [vatPct.round()])),
        Kpi(t('טווח מספרים'), numbers.isEmpty ? '—' : '${numbers.first}–${numbers.last}',
            sub: gaps.isEmpty ? t('רציף, בלי חורים') : t('{0} מספרים חסרים', [gaps.length]),
            subTone: gaps.isEmpty ? Tone.ok : Tone.bad),
        Kpi(t('לבדיקה'), '${big.length + pending.length}',
            tone: big.isEmpty && pending.isEmpty ? Tone.ok : Tone.warn, sub: t('מספרי הקצאה ותקבולים ממתינים')),
      ],
      sections: [
        ReportSection(t('סיכום מע״מ לתקופה'), [
          ReportRow(t('עסקאות חייבות לפני מע״מ'), value: money(net)),
          ReportRow(t('מע״מ על עסקאות'), value: money(vat)),
          ReportRow(t('זיכויים לפני מע״מ'), value: money(-cNet), tone: cNet > 0 ? Tone.warn : Tone.plain),
          ReportRow(t('מע״מ על זיכויים'), value: money(-cVat), tone: cVat > 0 ? Tone.warn : Tone.plain),
          ReportRow(t('סה״כ מע״מ עסקאות לדיווח'), value: money(round2(vat - cVat)), tone: Tone.info),
        ]),
        ReportSection(t('תקבולים לפי אמצעי תשלום'), [
          for (final m in PayMethod.values)
            if (byMethod[m] != null)
              ReportRow(m.label,
                  subtitle: m.isDeferred ? t('כולל חלקים שעוד לא אושרו') : null, value: money(byMethod[m]!)),
        ]),
        ReportSection(t('בדיקות לפני הגשה'), [
          ReportRow(t('מספור רציף של מסמכים'),
              subtitle: gaps.isEmpty ? null : t('חסרים: {0}', [gaps.take(10).join(', ')]),
              tag: gaps.isEmpty ? t('תקין') : t('לבדוק'),
              tone: gaps.isEmpty ? Tone.ok : Tone.bad),
          ReportRow(t('חשבוניות מעל {0} לפני מע״מ בלי מספר הקצאה', [money(allocationThreshold)]),
              subtitle: t('נדרש מספר הקצאה אם הלקוח הוא עסק (חשבוניות ישראל)'),
              value: '${big.length}',
              tone: big.isEmpty ? Tone.ok : Tone.warn),
          for (final x in big)
            ReportRow('${label(x)} ${x.docNo}',
                subtitle: '${fmtDate(x.date)} · ${x.customerName}', value: money(x.total), tone: Tone.warn),
          ReportRow(t('תקבולים בהעברה או בלינק שעוד לא אושרו'),
              value: '${pending.length}', tone: pending.isEmpty ? Tone.ok : Tone.warn),
          ReportRow(t('זיכויים בלי סיבה'),
              value: '${credits.where((x) => x.reason == null).length}',
              tone: credits.every((x) => x.reason != null) ? Tone.ok : Tone.warn),
        ]),
        ReportSection(t('יומן מסמכים'), [
          for (final x in docs)
            ReportRow('${label(x)} ${x.docNo}',
                subtitle: '${fmtDate(x.date)} · ${x.customerName} · ${x.lines.map((l) => l.method.label).join(' + ')}'
                    '${x.isCredit && x.creditOf != null ? ' · ${t('זיכוי למסמך {0}', [x.creditOf])}' : ''}',
                value: money(x.total),
                tag: vatPct > 0 ? t('מע״מ {0}', [money(splitVat(x.total, vatPct).$2)]) : null,
                tone: x.isCredit ? Tone.bad : Tone.plain),
        ]),
        ReportSection(t('שיקים שהתקבלו'), [
          for (final c in cheques)
            ReportRow(c.$1.customerName,
                subtitle: [
                  fmtDate(c.$2),
                  if (c.$4.isNotEmpty) c.$4,
                  t('מסמך {0}', [c.$1.number])
                ].join(' · '),
                value: money(c.$3)),
        ]),
      ],
      note: t(
          'הדוח מוכן להעברה לרואה החשבון (העתקה לאקסל). קובץ במבנה אחיד לרשות המסים ובקשת מספרי הקצאה מופקים בצד השרת, אחרי החיבור למערכת.'));
}

/// Daily close (Z report): what came in today and how, to check the cash drawer.
ReportData dailyReport(GymStore s, Period p) {
  final r = p == Period.week ? Period.week.range(s.today) : Period.today.range(s.today);
  final docs = s.receipts.where((x) => _inRange(x.date, r)).toList()..sort((a, b) => a.date.compareTo(b.date));
  double by(PayMethod m) => _sum([
        for (final x in docs)
          for (final l in x.lines.where((l) => l.method == m)) l.amount
      ]);
  final total = _sum(docs.map((x) => x.collectedNow));
  final credits = docs.where((x) => x.isCredit).toList();
  return ReportData(kpis: [
    Kpi(t('נכנס'), money(total), tone: Tone.ok, sub: t('{0} מסמכים', [docs.length])),
    Kpi(t('מזומן בקופה'), money(by(PayMethod.cash)), tone: Tone.info, sub: t('לספור ולהשוות')),
    Kpi(t('אשראי'), money(by(PayMethod.card))),
    Kpi(t('שיקים'), money(by(PayMethod.cheque))),
    Kpi(t('העברות'), money(by(PayMethod.bank))),
    Kpi(t('זיכויים'), money(-_sum(credits.map((x) => x.total))),
        tone: credits.isEmpty ? Tone.plain : Tone.warn, sub: t('{0} מסמכים', [credits.length])),
  ], sections: [
    ReportSection(t('מסמכים'), [
      for (final x in docs.reversed)
        ReportRow(x.customerName,
            subtitle:
                '${fmtDate(x.date)} ${x.date.hour.toString().padLeft(2, '0')}:${x.date.minute.toString().padLeft(2, '0')}'
                ' · ${x.docNo} · ${x.lines.map((l) => l.method.label).join(' + ')}',
            value: money(x.total),
            tone: x.isCredit ? Tone.bad : Tone.plain),
    ]),
  ], note: t('בסוף היום סופרים את המזומן בקופה ומשווים ל"מזומן בקופה". הפרש צריך הסבר.'));
}

// ------------------------------------------------------------------ money
ReportData revenueReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final list = s.receipts.where((x) => _inRange(x.date, r)).toList()..sort((a, b) => b.date.compareTo(a.date));
  final total = _sum(list.map((x) => x.collectedNow));
  final byMethod = <PayMethod, double>{};
  final byKind = <ReceiptKind, double>{};
  for (final x in list) {
    for (final l in x.lines) {
      if (!x.isCollected(l)) continue;
      byMethod[l.method] = round2((byMethod[l.method] ?? 0) + l.amount);
    }
    byKind[x.kind] = round2((byKind[x.kind] ?? 0) + x.collectedNow);
  }
  return ReportData(kpis: [
    Kpi(t('נגבה'), money(total), tone: Tone.ok),
    Kpi(t('קבלות'), '${list.length}'),
    Kpi(t('ממוצע לקבלה'), money(list.isEmpty ? 0 : total / list.length)),
  ], sections: [
    ReportSection(t('לפי אמצעי תשלום'), [
      for (final e in byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(e.key.label,
            value: money(e.value),
            tag: total == 0 ? null : '${(e.value / total * 100).round()}%',
            bar: total == 0 ? 0 : e.value / total),
    ]),
    ReportSection(t('לפי מקור'), [
      for (final e in byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(_receiptKind(e.key), value: money(e.value), bar: total == 0 ? 0 : e.value / total),
    ]),
    ReportSection(t('קבלות'), [
      for (final x in list)
        ReportRow(x.customerName,
            subtitle: '${fmtDate(x.date)} · ${x.description} · ${x.lines.map((l) => l.method.label).join(' + ')}'
                '${x.lines.where((l) => l.detailsText.isNotEmpty).map((l) => '\n${l.detailsText}').join()}',
            value: money(x.total),
            tag: x.docNo),
    ]),
  ]);
}

ReportData forecastReport(GymStore s, Period _) {
  final from = s.today, to = s.today.add(const Duration(days: 30));
  final due = s.charges.where((c) => c.isOpen() && !c.dueDate.isBefore(from) && c.dueDate.isBefore(to)).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final cheques = _chequeSchedule(s).where((c) => !c.$1.isBefore(from) && c.$1.isBefore(to)).toList();
  final auto = _sum(due.where((c) => !c.manual).map((c) => c.amount));
  final manual = _sum(due.where((c) => c.manual).map((c) => c.amount));
  final chq = _sum(cheques.map((c) => c.$3));
  return ReportData(kpis: [
    Kpi(t('צפוי ב-30 יום'), money(auto + manual + chq), tone: Tone.info),
    Kpi(t('חיוב אוטומטי'), money(auto)),
    Kpi(t('גבייה ידנית'), money(manual), tone: manual > 0 ? Tone.warn : Tone.plain),
    Kpi(t('שיקים'), money(chq)),
  ], sections: [
    ReportSection(t('חיובים חודשיים'), [
      for (final c in due)
        ReportRow(_name(s, c.customerId),
            subtitle: '${fmtDate(c.dueDate)} · ${c.manual ? t('גבייה ידנית') : t('אשראי / הוראת קבע')}',
            value: money(c.amount),
            tone: c.manual ? Tone.warn : Tone.plain),
    ]),
    ReportSection(t('שיקים לפירעון'), [
      for (final c in cheques) ReportRow(c.$2, subtitle: fmtDate(c.$1), value: money(c.$3)),
    ]),
  ], note: t('לא כולל מנויים חדשים ותשלומים מהירים שעוד לא בוצעו.'));
}

/// (date, customer, amount, details) for every post-dated cheque, from receipts.
List<(DateTime, String, double, String)> _chequeSchedule(GymStore s) {
  final out = <(DateTime, String, double, String)>[];
  for (final r in s.receipts) {
    for (final l in r.lines.where((l) => l.method == PayMethod.cheque)) {
      final each = round2(l.amount / l.cheques);
      final first = dateOnly(l.cheque.firstDate ?? r.date);
      for (var i = 0; i < l.cheques; i++) {
        final c = l.cheque;
        final det = c.number.isEmpty ? '' : t('שיק {0} · בנק {1} · סניף {2}', [c.numberAt(i), c.bank, c.branch]);
        out.add((addMonths(first, i), r.customerName, each, det));
      }
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

ReportData chequesReport(GymStore s, Period _) {
  final all = _chequeSchedule(s);
  final future = all.where((c) => !c.$1.isBefore(s.today)).toList();
  final deposited = all.where((c) => c.$1.isBefore(s.today)).toList();
  return ReportData(kpis: [
    Kpi(t('שיקים לפירעון'), '${future.length}'),
    Kpi(t('סכום עתידי'), money(_sum(future.map((c) => c.$3))), tone: Tone.info),
    Kpi(t('כבר נפרעו'), money(_sum(deposited.map((c) => c.$3)))),
  ], sections: [
    ReportSection(t('לפירעון'), [
      for (final c in future)
        ReportRow(c.$2,
            subtitle: c.$4.isEmpty ? fmtDate(c.$1) : '${fmtDate(c.$1)} · ${c.$4}',
            value: money(c.$3),
            tag: c.$1.difference(s.today).inDays <= 7 ? t('השבוע') : null,
            tone: c.$1.difference(s.today).inDays <= 7 ? Tone.warn : Tone.plain),
    ]),
    ReportSection(t('נפרעו'), [
      for (final c in deposited.reversed)
        ReportRow(c.$2, subtitle: c.$4.isEmpty ? fmtDate(c.$1) : '${fmtDate(c.$1)} · ${c.$4}', value: money(c.$3))
    ]),
  ]);
}

ReportData depositsReport(GymStore s, Period _) {
  final subs = s.subscriptions.where((x) => x.prepaidAmount > 0).toList();
  final covered = s.charges.where((c) => c.status == ChargeStatus.covered).toList();
  return ReportData(kpis: [
    Kpi(t('חודשים ששולמו מראש'), '${subs.length}'),
    Kpi(t('סכום מוחזק'), money(_sum(subs.map((x) => x.prepaidAmount))), tone: Tone.info),
  ], sections: [
    ReportSection(t('מנויים עם חודש אחרון משולם'), [
      for (final x in subs)
        ReportRow(_name(s, x.customerId),
            subtitle: t('{0} · הצטרף {1}', [_plan(s, x.planId), fmtDate(x.joinedAt)]), value: money(x.prepaidAmount)),
    ]),
    ReportSection(t('חודשים אחרונים שכוסו מהתשלום מראש'), [
      for (final c in covered)
        ReportRow(_name(s, c.customerId), subtitle: fmtDate(c.dueDate), value: money(c.amount), tag: t('לא חויב')),
    ]),
  ], note: t('בביטול מנוי כזה צריך הודעה חודש מראש, והחודש האחרון לא מחויב כי כבר שולם.'));
}

// ------------------------------------------------------------------ collection
ReportData manualMonthlyReport(GymStore s, Period p) {
  final r = p == Period.lastMonth ? p.range(s.today) : Period.month.range(s.today);
  final list = s.charges.where((c) => c.manual && _inRange(c.dueDate, r)).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final expected = _sum(list.map((c) => c.amount));
  final paid = list.where((c) => c.status == ChargeStatus.paid).toList();
  final open = list.where((c) => c.isOpen()).toList();
  String sub(Charge c) {
    final x = s.subscriptions.firstWhere((x) => x.id == c.subscriptionId);
    return '${_plan(s, x.planId)} · ${s.customer(c.customerId)?.phone ?? ''}';
  }

  return ReportData(kpis: [
    Kpi(t('לגבות בחודש'), money(expected)),
    Kpi(t('נגבה'), money(_sum(paid.map((c) => c.amount))), tone: Tone.ok),
    Kpi(t('נשאר'), money(_sum(open.map((c) => c.amount))), tone: open.isEmpty ? Tone.ok : Tone.warn),
    Kpi(t('לקוחות'), '${list.map((c) => c.customerId).toSet().length}'),
  ], sections: [
    ReportSection(
        t('עוד לא שילמו'),
        [
          for (final c in open)
            ReportRow(_name(s, c.customerId),
                subtitle: t('{0} · מועד {1}', [sub(c), fmtDate(c.dueDate)]),
                value: money(c.amount),
                tag: c.daysOverdue(s.today) > 0
                    ? t('באיחור {0} ימים', [c.daysOverdue(s.today)])
                    : t('ב-{0}', [fmtDate(c.dueDate)]),
                tone: c.daysOverdue(s.today) > 0 ? Tone.bad : Tone.info,
                chargeId: c.id),
        ],
        empty: t('כולם שילמו')),
    ReportSection(t('שילמו'), [
      for (final c in paid)
        ReportRow(_name(s, c.customerId),
            subtitle: t('{0} · שולם {1}', [sub(c), c.paidAt == null ? '' : fmtDate(c.paidAt!)]),
            value: money(c.amount),
            tag: c.paidWith?.label,
            tone: Tone.ok),
    ]),
  ], note: t('מנויים חודשיים שמשלמים בעצמם (מזומן, שיק או העברה) ולא בחיוב אוטומטי.'));
}

ReportData debtsReport(GymStore s, Period p) {
  final dash = s.dashboard;
  if (dash != null) return _serverDebtsReport(s, dash);
  final open = s.charges.where((c) => c.isOpen() && c.daysOverdue(s.today) > 0).toList()
    ..sort((a, b) => b.daysOverdue(s.today).compareTo(a.daysOverdue(s.today)));
  double bucket(int from, int to) =>
      _sum(open.where((c) => c.daysOverdue(s.today) >= from && c.daysOverdue(s.today) <= to).map((c) => c.amount));
  return ReportData(kpis: [
    Kpi(t('חוב פתוח'), money(_sum(open.map((c) => c.amount))), tone: open.isEmpty ? Tone.ok : Tone.bad),
    Kpi(t('1–7 ימים'), money(bucket(1, 7))),
    Kpi(t('8–30 ימים'), money(bucket(8, 30)), tone: Tone.warn),
    Kpi(t('מעל 30'), money(bucket(31, 100000)), tone: Tone.bad),
  ], sections: [
    ReportSection(
        t('חייבים'),
        [
          for (final c in open)
            ReportRow(_name(s, c.customerId),
                subtitle: t('{0} · מועד {1} · {2} תזכורות',
                    [c.manual ? t('גבייה ידנית') : t('אשראי נכשל'), fmtDate(c.dueDate), c.reminders]),
                value: money(c.amount),
                tag: s.entryBlocked(c.customerId) ? t('כניסה חסומה') : t('{0} ימים', [c.daysOverdue(s.today)]),
                tone: s.entryBlocked(c.customerId) ? Tone.bad : Tone.warn,
                chargeId: c.id),
        ],
        empty: t('אין חובות')),
  ]);
}

/// Debts from the server: failed membership charges and unpaid membership
/// invoices, the same list as the home screen's "Open debt".
ReportData _serverDebtsReport(GymStore s, ServerDashboard dash) {
  int days(DebtItem d) {
    if (d.date == null) return 0;
    final n = s.today.difference(DateTime(d.date!.year, d.date!.month, d.date!.day)).inDays;
    return n < 0 ? 0 : n;
  }

  final open = [...dash.debts]..sort((a, b) => days(b).compareTo(days(a)));
  double bucket(int from, int to) => _sum(open.where((d) => days(d) >= from && days(d) <= to).map((d) => d.amount));
  return ReportData(kpis: [
    Kpi(t('חוב פתוח'), money(dash.openDebt), tone: open.isEmpty ? Tone.ok : Tone.bad),
    Kpi(t('עד 7 ימים'), money(bucket(0, 7))),
    Kpi(t('8–30 ימים'), money(bucket(8, 30)), tone: Tone.warn),
    Kpi(t('מעל 30'), money(bucket(31, 100000)), tone: Tone.bad),
  ], sections: [
    ReportSection(
        t('חייבים'),
        [
          for (final d in open)
            ReportRow(d.customerName.isEmpty ? '—' : d.customerName,
                subtitle: t('{0} · מועד {1}', [
                  switch (d.kind) {
                    DebtKind.failedCharge => t('אשראי נכשל'),
                    DebtKind.unpaidInvoice => t('חשבונית {0}', [d.reference ?? '']),
                    DebtKind.manualDue => t('גבייה ידנית'),
                  },
                  d.date == null ? '—' : fmtDate(d.date!),
                ]),
                value: money(d.amount),
                tag: d.customerId != null && s.entryBlocked(d.customerId!) ? t('כניסה חסומה') : t('{0} ימים', [days(d)]),
                tone: d.customerId != null && s.entryBlocked(d.customerId!) ? Tone.bad : Tone.warn,
                // A failed charge is in the app's "to collect" list under the same id.
                chargeId: s.charges.any((c) => c.id == d.id) ? d.id : null),
        ],
        empty: t('אין חובות')),
  ]);
}

ReportData failedReport(GymStore s, Period _) {
  final f = s.charges.where((c) => c.status == ChargeStatus.failed).toList();
  return ReportData(
      kpis: [
        Kpi(t('חיובים שנכשלו'), '${f.length}', tone: f.isEmpty ? Tone.ok : Tone.bad),
        Kpi(t('סכום'), money(_sum(f.map((c) => c.amount)))),
      ],
      sections: [
        ReportSection(
            t('לטיפול'),
            [
              for (final c in f)
                ReportRow(_name(s, c.customerId),
                    subtitle: t('{0} · {1} ניסיונות · כרטיס {2}',
                        [fmtDate(c.dueDate), c.attempts, s.customer(c.customerId)?.savedCardLast4 ?? '—']),
                    value: money(c.amount),
                    tag: t('לשלוח לינק לעדכון כרטיס'),
                    tone: Tone.bad,
                    chargeId: c.id),
            ],
            empty: t('אין חיובים שנכשלו')),
      ],
      note: t('ניסיונות חוזרים אוטומטיים לפי ההגדרות: {0}.', [
        s.settings.retryDays.take(s.settings.retryAttempts).map((d) => t('יום {0}', [d])).join(', ')
      ]));
}

// ------------------------------------------------------------------ members
ReportData activeByPlanReport(GymStore s, Period _) {
  final live = _live(s);
  // From the server, members are counted once (as the home screen); in the app, memberships.
  final members = _fromServer(s) ? live.map((x) => x.customerId).toSet().length : live.length;
  final rows = <ReportRow>[];
  var mrr = 0.0;
  for (final p in s.plans) {
    final subs = live.where((x) => x.planId == p.id).toList();
    if (subs.isEmpty) continue;
    final monthly = _sum(subs.map((x) => x.monthlyAmount ?? (p.kind == PlanKind.term ? p.price / p.months : 0)));
    mrr += monthly;
    rows.add(
        ReportRow(p.name, subtitle: t('{0} · {1} בחודש', [p.kind.label, money(monthly)]), value: '${subs.length}'));
  }
  rows.sort((a, b) => int.parse(b.value!).compareTo(int.parse(a.value!)));
  return ReportData(kpis: [
    Kpi(t('מנויים פעילים'), '$members', tone: Tone.ok),
    Kpi(t('הכנסה חודשית חוזרת'), money(mrr), tone: Tone.info),
    Kpi(t('ממוצע למנוי'), money(members == 0 ? 0 : mrr / members)),
  ], sections: [
    ReportSection(t('לפי מסלול'), rows)
  ], note: t('במסלולי תקופה ההכנסה מחולקת לפי מספר החודשים.'));
}

ReportData expiringReport(GymStore s, Period _) {
  final to = s.today.add(const Duration(days: 30));
  final list = s.subscriptions
      .where((x) => x.status == SubStatus.active && x.end != null && !x.end!.isBefore(s.today) && x.end!.isBefore(to))
      .toList()
    ..sort((a, b) => a.end!.compareTo(b.end!));
  final cancelling =
      s.subscriptions.where((x) => x.cancelEffective != null && x.cancelEffective!.isAfter(s.today)).toList();
  return ReportData(kpis: [
    Kpi(t('מסתיימים ב-30 יום'), '${list.length}', tone: list.isEmpty ? Tone.ok : Tone.warn),
    Kpi(t('בתהליך ביטול'), '${cancelling.length}'),
  ], sections: [
    ReportSection(t('להציע חידוש'), [
      for (final x in list)
        ReportRow(_name(s, x.customerId),
            subtitle: '${_plan(s, x.planId)} · ${s.customer(x.customerId)?.phone ?? ''}',
            value: fmtDate(x.end!),
            tag: t('{0} ימים', [x.end!.difference(s.today).inDays]),
            tone: x.end!.difference(s.today).inDays <= 7 ? Tone.bad : Tone.warn),
    ]),
    ReportSection(t('ביטולים שייכנסו לתוקף'), [
      for (final x in cancelling)
        ReportRow(_name(s, x.customerId), subtitle: _plan(s, x.planId), value: fmtDate(x.cancelEffective!)),
    ]),
  ]);
}

ReportData joinsReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final joins = s.subscriptions.where((x) => _inRange(x.joinedAt, r)).toList();
  final cancels = s.subscriptions.where((x) => x.cancelledAt != null && _inRange(x.cancelledAt!, r)).toList();
  final active = _live(s).length;
  final churn = active == 0 ? 0 : (cancels.length / active * 100);
  return ReportData(kpis: [
    Kpi(t('הצטרפו'), '${joins.length}', tone: Tone.ok),
    Kpi(t('ביטלו'), '${cancels.length}', tone: cancels.isEmpty ? Tone.plain : Tone.warn),
    Kpi(t('נטו'), '${joins.length - cancels.length}'),
    Kpi(t('נטישה'), '${churn.toStringAsFixed(1)}%'),
  ], sections: [
    ReportSection(t('הצטרפויות'), [
      for (final x in joins)
        ReportRow(_name(s, x.customerId), subtitle: _plan(s, x.planId), value: fmtDate(x.joinedAt)),
    ]),
    ReportSection(t('ביטולים'), [
      for (final x in cancels)
        ReportRow(_name(s, x.customerId),
            subtitle: t('{0} · בתוקף עד {1}',
                [_plan(s, x.planId), x.cancelEffective == null ? '—' : fmtDate(x.cancelEffective!)]),
            value: fmtDate(x.cancelledAt!)),
    ]),
  ]);
}

ReportData frozenReport(GymStore s, Period _) {
  final f = s.subscriptions.where((x) => x.status == SubStatus.frozen).toList();
  return ReportData(kpis: [
    Kpi(t('מוקפאים'), '${f.length}', tone: Tone.info),
    Kpi(t('חיוב חודשי מושהה'), money(_sum(f.map((x) => x.monthlyAmount ?? 0)))),
  ], sections: [
    ReportSection(
        t('מוקפאים עכשיו'),
        [
          for (final x in f)
            ReportRow(_name(s, x.customerId),
                subtitle: t('{0} · נוצלו {1} ימים', [_plan(s, x.planId), x.freezeDaysUsed]),
                value: x.frozenUntil == null ? '—' : t('עד {0}', [fmtDate(x.frozenUntil!)])),
        ],
        empty: t('אין מנויים מוקפאים')),
  ]);
}

// ------------------------------------------------------------------ links
ReportData linksReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final list = s.links.where((l) => _inRange(l.createdAt, r)).toList();
  int reached(LinkStage st) => list
      .where((l) => l.timeline.containsKey(st) || (l.stage.index >= st.index && l.stage != LinkStage.failed))
      .length;
  final paid = reached(LinkStage.paid);
  final rate = list.isEmpty ? 0 : (paid / list.length * 100).round();
  return ReportData(kpis: [
    Kpi(t('נשלחו'), '${list.length}'),
    Kpi(t('שילמו'), '$paid', tone: Tone.ok),
    Kpi(t('המרה'), '$rate%', tone: Tone.info),
    Kpi(t('נכשלו'), '${list.where((l) => l.stage == LinkStage.failed).length}', tone: Tone.bad),
  ], sections: [
    ReportSection(t('משפך'), [
      for (final st in [LinkStage.sent, LinkStage.opened, LinkStage.details, LinkStage.signed, LinkStage.paid])
        ReportRow(st.label,
            value: '${reached(st)}', tag: list.isEmpty ? null : '${(reached(st) / list.length * 100).round()}%'),
    ]),
    ReportSection(t('לינקים'), [
      for (final l in list)
        ReportRow(l.sentTo,
            subtitle: '${fmtDate(l.createdAt)}${l.amount != null ? ' · ${money(l.amount!)}' : ''}',
            tag: l.stage.label,
            tone: switch (l.stage) {
              LinkStage.paid => Tone.ok,
              LinkStage.failed => Tone.bad,
              LinkStage.sent => Tone.plain,
              _ => Tone.warn,
            }),
    ]),
  ]);
}

List<ReportDef> get allReports => [
      ReportDef(
          'summary', ReportGroup.overview, t('סיכום העסק'), t('כל הפעילות במבט אחד, מול התקופה הקודמת'), summaryReport,
          usesPeriod: true, headline: (s) => summaryReport(s, Period.month).kpis.first.value),
      ReportDef('accountant', ReportGroup.accounting, t('חבילה לרואה חשבון'),
          t('מע״מ, יומן מסמכים, זיכויים, שיקים ובדיקות לפני הגשה'), accountantReport,
          usesPeriod: true,
          periods: const [Period.month, Period.lastMonth],
          headline: (s) => accountantReport(s, Period.lastMonth).kpis[3].value),
      ReportDef('daily', ReportGroup.accounting, t('סגירת קופה יומית'), t('מה נכנס היום ובאיזה אמצעי, לספירת הקופה'),
          dailyReport,
          usesPeriod: true,
          periods: const [Period.today, Period.week],
          headline: (s) => dailyReport(s, Period.today).kpis.first.value),
      ReportDef('revenue', ReportGroup.money, t('הכנסות'), t('נגבה לפי תקופה, אמצעי תשלום ומקור'), revenueReport,
          usesPeriod: true, headline: (s) => revenueReport(s, Period.month).kpis.first.value),
      ReportDef('forecast', ReportGroup.money, t('צפי ל-30 יום'), t('חיובים, גבייה ידנית ושיקים שצפויים להיכנס'),
          forecastReport,
          headline: (s) => forecastReport(s, Period.month).kpis.first.value),
      ReportDef('cheques', ReportGroup.money, t('שיקים לפירעון'), t('שיקים דחויים לפי תאריך'), chequesReport,
          headline: (s) => chequesReport(s, Period.month).kpis[1].value),
      ReportDef(
          'deposits', ReportGroup.money, t('חודש אחרון ששולם מראש'), t('כספים שמוחזקים עד סוף מנוי'), depositsReport,
          headline: (s) => depositsReport(s, Period.month).kpis[1].value),
      ReportDef('manual', ReportGroup.collection, t('גבייה ידנית חודשית'),
          t('ממי צריך לגבות במזומן / שיק / העברה החודש'), manualMonthlyReport,
          usesPeriod: true,
          periods: const [Period.month, Period.lastMonth],
          headline: (s) => manualMonthlyReport(s, Period.month).kpis[2].value),
      ReportDef('debts', ReportGroup.collection, t('חובות ופיגורים'), t('מי חייב, כמה ימים ומי חסום'), debtsReport,
          headline: (s) => debtsReport(s, Period.month).kpis.first.value),
      ReportDef('failed', ReportGroup.collection, t('חיובים שנכשלו'), t('כרטיסים שנדחו ומה לעשות'), failedReport,
          headline: (s) => failedReport(s, Period.month).kpis.first.value),
      ReportDef(
          'active', ReportGroup.members, t('מנויים פעילים'), t('כמה בכל מסלול והכנסה חודשית חוזרת'), activeByPlanReport,
          headline: (s) => activeByPlanReport(s, Period.month).kpis.first.value),
      ReportDef('expiring', ReportGroup.members, t('מסתיימים וחידושים'), t('מנויים שנגמרים ב-30 יום וביטולים'),
          expiringReport,
          headline: (s) => expiringReport(s, Period.month).kpis.first.value),
      ReportDef('joins', ReportGroup.members, t('הצטרפויות וביטולים'), t('גידול, ביטולים ואחוז נטישה'), joinsReport,
          usesPeriod: true, headline: (s) => '+${joinsReport(s, Period.month).kpis.first.value}'),
      ReportDef('frozen', ReportGroup.members, t('מוקפאים'), t('מי מוקפא ועד מתי'), frozenReport,
          headline: (s) => frozenReport(s, Period.month).kpis.first.value),
      ReportDef('links', ReportGroup.links, t('לינקים והמרה'), t('כמה נפתחו, חתמו ושילמו'), linksReport,
          usesPeriod: true, headline: (s) => linksReport(s, Period.month).kpis[2].value),
    ];
