import 'package:flutter/material.dart';

import '../domain/help.dart';
import '../domain/l10n.dart';
import '../domain/settings.dart';
import '../state/reports.dart';
import 'help.dart';
import 'theme.dart';
import 'widgets.dart';

/// Which reports this business sees in the reports tab.
class ReportPickerScreen extends StatelessWidget {
  const ReportPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final reports = allReports;
    return Scaffold(
      appBar: AppBar(title: Text(t('בחירת דוחות')), actions: [HelpButton.topic(HelpTopic.reportPicker)]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(t('{0} מתוך {1} דוחות מוצגים', [s.enabledReports.length, reports.length]),
            style: const TextStyle(color: Aura.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            key: const Key('reportsRecommended'),
            avatar: const Icon(Icons.auto_awesome, size: 18),
            label: Text(t('מומלץ ל{0}', [s.businessType.label])),
            onPressed: () {
              s.enabledReports = s.businessType.recommendedReports;
              store.touch();
            },
          ),
          ActionChip(
            key: const Key('reportsAll'),
            label: Text(t('הכל')),
            onPressed: () {
              s.enabledReports = {for (final r in reports) r.id};
              store.touch();
            },
          ),
        ]),
        const SizedBox(height: 10),
        for (final g in ReportGroup.values) ...[
          SectionLabel(g.label),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final r in reports.where((r) => r.group == g))
                SwitchListTile(
                  key: Key('rep-${r.id}'),
                  title: Text(r.title),
                  subtitle: Text(r.subtitle, style: const TextStyle(fontSize: 12.5)),
                  value: s.enabledReports.contains(r.id),
                  onChanged: (v) {
                    s.enabledReports = {...s.enabledReports};
                    v ? s.enabledReports.add(r.id) : s.enabledReports.remove(r.id);
                    store.touch();
                  },
                ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

/// Picks the business type; offers the recommended reports for it.
Future<void> pickBusinessType(BuildContext context) async {
  final store = StoreScope.read(context);
  final s = store.settings;
  final picked = await showModalBottomSheet<BusinessType>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('סוג העסק'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final b in BusinessType.values)
          ListTile(
            key: Key('bt-${b.name}'),
            leading: Icon(businessIcon(b), color: Aura.gold),
            title: Text(b.label),
            subtitle: Text(b.hint, style: const TextStyle(fontSize: 12.5)),
            trailing: s.businessType == b ? const Icon(Icons.check, color: Aura.ok) : null,
            onTap: () => Navigator.pop(ctx, b),
          ),
      ]),
    ),
  );
  if (picked == null) return;
  s.businessType = picked;
  s.enabledReports = picked.recommendedReports;
  store.touch();
  if (context.mounted) showDone(context, t('הוגדר {0} · הדוחות עודכנו לסט המומלץ', [picked.label]));
}

IconData businessIcon(BusinessType b) => switch (b) {
      BusinessType.gym => Icons.fitness_center,
      BusinessType.studio => Icons.self_improvement,
      BusinessType.crossfit => Icons.sports_gymnastics,
      BusinessType.martialArts => Icons.sports_martial_arts,
      BusinessType.pool => Icons.pool,
      BusinessType.dance => Icons.music_note,
      BusinessType.beauty => Icons.spa_outlined,
      BusinessType.clinic => Icons.healing_outlined,
      BusinessType.classes => Icons.school_outlined,
      BusinessType.kids => Icons.child_care,
    };
