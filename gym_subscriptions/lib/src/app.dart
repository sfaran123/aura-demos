import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/gym_store.dart';
import 'ui/collect_screen.dart';
import 'ui/home_screen.dart';
import 'ui/members_screen.dart';
import 'ui/plans_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

/// Standalone app. Inside the existing AURA app, wrap [GymModule] with your
/// own MaterialApp/route instead.
class AuraGymApp extends StatelessWidget {
  const AuraGymApp({super.key, required this.store});
  final GymStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA Gym',
      debugShowCheckedModeBanner: false,
      theme: auraTheme(),
      locale: const Locale('he'),
      supportedLocales: const [Locale('he'), Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: GymModule(store: store),
    );
  }
}

/// The whole gym module: one widget to push from the AURA app. It has its own
/// navigator, so every screen and sheet inside it can reach the store.
class GymModule extends StatefulWidget {
  const GymModule({super.key, required this.store});
  final GymStore store;

  @override
  State<GymModule> createState() => _GymModuleState();
}

class _GymModuleState extends State<GymModule> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => StoreScope(
        store: widget.store,
        child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _nav.currentState?.maybePop(),
          child: Navigator(
            key: _nav,
            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _Shell()),
          ),
        ),
      );
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final toCollect = store.toCollect.length;
    final pages = [
      HomeScreen(goTo: (i) => setState(() => tab = i)),
      const MembersScreen(),
      const CollectScreen(),
      const PlansScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(key: Key('navHome'), icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ראשי'),
          const NavigationDestination(key: Key('navMembers'), icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'מנויים'),
          NavigationDestination(
            key: const Key('navCollect'),
            icon: Badge(isLabelVisible: toCollect > 0, label: Text('$toCollect'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: const Icon(Icons.receipt_long),
            label: 'לגבייה',
          ),
          const NavigationDestination(key: Key('navPlans'), icon: Icon(Icons.view_list_outlined), selectedIcon: Icon(Icons.view_list), label: 'מסלולים'),
          const NavigationDestination(key: Key('navSettings'), icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'הגדרות'),
        ],
      ),
    );
  }
}
