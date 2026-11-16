// "Credit / cancel sale" on a server document, as the web offers it:
//  - Refund to the card (the web's Refund Card Payment): Z Credit refunds all or
//    part of the card payment; a credit and a minus receipt are made.
//  - Cancel the document (the web's Cancel Document): a receipt is cancelled at
//    once; a tax invoice(-receipt) by a credit for the whole document, with the
//    money given back in cash, by transfer or on the terminal.
// The server checks everything again (GymController::cancelSale / refundSaleCard).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/sale_builder.dart' show newAppUuid;
import '../domain/sale_credit.dart';
import '../integration/aura_api.dart';
import '../state/server_sync.dart';
import 'auth_screens.dart' show authErrorText;
import 'theme.dart';
import 'widgets.dart';

enum _Mode { card, cancel }

/// Loads what the server allows for [r] and opens the sheet.
Future<void> showServerCreditSheet(BuildContext context, GymSync sync, Receipt r) async {
  final saleId = r.saleId;
  if (saleId == null) return;
  SaleCreditOptions options;
  try {
    options = await sync.saleCreditOptions(saleId);
  } on AuraApiException catch (e) {
    if (context.mounted) await showCardProblem(context, t('זיכוי / ביטול עסקה'), authErrorText(e));
    return;
  }
  if (!context.mounted) return;
  final String? blocked = !options.allowed
      ? t('אין לכם הרשאה לבטל מסמכים')
      : options.cancelled
          ? t('המסמך כבר בוטל')
          : (!options.canCancel && !options.canRefundCard)
              ? t('אין מה לזכות במסמך הזה')
              : null;
  if (blocked != null) {
    await showCardProblem(context, t('זיכוי / ביטול עסקה'), blocked);
    return;
  }
  final done = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _CreditSheet(sync: sync, receipt: r, options: options),
  );
  if (done != null && context.mounted) {
    if (done.contains(t('שימו לב'))) {
      await showCardProblem(context, t('זיכוי / ביטול עסקה'), done);
    } else {
      showDone(context, done);
    }
  }
}

class _CreditSheet extends StatefulWidget {
  const _CreditSheet({required this.sync, required this.receipt, required this.options});
  final GymSync sync;
  final Receipt receipt;
  final SaleCreditOptions options;

  @override
  State<_CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends State<_CreditSheet> {
  late _Mode mode = widget.options.canRefundCard ? _Mode.card : _Mode.cancel;
  late final amount = TextEditingController(text: _fmt(widget.options.cardRefund?.refundable ?? 0));
  final reason = TextEditingController();
  late PayMethod? method = widget.options.refundMethods.firstOrNull;
  bool cancelMembership = false;
  bool busy = false;

  /// One key per attempt: a retry after a lost answer never refunds or cancels twice.
  String appUuid = newAppUuid();

  SaleCreditOptions get o => widget.options;
  double get refundable => o.cardRefund?.refundable ?? 0;

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  String? get problem {
    if (mode == _Mode.card) {
      final a = double.tryParse(amount.text) ?? 0;
      if (a <= 0) return t('צריך סכום לזיכוי');
      if (a > refundable + 0.001) return t('אפשר לזכות עד {0}', [money(refundable)]);
    } else if (o.cancelMode == 'document' && o.refundMethods.isNotEmpty && method == null) {
      return t('בחרו איך מחזירים את הכסף');
    }
    if (reason.text.trim().length < 2) return t('צריך לכתוב סיבה');
    return null;
  }

  Future<void> submit() async {
    final card = mode == _Mode.card;
    final a = card ? double.parse(amount.text) : o.total;
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('creditConfirmDialog'),
        title: Text(card ? t('להחזיר {0} לכרטיס?', [money(a)]) : t('לבטל את {0}?', [o.reference])),
        content: Text(card
            ? t('Z Credit יחזיר את הסכום לכרטיס של הלקוח, ויופקו מסמכי זיכוי. המסמך המקורי נשאר כמו שהוא.')
            : _cancelNote),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('חזרה'))),
          FilledButton(
            key: const Key('creditConfirmYes'),
            style: FilledButton.styleFrom(backgroundColor: Aura.warn),
            onPressed: () => Navigator.pop(c, true),
            child: Text(card ? t('כן, להחזיר') : t('כן, לבטל')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => busy = true);
    String? failTitle, failText;
    try {
      final String text;
      if (card) {
        final docs = await widget.sync.refundSaleCard(o.saleId,
            appUuid: appUuid, amount: a, reason: reason.text, cancelMembership: cancelMembership);
        text = [
          t('הוחזר {0} לכרטיס', [money(a)]),
          ..._made(credit: docs.tic, receipt: docs.receipt, needsCredit: true, needsReceipt: true),
        ].join(' · ');
      } else {
        final credit = await widget.sync.cancelSale(o.saleId,
            appUuid: appUuid,
            method: o.refundMethods.isEmpty ? null : method,
            reason: reason.text,
            cancelMembership: cancelMembership);
        // A receipt: a minus receipt. A tax invoice(-receipt): a credit, and a minus
        // receipt for the money that was paid.
        final direct = o.cancelMode == 'direct';
        text = [
          t('בוטל {0}', [o.reference]),
          ..._made(
              credit: credit.credit, receipt: credit.receipt, needsCredit: !direct, needsReceipt: direct || o.paid > 0),
        ].join(' · ');
      }
      if (mounted) Navigator.pop(context, text);
      return;
    } on SaleCreditException catch (e) {
      // Declined or refused: nothing was done, the next try is a new one. No clear
      // answer: the same key again, so the server never refunds twice.
      if (!e.unknown) appUuid = newAppUuid();
      failTitle = e.unknown
          ? t('לא ידוע אם ההחזר בוצע')
          : card
              ? t('ההחזר לא בוצע')
              : t('המסמך לא בוטל');
      failText = e.message;
    } on AuraApiException catch (e) {
      // No answer (timeout, connection, server error): the same key on the next try.
      final refused = e.kind == AuraErrorKind.forbidden ||
          e.kind == AuraErrorKind.sessionExpired ||
          (e.kind == AuraErrorKind.server && e.detail.startsWith('HTTP 4'));
      final unclear = card && !refused;
      if (!unclear) appUuid = newAppUuid();
      failTitle = unclear
          ? t('לא ידוע אם ההחזר בוצע')
          : card
              ? t('ההחזר לא בוצע')
              : t('המסמך לא בוטל');
      failText = authErrorText(e);
    }
    if (!mounted) return;
    setState(() => busy = false);
    await showCardProblem(context, failTitle, failText);
  }

  String get _cancelNote => o.cancelMode == 'direct'
      ? t('הקבלה תבוטל ותופק קבלה במינוס על כל הסכום.')
      : o.paid > 0
          ? t('תופק חשבונית זיכוי על כל הסכום וקבלה במינוס על הכסף שהוחזר, והמסמך יסומן כמבוטל.')
          : t('תופק חשבונית זיכוי על כל הסכום, והמסמך יסומן כמבוטל.');

  /// What the server made, in words; a document that had to be made and did not
  /// come back is said clearly, so nobody assumes it exists.
  List<String> _made(
          {required String credit, required String receipt, required bool needsCredit, required bool needsReceipt}) =>
      [
        if (credit.isNotEmpty) t('חשבונית זיכוי {0}', [credit]),
        if (receipt.isNotEmpty) t('קבלה במינוס {0}', [receipt]),
        if (needsCredit && credit.isEmpty) t('שימו לב: השרת לא החזיר חשבונית זיכוי. בדקו במערכת AURA.'),
        if (needsReceipt && receipt.isEmpty) t('שימו לב: השרת לא החזיר קבלה במינוס. בדקו במערכת AURA.'),
      ];

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    final p = problem;
    final card = o.cardRefund;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(t('זיכוי למסמך {0}', [r.docNo]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text('${r.customerName} · ${r.description} · ${money(o.total)}', style: const TextStyle(color: Aura.muted)),
          const SizedBox(height: 12),
          if (o.canRefundCard && o.canCancel)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in _Mode.values)
                ChoiceChip(
                  key: Key('creditMode-${m.name}'),
                  label: Text(m == _Mode.card ? t('החזר לכרטיס') : t('ביטול המסמך')),
                  selected: mode == m,
                  labelStyle: TextStyle(color: mode == m ? Colors.white : Aura.ink),
                  onSelected: busy ? null : (_) => setState(() => mode = m),
                ),
            ]),
          if (o.canRefundCard && o.canCancel) const SizedBox(height: 12),
          if (mode == _Mode.card) ...[
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('creditAmount'),
                  controller: amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: t('סכום לזיכוי'), suffixText: '₪'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('creditFull'),
                onPressed: busy ? null : () => setState(() => amount.text = _fmt(refundable)),
                child: Text(t('הכל')),
              ),
            ]),
            if (card != null && card.refunded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('כבר הוחזר לכרטיס: {0}', [money(card.refunded)]),
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ),
            if (card != null && card.waiting > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('יש החזר של {0} שעדיין לא ידוע אם עבר. בדקו במערכת Z Credit.', [money(card.waiting)]),
                    style: const TextStyle(fontSize: 12.5, color: Aura.warn)),
              ),
          ] else ...[
            Text(t('סכום לזיכוי'), style: const TextStyle(fontSize: 13, color: Aura.muted)),
            Text(money(o.total),
                key: const Key('creditTotal'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (o.refundMethods.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t('איך מחזירים את הכסף?'), style: const TextStyle(fontSize: 13, color: Aura.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in o.refundMethods)
                  ChoiceChip(
                    key: Key('refund-${m.name}'),
                    label: Text(m == PayMethod.card ? t('החזר במסוף') : m.label),
                    selected: method == m,
                    labelStyle: TextStyle(color: method == m ? Colors.white : Aura.ink),
                    onSelected: busy ? null : (_) => setState(() => method = m),
                  ),
              ]),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('creditReason'),
            controller: reason,
            enabled: !busy,
            decoration: InputDecoration(labelText: t('סיבה'), hintText: t('לדוגמה: חיוב כפול, ביטול מנוי, טעות במחיר')),
            onChanged: (_) => setState(() {}),
          ),
          if (o.membershipId != null && o.membershipActive)
            SwitchListTile(
              key: const Key('creditCancelSub'),
              contentPadding: EdgeInsets.zero,
              title: Text(t('לבטל גם את המנוי')),
              subtitle: Text(t('המנוי מתבטל היום'), style: const TextStyle(fontSize: 12.5)),
              value: cancelMembership,
              onChanged: busy ? null : (v) => setState(() => cancelMembership = v),
            ),
          const SizedBox(height: 6),
          Note(mode == _Mode.card
              ? t('Z Credit יחזיר את הסכום לכרטיס של הלקוח, ויופקו מסמכי זיכוי. המסמך המקורי נשאר כמו שהוא.')
              : _cancelNote),
          if (p != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(p, key: const Key('creditProblem'), style: const TextStyle(color: Aura.warn)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('creditConfirm'),
            style: FilledButton.styleFrom(backgroundColor: Aura.warn, minimumSize: const Size.fromHeight(46)),
            onPressed: p != null || busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(mode == _Mode.card
                    ? t('החזר לכרטיס · {0}', [money(double.tryParse(amount.text) ?? 0)])
                    : t('ביטול המסמך · {0}', [money(o.total)])),
          ),
        ]),
      ),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
