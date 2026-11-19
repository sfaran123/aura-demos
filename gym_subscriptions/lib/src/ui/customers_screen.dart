import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'checkin_screen.dart' show recordVisit;
import 'checkout/checkout_screens.dart';
import 'customer_cards.dart';
import 'pay_debts.dart' show DebtsPicker;
import 'members_screen.dart' show showMemberSheet;
import 'receipt_view.dart' show CustomerHistory;
import 'theme.dart';
import 'widgets.dart';

/// Every customer of the business, with or without a membership: find one, open
/// the customer's page (details, memberships, every document) and edit it.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final found = (q.isEmpty ? [...store.customers] : store.searchCustomers(q))
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text(t('לקוחות ({0})', [store.customers.length]))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        TextField(
          key: const Key('customerSearch'),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('חיפוש לפי שם או טלפון')),
          onChanged: (v) => setState(() => q = v.trim()),
        ),
        const SizedBox(height: 10),
        if (found.isEmpty) Note(t('לא נמצא לקוח כזה.')),
        for (final c in found.take(200)) _CustomerTile(customer: c),
        if (found.length > 200)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('מוצגים 200 הראשונים. חפשו כדי לצמצם.'), style: const TextStyle(color: Aura.muted)),
          ),
      ]),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = customer;
    final sub = store.currentSubscription(c.id);
    final plan = sub == null ? null : store.plan(sub.planId);
    final owed = store.charges
        .where((x) => x.customerId == c.id && x.isOpen() && !x.dueDate.isAfter(store.today))
        .fold(0.0, (a, x) => a + x.amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        key: Key('customer-${c.id}'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerScreen(customerId: c.id))),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Avatar(c.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
              Text([c.phone, plan?.name ?? t('בלי מנוי')].where((x) => x.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ]),
          ),
          if (owed > 0) Pill(money(owed), tone: PillTone.bad),
          const ForwardChevron(),
        ]),
      ),
    );
  }
}

/// One customer: details, what can be done, the memberships and the whole
/// ledger (every document, with what was paid and what is open).
class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key, required this.customerId});
  final String customerId;

  Future<void> _open(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) showDone(context, t('לא ניתן לפתוח במכשיר הזה'));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = store.customer(customerId);
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(t('לא נמצא לקוח כזה.'))));
    }
    final subs = store.subscriptions.where((s) => s.customerId == c.id).toList().reversed.toList();
    final debts = store.openDebtsOf(c.id);
    final rows = <(String, String)>[
      (t('טלפון'), c.phone),
      if ((c.idNumber ?? '').isNotEmpty) (t('ת"ז / ח"פ'), c.idNumber!),
      if ((c.email ?? '').isNotEmpty) (t('אימייל'), c.email!),
      (
        t('כרטיס אשראי'),
        c.savedCards.length > 1
            ? t('{0} כרטיסים · ברירת מחדל •••• {1}', [c.savedCards.length, c.savedCardLast4 ?? ''])
            : c.hasSavedCard
                ? '•••• ${c.savedCardLast4}'
                : t('לא שמור')
      ),
      (t('הצהרת בריאות'), c.healthDeclared ? t('נחתמה') : t('חסרה')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(c.name), actions: [
        IconButton(
          key: const Key('editCustomer'),
          tooltip: t('עריכת לקוח'),
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showCustomerEdit(context, c),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        SummaryBox(rows: rows),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('customerEdit'),
            onPressed: () => showCustomerEdit(context, c),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(t('עריכת לקוח')),
          ),
          if (whatsappNumber(c.phone).isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: () => _open(context, Uri(scheme: 'tel', path: c.phone.replaceAll(RegExp(r'\D'), ''))),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text(t('חיוג')),
            ),
            OutlinedButton.icon(
              onPressed: () => _open(context, Uri.parse('https://wa.me/${whatsappNumber(c.phone)}')),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
          ],
          OutlinedButton.icon(
            key: const Key('customerNewSub'),
            onPressed: () => startCheckout(context, CheckoutFlow.subscription, customer: c),
            icon: const Icon(Icons.add, size: 18),
            label: Text(t('מנוי חדש')),
          ),
          OutlinedButton.icon(
            key: const Key('customerQuickPay'),
            onPressed: () => startCheckout(context, CheckoutFlow.quickPay, customer: c),
            icon: const Icon(Icons.point_of_sale, size: 18),
            label: Text(t('תשלום')),
          ),
          if (subs.any(store.countsVisits))
            OutlinedButton.icon(
              key: const Key('customerCheckin'),
              onPressed: () async {
                final r = await recordVisit(context, c);
                if (r == null || !context.mounted) return;
                showDone(context, [t('הגעה נרשמה'), if (r.message.isNotEmpty) r.message].join(' · '));
              },
              icon: const Icon(Icons.how_to_reg, size: 18),
              label: Text(t('הגעה')),
            ),
        ]),
        if (debts.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionLabel(t('חודשים שלא שולמו ({0})', [debts.length])),
          Panel(
            key: const Key('customerDebts'),
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
            child: DebtsPicker(customer: c),
          ),
        ],
        const SizedBox(height: 16),
        CustomerCardsSection(customer: c),
        const SizedBox(height: 16),
        SectionLabel(t('מנויים ({0})', [subs.length])),
        if (subs.isEmpty) Note(t('ללקוח אין מנוי.')),
        for (final s in subs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              key: Key('customerSub-${s.id}'),
              onTap: () => showMemberSheet(context, s),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(store.plan(s.planId)?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(
                        [
                          t('התחלה {0}', [fmtDate(s.start)]),
                          if (s.end != null && s.end!.year < 2100) t('עד {0}', [fmtDate(s.end!)]),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                  ]),
                ),
                Pill(s.statusText, tone: toneFor(s.status)),
                const ForwardChevron(),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        // The ledger: every document of the customer, not only the latest.
        CustomerHistory(customerId: c.id, all: true),
        CardAttemptsSection(customer: c),
      ]),
    );
  }
}

/// Edits a customer's name, phone, ID number and email: on the AURA server when
/// signed in, in the app in the demo.
Future<void> showCustomerEdit(BuildContext context, Customer customer) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomerEdit(customer: customer),
    );

class _CustomerEdit extends StatefulWidget {
  const _CustomerEdit({required this.customer});
  final Customer customer;
  @override
  State<_CustomerEdit> createState() => _CustomerEditState();
}

class _CustomerEditState extends State<_CustomerEdit> {
  late final name = TextEditingController(text: widget.customer.name);
  late final phone = TextEditingController(text: widget.customer.phone);
  late final idNumber = TextEditingController(text: widget.customer.idNumber ?? '');
  late final email = TextEditingController(text: widget.customer.email ?? '');
  String? error;

  @override
  void dispose() {
    for (final c in [name, phone, idNumber, email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    final n = name.text.trim(), p = phone.text.trim(), mail = email.text.trim();
    if (n.isEmpty) return setState(() => error = t('צריך שם'));
    if (p.replaceAll(RegExp(r'\D'), '').length < 9) return setState(() => error = t('מספר הטלפון לא תקין'));
    if (mail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      return setState(() => error = t('כתובת האימייל לא תקינה'));
    }
    setState(() => error = null);
    if (sync != null) {
      final ok = await runOnServer(context,
          () => sync.updateMember(widget.customer, name: n, phone: p, idNumber: idNumber.text.trim(), email: mail));
      if (!ok || !mounted) return;
    } else {
      store.editCustomer(widget.customer, name: n, phone: p, idNumber: idNumber.text.trim(), email: mail);
    }
    if (!mounted) return;
    Navigator.pop(context);
    showDone(context, t('פרטי הלקוח נשמרו'));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('עריכת לקוח'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                key: const Key('editName'), controller: name, decoration: InputDecoration(labelText: t('שם מלא'))),
            const SizedBox(height: 10),
            TextField(
              key: const Key('editPhone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
              decoration: InputDecoration(labelText: t('טלפון')),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('editIdNumber'),
              controller: idNumber,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('ת"ז / ח"פ')),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('editEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: t('אימייל')),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!, key: const Key('editError'), style: const TextStyle(color: Aura.warn)),
              ),
            const SizedBox(height: 14),
            FilledButton(key: const Key('editSave'), onPressed: _save, child: Text(t('שמירה'))),
          ]),
        ),
      );
}
