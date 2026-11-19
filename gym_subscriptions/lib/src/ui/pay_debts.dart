// Paying what a customer owes: one debt or several months in ONE payment, by
// cash, cheque, transfer, a saved card (any of the customer's cards) or a card
// typed now. A card typed now is charged through the server and never kept by
// the app; after the charge the desk is asked whether to save it.

import 'package:flutter/material.dart';

import '../domain/card_entry.dart';
import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/gym_store.dart';
import '../state/server_sync.dart';
import 'auth_screens.dart' show SyncScope, authErrorText, runOnServer;
import 'checkout/checkout_screens.dart' show methodIcon;
import 'collect_screen.dart' show showPaymentDetailsSheet;
import 'member_card.dart' show CardEntry, CardFields;
import 'theme.dart';
import 'widgets.dart';

/// How a card pays: [payments] 0 = taken on the terminal (recorded only),
/// 1 = one payment, 2+ = installments; [cardId] the saved card ('' = the only
/// one); [newCard] = a card typed now.
typedef CardHow = ({int payments, String? cardId, bool newCard});

const _installments = [2, 3, 4, 6, 10, 12];

/// Asks how a card pays [amount]. [cards]: the saved cards that can be charged
/// from here (empty: none). [allowNew]: a card can be typed now.
Future<CardHow?> askCardHow(BuildContext context,
        {required List<SavedCard> cards, required double amount, bool allowNew = true}) =>
    showModalBottomSheet<CardHow>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CardHowSheet(cards: cards, amount: amount, allowNew: allowNew),
    );

class _CardHowSheet extends StatefulWidget {
  const _CardHowSheet({required this.cards, required this.amount, required this.allowNew});
  final List<SavedCard> cards;
  final double amount;
  final bool allowNew;
  @override
  State<_CardHowSheet> createState() => _CardHowSheetState();
}

class _CardHowSheetState extends State<_CardHowSheet> {
  late SavedCard? card = widget.cards.firstOrNull;

  void _pick(int payments) => Navigator.pop(context, (payments: payments, cardId: card?.id, newCard: false));

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount;
    final c = card;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('איך לחייב את הכרטיס? · {0}', [money(amount)]),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (c != null) ...[
            // Several saved cards: which one.
            if (widget.cards.length > 1) ...[
              Text(t('איזה כרטיס שמור לחייב?'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final x in widget.cards)
                  ChoiceChip(
                    key: Key('cardPick-${x.id}'),
                    label: Text(x.isDefault ? '${x.label} · ${t('ברירת מחדל')}' : x.label),
                    selected: x.id == c.id,
                    onSelected: (_) => setState(() => card = x),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: const Key('cardSavedRegular'),
              onPressed: () => _pick(1),
              icon: const Icon(Icons.credit_card, size: 18),
              label: Text(t('כרטיס שמור •••• {0} · תשלום רגיל', [c.last4])),
            ),
            const SizedBox(height: 12),
            Text(t('כרטיס שמור •••• {0} · בתשלומים', [c.last4]),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in _installments)
                ActionChip(
                  key: Key('cardSavedPayments-$n'),
                  label: Text('$n × ${money(amount / n)}'),
                  onPressed: () => _pick(n),
                ),
            ]),
            const SizedBox(height: 12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Note(t('ללקוח אין כרטיס שמור שאפשר לחייב מכאן.')),
            ),
          if (widget.allowNew) ...[
            OutlinedButton.icon(
              key: const Key('cardNew'),
              onPressed: () => Navigator.pop(context, (payments: 1, cardId: null, newCard: true)),
              icon: const Icon(Icons.add_card, size: 18),
              label: Text(t('תשלום בכרטיס חדש')),
            ),
            const SizedBox(height: 8),
          ],
          if (!widget.allowNew)
            OutlinedButton.icon(
              key: const Key('cardTerminal'),
              onPressed: () => Navigator.pop(context, (payments: 0, cardId: null, newCard: false)),
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: Text(t('חויב במסוף הסליקה (רישום בלבד)')),
            ),
        ]),
      ),
    );
  }
}

typedef _Paid = ({List<String> references, String? newCardKey, String? newCardLast4});

/// A card typed now pays [debts]. The sheet stays open when the card is not
/// approved, so another card can be tried; nothing is recorded until a charge
/// succeeds.
class _NewCardSheet extends StatefulWidget {
  const _NewCardSheet({required this.sync, required this.debts, required this.amount});
  final GymSync sync;
  final List<Charge> debts;
  final double amount;
  @override
  State<_NewCardSheet> createState() => _NewCardSheetState();
}

class _NewCardSheetState extends State<_NewCardSheet> {
  final card = CardEntry();
  int payments = 1;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    card.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (busy) return;
    final store = StoreScope.read(context);
    final problem = card.validate(store.today);
    if (problem != null) {
      setState(() => error = problem);
      return showCardProblem(context, t('הכרטיס לא תקין'), problem);
    }
    setState(() {
      busy = true;
      error = null;
    });
    String message;
    try {
      final r = await widget.sync.collectMany(widget.debts, PayMethod.card,
          payments: payments, newCard: (number: card.number.text, cvv: card.cvv.text, expiry: card.expiry.text));
      card.clear();
      if (mounted) Navigator.pop<_Paid>(context, r);
      return;
    } on CardChargedNotRecordedException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
      });
      showCardProblem(context, t('הכרטיס חויב, התשלום לא נרשם'), e.message);
      return;
    } on CardChargeException catch (e) {
      message = e.message;
    } on CardSaveException catch (e) {
      message = e.message;
    } catch (e) {
      message = authErrorText(e);
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      error = message;
    });
    showCardProblem(context, t('החיוב לא בוצע'), '$message\n\n${t('החוב נשאר פתוח. אפשר לנסות כרטיס אחר.')}');
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('תשלום בכרטיס חדש · {0}', [money(amount)]),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Note(t('הכרטיס יחויב עכשיו. הכרטיס השמור של הלקוח לא משתנה. אחרי החיוב תישאלו אם לשמור את הכרטיס החדש.'),
              icon: Icons.credit_card),
          const SizedBox(height: 12),
          CardFields(card: card, enabled: !busy),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              key: const Key('newCardPayments-1'),
              label: Text(t('תשלום רגיל')),
              selected: payments == 1,
              onSelected: busy ? null : (_) => setState(() => payments = 1),
            ),
            for (final n in _installments)
              ChoiceChip(
                key: Key('newCardPayments-$n'),
                label: Text('$n × ${money(amount / n)}'),
                selected: payments == n,
                onSelected: busy ? null : (_) => setState(() => payments = n),
              ),
          ]),
          if (error != null) ...[const SizedBox(height: 10), Note(error!, warn: true)],
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline, size: 16, color: Aura.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t('מספר הכרטיס וה-CVV נשלחים לחברת האשראי בלבד ולא נשמרים באפליקציה.'),
                  style: const TextStyle(fontSize: 12.5, color: Aura.muted, height: 1.4)),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('newCardPay'),
            onPressed: busy ? null : _pay,
            child: busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Aura.goldLight))
                : Text(t('חיוב {0}', [money(amount)])),
          ),
        ]),
      ),
    );
  }
}

/// Runs [action] on the server behind a spinner. A failure is an alert ON TOP
/// of whatever is open (a snackbar would sit behind the sheet), with the card
/// company's own words when it refused the card.
Future<bool> _run(BuildContext context, Future<void> Function() action, {required bool card}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  String? title, message;
  try {
    await action();
  } on CardChargedNotRecordedException catch (e) {
    title = t('הכרטיס חויב, התשלום לא נרשם');
    message = e.message;
  } on CardChargeException catch (e) {
    title = t('החיוב לא בוצע');
    message = '${e.message}\n\n${t('החוב נשאר פתוח. אפשר לנסות כרטיס אחר.')}';
  } on CardSaveException catch (e) {
    title = t('החיוב לא בוצע');
    message = e.message;
  } catch (e) {
    title = card ? t('החיוב לא בוצע') : t('התשלום לא נרשם');
    message = authErrorText(e);
  } finally {
    navigator.pop();
  }
  if (message == null) return true;
  if (context.mounted) await showCardProblem(context, title ?? '', message);
  return false;
}

/// Before paying several months: when this server makes a document per month
/// instead of one, the desk is told and chooses. True to go on.
Future<bool> _confirmDocuments(BuildContext context, GymSync sync, List<Charge> debts,
    {int? payments, String? cardId, bool newCard = false}) async {
  if (debts.length < 2) return true;
  var n = 1;
  if (!await _run(
      context, () async => n = await sync.documentsFor(debts, payments: payments, cardId: cardId, newCard: newCard),
      card: false)) {
    return false;
  }
  if (n < 2 || !context.mounted) return n < 2;
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          key: const Key('manyDocumentsDialog'),
          icon: const Icon(Icons.warning_amber, color: Aura.warn, size: 40),
          title: Text(t('יופקו {0} מסמכים נפרדים', [n]), textAlign: TextAlign.center),
          content: Text(t(
              'השרת עדיין לא מפיק מסמך אחד לכמה חודשים. אם תמשיכו, יופק מסמך נפרד לכל חודש ({0} מסמכים), ואי אפשר לאחד אותם אחר כך. כדי לקבל מסמך אחד, חכו לעדכון השרת.',
              [n])),
          actions: [
            TextButton(
                key: const Key('manyDocumentsCancel'),
                onPressed: () => Navigator.pop(c, false),
                child: Text(t('ביטול'))),
            FilledButton(
                key: const Key('manyDocumentsGo'),
                onPressed: () => Navigator.pop(c, true),
                child: Text(t('להפיק {0} מסמכים', [n]))),
          ],
        ),
      ) ==
      true;
}

String _paidText(List<Charge> debts, double amount, List<String> refs, String how) => [
      debts.length > 1 ? t('{0} תשלומים נגבו', [debts.length]) : t('התקבל'),
      if (refs.isNotEmpty) refs.join(', '),
      '${money(amount)} $how',
    ].join(' · ');

/// Signed in: [debts] of [customer] are paid by card in one charge. Asks how
/// (a saved card, a new card, or already taken on the terminal), charges and
/// records. True when paid. The messages go to [messenger], so they show even
/// when the row that started this has left the list.
Future<bool> payDebtsByCard(BuildContext context, GymSync sync, Customer customer, List<Charge> debts,
    {ScaffoldMessengerState? messenger}) async {
  final store = StoreScope.read(context);
  final m = messenger ?? ScaffoldMessenger.of(context);
  // The navigator stays while a row or a sheet goes: later sheets and dialogs are shown from it.
  final root = Navigator.of(context).context;
  void done(String text) => m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        backgroundColor: Aura.ok,
        content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
  final canCharge = store.posSettings?.cardTokens ?? false;
  final amount = round2(debts.fold(0.0, (a, c) => a + c.amount));
  final how =
      await askCardHow(context, cards: canCharge ? customer.savedCards : const [], amount: amount, allowNew: canCharge);
  if (how == null || !root.mounted) return false;
  if (!await _confirmDocuments(root, sync, debts,
      payments: how.payments == 0 ? null : how.payments, cardId: how.cardId, newCard: how.newCard)) {
    return false;
  }
  if (!root.mounted) return false;

  if (how.newCard) {
    final r = await showModalBottomSheet<_Paid>(
      context: root,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NewCardSheet(sync: sync, debts: debts, amount: amount),
    );
    if (r == null) return false;
    done(_paidText(debts, amount, r.references, t('בכרטיס •••• {0}', [r.newCardLast4 ?? ''])));
    final key = r.newCardKey;
    if (key != null && root.mounted) {
      final save = await showDialog<bool>(
        context: root,
        builder: (c) => AlertDialog(
          key: const Key('saveNewCardDialog'),
          icon: const Icon(Icons.credit_card, color: Aura.gold, size: 36),
          title: Text(t('לשמור את הכרטיס ללקוח?'), textAlign: TextAlign.center),
          content: Text(t(
              'הכרטיס •••• {0} חויב בהצלחה. אפשר לשמור אותו ל{1} לחיובים הבאים. הכרטיס השמור הקיים לא משתנה.',
              [r.newCardLast4 ?? '', customer.name])),
          actions: [
            TextButton(
                key: const Key('saveNewCardNo'), onPressed: () => Navigator.pop(c, false), child: Text(t('לא לשמור'))),
            FilledButton(
                key: const Key('saveNewCardYes'),
                onPressed: () => Navigator.pop(c, true),
                child: Text(t('שמירת הכרטיס'))),
          ],
        ),
      );
      if (save == true && root.mounted) {
        final ok = await runOnServer(root, () => sync.saveChargedCard(customer, key));
        if (ok && root.mounted) showCardSaved(root, t('הכרטיס נשמר בהצלחה · •••• {0}', [r.newCardLast4 ?? '']));
      }
    }
    return true;
  }

  var refs = const <String>[];
  final ok = await _run(root, () async {
    refs = (await sync.collectMany(debts, PayMethod.card,
            payments: how.payments == 0 ? null : how.payments, cardId: how.cardId))
        .references;
  }, card: how.payments != 0);
  if (!ok) return false;
  final last4 = customer.savedCards.where((x) => x.id == how.cardId).firstOrNull?.last4 ?? customer.savedCardLast4;
  done(_paidText(
      debts,
      amount,
      refs,
      how.payments == 0
          ? t('במסוף הסליקה')
          : how.payments > 1
              ? t('בכרטיס •••• {0} ב-{1} תשלומים', [last4 ?? '', how.payments])
              : t('בכרטיס •••• {0}', [last4 ?? ''])));
  return true;
}

/// Everything [customer] owes, each month with a checkbox, the total of the
/// chosen ones, and one payment for all of them.
Future<void> showPayDebts(BuildContext context, Customer customer, {Set<String>? preselect}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(t('תשלום חובות · {0}', [customer.name]),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DebtsPicker(customer: customer, preselect: preselect, onPaid: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );

/// The unpaid months of one customer: choose, see the total, pay once.
class DebtsPicker extends StatefulWidget {
  const DebtsPicker({super.key, required this.customer, this.preselect, this.onPaid});
  final Customer customer;

  /// The debts chosen at first; null: all of them.
  final Set<String>? preselect;
  final VoidCallback? onPaid;
  @override
  State<DebtsPicker> createState() => _DebtsPickerState();
}

class _DebtsPickerState extends State<DebtsPicker> {
  /// The chosen debts; null: all of them.
  late Set<String>? only = widget.preselect;
  PayMethod? method;

  bool _on(Charge c) => only?.contains(c.id) ?? true;

  void _set(List<Charge> debts, Charge c, bool on) => setState(() {
        final chosen = {
          for (final x in debts)
            if (_on(x)) x.id
        };
        on ? chosen.add(c.id) : chosen.remove(c.id);
        only = chosen;
      });

  String _status(GymStore store, Charge c) {
    final late = c.daysOverdue(store.today);
    return c.status == ChargeStatus.failed
        ? t('חיוב נכשל · {0} ניסיונות', [c.attempts])
        : late > 0
            ? t('באיחור {0} ימים', [late])
            : t('היום');
  }

  Future<void> _pay(List<Charge> chosen, PayMethod m) async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final total = round2(chosen.fold(0.0, (a, c) => a + c.amount));
    void done(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          backgroundColor: Aura.ok,
          content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
    PaymentLine? line;
    if (m == PayMethod.cheque || m == PayMethod.bank) {
      line = await showPaymentDetailsSheet(context, PaymentLine(method: m, amount: total));
      if (line == null || !mounted) return;
    }
    if (sync == null) {
      // Demo: a receipt per month, kept in the app.
      final numbers = [for (final c in chosen) '${store.collect(c, m, line: line).number}'];
      done(_paidText(chosen, total, numbers, t('ב{0}', [m.label])));
    } else if (m == PayMethod.card) {
      if (!await payDebtsByCard(context, sync, widget.customer, chosen, messenger: messenger)) return;
    } else {
      if (!await _confirmDocuments(context, sync, chosen) || !mounted) return;
      var refs = const <String>[];
      final ok = await _run(context, () async => refs = (await sync.collectMany(chosen, m, line: line)).references,
          card: false);
      if (!ok) return;
      done(_paidText(chosen, total, refs, t('ב{0}', [m.label])));
    }
    if (mounted) setState(() => only = null);
    widget.onPaid?.call();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final debts = store.openDebtsOf(widget.customer.id);
    if (debts.isEmpty) return Note(t('אין חובות פתוחים ללקוח.'), icon: Icons.check_circle_outline);
    final chosen = debts.where(_on).toList();
    final total = round2(chosen.fold(0.0, (a, c) => a + c.amount));
    final methods = [PayMethod.card, PayMethod.cash, PayMethod.cheque, PayMethod.bank]
        .where((m) => store.settings.enabledMethods.contains(m))
        .toList();
    final m = methods.contains(method) ? method! : methods.firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (debts.length > 1)
        CheckboxListTile(
          key: const Key('debtsAll'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          tristate: true,
          value: chosen.length == debts.length ? true : (chosen.isEmpty ? false : null),
          onChanged: (_) => setState(() => only = chosen.length == debts.length ? <String>{} : null),
          title: Text(t('בחירת הכול ({0})', [debts.length]), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      for (final c in debts)
        CheckboxListTile(
          key: Key('debt-${c.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _on(c),
          onChanged: (v) => _set(debts, c, v == true),
          title: Text('${c.monthLabel} · ${store.plan(_planId(store, c))?.name ?? ''}'),
          subtitle: Text(_status(store, c), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
          secondary: Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      const Divider(height: 16),
      Row(children: [
        Expanded(
            child: Text(t('נבחרו {0} מתוך {1}', [chosen.length, debts.length]),
                style: const TextStyle(color: Aura.muted))),
        Text(money(total),
            key: const Key('debtsTotal'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final x in methods)
          ChoiceChip(
            key: Key('debtsMethod-${x.name}'),
            avatar: Icon(methodIcon(x), size: 16),
            label: Text(x.label),
            selected: x == m,
            onSelected: (_) => setState(() => method = x),
          ),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('debtsPay'),
        onPressed: chosen.isEmpty || m == null ? null : () => _pay(chosen, m),
        icon: const Icon(Icons.check, size: 18),
        label: Text(chosen.isEmpty
            ? t('בחרו חודשים')
            : chosen.length == debts.length && debts.length > 1
                ? t('תשלום הכול · {0}', [money(total)])
                : t('תשלום {0}', [money(total)])),
      ),
      if (chosen.length > 1) ...[
        const SizedBox(height: 6),
        Text(t('חיוב אחד על כל הסכום. אם התשלום לא עובר, שום חודש לא מסומן כשולם.'),
            style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
      ],
    ]);
  }

  String _planId(GymStore store, Charge c) =>
      store.subscriptions.where((s) => s.id == c.subscriptionId).firstOrNull?.planId ?? '';
}
