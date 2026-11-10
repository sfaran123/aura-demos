import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/gym_store.dart';
import 'theme.dart';

/// Makes [GymStore] available to the widget tree and rebuilds dependants
/// when it changes.
class StoreScope extends InheritedNotifier<_StoreListenable> {
  StoreScope({super.key, required GymStore store, required super.child}) : super(notifier: _StoreListenable(store));

  static GymStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!.store;

  static GymStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!.store;
}

class _StoreListenable extends ChangeNotifier {
  _StoreListenable(this.store) {
    store.addListener(notifyListeners);
  }
  final GymStore store;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 13, color: Aura.muted, fontWeight: FontWeight.w500, letterSpacing: .2)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

enum PillTone { ok, wait, bad, info, neutral }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.neutral});
  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.ok => (Aura.okBg, Aura.ok),
      PillTone.wait => (Aura.goldBg, const Color(0xFF8A5A00)),
      PillTone.bad => (Aura.warnBg, Aura.warn),
      PillTone.info => (Aura.blueBg, Aura.blue),
      PillTone.neutral => (Aura.paper, Aura.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
    );
  }
}

PillTone toneFor(SubStatus s) => switch (s) {
      SubStatus.active => PillTone.ok,
      SubStatus.pendingPayment => PillTone.wait,
      SubStatus.frozen => PillTone.info,
      SubStatus.paymentFailed => PillTone.bad,
      SubStatus.cancelled || SubStatus.expired => PillTone.neutral,
    };

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Aura.paper, shape: BoxShape.circle),
        child: Text(name.trim().isEmpty ? '?' : name.trim().substring(0, 1),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: size * .4)),
      );
}

/// White rounded card with a hairline border.
class Panel extends StatelessWidget {
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.color,
      this.borderColor,
      this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // A Material (not a decorated box) so ListTiles and ink splashes inside
    // paint correctly.
    return Material(
      color: color ?? Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor ?? Aura.line, width: borderColor == null ? 1 : 2),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, this.selected = false, this.onTap, this.showKind = false});
  final SubscriptionPlan plan;
  final bool selected;
  final VoidCallback? onTap;
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Panel(
        onTap: onTap,
        color: selected ? Aura.goldBg : Colors.white,
        borderColor: selected ? Aura.goldLight : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(plan.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: money(plan.price), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (plan.isRecurring) const TextSpan(text: ' / חודש', style: TextStyle(fontSize: 12, color: Aura.muted)),
            ])),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (plan.badge != null) Pill(plan.badge!, tone: PillTone.wait),
            if (!plan.active) const Pill('לא פעיל', tone: PillTone.bad),
            if (showKind)
              Pill(plan.kind.label,
                  tone: switch (plan.kind) {
                    PlanKind.recurring => PillTone.ok,
                    PlanKind.term => PillTone.info,
                    PlanKind.punch => PillTone.wait,
                  }),
            for (final f in plan.features())
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration:
                    BoxDecoration(color: selected ? Colors.white : Aura.paper, borderRadius: BorderRadius.circular(8)),
                child: Text(f, style: const TextStyle(fontSize: 12, color: Aura.muted)),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// A row of single-choice chips.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow(
      {super.key,
      required this.values,
      required this.selected,
      required this.label,
      required this.onSelected,
      this.enabled});
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final bool Function(T)? enabled;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: (enabled?.call(v) ?? true) ? (_) => onSelected(v) : null,
            labelStyle: TextStyle(color: v == selected ? Colors.white : Aura.ink, fontFamily: 'Rubik'),
          ),
      ]);
}

/// Thin progress bar for the steps of a flow.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                    color: i <= step ? Aura.goldLight : Aura.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ]),
      );
}

/// Screen with a scrolling body and a fixed bottom action area.
class FlowScaffold extends StatelessWidget {
  const FlowScaffold({super.key, required this.title, required this.children, this.bottom, this.step, this.steps = 4});
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final int? step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: step == null
            ? null
            : PreferredSize(preferredSize: const Size.fromHeight(12), child: StepBar(step: step!, total: steps)),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: _gap(children)),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Aura.line))),
              child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: bottom)),
            ),
    );
  }

  static List<Widget> _gap(List<Widget> c) {
    final out = <Widget>[];
    for (var i = 0; i < c.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 12));
      out.add(c[i]);
    }
    return out;
  }
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.warn = false, this.icon});
  final String text;
  final bool warn;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: warn ? Aura.warnBg : Aura.paper, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? (warn ? Icons.error_outline : Icons.info_outline),
              size: 18, color: warn ? Aura.warn : Aura.muted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: warn ? Aura.warn : Aura.muted))),
        ]),
      );
}

/// Label / value rows inside a bordered box.
class SummaryBox extends StatelessWidget {
  const SummaryBox({super.key, required this.rows, this.total});
  final List<(String, String)> rows;
  final (String, String)? total;

  @override
  Widget build(BuildContext context) {
    Widget row(String a, String b, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          color: strong ? Aura.paper : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a,
                style: TextStyle(color: strong ? Aura.ink : Aura.muted, fontWeight: strong ? FontWeight.w700 : null)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(b,
                  textAlign: TextAlign.left,
                  style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w500, fontSize: strong ? 16 : 14)),
            ),
          ]),
        );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Aura.line)),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          row(rows[i].$1, rows[i].$2),
        ],
        if (total != null) ...[const Divider(), row(total!.$1, total!.$2, strong: true)],
      ]),
    );
  }
}

void showDone(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
