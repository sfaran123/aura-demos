import 'package:flutter/material.dart';

import '../domain/help.dart';
import '../domain/l10n.dart';
import 'guide_screen.dart';
import 'theme.dart';

/// The "?" in the app bar of every screen.
class HelpButton extends StatelessWidget {
  const HelpButton(this.content, {super.key});
  HelpButton.topic(HelpTopic topic, {super.key}) : content = helpFor(topic);
  final HelpContent content;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('help'),
        tooltip: t('מה המסך הזה נותן?'),
        icon: const Icon(Icons.help_outline),
        onPressed: () => showHelp(context, content),
      );
}

Future<void> showHelp(BuildContext context, HelpContent c) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Aura.goldBg, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.lightbulb_outline, color: Aura.gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(c.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
            ]),
            if (c.why.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t('למה זה עוזר'), style: const TextStyle(fontSize: 13, color: Aura.muted)),
              const SizedBox(height: 4),
              Text(c.why, style: const TextStyle(fontSize: 15.5, height: 1.45)),
            ],
            if (c.gives.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t('מה זה נותן לך'), style: const TextStyle(fontSize: 13, color: Aura.muted)),
              const SizedBox(height: 6),
              for (final g in c.gives)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle, size: 18, color: Aura.ok),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g, style: const TextStyle(fontSize: 15, height: 1.35))),
                  ]),
                ),
            ],
            TextButton.icon(
              key: const Key('helpGuide'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen()));
              },
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(t('למדריך המלא')),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('helpClose'),
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('הבנתי')),
              ),
            ),
          ]),
        ),
      ),
    );
