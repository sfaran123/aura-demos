import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/guide.dart';
import '../domain/l10n.dart';
import 'checkout/checkout_screens.dart' show startCheckout;
import '../domain/help.dart';
import 'help.dart';
import 'links.dart' show showSignupLinkSheet;
import 'links_screen.dart';
import 'plans_screen.dart';
import '../state/reports.dart' show allReports;
import 'report_picker.dart';
import 'reports_screen.dart' show ReportScreen;
import 'sales_screen.dart';
import 'auth_screens.dart';
import 'theme.dart';
import 'widgets.dart';

IconData _chapterIcon(GuideChapter c) => switch (c) {
      GuideChapter.start => Icons.rocket_launch_outlined,
      GuideChapter.desk => Icons.point_of_sale,
      GuideChapter.collection => Icons.payments_outlined,
      GuideChapter.members => Icons.people_outline,
      GuideChapter.reports => Icons.insert_chart_outlined,
    };

/// The user guide: search "what do you want to do?" and get the steps.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final topics = guideTopics.where((x) => x.matches(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(t('מדריך למשתמש')), actions: [HelpButton.topic(HelpTopic.guide)]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Aura.ink, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('מה רוצים לעשות?'),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('כותבים מילה אחת, לדוגמה "שיק", "הקפאה" או "קבלה", ומקבלים את הצעדים.'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('guideSearch'),
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                hintText: t('חיפוש במדריך'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (topics.isEmpty) Note(t('לא נמצא. נסו מילה אחרת, או לחצו ? בכל מסך.')),
        for (final ch in GuideChapter.values)
          if (topics.any((x) => x.chapter == ch)) ...[
            Row(children: [
              Icon(_chapterIcon(ch), size: 18, color: Aura.gold),
              const SizedBox(width: 6),
              Expanded(child: SectionLabel(ch.label)),
            ]),
            const SizedBox(height: 4),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, x) in topics.where((x) => x.chapter == ch).indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _TopicTile(topic: x, open: q.trim().length > 1),
                ],
              ]),
            ),
            const SizedBox(height: 14),
          ],
      ]),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.open});
  final GuideTopic topic;
  final bool open;

  void _report(BuildContext context, String id) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ReportScreen(report: allReports.firstWhere((r) => r.id == id))));

  void _go(BuildContext context, GuideAction a) {
    void tab(int i) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ShellTabs.of(context).value = i;
    }

    switch (a) {
      case GuideAction.accountant:
        _report(context, 'accountant');
      case GuideAction.daily:
        _report(context, 'daily');
      case GuideAction.sales:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen()));
      case GuideAction.prices:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen()));
      case GuideAction.newSub:
        startCheckout(context, CheckoutFlow.subscription);
      case GuideAction.quickPay:
        startCheckout(context, CheckoutFlow.quickPay);
      case GuideAction.link:
        if (SyncScope.maybeOf(context) != null) return showDone(context, t('תשלום בלינק עדיין לא זמין כאן.'));
        showSignupLinkSheet(context);
      case GuideAction.members:
        tab(1);
      case GuideAction.collect:
        tab(2);
      case GuideAction.reports:
        tab(3);
      case GuideAction.settings:
        tab(4);
      case GuideAction.plans:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen()));
      case GuideAction.reportPicker:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPickerScreen()));
      case GuideAction.links:
        if (SyncScope.maybeOf(context) != null) return showDone(context, t('תשלום בלינק עדיין לא זמין כאן.'));
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LinksScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = topic;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('guide-${x.id}-$open'),
        initiallyExpanded: open,
        title: Text(x.title, key: Key('guide-${x.id}'), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(x.when, style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in x.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Aura.goldBg, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Aura.ink)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s, style: const TextStyle(fontSize: 15, height: 1.4))),
              ]),
            ),
          if (x.tip != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Aura.okBg, borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Aura.ok),
                const SizedBox(width: 8),
                Expanded(child: Text(x.tip!, style: const TextStyle(fontSize: 13.5, height: 1.35))),
              ]),
            ),
          if (x.action != null)
            FilledButton.icon(
              key: Key('guideGo-${x.id}'),
              onPressed: () => _go(context, x.action!),
              icon: const Icon(Icons.arrow_forward),
              label: Text(t('קחו אותי לשם')),
            ),
        ],
      ),
    );
  }
}
