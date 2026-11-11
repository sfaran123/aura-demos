import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/reports.dart' show Period, PeriodLabel;
import '../domain/help.dart';
import 'help.dart';
import 'plans_screen.dart';
import 'receipt_view.dart';
import 'theme.dart';
import 'widgets.dart';

String receiptKindLabel(ReceiptKind k) => switch (k) {
      ReceiptKind.subscription => t('מנויים חדשים'),
      ReceiptKind.collection => t('גבייה חודשית'),
      ReceiptKind.quickPay => t('תשלום מהיר'),
      ReceiptKind.link => t('תשלום בלינק'),
      ReceiptKind.credit => t('זיכויים'),
    };

/// Every invoice-receipt issued, newest first, with search and filters.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String q = '';
  Period period = Period.month;
  ReceiptKind? kind;
  PayMethod? method;
  int shown = 40;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final r = period.range(store.today);
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final list = store.receipts.reversed.where((x) {
      if (x.date.isBefore(r.$1) || !x.date.isBefore(r.$2)) return false;
      if (kind != null && x.kind != kind) return false;
      if (method != null && !x.lines.any((l) => l.method == method)) return false;
      if (q.trim().isEmpty) return true;
      return x.customerName.contains(q.trim()) || (digits.isNotEmpty && x.docNo.replaceAll(RegExp(r'\D'), '').contains(digits));
    }).toList();
    final total = round2(list.fold(0.0, (a, x) => a + x.total));
    // Each document's own VAT (a credit note takes its VAT back).
    final vat = round2(list.fold(0.0, (a, x) => a + (x.total < 0 ? -1 : 1) * docVat(x, store).abs()));

    Widget filter<T>(
            String key, String label, T? value, List<T> values, String Function(T) name, ValueChanged<T?> set) =>
        PopupMenuButton<T?>(
          key: Key(key),
          onSelected: set,
          itemBuilder: (_) => [
            PopupMenuItem<T?>(value: null, child: Text(t('הכל'))),
            for (final v in values) PopupMenuItem<T?>(value: v, child: Text(name(v))),
          ],
          child: Chip(
            avatar: const Icon(Icons.filter_list, size: 16),
            label: Text(value == null ? label : name(value)),
            backgroundColor: value == null ? null : Aura.goldBg,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(t('מכירות וחשבוניות')), actions: [
        HelpButton.topic(HelpTopic.sales),
        IconButton(
          tooltip: t('העתקה לאקסל'),
          icon: const Icon(Icons.copy_all_outlined),
          onPressed: () {
            String c(String v) => '"${v.replaceAll('"', '""')}"';
            final b = StringBuffer(
                [t('מספר'), t('תאריך'), t('לקוח'), t('תיאור'), t('אמצעי תשלום'), t('סכום')].map(c).join(','));
            for (final x in list) {
              b.write('\n${[
                x.docNo,
                fmtDate(x.date),
                x.customerName,
                x.description,
                x.lines.map((l) => l.method.label).join(' + '),
                x.total.toStringAsFixed(2)
              ].map(c).join(',')}');
            }
            Clipboard.setData(ClipboardData(text: b.toString()));
            showDone(context, t('הרשימה הועתקה. אפשר להדביק באקסל'));
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        TextField(
          key: const Key('salesSearch'),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('חיפוש לפי לקוח או מספר מסמך')),
          onChanged: (v) => setState(() => q = v),
        ),
        const SizedBox(height: 8),
        ChoiceRow<Period>(
            values: Period.values,
            selected: period,
            label: (p) => p.label,
            onSelected: (p) => setState(() => period = p)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          filter<ReceiptKind>(
              'salesKind', t('סוג מכירה'), kind, ReceiptKind.values, receiptKindLabel, (v) => setState(() => kind = v)),
          filter<PayMethod>('salesMethod', t('אמצעי תשלום'), method, PayMethod.values, (m) => m.label,
              (v) => setState(() => method = v)),
        ]),
        const SizedBox(height: 10),
        Panel(
          color: Aura.ink,
          borderColor: Aura.ink,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('{0} מסמכים', [list.length]), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                Text(money(total),
                    key: const Key('salesTotal'),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (vat > 0)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(t('מתוכו מע״מ'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                Text(money(vat),
                    style: const TextStyle(color: Aura.goldLight, fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
          ]),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty) Note(t('אין מסמכים בסינון הזה.')),
        if (list.isNotEmpty)
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, x) in list.take(shown).indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: Key('sale-${x.number}'),
                  onTap: () => showReceiptSheet(context, x),
                  title: Text(x.customerName, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${docLabel(x, s.docType)} ${x.docNo} · ${fmtDate(x.date)}\n${x.description} · ${x.lines.map((l) => l.method.label).join(' + ')}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  isThreeLine: true,
                  trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(x.total),
                            style: TextStyle(fontWeight: FontWeight.w700, color: x.isCredit ? Aura.warn : Aura.ink)),
                        if (x.sent.isNotEmpty) const Icon(Icons.mark_email_read_outlined, size: 16, color: Aura.ok),
                      ]),
                ),
              ],
              if (list.length > shown) ...[
                const Divider(height: 1),
                TextButton(
                  key: const Key('salesMore'),
                  onPressed: () => setState(() => shown += 60),
                  child: Text(t('עוד {0}', [list.length - shown])),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Products and services sold at the desk, plus the membership plans.
class PriceListScreen extends StatelessWidget {
  const PriceListScreen({super.key});

  Future<void> _edit(BuildContext context, [ShopItem? item]) async {
    final store = StoreScope.read(context);
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(text: item == null ? '' : _fmt(item.price));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(item == null ? t('מוצר חדש') : t('עריכת מוצר'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
              key: const Key('itemName'),
              controller: name,
              decoration: InputDecoration(labelText: t('שם המוצר או השירות'))),
          const SizedBox(height: 8),
          TextField(
            key: const Key('itemPrice'),
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: t('מחיר'), suffixText: '₪'),
          ),
          const SizedBox(height: 12),
          FilledButton(key: const Key('itemSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(t('שמירה'))),
          if (item != null)
            TextButton(
              key: const Key('itemRemove'),
              onPressed: () {
                store.removeItem(item.id);
                Navigator.pop(ctx, false);
              },
              child: Text(t('הסרה מהמחירון'), style: const TextStyle(color: Aura.warn)),
            ),
        ]),
      ),
    );
    final p = double.tryParse(price.text) ?? 0;
    if (ok == true && name.text.trim().isNotEmpty && p > 0) {
      store.saveItem(ShopItem(item?.id ?? '', name.text.trim(), p, taxRate: item?.taxRate ?? 0, taxMethod: item?.taxMethod));
      if (context.mounted) showDone(context, t('המחירון עודכן'));
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('מחירון')), actions: [HelpButton.topic(HelpTopic.prices)]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newItem'),
        heroTag: 'newItemFab',
        backgroundColor: Aura.goldLight,
        foregroundColor: Aura.ink,
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: Text(t('מוצר חדש')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        SectionLabel(t('מוצרים ושירותים בקבלה')),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, x) in store.items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                key: Key('price-${x.id}'),
                title: Text(x.name),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(x.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined, size: 18, color: Aura.muted),
                ]),
                onTap: () => _edit(context, x),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        SectionLabel(t('מסלולי מנוי'),
            trailing: TextButton(
              key: const Key('priceListPlans'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
              child: Text(t('עריכה')),
            )),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, p) in store.plans.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                title: Text(p.name),
                subtitle: Text([
                  p.kind.label,
                  if (p.registrationFee > 0) t('דמי רישום {0}', [money(p.registrationFee)]),
                  if (!p.active) t('לא פעיל'),
                ].join(' · ')),
                trailing: Text('${money(p.price)}${p.isRecurring ? t(' / חודש') : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Note(t('המחירים כוללים מע״מ. שינוי מחיר משפיע על מכירות חדשות בלבד.')),
      ]),
    );
  }
}
