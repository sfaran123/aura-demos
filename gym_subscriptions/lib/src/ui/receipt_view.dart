import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/settings.dart';
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

/// The receipt as the customer gets it, with the send panel under it.
Future<void> showReceiptSheet(BuildContext context, Receipt r) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
            child:
                Column(children: [ReceiptCard(receipt: r), const SizedBox(height: 10), ReceiptSendPanel(receipt: r)])),
      ),
    );

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context).settings;
    final r = receipt;
    final vat = s.docType == DocType.taxInvoiceReceipt ? round2(r.total * s.vatPct / (100 + s.vatPct)) : 0.0;
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
        Row(children: [
          Expanded(
            child: Text(s.businessName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Pill('${s.docType.label} ${r.number}', tone: PillTone.info),
        ]),
        if (s.businessId.isNotEmpty)
          Text(t('ח.פ / ע.מ {0}', [s.businessId]), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        const SizedBox(height: 4),
        Text('${fmtDate(r.date)} · ${r.customerName}', style: const TextStyle(color: Aura.muted)),
        const Divider(height: 20),
        Text(r.description, style: const TextStyle(fontWeight: FontWeight.w500)),
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
          line(t('לפני מע״מ'), money(round2(r.total - vat))),
          line(t('מע״מ {0}%', [s.vatPct.round()]), money(vat)),
        ],
        line(t('סה״כ'), money(r.total), bold: true),
      ]),
    );
  }
}
