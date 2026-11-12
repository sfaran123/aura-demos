// A member's saved card: add one, or replace the saved one. As the web's
// customer page ("Payment Methods & Documents": card number, CVV, expiry,
// Confirm), the server checks the card with Z Credit (nothing is charged) and
// keeps the token for later charges. The app keeps only the last four digits.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/card_entry.dart';
import '../domain/checkout.dart' show fmtDate;
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/gym_store.dart';
import 'auth_screens.dart' show SyncScope, authErrorText;
import 'theme.dart';
import 'widgets.dart';

/// Whether a card can be saved here: signed in, when the server's Z Credit
/// terminal is set (and the sale settings loaded); in the demo, always.
bool canSaveMemberCard(BuildContext context, GymStore store) =>
    SyncScope.maybeOf(context) == null || store.posSettings?.cardTokens == true;

/// The three card fields, kept by the screen that shows them.
class CardEntry {
  final number = TextEditingController();
  final expiry = TextEditingController();
  final cvv = TextEditingController();

  bool get isEmpty => number.text.trim().isEmpty && expiry.text.trim().isEmpty && cvv.text.trim().isEmpty;

  /// The first problem with what was typed, or null.
  String? validate(DateTime today) =>
      cardNumberError(number.text) ?? expiryError(expiry.text, today) ?? cvvError(cvv.text);

  void clear() {
    number.clear();
    expiry.clear();
    cvv.clear();
  }

  void dispose() {
    number.dispose();
    expiry.dispose();
    cvv.dispose();
  }
}

/// Saves the typed card for [customer]: on the AURA server when signed in,
/// in the app in the demo. Returns null when saved, else the message to show.
Future<String?> saveMemberCard(BuildContext context, GymStore store, Customer customer, CardEntry card) async {
  final sync = SyncScope.maybeOf(context);
  if (sync == null) {
    store.setCustomerCard(customer, card.number.text);
    return null;
  }
  try {
    await sync.saveMemberCard(customer, number: card.number.text, cvv: card.cvv.text, expiry: card.expiry.text);
    return null;
  } on CardSaveException catch (e) {
    return e.message;
  } catch (e) {
    return authErrorText(e);
  }
}

class _Formatter extends TextInputFormatter {
  _Formatter(this.format);
  final String Function(String) format;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Deleting the slash or a space deletes the digit before it.
    var text = newValue.text;
    if (text.length < oldValue.text.length && oldValue.text.endsWith('/') && !text.endsWith('/')) {
      text = text.isEmpty ? '' : text.substring(0, text.length - 1);
    }
    final f = format(text);
    return TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
  }
}

class CardFields extends StatelessWidget {
  const CardFields({super.key, required this.card, this.enabled = true});
  final CardEntry card;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Card numbers and dates read left to right, also in Hebrew and Arabic.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const Key('cardNumber'),
          controller: card.number,
          enabled: enabled,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.creditCardNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
            _Formatter(formatCardNumberInput),
          ],
          decoration: InputDecoration(labelText: t('מספר כרטיס'), hintText: '0000 0000 0000 0000'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('cardExpiry'),
              controller: card.expiry,
              enabled: enabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.creditCardExpirationDate],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')), _Formatter(formatExpiryInput)],
              decoration: InputDecoration(labelText: t('תוקף'), hintText: 'MM/YY'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('cardCvv'),
              controller: card.cvv,
              enabled: enabled,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.creditCardSecurityCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(labelText: 'CVV', hintText: '***'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// The note under the card fields: what happens to the card.
class CardSaveNote extends StatelessWidget {
  const CardSaveNote({super.key});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lock_outline, size: 16, color: Aura.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            t('הכרטיס נבדק מול חברת האשראי, ללא חיוב, ונשמר ללקוח לחיובים הבאים. באפליקציה נשמרות רק 4 הספרות האחרונות.'),
            style: const TextStyle(fontSize: 12.5, color: Aura.muted, height: 1.4),
          ),
        ),
      ]);
}

/// Whether this membership's own card can be updated here.
bool canUpdateMembershipCard(BuildContext context, GymStore store, Subscription sub) =>
    membershipCardUpdatable(sub) && canSaveMemberCard(context, store);

/// Updates a membership's own card, as the web's subscription "Update Credit
/// Card Info": the new card is checked (nothing is charged) and saved on the
/// membership, which the server charges each month. Then, as on the web, the
/// months whose charge failed can be charged to the new card.
Future<void> showMembershipCardSheet(BuildContext context, Subscription sub) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MembershipCardSheet(sub: sub),
    );

class _MembershipCardSheet extends StatefulWidget {
  const _MembershipCardSheet({required this.sub});
  final Subscription sub;
  @override
  State<_MembershipCardSheet> createState() => _MembershipCardSheetState();
}

class _MembershipCardSheetState extends State<_MembershipCardSheet> {
  final card = CardEntry();
  String? error;
  bool busy = false;

  /// After the card was saved: the failed months to charge to it (empty: none).
  List<FailedMonth>? months;
  final picked = <String>{};

  @override
  void dispose() {
    card.dispose();
    super.dispose();
  }

  double get _payable => months!.where((m) => picked.contains(m.monthKey)).fold(0.0, (a, m) => a + m.amount);

  Future<void> _saveCard() async {
    if (busy) return;
    final store = StoreScope.read(context);
    final problem = card.validate(store.today);
    if (problem != null) return setState(() => error = problem);
    final sync = SyncScope.maybeOf(context);
    setState(() {
      busy = true;
      error = null;
    });
    List<FailedMonth> failed = const [];
    try {
      if (sync == null) {
        // Demo: kept in the app.
        widget.sub.hasCardToken = true;
        store.touch();
      } else {
        failed = (await sync.updateMembershipCard(widget.sub,
                number: card.number.text, cvv: card.cvv.text, expiry: card.expiry.text))
            .failedMonths;
      }
    } on CardSaveException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail(authErrorText(e));
    }
    if (!mounted) return;
    card.clear();
    if (failed.isEmpty) {
      Navigator.pop(context);
      showDone(context, t('כרטיס המנוי עודכן'));
      return;
    }
    setState(() {
      busy = false;
      months = failed;
    });
  }

  Future<void> _charge() async {
    if (busy || picked.isEmpty) return;
    final sync = SyncScope.maybeOf(context);
    if (sync == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await sync.payFailedMonths(widget.sub, picked.toList());
      if (!mounted) return;
      if (r.remaining.isEmpty) {
        Navigator.pop(context);
        showDone(context, t('חויב {0} בכרטיס המנוי · {1}', [money(r.amount), r.reference]));
        return;
      }
      showDone(context, t('חויב {0} בכרטיס המנוי · {1}', [money(r.amount), r.reference]));
      setState(() {
        busy = false;
        months = r.remaining;
        picked.clear();
      });
    } on CardChargeException catch (e) {
      _fail(t('החיוב לא אושר: {0}', [e.message]));
    } catch (e) {
      _fail(authErrorText(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      busy = false;
      error = message;
    });
  }

  Widget _spinner() => const SizedBox(
      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Aura.goldLight));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sub = widget.sub;
    final c = store.customer(sub.customerId);
    final plan = store.plan(sub.planId);
    final head = [
      if (c != null) c.name,
      if (plan != null) plan.name,
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: months == null ? _cardStep(sub, head) : _monthsStep(head),
        ),
      ),
    );
  }

  List<Widget> _cardStep(Subscription sub, String head) => [
        Text(sub.hasCardToken ? t('החלפת כרטיס המנוי') : t('הוספת כרטיס למנוי'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(head, style: const TextStyle(color: Aura.muted)),
        const SizedBox(height: 10),
        Note(
          [
            if (sub.hasCardToken) t('הכרטיס השמור במנוי יוחלף בכרטיס החדש.'),
            if (sub.nextCharge != null)
              t('החיוב החודשי ({0}) יחויב בכרטיס החדש החל מ-{1}.', [money(sub.monthlyAmount ?? 0), fmtDate(sub.nextCharge!)]),
            t('הכרטיס השמור של הלקוח לא משתנה.'),
          ].join(' '),
          icon: Icons.credit_card,
        ),
        const SizedBox(height: 12),
        CardFields(card: card, enabled: !busy),
        if (error != null) ...[const SizedBox(height: 10), Note(error!, warn: true)],
        const SizedBox(height: 10),
        const CardSaveNote(),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('saveMembershipCard'),
          onPressed: busy ? null : _saveCard,
          child: busy ? _spinner() : Text(t('אישור ועדכון כרטיס המנוי')),
        ),
      ];

  List<Widget> _monthsStep(String head) => [
        Text(t('חודשים שהחיוב בהם נכשל'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(head, style: const TextStyle(color: Aura.muted)),
        const SizedBox(height: 10),
        Note(t('הכרטיס נשמר. בחרו חודשים לחיוב עכשיו בכרטיס החדש, בחיוב אחד ובחשבונית מס קבלה אחת.'),
            icon: Icons.check_circle_outline),
        const SizedBox(height: 8),
        for (final m in months!)
          CheckboxListTile(
            key: Key('failedMonth-${m.monthKey}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: picked.contains(m.monthKey),
            onChanged: busy
                ? null
                : (v) => setState(() => v == true ? picked.add(m.monthKey) : picked.remove(m.monthKey)),
            title: Text('${m.month.month.toString().padLeft(2, '0')}/${m.month.year}'),
            secondary: Text(money(m.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (error != null) ...[const SizedBox(height: 6), Note(error!, warn: true)],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('chargeFailedMonths'),
          onPressed: busy || picked.isEmpty ? null : _charge,
          child: busy
              ? _spinner()
              : Text(picked.isEmpty ? t('בחרו חודשים') : t('חיוב {0} בכרטיס המנוי', [money(_payable)])),
        ),
        TextButton(
          key: const Key('skipFailedMonths'),
          onPressed: busy
              ? null
              : () {
                  Navigator.pop(context);
                  showDone(context, t('כרטיס המנוי עודכן. החודשים שלא חויבו נשארים ברשימת הגבייה.'));
                },
          child: Text(t('לא עכשיו')),
        ),
      ];
}

/// Adds a card for [customer], or replaces the saved one.
Future<void> showMemberCardSheet(BuildContext context, Customer customer) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MemberCardSheet(customer: customer),
    );

class _MemberCardSheet extends StatefulWidget {
  const _MemberCardSheet({required this.customer});
  final Customer customer;
  @override
  State<_MemberCardSheet> createState() => _MemberCardSheetState();
}

class _MemberCardSheetState extends State<_MemberCardSheet> {
  final card = CardEntry();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    card.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    final store = StoreScope.read(context);
    final problem = card.validate(store.today);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      saving = true;
      error = null;
    });
    final failed = await saveMemberCard(context, store, widget.customer, card);
    if (!mounted) return;
    if (failed != null) {
      setState(() {
        saving = false;
        error = failed;
      });
      return;
    }
    Navigator.pop(context);
    showDone(context, t('הכרטיס נשמר · •••• {0}', [widget.customer.savedCardLast4]));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final replacing = c.hasSavedCard;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(replacing ? t('החלפת כרטיס') : t('הוספת כרטיס'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(c.name, style: const TextStyle(color: Aura.muted)),
          if (replacing) ...[
            const SizedBox(height: 10),
            Note(t('הכרטיס השמור •••• {0} יוחלף בכרטיס החדש.', [c.savedCardLast4]), icon: Icons.credit_card),
          ],
          const SizedBox(height: 12),
          CardFields(card: card, enabled: !saving),
          if (error != null) ...[const SizedBox(height: 10), Note(error!, warn: true)],
          const SizedBox(height: 10),
          const CardSaveNote(),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('saveMemberCard'),
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Aura.goldLight))
                : Text(replacing ? t('אישור והחלפת הכרטיס') : t('אישור ושמירת הכרטיס')),
          ),
        ]),
      ),
    );
  }
}
