import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/gym_store.dart';
import '../state/server_sync.dart' show GymSync, ProductSaveException;
import 'auth_screens.dart' show SyncScope, authErrorText;
import 'theme.dart';
import 'widgets.dart';

/// Adds a product to the price list ([item] null) or edits [item]. Signed in, the
/// product is saved on the AURA server (POST gym/products, as the POS app's Add
/// Product) and a category is required, as on the web's product form; otherwise
/// it is kept on this device only. Returns the product to sell, or null (closed,
/// removed, or saved on a business that tracks stock: not sold until it has stock).
Future<ShopItem?> showProductEditor(BuildContext context, {ShopItem? item}) async {
  final sync = SyncScope.maybeOf(context);
  final store = StoreScope.read(context);
  final res = await showModalBottomSheet<({ShopItem item, bool needsStock})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _ProductSheet(item: item, sync: sync, store: store),
  );
  if (res == null || !context.mounted) return null;
  if (res.needsStock) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('productNeedsStock'),
        icon: const Icon(Icons.inventory_2_outlined, color: Aura.gold, size: 40),
        title: Text(t('המוצר "{0}" נשמר', [res.item.name]), textAlign: TextAlign.center),
        content: Text(t('העסק מנהל מלאי: המוצר יופיע למכירה אחרי שיוסף לו מלאי באתר AURA.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('הבנתי')))],
      ),
    );
    return null;
  }
  if (context.mounted) showDone(context, item == null ? t('המוצר "{0}" נוסף', [res.item.name]) : t('המחירון עודכן'));
  return res.item;
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.item, required this.sync, required this.store});
  final ShopItem? item;
  final GymSync? sync;
  final GymStore store;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final name = TextEditingController(text: widget.item?.name ?? '');
  late final price = TextEditingController(text: widget.item == null ? '' : _fmt(widget.item!.price));
  List<ProductCategory>? categories;
  String? loadError;
  int? categoryId;
  String? error;
  bool saving = false;

  bool get signedIn => widget.sync != null;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    categoryId = widget.item?.categoryId;
    if (signedIn) _loadCategories();
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => loadError = null);
    try {
      final list = await widget.sync!.categories();
      if (!mounted) return;
      setState(() {
        categories = list;
        // The product's category is no longer active: picked again.
        if (categoryId != null && !list.any((c) => c.id == categoryId)) categoryId = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadError = authErrorText(e));
    }
  }

  Future<void> _save() async {
    if (saving) return;
    final n = name.text.trim();
    final p = double.tryParse(price.text) ?? 0;
    if (n.isEmpty) return setState(() => error = t('צריך שם למוצר'));
    if (p <= 0) return setState(() => error = t('צריך מחיר גדול מ-0'));
    if (!signedIn) {
      final item = widget.item;
      final saved = ShopItem(item?.id ?? '', n, p, taxRate: item?.taxRate ?? 0, taxMethod: item?.taxMethod);
      widget.store.saveItem(saved);
      final stored = item != null ? saved : widget.store.items.last;
      Navigator.pop(context, (item: stored, needsStock: false));
      return;
    }
    if (categoryId == null) return setState(() => error = t('בחרו קטגוריה'));
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final res = await widget.sync!.saveProduct(id: widget.item?.id, name: n, price: p, categoryId: categoryId!);
      if (mounted) Navigator.pop(context, res);
    } on ProductSaveException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(authErrorText(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      saving = false;
      error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(item == null ? t('מוצר חדש') : t('עריכת מוצר'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
            key: const Key('itemName'),
            controller: name,
            enabled: !saving,
            decoration: InputDecoration(labelText: t('שם המוצר או השירות'))),
        const SizedBox(height: 8),
        TextField(
          key: const Key('itemPrice'),
          controller: price,
          enabled: !saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: t('מחיר (כולל מע״מ)'), suffixText: '₪'),
        ),
        if (signedIn) ...[
          const SizedBox(height: 8),
          if (loadError != null)
            Row(children: [
              Expanded(
                  child: Text(t('הקטגוריות לא נטענו: {0}', [loadError!]),
                      style: const TextStyle(color: Aura.warn, fontSize: 13))),
              TextButton(onPressed: _loadCategories, child: Text(t('נסו שוב'))),
            ])
          else if (categories == null)
            const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
          else
            DropdownButtonFormField<int>(
              key: const Key('itemCategory'),
              initialValue: categoryId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t('קטגוריה *')),
              items: [
                for (final c in categories!)
                  DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: saving ? null : (v) => setState(() => categoryId = v),
            ),
          if (categories != null && categories!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t('אין קטגוריות פעילות. הוסיפו קטגוריה באתר AURA.'),
                  style: const TextStyle(color: Aura.warn, fontSize: 13)),
            ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, key: const Key('itemError'), style: const TextStyle(color: Aura.warn, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('itemSave'),
          onPressed: saving || (signedIn && categories == null) ? null : _save,
          child: saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t('שמירה')),
        ),
        // On this device only: removed from the price list. Signed in, products are
        // removed (deactivated) on the web.
        if (item != null && !signedIn)
          TextButton(
            key: const Key('itemRemove'),
            onPressed: () {
              widget.store.removeItem(item.id);
              Navigator.pop(context);
            },
            child: Text(t('הסרה מהמחירון'), style: const TextStyle(color: Aura.warn)),
          ),
      ]),
    );
  }
}
