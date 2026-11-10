import 'package:flutter/material.dart';
import '../../domain/help.dart';
import 'package:flutter/services.dart';

import '../../domain/checkout.dart';
import '../../domain/models.dart';
import '../../domain/settings.dart';
import '../../state/gym_store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../plans_screen.dart' show PlanEditor;
import '../receipt_view.dart';
import '../sales_screen.dart' show PriceListScreen;
import 'card_sheet.dart';
import 'draft.dart';
import '../../domain/l10n.dart';

void startCheckout(BuildContext context, CheckoutFlow flow, {Customer? customer}) {
  final store = StoreScope.read(context);
  final draft = CheckoutDraft(store, flow);
  if (customer != null) {
    draft.setCustomer(customer);
    Navigator.push(context, MaterialPageRoute(builder: (_) => _nextAfterCustomer(draft)));
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerStep(draft: draft)));
  }
}

Widget _nextAfterCustomer(CheckoutDraft d) => d.isSubscription ? PlanStep(draft: d) : ItemsStep(draft: d);

// ---------------------------------------------------------------- customer
class CustomerStep extends StatefulWidget {
  const CustomerStep({super.key, required this.draft});
  final CheckoutDraft draft;
  @override
  State<CustomerStep> createState() => _CustomerStepState();
}

class _CustomerStepState extends State<CustomerStep> {
  String q = '';

  void _pick(Customer? c, {bool walkIn = false}) {
    widget.draft.setCustomer(c, walkIn: walkIn);
    Navigator.push(context, MaterialPageRoute(builder: (_) => _nextAfterCustomer(widget.draft)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = store.searchCustomers(q);
    final d = widget.draft;
    return FlowScaffold(
      title: d.isSubscription ? t('למי פותחים מנוי?') : t('למי התשלום?'),
      help: HelpTopic.customer,
      step: 0,
      children: [
        TextField(
          key: const Key('customerSearch'),
          decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: t('חיפוש לפי שם או טלפון')),
          onChanged: (v) => setState(() => q = v),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            key: const Key('newCustomer'),
            avatar: const Icon(Icons.person_add_alt_1, size: 18),
            label: Text(t('לקוח חדש')),
            onPressed: () async {
              final c = await showNewCustomerSheet(context, store);
              if (c != null) _pick(c);
            },
          ),
          if (!d.isSubscription)
            ActionChip(
              key: const Key('walkIn'),
              avatar: const Icon(Icons.directions_walk, size: 18),
              label: Text(t('לקוח מזדמן')),
              onPressed: () => _pick(null, walkIn: true),
            ),
        ]),
        SectionLabel(q.isEmpty ? t('לקוחות אחרונים') : t('תוצאות')),
        if (list.isEmpty) Note(t('לא נמצא לקוח. אפשר להוסיף לקוח חדש.')),
        for (final c in list) _CustomerTile(customer: c, onTap: () => _pick(c)),
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sub = store.currentSubscription(customer.id);
    final plan = sub == null ? null : store.plan(sub.planId);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Avatar(customer.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            Text('${customer.phone}${customer.hasSavedCard ? t(' · כרטיס שמור') : ''}',
                style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            const SizedBox(height: 4),
            if (sub != null)
              Pill(plan == null ? sub.status.label : '${sub.status.label} · ${plan.name}', tone: toneFor(sub.status))
            else
              Pill(t('ללא מנוי')),
          ]),
        ),
        const ForwardChevron(),
      ]),
    );
  }
}

Future<Customer?> showNewCustomerSheet(BuildContext context, GymStore store) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _NewCustomerSheet(store: store),
  );
}

class _NewCustomerSheet extends StatefulWidget {
  const _NewCustomerSheet({required this.store});
  final GymStore store;
  @override
  State<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<_NewCustomerSheet> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final idn = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    idn.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.store.settings;
    if (name.text.trim().length < 2) return setState(() => error = t('צריך שם מלא'));
    if (!isValidPhone(phone.text)) return setState(() => error = t('מספר הטלפון לא תקין'));
    if (s.requireIdNumber && idn.text.trim().isEmpty) return setState(() => error = t('צריך תעודת זהות'));
    if (idn.text.trim().isNotEmpty && !isValidIsraeliId(idn.text)) {
      return setState(() => error = t('תעודת הזהות לא עוברת בדיקת ספרת ביקורת'));
    }
    final dup = widget.store.customers
        .where((c) => c.phone.replaceAll(RegExp(r'\D'), '') == phone.text.replaceAll(RegExp(r'\D'), ''))
        .firstOrNull;
    if (dup != null) {
      Navigator.pop(context, dup);
      return;
    }
    final c =
        widget.store.addCustomer(name.text, phone.text, idNumber: idn.text.trim().isEmpty ? null : idn.text.trim());
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final reqId = widget.store.settings.requireIdNumber;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('לקוח חדש'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
            key: const Key('ncName'),
            controller: name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: t('שם מלא'))),
        const SizedBox(height: 10),
        TextField(
          key: const Key('ncPhone'),
          controller: phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
          decoration: InputDecoration(labelText: t('טלפון נייד'), hintText: '05X-XXXXXXX'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('ncId'),
          controller: idn,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          decoration: InputDecoration(labelText: reqId ? t('תעודת זהות') : t('תעודת זהות (לא חובה)')),
        ),
        if (error != null) ...[const SizedBox(height: 10), Note(error!, warn: true)],
        const SizedBox(height: 8),
        Text(t('הצהרת בריאות ופרטים נוספים אפשר להשלים אחר כך, או שהלקוח ימלא אותם בלינק.'),
            style: TextStyle(fontSize: 12.5, color: Aura.muted)),
        const SizedBox(height: 12),
        FilledButton(key: const Key('ncSave'), onPressed: _save, child: Text(t('שמירה והמשך'))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- plan
class PlanStep extends StatelessWidget {
  const PlanStep({super.key, required this.draft});
  final CheckoutDraft draft;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final p = draft.plan;
        final s = store.settings;
        return FlowScaffold(
          title: t('בחירת מסלול'),
          help: HelpTopic.plan,
          step: 1,
          bottom: FilledButton(
            key: const Key('toPayment'),
            onPressed: p == null
                ? null
                : () {
                    draft.prefillPayment();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStep(draft: draft)));
                  },
            child: Text(p == null ? t('בחרו מסלול') : t('המשך לתשלום · {0}', [money(draft.due)])),
          ),
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: t('עבור '), style: TextStyle(color: Aura.muted)),
              TextSpan(text: draft.customer!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ])),
            for (final kind in PlanKind.values)
              if (store.activePlans.any((x) => x.kind == kind)) ...[
                SectionLabel(kind.label),
                for (final x in store.activePlans.where((x) => x.kind == kind))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PlanCard(
                      key: Key('plan-${x.id}'),
                      plan: x,
                      selected: p?.id == x.id,
                      onTap: () => draft.setPlan(x),
                    ),
                  ),
              ],
            OutlinedButton.icon(
              key: const Key('planStepNew'),
              onPressed: () async {
                final created = await Navigator.push<SubscriptionPlan>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PlanEditor(
                          plan: SubscriptionPlan(
                              id: '', name: '', kind: PlanKind.recurring, price: 0, freezeDaysPerYear: 14))),
                );
                if (created != null) draft.setPlan(created);
              },
              icon: const Icon(Icons.add),
              label: Text(t('מסלול חדש')),
            ),
            if (p != null) ...[
              SectionLabel(t('אפשרויות')),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('תחילת מנוי'), style: TextStyle(fontSize: 13, color: Aura.muted)),
                  const SizedBox(height: 6),
                  ChoiceRow<StartOption>(
                    values: StartOption.values,
                    selected: draft.start,
                    label: (o) => o.label,
                    onSelected: draft.setStart,
                  ),
                  const SizedBox(height: 12),
                  Text(t('הנחה'), style: TextStyle(fontSize: 13, color: Aura.muted)),
                  const SizedBox(height: 6),
                  ChoiceRow<int>(
                    values: s.discountSteps(),
                    selected: draft.discountPct,
                    label: (d) => d == 0 ? t('ללא') : '$d%',
                    onSelected: draft.setDiscount,
                  ),
                  if (p.registrationFee > 0 && s.staffCanWaiveRegistration)
                    SwitchListTile(
                      key: const Key('waiveReg'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('ויתור על דמי רישום')),
                      subtitle: Text(t('{0} חד-פעמי', [money(p.registrationFee)])),
                      value: draft.waiveRegistration,
                      onChanged: draft.setWaive,
                    ),
                ]),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- items (quick pay)
class ItemsStep extends StatefulWidget {
  const ItemsStep({super.key, required this.draft});
  final CheckoutDraft draft;
  @override
  State<ItemsStep> createState() => _ItemsStepState();
}

class _ItemsStepState extends State<ItemsStep> {
  final amount = TextEditingController();
  final note = TextEditingController();

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void _custom() => widget.draft.setCustom(double.tryParse(amount.text) ?? 0, note.text.trim());

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    StoreScope.of(context); // rebuild when the price list changes
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => FlowScaffold(
        title: t('מה משלמים?'),
        help: HelpTopic.items,
        step: 1,
        bottom: FilledButton(
          key: const Key('itemsToPayment'),
          onPressed: d.due <= 0
              ? null
              : () {
                  d.prefillPayment();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStep(draft: d)));
                },
          child: Text(d.due <= 0 ? t('בחרו מוצר או סכום') : t('המשך לתשלום · {0}', [money(d.due)])),
        ),
        children: [
          Row(children: [
            Expanded(
              child: Text(d.walkIn ? t('לקוח מזדמן') : t('עבור {0}', [d.customer!.name]),
                  style: const TextStyle(color: Aura.muted)),
            ),
            TextButton.icon(
              key: const Key('editPriceList'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(t('עריכת מחירון')),
            ),
          ]),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in d.store.items)
                  SizedBox(
                      width: (box.maxWidth - 8) / 2,
                      child: Panel(
                        key: Key('item-${i.id}'),
                        onTap: () => d.addItem(i.id),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: (d.cart[i.id] ?? 0) > 0 ? Aura.goldBg : null,
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(i.name,
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(money(i.price), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                                ]),
                          ),
                          if ((d.cart[i.id] ?? 0) > 0)
                            InkWell(
                              onTap: () => d.removeItem(i.id),
                              borderRadius: BorderRadius.circular(14),
                              child: CircleAvatar(
                                radius: 13,
                                backgroundColor: Aura.goldLight,
                                child: Text('${d.cart[i.id]}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Aura.ink)),
                              ),
                            ),
                        ]),
                      )),
              ],
            ),
          ),
          if (d.cart.isNotEmpty)
            Text(t('לחיצה על המספר מורידה פריט אחד.'), style: TextStyle(fontSize: 12, color: Aura.muted)),
          SectionLabel(t('סכום חופשי')),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                key: const Key('customAmount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: t('סכום'), suffixText: '₪'),
                onChanged: (_) => _custom(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: note,
                decoration: InputDecoration(labelText: t('עבור (למשל: חוב אוקטובר)')),
                onChanged: (_) => _custom(),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- payment
IconData methodIcon(PayMethod m) => switch (m) {
      PayMethod.card => Icons.credit_card,
      PayMethod.cash => Icons.payments_outlined,
      PayMethod.cheque => Icons.edit_note,
      PayMethod.bank => Icons.account_balance_outlined,
      PayMethod.link => Icons.link,
    };

class PaymentStep extends StatelessWidget {
  const PaymentStep({super.key, required this.draft});
  final CheckoutDraft draft;

  Future<void> _needCard(BuildContext context) async {
    if (draft.newCardLast4 != null) return;
    final last4 = await showNewCardSheet(context);
    if (last4 != null) draft.cardEntered(last4);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final d = draft;
        final p = d.isSubscription ? d.plan : null;
        final problem = d.problem;
        final pct = d.due <= 0 ? 0.0 : (d.assigned / d.due).clamp(0.0, 1.0);
        return FlowScaffold(
          title: t('תשלום'),
          help: HelpTopic.payment,
          step: 2,
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child:
                    Text(problem, key: const Key('payProblem'), style: const TextStyle(color: Aura.warn, fontSize: 13)),
              ),
            FilledButton(
              key: const Key('toSummary'),
              onPressed: problem != null
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SummaryStep(draft: d))),
              child: Text(t('המשך לסיכום')),
            ),
          ]),
          children: [
            // amount due + progress
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Aura.ink, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        p != null && p.isRecurring
                            ? '${t('לתשלום היום')} (${[
                                t('חודש ראשון'),
                                if (p.prepayLastMonth) t('חודש אחרון מראש'),
                                if (!d.waiveRegistration && p.registrationFee > 0) t('דמי רישום'),
                              ].join(' + ')})'
                            : t('לתשלום'),
                        style: const TextStyle(color: Aura.goldLight, fontSize: 12.5),
                      ),
                      Text(money(d.due),
                          key: const Key('dueAmount'),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(t('שויך'), style: TextStyle(color: Aura.goldLight, fontSize: 12.5)),
                    Text(money(d.assigned),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    color: d.remaining == 0 ? const Color(0xFF4CC38A) : Aura.goldLight,
                  ),
                ),
              ]),
            ),
            for (final l in d.lines)
              _LineEditor(key: ObjectKey(l), draft: d, line: l, needCard: () => _needCard(context)),
            SectionLabel(d.lines.isEmpty ? t('איך משלמים?') : t('הוספת אמצעי נוסף (פיצול)')),
            Row(children: [
              for (final m in PayMethod.values) ...[
                if (m != PayMethod.values.first) const SizedBox(width: 6),
                Expanded(
                  child: _MethodButton(
                    key: Key('add-${m.name}'),
                    method: m,
                    enabled: d.allowed(m) && d.remaining > 0,
                    onTap: () async {
                      final l = d.addLine(m);
                      if (m == PayMethod.card && l.cardSource == CardSource.newCard) await _needCard(context);
                    },
                  ),
                ),
              ],
            ]),
            if (p != null && p.isRecurring) ...[
              SectionLabel(t('החיוב החודשי · {0} כל חודש', [money(d.monthly)])),
              ChoiceRow<RecurringMethod>(
                values: d.recurringChoices,
                selected: d.recurring,
                label: (m) => switch (m) {
                  RecurringMethod.savedCard => t('כרטיס שמור •••• {0}', [d.customer!.savedCardLast4]),
                  RecurringMethod.newCard =>
                    d.newCardLast4 != null ? t('כרטיס •••• {0}', [d.newCardLast4]) : t('כרטיס חדש'),
                  _ => m.label,
                },
                onSelected: (m) async {
                  d.setRecurring(m);
                  if (m == RecurringMethod.newCard) await _needCard(context);
                },
              ),
              Note(switch (d.recurring) {
                RecurringMethod.manual => t(
                    t('בכל חודש התשלום יופיע ברשימת "לגבייה" עם תזכורת ללקוח. אחרי {0} ימי איחור הכניסה נחסמת.'),
                    [d.store.settings.graceDays]),
                RecurringMethod.standingOrder =>
                  t('החיוב יעבור דרך הבנק. יש להחתים את הלקוח על טופס הרשאה לחיוב חשבון.'),
                null => t('בחרו איך ייגבה החודש הבא.'),
                _ => p.commitMonths > 0
                    ? t('חיוב אוטומטי כל חודש · התחייבות ל-{0} חודשים.', [p.commitMonths])
                    : t('חיוב אוטומטי כל חודש · ביטול בהודעה של {0} יום מראש.', [p.cancelNoticeDays]),
              }),
            ],
          ],
        );
      },
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({super.key, required this.method, required this.enabled, required this.onTap});
  final PayMethod method;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .35,
        child: Panel(
          onTap: enabled ? onTap : null,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Column(children: [
            Icon(methodIcon(method), size: 22),
            const SizedBox(height: 4),
            Text(method.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({super.key, required this.draft, required this.line, required this.needCard});
  final CheckoutDraft draft;
  final PaymentLine line;
  final Future<void> Function() needCard;
  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(text: _fmt(widget.line.amount));
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final l = widget.line;
    final card = d.customer?.savedCardLast4;
    final maxI = d.maxInstallments;
    final maxC = d.maxCheques;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Aura.goldBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(methodIcon(l.method), size: 18, color: Aura.gold),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(l.method.label, style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(
            width: 120,
            child: TextField(
              key: Key('amount-${d.lines.indexOf(l)}'),
              controller: ctrl,
              textAlign: TextAlign.left,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(
                  isDense: true, suffixText: '₪', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              style: const TextStyle(fontWeight: FontWeight.w600),
              onChanged: (v) => d.setAmount(l, double.tryParse(v) ?? 0),
            ),
          ),
          IconButton(
            tooltip: t('הסרה'),
            onPressed: () => d.removeLine(l),
            icon: const Icon(Icons.close, color: Aura.muted),
          ),
        ]),
        if (l.method == PayMethod.card) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (card != null)
              ChoiceChip(
                label: Text(t('שמור •••• {0}', [card])),
                selected: l.cardSource == CardSource.saved,
                labelStyle: TextStyle(color: l.cardSource == CardSource.saved ? Colors.white : Aura.ink),
                onSelected: (_) => d.setCardSource(l, CardSource.saved),
              ),
            ChoiceChip(
              label: Text(d.newCardLast4 != null ? t('חדש •••• {0}', [d.newCardLast4]) : t('כרטיס חדש')),
              selected: l.cardSource == CardSource.newCard,
              labelStyle: TextStyle(color: l.cardSource == CardSource.newCard ? Colors.white : Aura.ink),
              onSelected: (_) async {
                d.setCardSource(l, CardSource.newCard);
                await widget.needCard();
              },
            ),
          ]),
          if (maxI > 1) ...[
            const SizedBox(height: 8),
            ChoiceRow<int>(
              values: [1, 2, 3, 6, 10, 12].where((x) => x <= maxI).toList(),
              selected: l.installments,
              label: (x) => x == 1 ? t('תשלום אחד') : t('{0} תשלומים', [x]),
              onSelected: (x) => d.setInstallments(l, x),
            ),
          ],
          if (l.installments > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${l.installments} × ${money(l.amount / l.installments)}',
                  style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
            ),
        ],
        if (l.method == PayMethod.cheque) ...[
          const SizedBox(height: 8),
          ChoiceRow<int>(
            values: [1, 2, 3, 6, 10, 12].where((x) => x <= maxC).toList(),
            selected: l.cheques,
            label: (x) => x == 1 ? t('שיק אחד') : t('{0} שיקים', [x]),
            onSelected: (x) => d.setCheques(l, x),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                t('{0} × {1} · הראשון היום והשאר בכל חודש. מספרי השיקים נרשמים בקבלה.',
                    [l.cheques, money(l.amount / l.cheques)]),
                style: const TextStyle(fontSize: 12.5, color: Aura.muted, height: 1.4)),
          ),
          const SizedBox(height: 8),
          PaymentDetailsFields(line: l, index: d.lines.indexOf(l), onChanged: d.detailsChanged),
        ],
        if (l.method == PayMethod.cash)
          Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(t('המזומן נרשם בקופה, והקבלה תציין "מזומן".'),
                  style: TextStyle(fontSize: 12.5, color: Aura.muted))),
        if (l.method == PayMethod.bank)
          Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(t('החלק הזה יאושר כשההעברה תופיע בחשבון. עד אז המנוי ממתין.'),
                  style: TextStyle(fontSize: 12.5, color: Aura.muted))),
        if (l.method == PayMethod.bank) ...[
          const SizedBox(height: 8),
          PaymentDetailsFields(line: l, index: d.lines.indexOf(l), onChanged: d.detailsChanged),
        ],
        if (l.method == PayMethod.link)
          Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(t('החלק הזה נשלח ללקוח בלינק לתשלום. עד שהוא משלם, המנוי ממתין.'),
                  style: TextStyle(fontSize: 12.5, color: Aura.muted))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- summary
class SummaryStep extends StatelessWidget {
  const SummaryStep({super.key, required this.draft});
  final CheckoutDraft draft;

  String _lineText(PaymentLine l) {
    final b = StringBuffer(money(l.amount));
    if (l.method == PayMethod.card) {
      b.write(
          t(' · כרטיס {0}', [l.cardSource == CardSource.saved ? draft.customer!.savedCardLast4 : draft.newCardLast4]));
      if (l.installments > 1) b.write(t(' · {0} תשלומים', [l.installments]));
    }
    if (l.method == PayMethod.cheque) b.write(t(' · {0} שיקים', [l.cheques]));
    if (l.detailsText.isNotEmpty) b.write('\n${l.detailsText}');
    if (l.method.isDeferred) b.write(t(' · ממתין'));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final store = d.store;
    final p = d.isSubscription ? d.plan : null;
    final start = startDate(d.start, store.now);
    final rows = <(String, String)>[
      (t('לקוח'), d.walkIn ? t('לקוח מזדמן') : d.customer!.name),
      if (p != null) ...[
        (t('מסלול'), p.name),
        (t('תחילה'), fmtDate(start)),
        (
          p.isRecurring ? t('חידוש') : t('סיום'),
          switch (p.kind) {
            PlanKind.recurring => t('כל חודש, עד ביטול'),
            PlanKind.term => fmtDate(endDate(p, start)!),
            PlanKind.punch => t('{0} כניסות, עד {1}', [p.entries, fmtDate(endDate(p, start)!)]),
          }
        ),
        if (d.discountPct > 0) (t('הנחה'), '${d.discountPct}%'),
        if (p.registrationFee > 0) (t('דמי רישום'), d.waiveRegistration ? t('בוטלו') : money(p.registrationFee)),
        if (p.isRecurring && p.prepayLastMonth) (t('חודש אחרון ששולם מראש'), money(d.monthly)),
      ] else
        (t('פריטים'), d.itemsDescription),
    ];
    final pending = isPending(d.lines);
    final channel = store.settings.receiptChannels.map((c) => c.label).join(' / ');
    return FlowScaffold(
      title: t('סיכום ואישור'),
      help: HelpTopic.summary,
      step: 3,
      bottom: FilledButton(
        key: const Key('confirm'),
        style: FilledButton.styleFrom(backgroundColor: Aura.goldLight, foregroundColor: Aura.ink),
        onPressed: () {
          Receipt r;
          Subscription? sub;
          if (p != null) {
            final res = store.openSubscription(
              customer: d.customer!,
              plan: p,
              start: d.start,
              discountPct: d.discountPct,
              waiveRegistration: d.waiveRegistration,
              lines: d.lines,
              recurring: d.recurring,
              newCardLast4: d.newCardLast4,
            );
            r = res.receipt;
            sub = res.sub;
          } else {
            r = store.quickPay(customer: d.customer, description: d.itemsDescription, lines: d.lines);
          }
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => DoneScreen(draft: d, receipt: r, sub: sub)),
            (route) => route.isFirst,
          );
        },
        child: Text('${p != null ? t('פתיחת המנוי') : t('ביצוע התשלום')} · ${money(d.due)}'),
      ),
      children: [
        SummaryBox(rows: rows),
        SectionLabel(t('תשלום')),
        SummaryBox(
          rows: [for (final l in d.lines) (l.method.label, _lineText(l))],
          total: (t('סה״כ היום'), money(d.due)),
        ),
        if (p != null && p.isRecurring)
          Note(d.recurring == RecurringMethod.manual
              ? t('מהחודש הבא: {0} בגבייה ידנית. התשלום יופיע ברשימת "לגבייה" בכל חודש.', [money(d.monthly)])
              : t('מהחודש הבא: {0} ב{1}.', [money(d.monthly), d.recurring!.label])),
        Note([
          if (pending) t('המנוי ייפתח במצב "ממתין לתשלום" ויופעל אוטומטית כשהחלק שבלינק או בהעברה יאושר.'),
          t('{0} אחת עם כל אמצעי התשלום{1}.', [
            store.settings.docType.label,
            d.walkIn ? t(' תודפס או תישלח ב-SMS') : t(' תישלח ב-{0} ל-{1}', [channel, d.customer!.phone])
          ]),
        ].join(' ')),
      ],
    );
  }
}

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.draft, required this.receipt, this.sub});
  final CheckoutDraft draft;
  final Receipt receipt;
  final Subscription? sub;

  @override
  Widget build(BuildContext context) {
    final pending = sub?.status == SubStatus.pendingPayment;
    final p = draft.plan;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(pending ? t('ממתין לתשלום') : t('בוצע'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SizedBox(height: 12),
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: pending ? Aura.goldBg : Aura.okBg,
              child: Icon(pending ? Icons.hourglass_top : Icons.check, size: 38, color: pending ? Aura.gold : Aura.ok),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            sub == null
                ? t('התשלום התקבל')
                : (pending ? t('המנוי נפתח וממתין לתשלום') : t('{0} – מנוי פעיל', [draft.customer!.name])),
            key: const Key('doneTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text('${draft.store.settings.docType.label} ${receipt.number} · ${money(receipt.total)}',
              textAlign: TextAlign.center, style: const TextStyle(color: Aura.muted)),
          Center(
            child: TextButton.icon(
              key: const Key('viewReceipt'),
              onPressed: () => showReceiptSheet(context, receipt),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(t('הצגת הקבלה')),
            ),
          ),
          const SizedBox(height: 6),
          ReceiptSendPanel(receipt: receipt),
          if (sub != null && p != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Aura.ink, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('{0} · כרטיס מנוי', [draft.store.settings.businessName]),
                        style: const TextStyle(color: Aura.goldLight, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(draft.customer!.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(p.name, style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                const Icon(Icons.qr_code_2, size: 64, color: Colors.white),
              ]),
            ),
          ],
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              key: const Key('again'),
              onPressed: () {
                Navigator.pop(context);
                startCheckout(context, draft.flow);
              },
              child: Text(draft.isSubscription ? t('מנוי נוסף') : t('תשלום נוסף')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t('חזרה למסך הראשי'))),
          ]),
        ),
      ),
    );
  }
}

/// Basic details for a cheque (number, bank, branch, account, first date) or a
/// bank transfer (reference, paying bank, date). Used at checkout and when
/// collecting a monthly payment.
class PaymentDetailsFields extends StatelessWidget {
  const PaymentDetailsFields({super.key, required this.line, required this.index, required this.onChanged});
  final PaymentLine line;
  final int index;
  final VoidCallback onChanged;

  Widget _f(String key, String label, String value, ValueChanged<String> set,
          {int max = 10, bool digits = true, String? helper}) =>
      TextFormField(
        key: Key('$key-$index'),
        initialValue: value,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: [
          if (digits) FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(max),
        ],
        decoration: InputDecoration(isDense: true, labelText: label, helperText: helper),
        onChanged: (v) {
          set(v.trim());
          onChanged();
        },
      );

  Widget _grid(List<Widget> c) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in c) SizedBox(width: w, child: x)]);
      });

  Future<void> _pickDate(BuildContext context, DateTime current, ValueChanged<DateTime> set) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: current.subtract(const Duration(days: 365)),
      lastDate: current.add(const Duration(days: 730)),
    );
    if (d != null) {
      set(d);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final problem = line.detailsProblem;
    final isCheque = line.method == PayMethod.cheque;
    final c = line.cheque, tr = line.transfer;
    final bank = bankName(isCheque ? c.bank : tr.bank);
    final date = (isCheque ? c.firstDate : tr.date) ?? today;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: problem == null ? Aura.okBg : Aura.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: problem == null ? Aura.okBg : Aura.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isCheque ? t('פרטי השיק') : t('פרטי ההעברה'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (isCheque)
          _grid([
            _f('chq-number', t('מספר שיק'), c.number, (v) => c.number = v),
            _f('chq-bank', t('בנק (קוד)'), c.bank, (v) => c.bank = v, max: 2, helper: bank.isEmpty ? null : bank),
            _f('chq-branch', t('סניף'), c.branch, (v) => c.branch = v, max: 3),
            _f('chq-account', t('מספר חשבון'), c.account, (v) => c.account = v, max: 9),
          ])
        else
          _grid([
            _f('tr-ref', t('אסמכתא'), tr.reference, (v) => tr.reference = v, max: 20, digits: false),
            _f('tr-bank', t('בנק משלם (קוד)'), tr.bank, (v) => tr.bank = v, max: 2, helper: bank.isEmpty ? null : bank),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(isCheque ? t('תאריך השיק הראשון') : t('תאריך ההעברה'),
                style: const TextStyle(fontSize: 13, color: Aura.muted)),
          ),
          TextButton.icon(
            key: Key('${isCheque ? 'chq' : 'tr'}-date-$index'),
            onPressed: () => _pickDate(context, date, (d) => isCheque ? c.firstDate = d : tr.date = d),
            icon: const Icon(Icons.event, size: 18),
            label: Text(fmtDate(date)),
          ),
        ]),
        if (isCheque && line.cheques > 1 && c.number.isNotEmpty)
          Text(t('{0} שיקים: {1} עד {2}, אחד בכל חודש', [line.cheques, c.numberAt(0), c.numberAt(line.cheques - 1)]),
              style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(problem, style: const TextStyle(fontSize: 12.5, color: Aura.warn)),
          ),
      ]),
    );
  }
}
