// The loading line along the top of the home screen, and the first load after
// sign-in (the app opens at once, with placeholders, never a blocking spinner).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';
import 'package:aura_gym/src/ui/loading_bar.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

void main() {
  setUp(() => L10n.lang = AppLang.en);
  firstLoadTests();

  Widget host(bool active, {bool rtl = false}) => MaterialApp(
        home: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(appBar: AppBar(title: const Text('Home'), bottom: _Bar(active))),
        ),
      );

  double opacity(WidgetTester t) => t.widget<AnimatedOpacity>(find.byKey(const Key('topLoadingBar'))).opacity;
  bool painting(WidgetTester t) =>
      find.descendant(of: find.byKey(const Key('topLoadingBar')), matching: find.byType(CustomPaint)).evaluate().isNotEmpty;

  testWidgets('a quick load never flashes the line', (t) async {
    await t.pumpWidget(host(true));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpWidget(host(false));
    await t.pump(const Duration(seconds: 1));
    expect(opacity(t), 0);
    expect(painting(t), isFalse);
  });

  testWidgets('a longer load shows it, keeps it a moment, then it fades and stops', (t) async {
    await t.pumpWidget(host(true));
    await t.pump(const Duration(milliseconds: 200));
    expect(opacity(t), 1);
    await t.pump(const Duration(milliseconds: 400));
    expect(painting(t), isTrue);
    expect(find.bySemanticsLabel('Loading data'), findsOneWidget);

    // Done at once: still shown until it has been on screen long enough.
    await t.pumpWidget(host(false));
    await t.pump(const Duration(milliseconds: 100));
    expect(opacity(t), 1);
    await t.pump(const Duration(milliseconds: 200));
    expect(opacity(t), 0);
    await t.pumpAndSettle();
    expect(painting(t), isFalse, reason: 'no frames while idle');
  });

  testWidgets('loads back to back keep one line going (no flicker)', (t) async {
    await t.pumpWidget(host(true));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpWidget(host(false));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpWidget(host(true));
    await t.pump(const Duration(milliseconds: 600));
    expect(opacity(t), 1);
    await t.pumpWidget(host(false));
    await t.pumpAndSettle();
    expect(opacity(t), 0);
  });

  testWidgets('right to left and reduce motion draw without errors', (t) async {
    await t.pumpWidget(host(true, rtl: true));
    await t.pump(const Duration(milliseconds: 900));
    expect(painting(t), isTrue);
    await t.pumpWidget(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: host(true)));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    await t.pumpWidget(host(false));
    await t.pumpAndSettle();
  });
}

class _Bar extends StatelessWidget implements PreferredSizeWidget {
  const _Bar(this.active);
  final bool active;
  @override
  Size get preferredSize => const Size.fromHeight(TopLoadingBar.height);
  @override
  Widget build(BuildContext context) => TopLoadingBar(active: active);
}

/// The first load after sign-in, held open until [release] is completed.
class _SlowApi extends FakeApi {
  final release = Completer<void>();

  @override
  Future<Object?> getJson(AuraWorkspace workspace, AuraSession session, String path,
      {Map<String, String>? query}) async {
    if (path == '/gym/members') await release.future;
    return super.getJson(workspace, session, path, query: query);
  }
}

void firstLoadTests() {
  testWidgets('first load after sign-in: the dashboard at once, placeholders and the line, then the data',
      (t) async {
    L10n.lang = AppLang.en;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final api = _SlowApi();
    api.responses.addAll(serverApi().responses);
    final store = GymStore(clock: () => today);
    await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    // Not a full-screen spinner: the app with its navigation, the dashboard's shape.
    expect(find.byKey(const Key('navHome')), findsOneWidget);
    expect(find.byKey(const Key('homeFirstLoad')), findsOneWidget);
    expect(find.text('0'), findsNothing, reason: 'no zeros that look like real numbers');
    expect(t.widget<AnimatedOpacity>(find.byKey(const Key('topLoadingBar')).first).opacity, 1);
    // Nothing can be started before plans and prices are here.
    await t.tap(find.byKey(const Key('tileNewSub')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('homeFirstLoad')), findsOneWidget);
    // Lists say they are loading instead of looking empty; Settings stays usable.
    await t.tap(find.byKey(const Key('navMembers')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading your business data…'), findsOneWidget);
    await t.tap(find.byKey(const Key('navHome')));
    await t.pump(const Duration(milliseconds: 100));

    api.release.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('homeFirstLoad')), findsNothing);
    expect(find.byKey(const Key('kpiActive')), findsOneWidget);
    expect(store.customers.any((c) => c.name == 'Dana Levi'), isTrue);
    expect(t.widget<AnimatedOpacity>(find.byKey(const Key('topLoadingBar')).first).opacity, 0);
  });
}
