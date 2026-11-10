// Reports for the gym owner. Each report is computed from the store into a
// neutral structure (KPIs + sections of rows) that one screen renders.

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'gym_store.dart';

enum Period { today, week, month, lastMonth }

extension PeriodLabel on Period {
  String get label => switch (this) {
        Period.today => 'היום',
        Period.week => '7 ימים',
        Period.month => 'החודש',
        Period.lastMonth => 'חודש קודם',
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
  const Kpi(this.label, this.value, {this.tone = Tone.plain});
  final String label;
  final String value;
  final Tone tone;
}

class ReportRow {
  const ReportRow(this.title, {this.subtitle, this.value, this.tag, this.tone = Tone.plain});
  final String title;
  final String? subtitle;
  final String? value;
  final String? tag;
  final Tone tone;
}

class ReportSection {
  const ReportSection(this.title, this.rows, {this.empty = 'אין נתונים'});
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

enum ReportGroup { money, collection, members, links }

extension ReportGroupLabel on ReportGroup {
  String get label => switch (this) {
        ReportGroup.money => 'כספים',
        ReportGroup.collection => 'גבייה וחובות',
        ReportGroup.members => 'מנויים',
        ReportGroup.links => 'לינקים',
      };
}

/// One report in the reports hub.
class ReportDef {
  const ReportDef(this.id, this.group, this.title, this.subtitle, this.build, {this.usesPeriod = false, this.headline});
  final String id;
  final ReportGroup group;
  final String title;
  final String subtitle;
  final bool usesPeriod;
  final ReportData Function(GymStore s, Period p) build;

  /// The number shown on the report's card in the hub.
  final String Function(GymStore s)? headline;
}

bool _inRange(DateTime d, (DateTime, DateTime) r) => !d.isBefore(r.$1) && d.isBefore(r.$2);
double _sum(Iterable<double> v) => round2(v.fold(0.0, (a, b) => a + b));
String _name(GymStore s, String customerId) => s.customer(customerId)?.name ?? '—';
String _plan(GymStore s, String planId) => s.plan(planId)?.name ?? '—';

String _receiptKind(ReceiptKind k) => switch (k) {
      ReceiptKind.subscription => 'מנויים חדשים',
      ReceiptKind.collection => 'גבייה חודשית',
      ReceiptKind.quickPay => 'תשלום מהיר',
      ReceiptKind.link => 'תשלום בלינק',
    };

// ------------------------------------------------------------------ money
ReportData revenueReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final list = s.receipts.where((x) => _inRange(x.date, r)).toList()..sort((a, b) => b.date.compareTo(a.date));
  final total = _sum(list.map((x) => x.collectedNow));
  final byMethod = <PayMethod, double>{};
  final byKind = <ReceiptKind, double>{};
  for (final x in list) {
    for (final l in x.lines) {
      if (l.method.isDeferred) continue;
      byMethod[l.method] = round2((byMethod[l.method] ?? 0) + l.amount);
    }
    byKind[x.kind] = round2((byKind[x.kind] ?? 0) + x.collectedNow);
  }
  return ReportData(kpis: [
    Kpi('נגבה', money(total), tone: Tone.ok),
    Kpi('קבלות', '${list.length}'),
    Kpi('ממוצע לקבלה', money(list.isEmpty ? 0 : total / list.length)),
  ], sections: [
    ReportSection('לפי אמצעי תשלום', [
      for (final e in byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(e.key.label, value: money(e.value), tag: total == 0 ? null : '${(e.value / total * 100).round()}%'),
    ]),
    ReportSection('לפי מקור', [
      for (final e in byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        ReportRow(_receiptKind(e.key), value: money(e.value)),
    ]),
    ReportSection('קבלות', [
      for (final x in list)
        ReportRow(x.customerName,
            subtitle: '${fmtDate(x.date)} · ${x.description} · ${x.lines.map((l) => l.method.label).join(' + ')}',
            value: money(x.total),
            tag: '${x.number}'),
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
    Kpi('צפוי ב-30 יום', money(auto + manual + chq), tone: Tone.info),
    Kpi('חיוב אוטומטי', money(auto)),
    Kpi('גבייה ידנית', money(manual), tone: manual > 0 ? Tone.warn : Tone.plain),
    Kpi('שיקים', money(chq)),
  ], sections: [
    ReportSection('חיובים חודשיים', [
      for (final c in due)
        ReportRow(_name(s, c.customerId),
            subtitle: '${fmtDate(c.dueDate)} · ${c.manual ? 'גבייה ידנית' : 'אשראי / הוראת קבע'}',
            value: money(c.amount),
            tone: c.manual ? Tone.warn : Tone.plain),
    ]),
    ReportSection('שיקים לפירעון', [
      for (final c in cheques) ReportRow(c.$2, subtitle: fmtDate(c.$1), value: money(c.$3)),
    ]),
  ], note: 'לא כולל מנויים חדשים ותשלומים מהירים שעוד לא בוצעו.');
}

/// (date, customer, amount) for every post-dated cheque, from receipts.
List<(DateTime, String, double)> _chequeSchedule(GymStore s) {
  final out = <(DateTime, String, double)>[];
  for (final r in s.receipts) {
    for (final l in r.lines.where((l) => l.method == PayMethod.cheque)) {
      final each = round2(l.amount / l.cheques);
      for (var i = 0; i < l.cheques; i++) {
        out.add((addMonths(dateOnly(r.date), i), r.customerName, each));
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
    Kpi('שיקים לפירעון', '${future.length}'),
    Kpi('סכום עתידי', money(_sum(future.map((c) => c.$3))), tone: Tone.info),
    Kpi('כבר נפרעו', money(_sum(deposited.map((c) => c.$3)))),
  ], sections: [
    ReportSection('לפירעון', [
      for (final c in future)
        ReportRow(c.$2,
            subtitle: fmtDate(c.$1),
            value: money(c.$3),
            tag: c.$1.difference(s.today).inDays <= 7 ? 'השבוע' : null,
            tone: c.$1.difference(s.today).inDays <= 7 ? Tone.warn : Tone.plain),
    ]),
    ReportSection('נפרעו', [for (final c in deposited) ReportRow(c.$2, subtitle: fmtDate(c.$1), value: money(c.$3))]),
  ]);
}

ReportData depositsReport(GymStore s, Period _) {
  final subs = s.subscriptions.where((x) => x.prepaidAmount > 0).toList();
  final covered = s.charges.where((c) => c.status == ChargeStatus.covered).toList();
  return ReportData(kpis: [
    Kpi('חודשים ששולמו מראש', '${subs.length}'),
    Kpi('סכום מוחזק', money(_sum(subs.map((x) => x.prepaidAmount))), tone: Tone.info),
  ], sections: [
    ReportSection('מנויים עם חודש אחרון משולם', [
      for (final x in subs)
        ReportRow(_name(s, x.customerId),
            subtitle: '${_plan(s, x.planId)} · הצטרף ${fmtDate(x.joinedAt)}', value: money(x.prepaidAmount)),
    ]),
    ReportSection('חודשים אחרונים שכוסו מהתשלום מראש', [
      for (final c in covered)
        ReportRow(_name(s, c.customerId), subtitle: fmtDate(c.dueDate), value: money(c.amount), tag: 'לא חויב'),
    ]),
  ], note: 'בביטול מנוי כזה צריך הודעה חודש מראש, והחודש האחרון לא מחויב כי כבר שולם.');
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
    Kpi('לגבות בחודש', money(expected)),
    Kpi('נגבה', money(_sum(paid.map((c) => c.amount))), tone: Tone.ok),
    Kpi('נשאר', money(_sum(open.map((c) => c.amount))), tone: open.isEmpty ? Tone.ok : Tone.warn),
    Kpi('לקוחות', '${list.map((c) => c.customerId).toSet().length}'),
  ], sections: [
    ReportSection(
        'עוד לא שילמו',
        [
          for (final c in open)
            ReportRow(_name(s, c.customerId),
                subtitle: '${sub(c)} · מועד ${fmtDate(c.dueDate)}',
                value: money(c.amount),
                tag: c.daysOverdue(s.today) > 0 ? 'באיחור ${c.daysOverdue(s.today)} ימים' : 'ב-${fmtDate(c.dueDate)}',
                tone: c.daysOverdue(s.today) > 0 ? Tone.bad : Tone.info),
        ],
        empty: 'כולם שילמו'),
    ReportSection('שילמו', [
      for (final c in paid)
        ReportRow(_name(s, c.customerId),
            subtitle: '${sub(c)} · שולם ${c.paidAt == null ? '' : fmtDate(c.paidAt!)}',
            value: money(c.amount),
            tag: c.paidWith?.label,
            tone: Tone.ok),
    ]),
  ], note: 'מנויים חודשיים שמשלמים בעצמם (מזומן, שיק או העברה) ולא בחיוב אוטומטי.');
}

ReportData debtsReport(GymStore s, Period _) {
  final open = s.charges.where((c) => c.isOpen() && c.daysOverdue(s.today) > 0).toList()
    ..sort((a, b) => b.daysOverdue(s.today).compareTo(a.daysOverdue(s.today)));
  double bucket(int from, int to) =>
      _sum(open.where((c) => c.daysOverdue(s.today) >= from && c.daysOverdue(s.today) <= to).map((c) => c.amount));
  return ReportData(kpis: [
    Kpi('חוב פתוח', money(_sum(open.map((c) => c.amount))), tone: open.isEmpty ? Tone.ok : Tone.bad),
    Kpi('1–7 ימים', money(bucket(1, 7))),
    Kpi('8–30 ימים', money(bucket(8, 30)), tone: Tone.warn),
    Kpi('מעל 30', money(bucket(31, 100000)), tone: Tone.bad),
  ], sections: [
    ReportSection(
        'חייבים',
        [
          for (final c in open)
            ReportRow(_name(s, c.customerId),
                subtitle:
                    '${c.manual ? 'גבייה ידנית' : 'אשראי נכשל'} · מועד ${fmtDate(c.dueDate)} · ${c.reminders} תזכורות',
                value: money(c.amount),
                tag: s.entryBlocked(c.customerId) ? 'כניסה חסומה' : '${c.daysOverdue(s.today)} ימים',
                tone: s.entryBlocked(c.customerId) ? Tone.bad : Tone.warn),
        ],
        empty: 'אין חובות'),
  ]);
}

ReportData failedReport(GymStore s, Period _) {
  final f = s.charges.where((c) => c.status == ChargeStatus.failed).toList();
  return ReportData(
      kpis: [
        Kpi('חיובים שנכשלו', '${f.length}', tone: f.isEmpty ? Tone.ok : Tone.bad),
        Kpi('סכום', money(_sum(f.map((c) => c.amount)))),
      ],
      sections: [
        ReportSection(
            'לטיפול',
            [
              for (final c in f)
                ReportRow(_name(s, c.customerId),
                    subtitle:
                        '${fmtDate(c.dueDate)} · ${c.attempts} ניסיונות · כרטיס ${s.customer(c.customerId)?.savedCardLast4 ?? '—'}',
                    value: money(c.amount),
                    tag: 'לשלוח לינק לעדכון כרטיס',
                    tone: Tone.bad),
            ],
            empty: 'אין חיובים שנכשלו'),
      ],
      note:
          'ניסיונות חוזרים אוטומטיים לפי ההגדרות: ${s.settings.retryDays.take(s.settings.retryAttempts).map((d) => 'יום $d').join(', ')}.');
}

// ------------------------------------------------------------------ members
ReportData activeByPlanReport(GymStore s, Period _) {
  final live = s.subscriptions.where((x) => x.status == SubStatus.active || x.status == SubStatus.frozen).toList();
  final rows = <ReportRow>[];
  var mrr = 0.0;
  for (final p in s.plans) {
    final subs = live.where((x) => x.planId == p.id).toList();
    if (subs.isEmpty) continue;
    final monthly = _sum(subs.map((x) => x.monthlyAmount ?? (p.kind == PlanKind.term ? p.price / p.months : 0)));
    mrr += monthly;
    rows.add(ReportRow(p.name, subtitle: '${p.kind.label} · ${money(monthly)} בחודש', value: '${subs.length}'));
  }
  rows.sort((a, b) => int.parse(b.value!).compareTo(int.parse(a.value!)));
  return ReportData(kpis: [
    Kpi('מנויים פעילים', '${live.length}', tone: Tone.ok),
    Kpi('הכנסה חודשית חוזרת', money(mrr), tone: Tone.info),
    Kpi('ממוצע למנוי', money(live.isEmpty ? 0 : mrr / live.length)),
  ], sections: [
    ReportSection('לפי מסלול', rows)
  ], note: 'במסלולי תקופה ההכנסה מחולקת לפי מספר החודשים.');
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
    Kpi('מסתיימים ב-30 יום', '${list.length}', tone: list.isEmpty ? Tone.ok : Tone.warn),
    Kpi('בתהליך ביטול', '${cancelling.length}'),
  ], sections: [
    ReportSection('להציע חידוש', [
      for (final x in list)
        ReportRow(_name(s, x.customerId),
            subtitle: '${_plan(s, x.planId)} · ${s.customer(x.customerId)?.phone ?? ''}',
            value: fmtDate(x.end!),
            tag: '${x.end!.difference(s.today).inDays} ימים',
            tone: x.end!.difference(s.today).inDays <= 7 ? Tone.bad : Tone.warn),
    ]),
    ReportSection('ביטולים שייכנסו לתוקף', [
      for (final x in cancelling)
        ReportRow(_name(s, x.customerId), subtitle: _plan(s, x.planId), value: fmtDate(x.cancelEffective!)),
    ]),
  ]);
}

ReportData joinsReport(GymStore s, Period p) {
  final r = p.range(s.today);
  final joins = s.subscriptions.where((x) => _inRange(x.joinedAt, r)).toList();
  final cancels = s.subscriptions.where((x) => x.cancelledAt != null && _inRange(x.cancelledAt!, r)).toList();
  final active = s.subscriptions.where((x) => x.status == SubStatus.active || x.status == SubStatus.frozen).length;
  final churn = active == 0 ? 0 : (cancels.length / active * 100);
  return ReportData(kpis: [
    Kpi('הצטרפו', '${joins.length}', tone: Tone.ok),
    Kpi('ביטלו', '${cancels.length}', tone: cancels.isEmpty ? Tone.plain : Tone.warn),
    Kpi('נטו', '${joins.length - cancels.length}'),
    Kpi('נטישה', '${churn.toStringAsFixed(1)}%'),
  ], sections: [
    ReportSection('הצטרפויות', [
      for (final x in joins)
        ReportRow(_name(s, x.customerId), subtitle: _plan(s, x.planId), value: fmtDate(x.joinedAt)),
    ]),
    ReportSection('ביטולים', [
      for (final x in cancels)
        ReportRow(_name(s, x.customerId),
            subtitle:
                '${_plan(s, x.planId)} · בתוקף עד ${x.cancelEffective == null ? '—' : fmtDate(x.cancelEffective!)}',
            value: fmtDate(x.cancelledAt!)),
    ]),
  ]);
}

ReportData frozenReport(GymStore s, Period _) {
  final f = s.subscriptions.where((x) => x.status == SubStatus.frozen).toList();
  return ReportData(kpis: [
    Kpi('מוקפאים', '${f.length}', tone: Tone.info),
    Kpi('חיוב חודשי מושהה', money(_sum(f.map((x) => x.monthlyAmount ?? 0)))),
  ], sections: [
    ReportSection(
        'מוקפאים עכשיו',
        [
          for (final x in f)
            ReportRow(_name(s, x.customerId),
                subtitle: '${_plan(s, x.planId)} · נוצלו ${x.freezeDaysUsed} ימים',
                value: x.frozenUntil == null ? '—' : 'עד ${fmtDate(x.frozenUntil!)}'),
        ],
        empty: 'אין מנויים מוקפאים'),
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
    Kpi('נשלחו', '${list.length}'),
    Kpi('שילמו', '$paid', tone: Tone.ok),
    Kpi('המרה', '$rate%', tone: Tone.info),
    Kpi('נכשלו', '${list.where((l) => l.stage == LinkStage.failed).length}', tone: Tone.bad),
  ], sections: [
    ReportSection('משפך', [
      for (final st in [LinkStage.sent, LinkStage.opened, LinkStage.details, LinkStage.signed, LinkStage.paid])
        ReportRow(st.label,
            value: '${reached(st)}', tag: list.isEmpty ? null : '${(reached(st) / list.length * 100).round()}%'),
    ]),
    ReportSection('לינקים', [
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
  ReportDef('revenue', ReportGroup.money, 'הכנסות', 'נגבה לפי תקופה, אמצעי תשלום ומקור', revenueReport,
      usesPeriod: true, headline: (s) => revenueReport(s, Period.month).kpis.first.value),
  ReportDef('forecast', ReportGroup.money, 'צפי ל-30 יום', 'חיובים, גבייה ידנית ושיקים שצפויים להיכנס', forecastReport,
      headline: (s) => forecastReport(s, Period.month).kpis.first.value),
  ReportDef('cheques', ReportGroup.money, 'שיקים לפירעון', 'שיקים דחויים לפי תאריך', chequesReport,
      headline: (s) => chequesReport(s, Period.month).kpis[1].value),
  ReportDef('deposits', ReportGroup.money, 'חודש אחרון ששולם מראש', 'כספים שמוחזקים עד סוף מנוי', depositsReport,
      headline: (s) => depositsReport(s, Period.month).kpis[1].value),
  ReportDef('manual', ReportGroup.collection, 'גבייה ידנית חודשית', 'ממי צריך לגבות במזומן / שיק / העברה החודש',
      manualMonthlyReport,
      usesPeriod: true, headline: (s) => manualMonthlyReport(s, Period.month).kpis[2].value),
  ReportDef('debts', ReportGroup.collection, 'חובות ופיגורים', 'מי חייב, כמה ימים ומי חסום', debtsReport,
      headline: (s) => debtsReport(s, Period.month).kpis.first.value),
  ReportDef('failed', ReportGroup.collection, 'חיובים שנכשלו', 'כרטיסים שנדחו ומה לעשות', failedReport,
      headline: (s) => failedReport(s, Period.month).kpis.first.value),
  ReportDef('active', ReportGroup.members, 'מנויים פעילים', 'כמה בכל מסלול והכנסה חודשית חוזרת', activeByPlanReport,
      headline: (s) => activeByPlanReport(s, Period.month).kpis.first.value),
  ReportDef('expiring', ReportGroup.members, 'מסתיימים וחידושים', 'מנויים שנגמרים ב-30 יום וביטולים', expiringReport,
      headline: (s) => expiringReport(s, Period.month).kpis.first.value),
  ReportDef('joins', ReportGroup.members, 'הצטרפויות וביטולים', 'גידול, ביטולים ואחוז נטישה', joinsReport,
      usesPeriod: true, headline: (s) => '+${joinsReport(s, Period.month).kpis.first.value}'),
  ReportDef('frozen', ReportGroup.members, 'מוקפאים', 'מי מוקפא ועד מתי', frozenReport,
      headline: (s) => frozenReport(s, Period.month).kpis.first.value),
  ReportDef('links', ReportGroup.links, 'לינקים והמרה', 'כמה נפתחו, חתמו ושילמו', linksReport,
      usesPeriod: true, headline: (s) => linksReport(s, Period.month).kpis[2].value),
];
