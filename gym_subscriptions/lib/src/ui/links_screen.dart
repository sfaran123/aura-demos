import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'links.dart';
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

PillTone stageTone(LinkStage s) => switch (s) {
      LinkStage.paid => PillTone.ok,
      LinkStage.failed => PillTone.bad,
      LinkStage.sent => PillTone.neutral,
      _ => PillTone.wait,
    };

IconData stageIcon(LinkStage s) => switch (s) {
      LinkStage.sent => Icons.send_outlined,
      LinkStage.opened => Icons.visibility_outlined,
      LinkStage.details => Icons.person_outline,
      LinkStage.signed => Icons.draw_outlined,
      LinkStage.paid => Icons.check_circle_outline,
      LinkStage.failed => Icons.error_outline,
    };

String _time(DateTime d, DateTime now) {
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return dateOnly(d) == dateOnly(now) ? hm : '${fmtDate(d)} $hm';
}

enum _LinkFilter { all, waiting, opened, signed, paid, failed }

extension on _LinkFilter {
  String get label => switch (this) {
        _LinkFilter.all => t('הכל'),
        _LinkFilter.waiting => t('ממתין לתשלום'),
        _LinkFilter.opened => t('נפתח'),
        _LinkFilter.signed => t('חתם'),
        _LinkFilter.paid => t('שולם'),
        _LinkFilter.failed => t('נכשל'),
      };

  bool matches(SignupLink l) => switch (this) {
        _LinkFilter.all => true,
        _LinkFilter.waiting => l.stage != LinkStage.paid,
        _LinkFilter.opened => l.stage == LinkStage.opened || l.stage == LinkStage.details,
        _LinkFilter.signed => l.stage == LinkStage.signed,
        _LinkFilter.paid => l.stage == LinkStage.paid,
        _LinkFilter.failed => l.stage == LinkStage.failed,
      };
}

/// Every link sent, with live status and filters.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key});
  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  _LinkFilter f = _LinkFilter.all;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = store.links.where(f.matches).toList();
    return Scaffold(
      appBar: AppBar(title: Text(t('לינקים שנשלחו'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sendLinkFab',
        backgroundColor: Aura.goldLight,
        foregroundColor: Aura.ink,
        onPressed: () => showSignupLinkSheet(context),
        icon: const Icon(Icons.send),
        label: Text(t('לינק חדש')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final x in _LinkFilter.values) ...[
              ChoiceChip(
                key: Key('linkFilter-${x.name}'),
                label: Text('${x.label} ${store.links.where(x.matches).length}'),
                selected: f == x,
                labelStyle: TextStyle(color: f == x ? Colors.white : Aura.ink),
                onSelected: (_) => setState(() => f = x),
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty) Note(t('אין לינקים בסטטוס הזה.')),
        for (final l in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: LinkTile(link: l)),
      ]),
    );
  }
}

class LinkTile extends StatelessWidget {
  const LinkTile({super.key, required this.link});
  final SignupLink link;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final plan = link.planId == null ? null : store.plan(link.planId!);
    final last = link.timeline[link.stage] ?? link.createdAt;
    return Panel(
      key: Key('link-${link.id}'),
      onTap: () => showLinkLive(context, link),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Aura.paper, borderRadius: BorderRadius.circular(19)),
          child: Icon(stageIcon(link.stage), size: 20, color: Aura.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(link.sentTo, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              [
                plan?.name ?? t('לינק הרשמה'),
                if (link.amount != null) money(link.amount!),
                _time(last, store.now),
              ].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: Aura.muted),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              Pill(link.stage.label, tone: stageTone(link.stage)),
              if (store.isSimulating(link)) Pill(t('בשידור חי'), tone: PillTone.info),
            ]),
          ]),
        ),
        const ForwardChevron(),
      ]),
    );
  }
}

Future<void> showLinkLive(BuildContext context, SignupLink link) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LinkLiveSheet(link: link),
    );

/// Live status of one link: a timeline that updates as the customer moves on.
class _LinkLiveSheet extends StatelessWidget {
  const _LinkLiveSheet({required this.link});
  final SignupLink link;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final steps = [LinkStage.sent, LinkStage.opened, LinkStage.details, LinkStage.signed, LinkStage.paid];
    final failed = link.stage == LinkStage.failed;
    final live = store.isSimulating(link);
    final plan = link.planId == null ? null : store.plan(link.planId!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(link.sentTo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                Text([plan?.name ?? t('לינק הרשמה'), if (link.amount != null) money(link.amount!)].join(' · '),
                    style: const TextStyle(color: Aura.muted)),
              ]),
            ),
            Pill(link.stage.label, tone: stageTone(link.stage)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.circle, size: 10, color: live ? Aura.ok : Aura.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(live ? t('מתעדכן בזמן אמת') : t('הסטטוס מתעדכן ברגע שהלקוח מתקדם'),
                  style: TextStyle(fontSize: 12.5, color: live ? Aura.ok : Aura.muted)),
            ),
          ]),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _Step(
              stage: steps[i],
              at: link.timeline[steps[i]],
              current: link.stage == steps[i] || (failed && steps[i] == LinkStage.paid),
              failed: failed && steps[i] == LinkStage.paid,
              last: i == steps.length - 1,
              now: store.now,
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: Aura.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: Aura.line)),
            child: Row(children: [
              Expanded(
                  child: Directionality(
                      textDirection: TextDirection.ltr, child: Text(link.url, overflow: TextOverflow.ellipsis))),
              IconButton(
                tooltip: t('העתקה'),
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'https://${link.url}'));
                  showDone(context, t('הלינק הועתק'));
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (link.stage != LinkStage.paid) ...[
            FilledButton.icon(
              key: const Key('simulateLink'),
              onPressed: live ? null : () => store.simulateLink(link),
              icon: const Icon(Icons.play_arrow),
              label: Text(live ? t('הלקוח מתקדם…') : t('הדגמה חיה: הלקוח ממלא ומשלם')),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    openCustomerPreview(context, link);
                  },
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: Text(t('לפתוח כלקוח')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDone(context, t('תזכורת נשלחה ל{0}', [link.sentTo])),
                  icon: const Icon(Icons.notifications_none, size: 18),
                  label: Text(t('תזכורת')),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.stage,
      required this.at,
      required this.current,
      required this.failed,
      required this.last,
      required this.now});
  final LinkStage stage;
  final DateTime? at;
  final bool current;
  final bool failed;
  final bool last;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final done = at != null && !failed;
    final color = failed ? Aura.warn : (done ? Aura.ok : Aura.line);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: done || failed ? color : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: current ? Aura.goldLight : color, width: current ? 3 : 2),
              ),
              child: Icon(failed ? Icons.close : (done ? Icons.check : stageIcon(stage)),
                  size: 14, color: done || failed ? Colors.white : Aura.muted),
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? Aura.ok : Aura.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 16),
            child: Row(children: [
              Expanded(
                child: Text(failed ? LinkStage.failed.label : stage.label,
                    style: TextStyle(
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        color: done || current || failed ? Aura.ink : Aura.muted)),
              ),
              if (at != null) Text(_time(at!, now), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}
