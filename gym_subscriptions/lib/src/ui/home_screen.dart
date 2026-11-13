import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'guide_screen.dart';
import 'help.dart';
import 'plans_screen.dart';
import 'sales_screen.dart';
import 'receipt_view.dart';

import '../domain/checkout.dart';
import '../domain/dashboard.dart';
import '../domain/models.dart';
import 'checkout/checkout_screens.dart';
import 'links.dart';
import 'links_screen.dart';
import 'loading_bar.dart';
import 'auth_screens.dart';
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.goTo});

  /// Switches the bottom navigation tab (1 = members, 2 = to collect).
  final ValueChanged<int> goTo;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    // Signed in and synced: every number and list comes from the AURA server.
    // Otherwise (demo, tests) they are worked out from the data in the app.
    final dash = store.dashboard;
    final businessName =
        (dash != null && dash.businessName.isNotEmpty) ? dash.businessName : store.settings.businessName;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Aura.ink, borderRadius: BorderRadius.circular(10)),
            child: const Text('A', style: TextStyle(color: Aura.goldLight, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(isolate(businessName), key: const Key('homeBusinessName'), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            key: const Key('openGuide'),
            tooltip: t('מדריך למשתמש'),
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())),
          ),
          HelpButton.topic(HelpTopic.home),
        ],
      ),
      // While the data loads from the AURA server: a line along the top, over
      // the content (the screen itself never moves).
      body: Stack(children: [
        Positioned.fill(child: _homeList(context)),
        const Positioned(top: 0, left: 0, right: 0, child: SyncLoadingBar()),
      ]),
    );
  }

  /// The first load after sign-in: the dashboard's shape with quiet placeholders
  /// (the line on top shows it is loading). Never zeros that look like real
  /// numbers, and nothing to start before plans and prices are here.
  Widget _firstLoadList(BuildContext context) => ListView(
        key: const Key('homeFirstLoad'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(children: [
            _Kpi(key: const Key('kpiActive'), label: t('מנויים פעילים'), value: null),
            const SizedBox(width: 8),
            _Kpi(key: const Key('kpiRevenue'), label: t('הכנסות היום'), value: null),
            const SizedBox(width: 8),
            _Kpi(key: const Key('kpiDebt'), label: t('חוב פתוח'), value: null),
          ]),
          const SizedBox(height: 14),
          _TileRow(
              left: _Tile(
                  key: const Key('tileNewSub'),
                  primary: true,
                  icon: Icons.add,
                  title: t('מנוי חדש'),
                  sub: t('לקוח בקבלה')),
              right: _Tile(
                  key: const Key('tileQuickPay'),
                  icon: Icons.point_of_sale,
                  title: t('תשלום מהיר'),
                  sub: t('מוצרים, אימון אישי או סכום חופשי'))),
          const SizedBox(height: 10),
          _TileRow(
              left: _Tile(
                  key: const Key('tileMembers'),
                  icon: Icons.people_outline,
                  title: t('מנויים'),
                  sub: t('חיפוש לפי שם או טלפון')),
              right: _Tile(key: const Key('tileCollect'), icon: Icons.receipt_long, title: t('לגבייה'), sub: '')),
          const SizedBox(height: 10),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final w in const [0.62, 0.48, 0.55]) ...[
                Row(children: [
                  const _Skeleton(width: 32, height: 32, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FractionallySizedBox(widthFactor: w, child: const _Skeleton(height: 12)),
                      const SizedBox(height: 7),
                      FractionallySizedBox(widthFactor: w * .6, child: const _Skeleton(height: 10)),
                    ]),
                  ),
                ]),
                if (w != 0.55) const SizedBox(height: 16),
              ],
            ]),
          ),
        ],
      );

  Widget _homeList(BuildContext context) {
    final store = StoreScope.of(context);
    if (SyncScope.maybeOf(context) != null && !store.serverLoaded) return _firstLoadList(context);
    final collect = store.toCollect;
    final overdue = collect.where((c) => !c.dueDate.isAfter(store.today)).toList();
    final waiting = store.links.where((l) => l.stage != LinkStage.paid).toList();
    final expiring = store.expiringSoon;
    final dash = store.dashboard;
    final signedIn = SyncScope.maybeOf(context) != null;
    final activeMembers = dash?.activeMembers ?? store.activeCount;
    final revenueToday = dash?.revenueToday ?? store.todayRevenue;
    final openDebt = dash?.openDebt ?? store.openDebt;
    final collectSub = dash == null
        ? (collect.isEmpty
            ? t('אין תשלומים פתוחים')
            : t('{0} תשלומים · {1}', [collect.length, money(collect.fold(0.0, (a, c) => a + c.amount))]))
        : (dash.debts.isEmpty
            ? t('אין תשלומים פתוחים')
            : t('{0} תשלומים · {1}', [dash.debts.length, money(dash.openDebt)]));
    final documentsMonth = dash?.documentsMonth ??
        store.receipts.where((r) => r.date.year == store.today.year && r.date.month == store.today.month).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      const SyncBanner(),
      Row(children: [
        _Kpi(key: const Key('kpiActive'), label: t('מנויים פעילים'), value: '$activeMembers'),
        const SizedBox(width: 8),
        _Kpi(key: const Key('kpiRevenue'), label: t('הכנסות היום'), value: money(revenueToday)),
        const SizedBox(width: 8),
        _Kpi(
            key: const Key('kpiDebt'),
            label: t('חוב פתוח'),
            value: money(openDebt),
            alert: openDebt > 0,
            onTap: () => goTo(3)),
      ]),
      const SizedBox(height: 14),
      _TileRow(
          left: _Tile(
            key: const Key('tileNewSub'),
            primary: true,
            icon: Icons.add,
            title: t('מנוי חדש'),
            sub: t('לקוח בקבלה'),
            onTap: () => startCheckout(context, CheckoutFlow.subscription),
          ),
          right: _Tile(
            key: const Key('tileQuickPay'),
            icon: Icons.point_of_sale,
            title: t('תשלום מהיר'),
            sub: t('מוצרים, אימון אישי או סכום חופשי'),
            onTap: () => startCheckout(context, CheckoutFlow.quickPay),
          )),
      const SizedBox(height: 10),
      _TileRow(
          // Signed in, sign-up links are not connected to the server yet: the
          // members list takes the tile's place.
          left: signedIn
              ? _Tile(
                  key: const Key('tileMembers'),
                  icon: Icons.people_outline,
                  title: t('מנויים'),
                  sub: t('חיפוש לפי שם או טלפון'),
                  onTap: () => goTo(2),
                )
              : _Tile(
                  key: const Key('tileLink'),
                  icon: Icons.ios_share,
                  title: t('לינק הרשמה'),
                  sub: t('הלקוח בוחר מסלול ומשלם לבד'),
                  onTap: store.settings.signupLinkEnabled ? () => showSignupLinkSheet(context) : null,
                ),
          right: _Tile(
            key: const Key('tileCollect'),
            icon: Icons.receipt_long,
            title: t('לגבייה'),
            sub: collectSub,
            onTap: () => goTo(3),
          )),
      const SizedBox(height: 10),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _LinkRow(
            key: const Key('homeSales'),
            icon: Icons.receipt_outlined,
            title: t('מכירות וחשבוניות'),
            sub: t('{0} מסמכים החודש', [documentsMonth]),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
          ),
          const Divider(height: 1),
          _LinkRow(
            key: const Key('homePrices'),
            icon: Icons.sell_outlined,
            title: t('מחירון'),
            sub: t('{0} מוצרים ו-{1} מסלולים', [store.items.length, store.plans.length]),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
          ),
          const Divider(height: 1),
          _LinkRow(
            key: const Key('homePlans'),
            icon: Icons.view_list,
            title: t('מסלולי מנוי'),
            sub: t('{0} מסלולים פעילים · הגדרת מסלול חדש', [store.activePlans.length]),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
          ),
        ]),
      ),
      if (dash != null) ..._serverAlerts(context, dash),
      if (dash == null && (overdue.isNotEmpty || expiring.isNotEmpty)) ...[
        const SizedBox(height: 8),
        SectionLabel(t('דורש טיפול')),
        for (final c in overdue.take(4))
          _Alert(
            icon: Icons.warning_amber_rounded,
            tone: PillTone.bad,
            title: store.customer(c.customerId)!.name,
            text: c.manual
                ? t('גבייה ידנית · {0} · באיחור של {1} ימים', [money(c.amount), c.daysOverdue(store.today)])
                : t('חיוב באשראי נכשל · {0} · {1} ניסיונות', [money(c.amount), c.attempts]),
            onTap: () => goTo(3),
          ),
        if (overdue.length > 4)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('homeAllOverdue'),
              onPressed: () => goTo(3),
              child: Text(t('עוד {0} באיחור · לרשימת הגבייה', [overdue.length - 4])),
            ),
          ),
        for (final s in expiring.take(3))
          _Alert(
            icon: Icons.event_busy,
            tone: PillTone.info,
            title: store.customer(s.customerId)!.name,
            text: t('{0} מסתיים ב-{1} · להציע חידוש', [store.plan(s.planId)!.name, fmtDate(s.end!)]),
            onTap: () => startCheckout(context, CheckoutFlow.subscription, customer: store.customer(s.customerId)),
          ),
      ],
      // Sign-up links are not on the server yet: hidden while signed in.
      if (!signedIn && waiting.isNotEmpty) ...[
        const SizedBox(height: 8),
        SectionLabel(t('לינקים פתוחים ({0})', [waiting.length]),
            trailing: TextButton(
              key: const Key('allLinks'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinksScreen())),
              child: Text(t('כל הלינקים')),
            )),
        for (final l in waiting.take(3)) Padding(padding: const EdgeInsets.only(bottom: 8), child: LinkTile(link: l)),
      ],
      const SizedBox(height: 8),
      SectionLabel(t('תשלומים אחרונים')),
      if (dash != null)
        for (final p in dash.recentPayments) _ServerPaymentTile(payment: p),
      if (dash == null)
        for (final r in store.receipts.reversed.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              key: Key('receipt-${r.number}'),
              onTap: () => showReceiptSheet(context, r),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.customerName, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${r.description} · ${r.lines.map((l) => l.method.label).join(' + ')}',
                        style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                  ]),
                ),
                Text(money(r.total), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
    ]);
  }
}

/// The server document a payment or debt belongs to, when it is in the synced sales list.
Receipt? _receiptForSale(BuildContext context, String? saleId) {
  final id = int.tryParse(saleId ?? '');
  if (id == null) return null;
  return StoreScope.read(context).receipts.where((r) => r.reference != null && r.number == id).firstOrNull;
}

/// "Needs attention" from the server: open debts (failed charges, unpaid
/// membership invoices) and memberships ending soon.
List<Widget> _serverAlerts(BuildContext context, ServerDashboard dash) {
  if (dash.debts.isEmpty && dash.expiring.isEmpty) return const [];
  final store = StoreScope.of(context);
  final goTo = ShellTabs.of(context);
  return [
    const SizedBox(height: 8),
    SectionLabel(t('דורש טיפול')),
    for (final d in dash.debts.take(4))
      _Alert(
        key: Key('debt-${d.id}'),
        icon: Icons.warning_amber_rounded,
        tone: PillTone.bad,
        title: d.customerName.isEmpty ? t('לקוח') : d.customerName,
        text: switch (d.kind) {
          DebtKind.failedCharge =>
            t('חיוב נכשל · {0} · {1}', [money(d.amount), d.date == null ? (d.description ?? '') : fmtDate(d.date!)]),
          DebtKind.unpaidInvoice => t('חשבונית {0} לא שולמה · נותרו {1}', [d.reference ?? '', money(d.amount)]),
          DebtKind.manualDue => t('גבייה ידנית · {0} · באיחור של {1} ימים', [
              money(d.amount),
              d.date == null ? 0 : store.today.difference(DateTime(d.date!.year, d.date!.month, d.date!.day)).inDays,
            ]),
        },
        onTap: () {
          final r = _receiptForSale(context, d.saleId);
          if (r != null) {
            showReceiptSheet(context, r);
          } else {
            goTo.value = 3;
          }
        },
      ),
    if (dash.debts.length > 4)
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          key: const Key('homeAllOverdue'),
          onPressed: () => goTo.value = 3,
          child: Text(t('עוד {0} באיחור · לרשימת הגבייה', [dash.debts.length - 4])),
        ),
      ),
    for (final e in dash.expiring.take(3))
      _Alert(
        key: Key('expiring-${e.subscriptionId}'),
        icon: Icons.event_busy,
        tone: PillTone.info,
        title: e.customerName,
        text: t('{0} מסתיים ב-{1} · להציע חידוש', [e.planName, fmtDate(e.endDate)]),
        onTap: () => startCheckout(context, CheckoutFlow.subscription,
            customer: e.customerId == null ? null : store.customer(e.customerId!)),
      ),
  ];
}

/// One of the last payments taken (any staff member, as the web dashboard).
class _ServerPaymentTile extends StatelessWidget {
  const _ServerPaymentTile({required this.payment});
  final RecentPayment payment;

  static const _known = {
    'cash',
    'credit card',
    'card',
    'cheque',
    'check',
    'bank transfer',
    'bank_transfer',
    'transfer',
    // The web's bank transfer.
    'deposit',
  };

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final method = _known.contains(p.methodName.toLowerCase()) ? p.method.label : p.methodName;
    final receipt = _receiptForSale(context, p.saleId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        key: Key('payment-${p.id}'),
        onTap: receipt == null ? null : () => showReceiptSheet(context, receipt),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.customerName ?? t('לקוח מזדמן'), style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                  [
                    if (p.reference != null) p.reference!,
                    method,
                    if (p.date != null) fmtDate(p.date!),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ]),
          ),
          Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// A quiet placeholder block for a value that is still loading.
class _Skeleton extends StatelessWidget {
  const _Skeleton({this.width, required this.height, this.radius = 6});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: const Color(0xFFEFECE5), borderRadius: BorderRadius.circular(radius)),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi({super.key, required this.label, required this.value, this.alert = false, this.onTap});
  final String label;

  /// null while the first load runs: a placeholder in its place.
  final String? value;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Panel(
          onTap: onTap,
          color: alert ? Aura.warnBg : Colors.white,
          borderColor: alert ? Aura.warnBg : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: alert ? Aura.warn : Aura.muted)),
            const SizedBox(height: 2),
            if (value == null)
              // Same height as the number, so nothing moves when it arrives.
              const SizedBox(
                height: 24,
                child: Align(alignment: AlignmentDirectional.centerStart, child: _Skeleton(width: 56, height: 14)),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value!,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: alert ? Aura.warn : Aura.ink)),
              ),
          ]),
        ),
      );
}

/// Two tiles side by side with equal height; height follows the content, so
/// large system fonts never overflow.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(
      {super.key, required this.icon, required this.title, required this.sub, this.onTap, this.primary = false});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : Aura.ink;
    return Opacity(
      opacity: onTap == null ? .45 : 1,
      child: Panel(
        onTap: onTap,
        color: primary ? Aura.ink : Colors.white,
        borderColor: primary ? Aura.ink : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration:
                BoxDecoration(color: primary ? Aura.goldLight : Aura.goldBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: primary ? Aura.ink : Aura.gold),
          ),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w600)),
          Text(sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: primary ? Aura.goldLight : Aura.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert(
      {super.key, required this.icon, required this.tone, required this.title, required this.text, this.onTap});
  final IconData icon;
  final PillTone tone;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      PillTone.bad => Aura.warn,
      PillTone.wait => Aura.gold,
      PillTone.info => Aura.blue,
      _ => Aura.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(text, style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ]),
          ),
          const ForwardChevron(),
        ]),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, color: Aura.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(sub, style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            const ForwardChevron(),
          ]),
        ),
      );
}
