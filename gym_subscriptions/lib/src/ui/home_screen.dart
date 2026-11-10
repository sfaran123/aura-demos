import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import 'checkout/checkout_screens.dart';
import 'links.dart';
import 'links_screen.dart';
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
    final collect = store.toCollect;
    final overdue = collect.where((c) => !c.dueDate.isAfter(store.today)).toList();
    final waiting = store.links.where((l) => l.stage != LinkStage.paid).toList();
    final expiring = store.expiringSoon;

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
          Text(store.settings.businessName),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Row(children: [
          _Kpi(label: t('מנויים פעילים'), value: '${store.activeCount}'),
          const SizedBox(width: 8),
          _Kpi(label: t('הכנסות היום'), value: money(store.todayRevenue)),
          const SizedBox(width: 8),
          _Kpi(label: t('חוב פתוח'), value: money(store.openDebt), alert: store.openDebt > 0, onTap: () => goTo(2)),
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
            left: _Tile(
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
              sub: collect.isEmpty
                  ? t('אין תשלומים פתוחים')
                  : t('{0} תשלומים · {1}', [collect.length, money(collect.fold(0.0, (a, c) => a + c.amount))]),
              onTap: () => goTo(2),
            )),
        if (overdue.isNotEmpty || expiring.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionLabel(t('דורש טיפול')),
          for (final c in overdue)
            _Alert(
              icon: Icons.warning_amber_rounded,
              tone: PillTone.bad,
              title: store.customer(c.customerId)!.name,
              text: c.manual
                  ? t('גבייה ידנית · {0} · באיחור של {1} ימים', [money(c.amount), c.daysOverdue(store.today)])
                  : t('חיוב באשראי נכשל · {0} · {1} ניסיונות', [money(c.amount), c.attempts]),
              onTap: () => goTo(2),
            ),
          for (final s in expiring)
            _Alert(
              icon: Icons.event_busy,
              tone: PillTone.info,
              title: store.customer(s.customerId)!.name,
              text: t('{0} מסתיים ב-{1} · להציע חידוש', [store.plan(s.planId)!.name, fmtDate(s.end!)]),
              onTap: () => startCheckout(context, CheckoutFlow.subscription, customer: store.customer(s.customerId)),
            ),
        ],
        if (waiting.isNotEmpty) ...[
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
        for (final r in store.receipts.reversed.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
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
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.alert = false, this.onTap});
  final String label;
  final String value;
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
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
  const _Alert({required this.icon, required this.tone, required this.title, required this.text, this.onTap});
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
