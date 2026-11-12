// A slim loading line under the app bar, shown while data loads from the server.
//
// Behaves like the bars of mature web and mobile apps:
//  - Quick loads never flash it: it appears only when loading takes longer than
//    [TopLoadingBar.showAfter].
//  - Once shown it stays at least [TopLoadingBar.minVisible], then fades out
//    (no flicker when loads come back to back).
//  - A soft gold comet sweeps in the reading direction (right to left in
//    Hebrew and Arabic), with a faint track and glow.
//  - With "reduce motion" on, a calm static line instead of the sweep.
//  - Screen readers hear "Loading data".

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/l10n.dart';
import 'auth_screens.dart' show SyncScope;
import 'theme.dart';

/// The loading line for the AURA server sync: active while [GymSync.syncing].
/// Nothing in the demo (no server).
class SyncLoadingBar extends StatelessWidget implements PreferredSizeWidget {
  const SyncLoadingBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(TopLoadingBar.height);

  @override
  Widget build(BuildContext context) => TopLoadingBar(active: SyncScope.maybeOf(context)?.syncing ?? false);
}

class TopLoadingBar extends StatefulWidget {
  const TopLoadingBar({
    super.key,
    required this.active,
    this.showAfter = const Duration(milliseconds: 180),
    this.minVisible = const Duration(milliseconds: 600),
  });

  final bool active;
  final Duration showAfter;
  final Duration minVisible;

  static const double height = 3;

  @override
  State<TopLoadingBar> createState() => _TopLoadingBarState();
}

class _TopLoadingBarState extends State<TopLoadingBar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  Timer? _showTimer, _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleShow();
  }

  @override
  void didUpdateWidget(TopLoadingBar old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    widget.active ? _scheduleShow() : _scheduleHide();
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    if (_visible) return; // still on screen from the last load: just keep going
    _showTimer?.cancel();
    _showTimer = Timer(widget.showAfter, () {
      if (!mounted) return;
      setState(() => _visible = true);
      _sweep.repeat();
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel(); // finished before it was worth showing
    if (!_visible) return;
    // Time on screen, by the sweep's own ticker (frame time, like the animation).
    final shown = _sweep.lastElapsedDuration ?? Duration.zero;
    final wait = widget.minVisible - shown;
    _hideTimer?.cancel();
    if (wait <= Duration.zero) {
      setState(() => _visible = false);
    } else {
      _hideTimer = Timer(wait, () {
        if (mounted && !widget.active) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      height: TopLoadingBar.height,
      width: double.infinity,
      child: AnimatedOpacity(
        key: const Key('topLoadingBar'),
        opacity: _visible ? 1 : 0,
        duration: Duration(milliseconds: _visible ? 160 : 320),
        curve: Curves.easeOut,
        // Faded out: the sweep stops (no frames while idle).
        onEnd: () {
          if (!_visible) setState(_sweep.stop);
        },
        child: !_visible && !_sweep.isAnimating
            ? const SizedBox.shrink()
            : Semantics(
                label: t('טוען נתונים'),
                liveRegion: true,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: reduceMotion ? _StaticLinePainter() : _SweepPainter(_sweep, rtl: rtl),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A faint track with two gold comets: a long one and a short, fainter one
/// following half a cycle behind, both easing in and out.
class _SweepPainter extends CustomPainter {
  _SweepPainter(this.anim, {required this.rtl}) : super(repaint: anim);
  final Animation<double> anim;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    // The glow stays inside the line's own height (never over the content below).
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
      Paint()..color = Aura.gold.withValues(alpha: 0.10),
    );
    _comet(canvas, size, anim.value % 1, length: 0.42, strength: 1);
    _comet(canvas, size, (anim.value + 0.55) % 1, length: 0.18, strength: 0.55);
  }

  void _comet(Canvas canvas, Size size, double t, {required double length, required double strength}) {
    final w = size.width, h = size.height;
    final seg = w * length;
    // Eased travel from fully off one side to fully off the other.
    final eased = Curves.easeInOutCubic.transform(t);
    var left = -seg + (w + seg) * eased;
    if (rtl) left = w - left - seg;
    final rect = Rect.fromLTWH(left, 0, seg, h);
    // The head is bright gold, the tail fades out behind it.
    final colors = [
      Aura.goldLight.withValues(alpha: 0),
      Aura.gold.withValues(alpha: 0.85 * strength),
      Aura.goldLight.withValues(alpha: strength),
      Aura.goldLight.withValues(alpha: 0),
    ];
    final stops = const [0.0, 0.55, 0.9, 1.0];
    final shader = LinearGradient(
      begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
      end: rtl ? Alignment.centerLeft : Alignment.centerRight,
      colors: colors,
      stops: stops,
    ).createShader(rect);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
    // A soft glow under the head.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, h)),
    );
    canvas.drawRRect(rr, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.rtl != rtl || old.anim != anim;
}

/// Reduce motion: a still, softly graded line.
class _StaticLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()
        ..shader = LinearGradient(colors: [
          Aura.gold.withValues(alpha: 0.35),
          Aura.goldLight.withValues(alpha: 0.9),
          Aura.gold.withValues(alpha: 0.35),
        ]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_StaticLinePainter old) => false;
}
