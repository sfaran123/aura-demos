import 'package:aura_gym/src/ui/splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts its own builds' state: a new State means the app was rebuilt from scratch.
class _Counter extends StatefulWidget {
  const _Counter();
  static int created = 0;
  @override
  State<_Counter> createState() {
    created++;
    return _CounterState();
  }
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextButton(key: const Key('tap'), onPressed: () => setState(() => taps++), child: Text('taps $taps')),
          ),
        ),
      );
}

void main() {
  testWidgets('the launch screen opens into the app, which keeps its state', (t) async {
    _Counter.created = 0;
    await t.runAsync(() async {
      await t.pumpWidget(const SplashReveal(child: _Counter()));
      // Let the images decode (real async), then run the reveal.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(find.byKey(const Key('splashReveal')), findsOneWidget, reason: 'drawn as the native splash first');
    expect(find.byKey(const Key('splashLoading')), findsOneWidget, reason: 'the loading line runs under the mark');
    expect(find.text('taps 0'), findsOneWidget, reason: 'the app is already built under it');

    // Short: gone within the hold + the fade.
    // (The hold timer was started in real time, inside runAsync.)
    await t.runAsync(() => Future<void>.delayed(SplashReveal.hold + const Duration(milliseconds: 20)));
    await t.pump();
    await t.pump(SplashReveal.exit + const Duration(milliseconds: 50));
    // (Its end callback also runs in real time.)
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
    expect(find.byKey(const Key('splashReveal')), findsNothing, reason: 'gone within ${SplashReveal.hold + SplashReveal.exit}');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('splashReveal')), findsNothing, reason: 'gone after the reveal');
    await t.tap(find.byKey(const Key('tap')));
    await t.pump();
    expect(find.text('taps 1'), findsOneWidget);
    expect(_Counter.created, 1, reason: 'the app was not rebuilt from scratch when the layer went');
  });

  testWidgets('reduced motion: no animation, straight into the app', (t) async {
    await t.runAsync(() async {
      await t.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SplashReveal(child: _Counter()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(find.byKey(const Key('splashReveal')), findsNothing);
    expect(find.text('taps 0'), findsOneWidget);
  });
}
