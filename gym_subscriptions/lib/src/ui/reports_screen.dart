import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/reports.dart';
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
      _ => Icons.insert_chart_outlined,
    };

/// Reports hub: every report is one tap away from here (two from anywhere).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('דוחות'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        for (final g in ReportGroup.values) ...[
          SectionLabel(g.label),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - 10) / 2;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final r in allReports.where((r) => r.group == g))
                  SizedBox(
                    width: w,
                    child: Panel(
                      key: Key('report-${r.id}'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(report: r))),
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
      ]),
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
  Period period = Period.month;

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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final r = widget.report;
    final data = r.build(store, period);
    return Scaffold(
      appBar: AppBar(
        title: Text(r.title),
        actions: [
          IconButton(
            tooltip: t('העתקה לאקסל'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data.toCsv(r.title)));
              showDone(context, t('הדוח הועתק. אפשר להדביק באקסל או בגוגל שיטס'));
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(r.subtitle, style: const TextStyle(color: Aura.muted, fontSize: 13)),
        if (r.usesPeriod) ...[
          const SizedBox(height: 10),
          ChoiceRow<Period>(
            values: r.id == 'manual' ? const [Period.month, Period.lastMonth] : Period.values,
            selected: r.id == 'manual' && period != Period.lastMonth ? Period.month : period,
            label: (p) => p.label,
            onSelected: (p) => setState(() => period = p),
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
                for (var i = 0; i < sec.rows.length; i++) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sec.rows[i].title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (sec.rows[i].subtitle != null)
                            Text(sec.rows[i].subtitle!, style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                          if (sec.rows[i].tag != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Pill(sec.rows[i].tag!, tone: _pill(sec.rows[i].tone)),
                            ),
                        ]),
                      ),
                      if (sec.rows[i].value != null) ...[
                        const SizedBox(width: 10),
                        Text(sec.rows[i].value!,
                            style: TextStyle(fontWeight: FontWeight.w700, color: _fg(sec.rows[i].tone))),
                      ],
                    ]),
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
