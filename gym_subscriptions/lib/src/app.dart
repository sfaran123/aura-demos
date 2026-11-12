import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain/l10n.dart';
import 'integration/tap_to_pay_service.dart';
import 'state/auth.dart';
import 'state/gym_store.dart';
import 'state/server_sync.dart';
import 'ui/auth_screens.dart';
import 'ui/collect_screen.dart';
import 'ui/home_screen.dart';
import 'ui/loading_bar.dart';
import 'ui/members_screen.dart';
import 'ui/reports_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

/// Standalone app. Inside the existing AURA app, wrap [GymModule] with your
/// own MaterialApp/route instead.
class AuraGymApp extends StatefulWidget {
  const AuraGymApp({super.key, required this.store, this.auth});
  final GymStore store;

  /// Sign-in to the AURA backend (domain + login screens). Without it (tests,
  /// demos) the app opens straight to the gym module.
  final AuthController? auth;

  @override
  State<AuraGymApp> createState() => _AuraGymAppState();
}

class _AuraGymAppState extends State<AuraGymApp> with WidgetsBindingObserver {
  AppLang _lang = L10n.lang;

  /// Signed in, the data is loaded again every few minutes and when the app comes
  /// back to the front, so a second device sees what the first one did.
  static const _refreshEvery = Duration(minutes: 5);
  Timer? _refreshTimer;

  void _refresh() {
    if (widget.auth?.stage == AuthStage.signedIn) _sync?.pull();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Loads the server data after sign-in and at start (signed in only).
  GymSync? _sync;
  AuthStage? _stage;

  void _onStore() {
    if (L10n.lang != _lang) setState(() => _lang = L10n.lang);
  }

  void _onAuth() {
    // Tap to Pay registers the device with the signed-in user's TPN / merchant code.
    final session = widget.auth!.session;
    TapToPayService.instance
      ..userTpn = session?.tapToPayTpn
      ..userMerchantCode = session?.tapToPayMerchantCode;
    final stage = widget.auth!.stage;
    final store = widget.store;
    if (stage == AuthStage.signedIn && _stage != AuthStage.signedIn) {
      // Whatever the device holds that is not this business's (demo data, another
      // business) goes before anything shows; another business's settings go too.
      final owner = GymSync.ownerKey(widget.auth!.workspace!);
      if (store.serverOwner != owner) store.clearServerData(settings: store.serverOwner != null, owner: owner);
      _sync!.pull();
    } else if (stage != AuthStage.signedIn && _stage == AuthStage.signedIn) {
      // Signed out: the business's members and documents leave the device.
      // Its settings stay for the next user of the same business.
      store.clearServerData();
    } else if (stage != AuthStage.signedIn) {
      store.posSettings = null;
    }
    _stage = stage;
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    final auth = widget.auth;
    if (auth != null) {
      _sync = GymSync(auth: auth, store: widget.store);
      auth.addListener(_onAuth);
      _onAuth();
      WidgetsBinding.instance.addObserver(this);
      _refreshTimer = Timer.periodic(_refreshEvery, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    widget.auth?.removeListener(_onAuth);
    if (widget.auth != null) WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return MaterialApp(
      title: 'AURA Gym',
      debugShowCheckedModeBanner: false,
      theme: auraTheme(_lang),
      locale: Locale(_lang.code),
      supportedLocales: const [Locale('he'), Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: widget.auth == null
          ? GymModule(store: store)
          : AuthGate(
              auth: widget.auth!,
              store: store,
              child: SyncScope(
                  sync: _sync!,
                  child:
                      FirstSyncGate(sync: _sync!, store: store, auth: widget.auth!, child: GymModule(store: store)))),
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
  final _tab = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
        store: widget.store,
        child: ShellTabs(
          tab: _tab,
          child: NavigatorPopHandler<Object?>(
            onPopWithResult: (_) => _nav.currentState?.maybePop(),
            child: Navigator(
              key: _nav,
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _Shell()),
            ),
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
  @override
  Widget build(BuildContext context) {
    final tabs = ShellTabs.of(context);
    return ValueListenableBuilder<int>(valueListenable: tabs, builder: (context, tab, _) => _build(context, tab, tabs));
  }

  Widget _build(BuildContext context, int tab, ValueNotifier<int> tabs) {
    final store = StoreScope.of(context);
    final sync = SyncScope.maybeOf(context);
    final toCollect = store.toCollect.length;
    // Signed in, before the first load arrives: lists would look empty, so
    // those tabs say they are loading (Settings stays usable).
    final firstLoad = sync != null && !store.serverLoaded;
    final pages = [
      HomeScreen(goTo: (i) => tabs.value = i),
      firstLoad ? const _FirstLoadTab() : const MembersScreen(),
      firstLoad ? const _FirstLoadTab() : const CollectScreen(),
      firstLoad ? const _FirstLoadTab() : const ReportsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      // Signed in: pulling a screen down loads the data again.
      body: sync == null
          ? IndexedStack(index: tab, children: pages)
          : RefreshIndicator(onRefresh: sync.pull, child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => tabs.value = i,
        destinations: [
          NavigationDestination(
              key: Key('navHome'), icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: t('ראשי')),
          NavigationDestination(
              key: Key('navMembers'),
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: t('מנויים')),
          NavigationDestination(
            key: const Key('navCollect'),
            icon: Badge(
                isLabelVisible: toCollect > 0,
                label: Text('$toCollect'),
                child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: const Icon(Icons.receipt_long),
            label: t('לגבייה'),
          ),
          NavigationDestination(
              key: Key('navReports'),
              icon: Icon(Icons.insert_chart_outlined),
              selectedIcon: Icon(Icons.insert_chart),
              label: t('דוחות')),
          NavigationDestination(
              key: Key('navSettings'),
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: t('הגדרות')),
        ],
      ),
    );
  }
}

/// A tab whose data is still on its way (first load after sign-in).
class _FirstLoadTab extends StatelessWidget {
  const _FirstLoadTab();

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('firstLoadTab'),
        body: SafeArea(
          child: Stack(children: [
            Center(child: Text(t('טוען את נתוני העסק…'), style: const TextStyle(color: Aura.muted))),
            const Positioned(top: 0, left: 0, right: 0, child: SyncLoadingBar()),
          ]),
        ),
      );
}
