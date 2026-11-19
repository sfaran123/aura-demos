// The cards saved for a customer: the list (last four digits, brand, expiry),
// add a card, remove one, and choose the default that recurring charges use.
// Also the log of card charges tried for the customer, when the server has one.

import 'package:flutter/material.dart';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../state/server_sync.dart';
import 'auth_screens.dart' show SyncScope, runOnServer;
import 'member_card.dart' show canSaveMemberCard, showMemberCardSheet;
import 'theme.dart';
import 'widgets.dart';

String _cardKey(SavedCard c) => c.id.isEmpty ? 'main' : c.id;

class CustomerCardsSection extends StatelessWidget {
  const CustomerCardsSection({super.key, required this.customer});
  final Customer customer;

  Future<void> _makeDefault(BuildContext context, SavedCard card) async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    if (sync == null) {
      store.setDefaultCustomerCard(customer, card);
    } else if (!await runOnServer(context, () => sync.setDefaultCard(customer, card))) {
      return;
    }
    if (context.mounted) showDone(context, t('הכרטיס •••• {0} הוא עכשיו ברירת המחדל', [card.last4]));
  }

  Future<void> _remove(BuildContext context, SavedCard card) async {
    final store = StoreScope.read(context);
    final sync = SyncScope.maybeOf(context);
    final last = customer.savedCards.length == 1;
    final billed = store.hasCardBilledMembership(customer.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('removeCardDialog'),
        icon: last && billed ? const Icon(Icons.warning_amber, color: Aura.warn, size: 40) : null,
        title: Text(t('להסיר את הכרטיס •••• {0}?', [card.last4]), textAlign: TextAlign.center),
        content: Text(last && billed
            ? t('זה הכרטיס האחרון של הלקוח, ויש לו מנוי פעיל שמחויב בכרטיס. בלי כרטיס שמור החיוב החודשי ייכשל.')
            : card.isDefault && !last
                ? t('זה כרטיס ברירת המחדל. אחרי ההסרה כרטיס אחר יהפוך לברירת המחדל.')
                : t('אחרי ההסרה אי אפשר יהיה לחייב את הכרטיס הזה.')),
        actions: [
          TextButton(
              key: const Key('removeCardCancel'), onPressed: () => Navigator.pop(c, false), child: Text(t('ביטול'))),
          FilledButton(
              key: const Key('removeCardConfirm'),
              onPressed: () => Navigator.pop(c, true),
              child: Text(last && billed ? t('להסיר בכל זאת') : t('הסרת הכרטיס'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (sync == null) {
      store.removeCustomerCard(customer, card);
    } else if (!await runOnServer(context, () => sync.removeMemberCard(customer, card))) {
      return;
    }
    if (context.mounted) showDone(context, t('הכרטיס •••• {0} הוסר', [card.last4]));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cards = customer.savedCards;
    final canSave = canSaveMemberCard(context, store);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(t('כרטיסים שמורים ({0})', [cards.length])),
      if (cards.isEmpty) Note(t('ללקוח אין כרטיס שמור.')),
      for (final card in cards)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            key: Key('card-${_cardKey(card)}'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(children: [
              const Icon(Icons.credit_card, color: Aura.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('${card.brand.isEmpty ? '' : '${card.brand} '}•••• ${card.last4}',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (card.expiry.isNotEmpty)
                    Text(t('תוקף {0}', [card.expiry]), style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
                ]),
              ),
              if (card.isDefault) Pill(t('ברירת מחדל'), tone: PillTone.ok),
              PopupMenuButton<String>(
                key: Key('cardMenu-${_cardKey(card)}'),
                onSelected: (v) => v == 'default' ? _makeDefault(context, card) : _remove(context, card),
                itemBuilder: (_) => [
                  if (!card.isDefault)
                    PopupMenuItem(
                        key: Key('cardDefault-${_cardKey(card)}'),
                        value: 'default',
                        child: Text(t('קביעה כברירת מחדל'))),
                  PopupMenuItem(
                      key: Key('cardRemove-${_cardKey(card)}'), value: 'remove', child: Text(t('הסרת הכרטיס'))),
                ],
              ),
            ]),
          ),
        ),
      if (cards.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t('החיוב החודשי יורד מכרטיס ברירת המחדל.'),
              style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
        ),
      if (canSave)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('customerAddCard'),
            onPressed: () => showMemberCardSheet(context, customer, add: true),
            icon: const Icon(Icons.add_card, size: 18),
            label: Text(cards.isEmpty ? t('הוספת כרטיס') : t('הוספת כרטיס נוסף')),
          ),
        ),
    ]);
  }
}

/// Every card charge tried for the customer, with what the card company
/// answered. Nothing is shown when the server has no log.
class CardAttemptsSection extends StatefulWidget {
  const CardAttemptsSection({super.key, required this.customer});
  final Customer customer;
  @override
  State<CardAttemptsSection> createState() => _CardAttemptsSectionState();
}

class _CardAttemptsSectionState extends State<CardAttemptsSection> {
  Future<List<CardAttempt>>? attempts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    attempts ??= SyncScope.maybeOf(context)?.cardAttempts(widget.customer);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CardAttempt>>(
        future: attempts,
        builder: (context, snap) {
          final list = snap.data ?? const <CardAttempt>[];
          if (list.isEmpty) return const SizedBox.shrink();
          String two(int n) => n.toString().padLeft(2, '0');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 16),
            SectionLabel(t('ניסיונות חיוב בכרטיס ({0})', [list.length])),
            for (final (i, a) in list.take(30).indexed)
              Padding(
                key: Key('attempt-$i'),
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(a.ok ? Icons.check_circle_outline : Icons.error_outline,
                      size: 18, color: a.ok ? Aura.ok : Aura.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        [
                          '${fmtDate(a.at)} ${two(a.at.hour)}:${two(a.at.minute)}',
                          money(a.amount),
                          if (a.last4.isNotEmpty) '•••• ${a.last4}',
                          if (a.payments > 1) t('{0} תשלומים', [a.payments]),
                          a.ok ? t('חויב') : t('נכשל'),
                          if (a.message.isNotEmpty) a.message,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
          ]);
        },
      );
}
