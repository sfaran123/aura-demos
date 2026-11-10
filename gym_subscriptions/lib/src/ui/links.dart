import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import '../domain/settings.dart';
import 'checkout/card_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Owner side: create and send an open registration link.
Future<void> showSignupLinkSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _SignupLinkSheet(),
  );
}

class _SignupLinkSheet extends StatefulWidget {
  const _SignupLinkSheet();
  @override
  State<_SignupLinkSheet> createState() => _SignupLinkSheetState();
}

class _SignupLinkSheetState extends State<_SignupLinkSheet> {
  final to = TextEditingController();

  @override
  void dispose() {
    to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final url = '${store.settings.linkSlug}.aura.link/join';
    final shown = store.activePlans.where((p) => p.onlineSignup).map((p) => p.name).join(', ');
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('לינק הרשמה', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
            'הלקוח בוחר מסלול, ממלא פרטים${store.settings.requireHealthDeclaration ? ', חותם על הצהרת בריאות' : ''} ומשלם באשראי. המנוי נפתח אוטומטית אחרי התשלום.',
            style: const TextStyle(color: Aura.muted, height: 1.45)),
        const SizedBox(height: 4),
        Text('מסלולים בלינק: $shown', style: const TextStyle(color: Aura.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: Aura.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: Aura.line)),
          child: Row(children: [
            Expanded(
                child: Directionality(
                    textDirection: TextDirection.ltr, child: Text(url, overflow: TextOverflow.ellipsis))),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'https://$url'));
                showDone(context, 'הלינק הועתק');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('העתקה'),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('linkTo'),
          controller: to,
          decoration: const InputDecoration(labelText: 'שם או טלפון של הלקוח (לא חובה)'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('sendLink'),
              onPressed: () {
                final l = store.sendSignupLink(to.text);
                Navigator.pop(context);
                showDone(context, 'הלינק נשלח ל${l.sentTo}');
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('שליחה'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final l = store.sendSignupLink(to.text);
                Navigator.pop(context);
                openCustomerPreview(context, l);
              },
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('איך הלקוח רואה'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Customer side of a link, shown inside the app to preview and test it.
void openCustomerPreview(BuildContext context, SignupLink link) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerLinkFlow(link: link)));
}

class CustomerLinkFlow extends StatefulWidget {
  const CustomerLinkFlow({super.key, required this.link});
  final SignupLink link;
  @override
  State<CustomerLinkFlow> createState() => _CustomerLinkFlowState();
}

class _CustomerLinkFlowState extends State<CustomerLinkFlow> {
  int step = 0;
  SubscriptionPlan? plan;
  final name = TextEditingController();
  final phone = TextEditingController();
  final idn = TextEditingController();
  bool health = false;
  bool terms = false;
  String? card;
  int installments = 1;
  String? error;

  @override
  void initState() {
    super.initState();
    final store = StoreScope.read(context);
    final l = widget.link;
    if (l.planId != null) {
      plan = store.plan(l.planId!);
      step = 2;
    }
    if (l.customerId != null) {
      final c = store.customer(l.customerId!)!;
      name.text = c.name;
      phone.text = c.phone;
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    idn.dispose();
    super.dispose();
  }

  double get amountNow => widget.link.amount ?? (plan == null ? 0 : subscriptionDueNow(plan!));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Aura.blueBg, borderRadius: BorderRadius.circular(10)),
      child:
          const Text('תצוגה מקדימה של מה שהלקוח רואה בטלפון שלו', style: TextStyle(color: Aura.blue, fontSize: 12.5)),
    );

    if (step == 3) {
      return Scaffold(
        appBar: AppBar(title: Text(s.businessName), automaticallyImplyLeading: false),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          banner,
          const SizedBox(height: 24),
          const Center(
              child: CircleAvatar(
                  radius: 38, backgroundColor: Aura.okBg, child: Icon(Icons.check, size: 38, color: Aura.ok))),
          const SizedBox(height: 14),
          const Text('המנוי שלך פעיל',
              key: Key('linkDone'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('קבלה וכרטיס מנוי נשלחו ב-${s.receiptChannels.map((c) => c.label).join(' / ')}. בכניסה מציגים את הקוד.',
              textAlign: TextAlign.center, style: const TextStyle(color: Aura.muted)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Aura.ink, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.businessName} · כרטיס מנוי', style: const TextStyle(color: Aura.goldLight, fontSize: 12)),
                  Text(name.text,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(plan!.name, style: const TextStyle(color: Colors.white70)),
                ]),
              ),
              const Icon(Icons.qr_code_2, size: 64, color: Colors.white),
            ]),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('חזרה לאפליקציית העסק')),
          ),
        ),
      );
    }

    if (step == 0) {
      final plans = store.activePlans.where((p) => p.onlineSignup).toList();
      return FlowScaffold(
        title: '${s.businessName} · הצטרפות',
        step: 0,
        steps: 3,
        children: [
          banner,
          const Text('בחרו מסלול', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          for (final p in plans)
            PlanCard(
              key: Key('linkPlan-${p.id}'),
              plan: p,
              selected: plan?.id == p.id,
              onTap: () => setState(() {
                plan = p;
                step = 1;
              }),
            ),
        ],
      );
    }

    if (step == 1) {
      final ok = name.text.trim().length > 1 &&
          isValidPhone(phone.text) &&
          (!s.requireHealthDeclaration || health) &&
          terms &&
          (!s.requireIdNumber || isValidIsraeliId(idn.text)) &&
          (idn.text.isEmpty || isValidIsraeliId(idn.text));
      final p = plan!;
      return FlowScaffold(
        title: 'הפרטים שלך',
        step: 1,
        steps: 3,
        bottom: FilledButton(
          key: const Key('linkToPay'),
          onPressed: ok ? () => setState(() => step = 2) : null,
          child: const Text('המשך לתשלום'),
        ),
        children: [
          Text('${p.name} · ${money(p.price)}${p.isRecurring ? ' לחודש' : ''}',
              style: const TextStyle(color: Aura.muted)),
          TextField(
              key: const Key('lName'),
              controller: name,
              decoration: const InputDecoration(labelText: 'שם מלא'),
              onChanged: (_) => setState(() {})),
          TextField(
            key: const Key('lPhone'),
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'טלפון נייד', hintText: '05X-XXXXXXX'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: idn,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            decoration: InputDecoration(
              labelText: s.requireIdNumber ? 'תעודת זהות' : 'תעודת זהות (לא חובה)',
              errorText:
                  idn.text.isNotEmpty && idn.text.length >= 5 && !isValidIsraeliId(idn.text) ? 'מספר לא תקין' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (s.requireHealthDeclaration)
            CheckboxListTile(
              key: const Key('lHealth'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: health,
              onChanged: (v) => setState(() => health = v ?? false),
              title: const Text('אני מצהיר/ה שמצב בריאותי מאפשר פעילות גופנית (הצהרת בריאות)'),
            ),
          CheckboxListTile(
            key: const Key('lTerms'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: terms,
            onChanged: (v) => setState(() => terms = v ?? false),
            title: Text(p.isRecurring
                ? (p.commitMonths > 0
                    ? 'קראתי ואני מסכים/ה לתקנון ולהתחייבות ל-${p.commitMonths} חודשים'
                    : 'קראתי ואני מסכים/ה לתקנון ולחיוב חודשי עד ביטול (${p.cancelNoticeDays} יום הודעה מראש)')
                : 'קראתי ואני מסכים/ה לתקנון'),
          ),
        ],
      );
    }

    // step 2 – payment
    final p = plan!;
    final maxI = p.isRecurring ? 1 : (p.maxInstallments < s.maxInstallments ? p.maxInstallments : s.maxInstallments);
    final needsDetails = name.text.trim().isEmpty || !isValidPhone(phone.text);
    return FlowScaffold(
      title: 'תשלום',
      step: 2,
      steps: 3,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 6), child: Text(error!, style: const TextStyle(color: Aura.warn))),
        FilledButton(
          key: const Key('linkPay'),
          style: FilledButton.styleFrom(backgroundColor: Aura.goldLight, foregroundColor: Aura.ink),
          onPressed: card == null
              ? null
              : () {
                  if (needsDetails) return setState(() => step = 1);
                  store.completeSignup(widget.link,
                      name: name.text,
                      phone: phone.text,
                      idNumber: idn.text.isEmpty ? null : idn.text,
                      plan: p,
                      cardLast4: card!,
                      installments: installments);
                  setState(() => step = 3);
                },
          child: Text('תשלום ${money(amountNow)}'),
        ),
      ]),
      children: [
        if (widget.link.planId != null) banner,
        SummaryBox(
          rows: [
            (p.name, '${money(p.price)}${p.isRecurring ? ' / חודש' : ''}'),
            if (p.registrationFee > 0 && widget.link.amount == null) ('דמי רישום (חד-פעמי)', money(p.registrationFee)),
          ],
          total: ('לתשלום עכשיו', money(amountNow)),
        ),
        if (p.isRecurring)
          Note(p.commitMonths > 0
              ? 'מהחודש הבא יחויבו ${money(p.price)} בכל חודש באותו כרטיס, בהתחייבות ל-${p.commitMonths} חודשים.'
              : 'מהחודש הבא יחויבו ${money(p.price)} בכל חודש באותו כרטיס. אפשר לבטל בהודעה של ${p.cancelNoticeDays} יום.'),
        Panel(
          onTap: () async {
            final c = await showNewCardSheet(context);
            if (c != null) setState(() => card = c);
          },
          borderColor: Aura.goldLight,
          child: Row(children: [
            const Icon(Icons.lock_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(card == null ? 'הזנת כרטיס אשראי' : 'כרטיס •••• $card', key: const Key('linkCard'))),
            const Icon(Icons.chevron_left),
          ]),
        ),
        if (maxI > 1)
          ChoiceRow<int>(
            values: [1, 2, 3, 6, 10, 12].where((x) => x <= maxI).toList(),
            selected: installments,
            label: (x) => x == 1 ? 'תשלום אחד' : '$x תשלומים',
            onSelected: (x) => setState(() => installments = x),
          ),
      ],
    );
  }
}
