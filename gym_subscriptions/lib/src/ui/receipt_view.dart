import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/doc_types.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/settings.dart';
import '../state/gym_store.dart';
import 'auth_screens.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sends a receipt to the customer by SMS, WhatsApp or email.
class ReceiptSendPanel extends StatefulWidget {
  const ReceiptSendPanel({super.key, required this.receipt});
  final Receipt receipt;
  @override
  State<ReceiptSendPanel> createState() => _ReceiptSendPanelState();
}

class _ReceiptSendPanelState extends State<ReceiptSendPanel> {
  late final TextEditingController phone;
  final email = TextEditingController();
  bool showEmail = false;

  @override
  void initState() {
    super.initState();
    final id = widget.receipt.customerId;
    final c = id == null ? null : StoreScope.read(context).customer(id);
    phone = TextEditingController(text: c?.phone ?? '');
  }

  @override
  void dispose() {
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  void _send(Channel ch) {
    final store = StoreScope.read(context);
    final to = ch == Channel.email ? email.text.trim() : phone.text.trim();
    final ok = ch == Channel.email ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(to) : isValidPhone(to);
    if (!ok) {
      showDone(context, ch == Channel.email ? t('כתובת המייל לא תקינה') : t('מספר הטלפון לא תקין'));
      return;
    }
    store.sendReceipt(widget.receipt, ch, ch == Channel.email ? to : formatPhone(to));
    showDone(context, t('הקבלה נשלחה ב-{0} ל-{1}', [ch.label, ch == Channel.email ? to : formatPhone(to)]));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Signed in, nothing is really sent yet (no SMS / WhatsApp / email provider is
    // connected), so the panel is not offered.
    if (SyncScope.maybeOf(context) != null) return const SizedBox.shrink();
    final r = widget.receipt;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('שליחת הקבלה ללקוח'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sendPhone'),
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\- ]'))],
          decoration: InputDecoration(isDense: true, labelText: t('טלפון'), prefixIcon: const Icon(Icons.phone_iphone)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('sendSms'),
              onPressed: () => _send(Channel.sms),
              icon: const Icon(Icons.sms_outlined, size: 18),
              label: const Text('SMS'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('sendWhatsapp'),
              onPressed: () => _send(Channel.whatsapp),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const FittedBox(child: Text('WhatsApp')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            key: const Key('sendEmailToggle'),
            tooltip: t('מייל'),
            onPressed: () => setState(() => showEmail = !showEmail),
            icon: const Icon(Icons.alternate_email),
          ),
        ]),
        if (showEmail) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('sendEmail'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(isDense: true, labelText: t('מייל')),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(key: const Key('sendEmailGo'), onPressed: () => _send(Channel.email), child: Text(t('שליחה'))),
          ]),
        ],
        if (r.sent.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in r.sent) Pill(t('נשלח ב-{0} · {1}', [s.$1, s.$2]), tone: PillTone.ok),
          ]),
        ],
        const SizedBox(height: 6),
        Text(t('בגרסת ההדגמה ההודעה לא יוצאת בפועל. בחיבור לספק ה-SMS נשלחת הודעה עם לינק לקבלה.'),
            style: const TextStyle(fontSize: 11.5, color: Aura.muted)),
      ]),
    );
  }
}

/// The VAT inside a document. A server document carries its own VAT; signed in to an
/// exempt dealer there is none; only the demo works it out from the settings.
double docVat(Receipt r, GymStore store) {
  if (r.docType != null) return r.vat ?? 0;
  if (store.posSettings?.noVat ?? false) return 0;
  final s = store.settings;
  return s.docType == DocType.taxInvoiceReceipt ? round2(r.total * s.vatPct / (100 + s.vatPct)) : 0.0;
}

/// Signed in: the name of a document saved on the server. A stand-in shown before
/// the server's own copy arrives is named by how this business saves sales.
String serverDocLabel(Receipt r, GymStore store) => r.docType != null
    ? docLabel(r, store.settings.docType)
    : ((store.posSettings?.noVat ?? false) ? DocType.receipt : DocType.taxInvoiceReceipt).label;

/// The document's name as printed: invoice-receipt, receipt, or a credit note.
String docLabel(Receipt r, DocType type) => r.docType != null
    // A server document: its own type on the web.
    ? serverDocTypeLabel(r.docType!)
    : r.isCredit
        ? (type == DocType.taxInvoiceReceipt ? t('חשבונית מס זיכוי') : t('קבלת החזר'))
        : type.label;

/// The receipt as the customer gets it, with the send panel under it.
Future<void> showReceiptSheet(BuildContext context, Receipt r) {
  final signedIn = SyncScope.maybeOf(context) != null;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ReceiptCard(receipt: r),
        const SizedBox(height: 10),
        ReceiptSendPanel(receipt: r),
        // Signed in, a credit note is not saved on the server yet (and refunds nothing): not offered.
        if (!signedIn && !r.isCredit && r.creditable > 0 && StoreScope.read(ctx).settings.staffCanRefund) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('creditReceipt'),
            style: OutlinedButton.styleFrom(foregroundColor: Aura.warn, minimumSize: const Size.fromHeight(44)),
            onPressed: () async {
              Navigator.pop(ctx);
              await showCreditSheet(context, r);
            },
            icon: const Icon(Icons.undo),
            label: Text(t('זיכוי / ביטול עסקה')),
          ),
        ],
      ])),
    ),
  );
}

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final r = receipt;
    // Signed in: the company name from the AURA server, as on the home screen.
    final serverName = store.dashboard?.businessName ?? '';
    final businessName = serverName.isNotEmpty ? serverName : s.businessName;
    // A server document: its own total (an unpaid invoice has no payment lines) and VAT.
    final total = r.docTotal ?? r.total;
    final vat = docVat(r, store);
    final vatPct = total - vat == 0 ? 0 : (vat / (total - vat) * 100).round();
    Widget line(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    return Panel(
      key: const Key('receiptCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(isolate(businessName), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          // Flexible: server document numbers (e.g. "TIR-80011") are longer than the app's own.
          Flexible(
            child: Pill('${docLabel(r, s.docType)} ${r.docNo}', tone: r.isCredit ? PillTone.bad : PillTone.info),
          ),
        ]),
        if (s.businessId.isNotEmpty)
          Text(t('ח.פ / ע.מ {0}', [s.businessId]), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        const SizedBox(height: 4),
        Text('${fmtDate(r.date)} · ${r.customerName}', style: const TextStyle(color: Aura.muted)),
        if (r.allocationNumber != null)
          Text(t('מספר הקצאה {0}', [r.allocationNumber]), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        const Divider(height: 20),
        Text(r.description, style: const TextStyle(fontWeight: FontWeight.w500)),
        if (r.reason != null)
          Text(t('סיבה: {0}', [r.reason]), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        if (!r.isCredit && r.credited > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Pill(
                r.creditable <= 0 ? t('זוכה במלואו') : t('זוכה {0} מתוך {1}', [money(r.credited), money(r.total)]),
                tone: PillTone.bad),
          ),
        const SizedBox(height: 6),
        for (final l in r.lines) ...[
          line(
              l.method.label +
                  (l.method == PayMethod.card && l.installments > 1 ? t(' · {0} תשלומים', [l.installments]) : ''),
              money(l.amount)),
          if (l.detailsText.isNotEmpty) Text(l.detailsText, style: const TextStyle(fontSize: 12, color: Aura.muted)),
        ],
        const Divider(height: 20),
        if (vat > 0) ...[
          line(t('לפני מע״מ'), money(round2(total - vat))),
          line(t('מע״מ {0}%', [vatPct]), money(vat)),
        ],
        line(t('סה״כ'), money(total), bold: true),
      ]),
    );
  }
}

/// Issues a credit note for a receipt: how much, how the money goes back, and why.
Future<void> showCreditSheet(BuildContext context, Receipt r) async {
  final store = StoreScope.read(context);
  final amount = TextEditingController(text: _fmt(r.creditable));
  final reason = TextEditingController();
  var method = store.defaultRefundMethod(r);
  var cancelSub = false;
  final sub = r.subscriptionId == null ? null : store.subscriptions.where((s) => s.id == r.subscriptionId).firstOrNull;
  final methods = [
    if (r.lines.any((l) => l.method == PayMethod.card)) PayMethod.card,
    PayMethod.cash,
    PayMethod.bank,
  ];
  final done = await showModalBottomSheet<Receipt>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final a = double.tryParse(amount.text) ?? 0;
      final problem = a <= 0
          ? t('צריך סכום לזיכוי')
          : a > r.creditable + 0.001
              ? t('אפשר לזכות עד {0}', [money(r.creditable)])
              : reason.text.trim().length < 2
                  ? t('צריך לכתוב סיבה')
                  : null;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(t('זיכוי למסמך {0}', [r.docNo]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${r.customerName} · ${r.description} · ${money(r.total)}', style: const TextStyle(color: Aura.muted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('creditAmount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: t('סכום לזיכוי'), suffixText: '₪'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('creditFull'),
                onPressed: () => setState(() => amount.text = _fmt(r.creditable)),
                child: Text(t('הכל')),
              ),
            ]),
            const SizedBox(height: 12),
            Text(t('איך מחזירים את הכסף?'), style: const TextStyle(fontSize: 13, color: Aura.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in methods)
                ChoiceChip(
                  key: Key('refund-${m.name}'),
                  label: Text(m == PayMethod.card ? t('החזר לכרטיס') : m.label),
                  selected: method == m,
                  labelStyle: TextStyle(color: method == m ? Colors.white : Aura.ink),
                  onSelected: (_) => setState(() => method = m),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('creditReason'),
              controller: reason,
              decoration:
                  InputDecoration(labelText: t('סיבה'), hintText: t('לדוגמה: חיוב כפול, ביטול מנוי, טעות במחיר')),
              onChanged: (_) => setState(() {}),
            ),
            if (sub != null && sub.status != SubStatus.cancelled)
              SwitchListTile(
                key: const Key('creditCancelSub'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('לבטל גם את המנוי')),
                subtitle: Text(t('המנוי מסתיים היום והחיובים הפתוחים נמחקים'), style: const TextStyle(fontSize: 12.5)),
                value: cancelSub,
                onChanged: (v) => setState(() => cancelSub = v),
              ),
            const SizedBox(height: 6),
            Note(t('תופק חשבונית זיכוי עם מספר חדש. המסמך המקורי לא נמחק ולא משתנה, כנדרש בניהול ספרים.')),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(problem, style: const TextStyle(color: Aura.warn)),
              ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('creditConfirm'),
              style: FilledButton.styleFrom(backgroundColor: Aura.warn),
              onPressed: problem != null
                  ? null
                  : () => Navigator.pop(ctx,
                      store.credit(r, amount: a, method: method, reason: reason.text, cancelMembership: cancelSub)),
              child: Text(t('הפקת זיכוי · {0}', [money(a)])),
            ),
          ]),
        ),
      );
    }),
  );
  if (done != null && context.mounted) {
    showDone(context, t('הופקה {0} {1}', [docLabel(done, store.settings.docType), done.number]));
    await showReceiptSheet(context, done);
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Everything a customer paid, was credited, and still owes.
class CustomerHistory extends StatelessWidget {
  const CustomerHistory({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final docs = store.receiptsOf(customerId);
    final paid = round2(docs.fold(0.0, (a, r) => a + r.collectedNow));
    final open = store.charges.where((c) => c.customerId == customerId && c.isOpen()).toList();
    final owed = round2(open.fold(0.0, (a, c) => a + c.amount));
    final type = store.settings.docType;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(t('היסטוריית תשלומים'), trailing: Text('${docs.length}', style: const TextStyle(color: Aura.muted))),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: Panel(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('שולם בסך הכל'), style: const TextStyle(fontSize: 12, color: Aura.muted)),
              Text(money(paid),
                  key: const Key('historyPaid'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Panel(
            padding: const EdgeInsets.all(10),
            color: owed > 0 ? Aura.warnBg : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('פתוח לתשלום'), style: const TextStyle(fontSize: 12, color: Aura.muted)),
              Text(money(owed),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: owed > 0 ? Aura.warn : Aura.ok)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (docs.isEmpty) Note(t('עוד אין מסמכים ללקוח הזה.')),
      if (docs.isNotEmpty)
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, r) in docs.take(12).indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                key: Key('history-${r.number}'),
                dense: true,
                onTap: () => showReceiptSheet(context, r),
                title: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${docLabel(r, type)} ${r.docNo} · ${fmtDate(r.date)}'
                    '${r.credited > 0 ? ' · ${t('זוכה')}' : ''}'),
                trailing: Text(money(r.total),
                    style: TextStyle(fontWeight: FontWeight.w700, color: r.isCredit ? Aura.warn : Aura.ink)),
              ),
            ],
            if (docs.length > 12)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t('ועוד {0} במסך המכירות', [docs.length - 12]), style: const TextStyle(color: Aura.muted)),
              ),
          ]),
        ),
    ]);
  }
}
