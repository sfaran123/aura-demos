import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/help.dart';
import '../domain/models.dart';
import '../state/reports.dart';
import 'collect_screen.dart';
import 'help.dart';
import 'pdf_documents.dart' show businessNameOf, pdfFileName, reportPdf;
import 'pdf_view.dart';
import 'report_picker.dart';
import 'sales_screen.dart';
import 'auth_screens.dart';
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

IconData _icon(String id) => switch (id) {
      'revenue' => Icons.trending_up,
      'forecast' => Icons.calendar_month,
      'cheques' => Icons.edit_note,
      'deposits' => Icons.savings_outlined,
      'manual' => Icons.payments_outlined,
      'debts' => Icons.warning_amber_rounded,
      'failed' => Icons.credit_card_off_outlined,
      'active' => Icons.groups_outlined,
      'expiring' => Icons.event_busy_outlined,
      'joins' => Icons.swap_vert,
      'frozen' => Icons.ac_unit,
      'links' => Icons.link,
      'summary' => Icons.dashboard_outlined,
      'accountant' => Icons.account_balance_outlined,
      'daily' => Icons.point_of_sale,
      _ => Icons.insert_chart_outlined,
    };

/// Reports hub: every report is one tap away from here (two from anywhere).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  void _open(BuildContext context, ReportDef r) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(report: r)));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final on = store.settings.enabledReports;
    // Sign-up links are not on the server yet: their report is left out while signed in.
    final reports =
        allReports.where((r) => on.contains(r.id) && !(SyncScope.maybeOf(context) != null && r.id == 'links')).toList();
    final summary = reports.where((r) => r.id == 'summary').firstOrNull;
    final debt = store.openDebt;
    final debtors = store.toCollect.where((c) => !c.dueDate.isAfter(store.today)).map((c) => c.customerId).toSet();
    return Scaffold(
      appBar: AppBar(title: Text(t('דוחות')), actions: [
        IconButton(
          key: const Key('pickReports'),
          tooltip: t('בחירת דוחות'),
          icon: const Icon(Icons.tune),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPickerScreen())),
        ),
        HelpButton.topic(HelpTopic.reports),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        if (summary != null) _SummaryCard(report: summary, onTap: () => _open(context, summary)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('hubSales'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
              icon: const Icon(Icons.receipt_outlined, size: 18),
              label: Text(t('כל החשבוניות')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('hubPrices'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(t('מחירון')),
            ),
          ),
        ]),
        if (debt > 0) ...[
          const SizedBox(height: 10),
          Panel(
            color: Aura.warnBg,
            borderColor: Aura.warnBg,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Aura.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('חוב פתוח {0}', [money(debt)]),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Aura.warn)),
                  Text(t('{0} לקוחות · גבייה, לינק או תזכורת', [debtors.length]),
                      style: const TextStyle(fontSize: 12.5, color: Aura.ink)),
                ]),
              ),
              FilledButton(
                key: const Key('hubCollect'),
                style: FilledButton.styleFrom(backgroundColor: Aura.warn, minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectScreen())),
                child: Text(t('לגבות')),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        for (final g in ReportGroup.values.where((g) => g != ReportGroup.overview))
          if (reports.any((r) => r.group == g)) ...[
            SectionLabel(g.label),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, box) {
                final w = (box.maxWidth - 10) / 2;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final r in reports.where((r) => r.group == g))
                    SizedBox(
                      width: w,
                      child: Panel(
                        key: Key('report-${r.id}'),
                        onTap: () => _open(context, r),
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(color: Aura.goldBg, borderRadius: BorderRadius.circular(9)),
                              child: Icon(_icon(r.id), size: 18, color: Aura.gold),
                            ),
                            const Spacer(),
                            const ForwardChevron(size: 18),
                          ]),
                          const SizedBox(height: 10),
                          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                          if (r.headline != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(r.headline!(store),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                            ),
                          const SizedBox(height: 2),
                          Text(r.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Aura.muted)),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 14),
          ],
        if (reports.isEmpty) Note(t('לא נבחרו דוחות. אפשר לבחור בכפתור ההגדרות למעלה.')),
      ]),
    );
  }
}

/// The business summary at the top of the hub.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report, required this.onTap});
  final ReportDef report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = report.build(store, Period.month);
    final k = {for (final x in d.kpis) x.label: x};
    Widget stat(Kpi? x) => x == null
        ? const SizedBox()
        : Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.label, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(x.value,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          );
    final rev = d.kpis.first;
    return Material(
      key: const Key('report-summary'),
      color: Aura.ink,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.dashboard_outlined, color: Aura.goldLight, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('{0} · החודש', [report.title]),
                    style: const TextStyle(color: Aura.goldLight, fontWeight: FontWeight.w600)),
              ),
              const ForwardChevron(size: 18, color: Colors.white70),
            ]),
            const SizedBox(height: 8),
            Text(rev.value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
            if (rev.sub != null)
              Text(rev.sub!,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: rev.subTone == Tone.bad ? const Color(0xFFFF9C8A) : const Color(0xFF8FE3B0))),
            const SizedBox(height: 12),
            Row(children: [
              stat(k[t('מנויים פעילים')]),
              stat(k[t('הצטרפו')]),
              stat(k[t('אחוז גבייה')]),
              stat(k[t('חוב פתוח')]),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.report});
  final ReportDef report;
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late Period period = widget.report.periods?.first ?? Period.month;
  final Set<String> expanded = {};
  static const _rowsShown = 15;

  Color _fg(Tone t) => switch (t) {
        Tone.ok => Aura.ok,
        Tone.warn => const Color(0xFF8A5A00),
        Tone.bad => Aura.warn,
        Tone.info => Aura.blue,
        Tone.plain => Aura.ink,
      };

  PillTone _pill(Tone t) => switch (t) {
        Tone.ok => PillTone.ok,
        Tone.warn => PillTone.wait,
        Tone.bad => PillTone.bad,
        Tone.info => PillTone.info,
        Tone.plain => PillTone.neutral,
      };

  Future<void> _collect(BuildContext context, Charge c) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SingleChildScrollView(
            child: Builder(builder: (ctx) {
              StoreScope.of(ctx);
              return c.isOpen()
                  ? ChargeCard(charge: c)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Note(t('שולם. הקבלה הופקה.'), icon: Icons.check_circle_outline),
                    );
            }),
          ),
        ),
      );

  Future<void> _sendToAccountant(BuildContext context, ReportData data, String title) async {
    final store = StoreScope.read(context);
    var email = store.settings.accountantEmail;
    if (email.isEmpty) {
      final c = TextEditingController();
      final v = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('המייל של רואה החשבון')),
          content: TextField(
            key: const Key('accountantEmail'),
            controller: c,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'name@example.com'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('ביטול'))),
            FilledButton(
                key: const Key('accountantEmailSave'),
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: Text(t('שמירה'))),
          ],
        ),
      );
      if (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
        if (v != null && context.mounted) showDone(context, t('כתובת המייל לא תקינה'));
        return;
      }
      email = v;
      store.settings.accountantEmail = v;
      store.touch();
    }
    await Clipboard.setData(ClipboardData(text: data.toCsv('$title · ${period.label}')));
    if (context.mounted) {
      showDone(context, t('הדוח הועתק. בגרסה המחוברת הוא יישלח ל-{0} כקובץ אקסל', [email]));
    }
  }

  Widget _row(BuildContext context, ReportRow row) {
    final store = StoreScope.of(context);
    final charge = row.chargeId == null ? null : store.charges.where((c) => c.id == row.chargeId).firstOrNull;
    final open = charge != null && charge.isOpen();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (row.subtitle != null) Text(row.subtitle!, style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              if (row.tag != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Pill(row.tag!, tone: _pill(row.tone)),
                ),
            ]),
          ),
          if (row.value != null) ...[
            const SizedBox(width: 10),
            Text(row.value!, style: TextStyle(fontWeight: FontWeight.w700, color: _fg(row.tone))),
          ],
        ]),
        if (row.bar != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: row.bar!.clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: Aura.paper,
                color: row.tone == Tone.plain ? Aura.gold : _fg(row.tone),
              ),
            ),
          ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: Key('payRow-${charge.id}'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => _collect(context, charge),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(t('לגבות {0}', [money(charge.amount)])),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final r = widget.report;
    final data = r.build(store, period);
    final openCharges = {
      for (final sec in data.sections)
        for (final row in sec.rows)
          if (row.chargeId != null) row.chargeId!
    }.map((id) => store.charges.where((c) => c.id == id && c.isOpen()).firstOrNull).whereType<Charge>().toList();
    final openSum = round2(openCharges.fold(0.0, (a, c) => a + c.amount));
    return Scaffold(
      appBar: AppBar(
        title: Text(r.title),
        actions: [
          IconButton(
            key: const Key('reportPdf'),
            tooltip: t('PDF · הורדה / שיתוף'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () {
              final when = r.usesPeriod ? period.label : null;
              openPdf(
                context,
                title: r.title,
                fileName: pdfFileName([r.title, if (when != null) when].join(' ')),
                load: () => reportPdf(data, title: r.title, subtitle: r.subtitle, period: when, business: businessNameOf(store)),
              );
            },
          ),
          IconButton(
            tooltip: t('העתקה לאקסל'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data.toCsv(r.title)));
              showDone(context, t('הדוח הועתק. אפשר להדביק באקסל או בגוגל שיטס'));
            },
          ),
          HelpButton(r.help),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(r.subtitle, style: const TextStyle(color: Aura.muted, fontSize: 13)),
        if (r.usesPeriod) ...[
          const SizedBox(height: 10),
          ChoiceRow<Period>(
            values: r.periods ?? Period.values,
            selected: (r.periods ?? Period.values).contains(period) ? period : (r.periods ?? Period.values).first,
            label: (p) => p.label,
            onSelected: (p) => setState(() => period = p),
          ),
        ],
        if (r.id == 'accountant') ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('sendAccountant'),
            onPressed: () => _sendToAccountant(context, data, r.title),
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: Text(store.settings.accountantEmail.isEmpty
                ? t('שליחה לרואה החשבון')
                : t('שליחה ל-{0}', [store.settings.accountantEmail])),
          ),
        ],
        if (openCharges.isNotEmpty) ...[
          const SizedBox(height: 10),
          Panel(
            color: Aura.warnBg,
            borderColor: Aura.warnBg,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: Text(t('{0} פתוחים לגבייה · {1}', [openCharges.length, money(openSum)]),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Aura.warn)),
              ),
              TextButton(
                key: const Key('reportCollectAll'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectScreen())),
                child: Text(t('לגבות הכל')),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final cols = data.kpis.length >= 4 ? 2 : data.kpis.length;
          final w = (box.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in data.kpis)
              SizedBox(
                width: w,
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.label, style: const TextStyle(fontSize: 12, color: Aura.muted)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(k.value,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _fg(k.tone))),
                    ),
                    if (k.sub != null)
                      Text(k.sub!,
                          maxLines: 2,
                          style:
                              TextStyle(fontSize: 11.5, color: k.subTone == Tone.plain ? Aura.muted : _fg(k.subTone))),
                  ]),
                ),
              ),
          ]);
        }),
        for (final sec in data.sections) ...[
          const SizedBox(height: 14),
          SectionLabel(sec.title, trailing: Text('${sec.rows.length}', style: const TextStyle(color: Aura.muted))),
          const SizedBox(height: 4),
          if (sec.rows.isEmpty)
            Note(sec.empty, icon: Icons.check_circle_outline)
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < sec.rows.length && (i < _rowsShown || expanded.contains(sec.title)); i++) ...[
                  if (i > 0) const Divider(),
                  _row(context, sec.rows[i]),
                ],
                if (sec.rows.length > _rowsShown && !expanded.contains(sec.title)) ...[
                  const Divider(),
                  TextButton(
                    key: Key('more-${sec.title}'),
                    onPressed: () => setState(() => expanded.add(sec.title)),
                    child: Text(t('הצגת כל {0}', [sec.rows.length])),
                  ),
                ],
              ]),
            ),
        ],
        if (data.note != null) ...[const SizedBox(height: 14), Note(data.note!)],
      ]),
    );
  }
}
