import 'package:flutter/foundation.dart';

import '../../domain/checkout.dart';
import '../../domain/models.dart';
import '../../domain/sale_builder.dart';
import '../../state/gym_store.dart';
import '../../domain/l10n.dart';

/// Everything chosen during one checkout (new subscription or quick payment).
class CheckoutDraft extends ChangeNotifier {
  CheckoutDraft(this.store, this.flow, {this.onServer = false});

  final GymStore store;
  final CheckoutFlow flow;

  /// Signed in to AURA: the sale is saved on the server as the POS app saves one
  /// (sales/store-v2), with the amounts worked out the same way.
  final bool onServer;

  Customer? customer;
  bool walkIn = false;
  SubscriptionPlan? plan;
  StartOption start = StartOption.today;

  /// The day picked when [start] is [StartOption.date].
  DateTime? startOn;
  int discountPct = 0;
  bool waiveRegistration = false;
  final List<PaymentLine> lines = [];
  RecurringMethod? recurring;
  String? newCardLast4;
  final Map<String, int> cart = {};
  double customAmount = 0;
  String customNote = '';

  bool get isSubscription => flow == CheckoutFlow.subscription;
  bool get hasSavedCard => customer?.hasSavedCard ?? false;

  double get due {
    final pos = store.posSettings;
    if (onServer && pos != null) {
      try {
        return saleTotals(saleLines(), pos).grandTotal.toDouble();
      } on Error {
        // No sign-up fee product yet: the checkout stops on it at the end.
      }
    }
    return isSubscription
        ? (plan == null ? 0 : subscriptionDueNow(plan!, discountPct: discountPct, waiveRegistration: waiveRegistration))
        : cartTotal(cart, store.items, customAmount);
  }

  /// The sale's product lines, as saved on the server. Throws [StateError] when the
  /// plan has a sign-up fee and no fee product is chosen in Settings.
  List<SaleLine> saleLines() {
    if (!isSubscription) return cartSaleLines(cart, store.items);
    if (plan == null) return const [];
    final feeId = store.settings.registrationFeeProductId;
    return membershipSaleLines(
      plan: plan!,
      discountPct: discountPct,
      waiveRegistration: waiveRegistration,
      feeProduct: feeId == null ? null : store.items.where((i) => i.id == feeId).firstOrNull,
    );
  }

  double get assigned => linesTotal(lines);
  double get remaining => round2(due - assigned);
  double get monthly => plan == null ? 0 : planPriceAfterDiscount(plan!, discountPct);

  String? get problem => onServer && recurring == RecurringMethod.newCard
      // Signed in, a new card is saved for the member first (then it is the saved card).
      ? t('שמרו את הכרטיס החדש של הלקוח')
      // Signed in, a card line waiting for a card that was not saved (or the saved
      // card without one): blocked until a card is saved or the terminal is picked.
      : onServer &&
              lines.any((l) =>
                  l.method == PayMethod.card &&
                  (l.cardSource == CardSource.newCard || (l.cardSource == CardSource.saved && !hasSavedCard)))
          ? t('שמרו את הכרטיס של הלקוח')
          // The saved card: the desk must say regular or installments.
          : onServer && lines.any((l) => _savedCardLine(l) && l.installments == 0)
              ? t('בחרו: תשלום רגיל או תשלומים')
              : onServer && lines.any((l) => _savedCardLine(l) && l.installments < 0)
                  ? t('מספר התשלומים חייב להיות 2 לפחות')
                  : paymentProblem(
        due: due,
        lines: lines,
        // Signed in, a card is charged on the payment terminal: nothing to type here.
        newCardReady: onServer || newCardLast4 != null,
        plan: isSubscription ? plan : null,
        recurring: recurring,
      );

  /// Signed in, a payment link is not offered yet (the sale is saved paid at the desk).
  bool allowed(PayMethod m) =>
      !(onServer && m == PayMethod.link) &&
      methodAllowed(m, store.settings, plan: isSubscription ? plan : null, walkIn: walkIn);

  int get maxInstallments => maxInstallmentsFor(isSubscription ? plan : null, store.settings);
  int get maxCheques => maxChequesFor(isSubscription ? plan : null, store.settings);

  /// Signed in, monthly by card needs the server's Z Credit terminal: the
  /// member's saved card is copied to the membership and the server's daily
  /// charge bills it. "New card" saves a card for the member first.
  bool get cardBilling => !onServer || (store.posSettings?.cardTokens ?? false);

  List<RecurringMethod> get recurringChoices => [
        for (final m in recurringOptions(hasSavedCard: hasSavedCard, s: store.settings))
          if (cardBilling || (m != RecurringMethod.savedCard && m != RecurringMethod.newCard)) m
      ];

  void _resetPayment() {
    lines.clear();
    recurring = null;
  }

  void setCustomer(Customer? c, {bool walkIn = false}) {
    customer = c;
    this.walkIn = walkIn;
    newCardLast4 = null;
    _resetPayment();
    notifyListeners();
  }

  /// The first day of the membership, from [start] and the day picked ([startOn]).
  DateTime get startDay => startDate(start, store.now, startOn);

  void setPlan(SubscriptionPlan p) {
    plan = p;
    // A picked day too early for the new plan (a monthly plan allows less back): today.
    if (start == StartOption.date && startOn != null && startOn!.isBefore(earliestStart(p, store.now))) {
      start = StartOption.today;
      startOn = null;
    }
    if (p.registrationFee == 0) waiveRegistration = false;
    if (discountPct > store.settings.staffMaxDiscountPct) discountPct = 0;
    _resetPayment();
    notifyListeners();
  }

  /// [on]: the day picked for [StartOption.date].
  void setStart(StartOption s, [DateTime? on]) {
    start = s;
    startOn = s == StartOption.date ? on : null;
    notifyListeners();
  }

  void setDiscount(int d) {
    discountPct = d;
    lines.clear();
    notifyListeners();
  }

  void setWaive(bool v) {
    waiveRegistration = v;
    lines.clear();
    notifyListeners();
  }

  void addItem(String id) {
    cart[id] = (cart[id] ?? 0) + 1;
    lines.clear();
    notifyListeners();
  }

  void removeItem(String id) {
    final q = (cart[id] ?? 0) - 1;
    if (q <= 0) {
      cart.remove(id);
    } else {
      cart[id] = q;
    }
    lines.clear();
    notifyListeners();
  }

  void setCustom(double v, String note) {
    customAmount = v < 0 ? 0 : v;
    customNote = note;
    lines.clear();
    notifyListeners();
  }

  /// Called when the payment step opens: a customer with a saved card gets a
  /// ready card line for the full amount, so most sales are one tap.
  void prefillPayment() {
    if (onServer) {
      // The first payment is taken at the desk; the next months by the saved card, when there is one.
      if (isSubscription && plan!.isRecurring && recurring == null && hasSavedCard && cardBilling) {
        recurring = RecurringMethod.savedCard;
        notifyListeners();
      }
      return;
    }
    if (lines.isEmpty && hasSavedCard && allowed(PayMethod.card)) {
      lines.add(newLine(PayMethod.card, due, hasSavedCard: true));
    }
    if (isSubscription && plan!.isRecurring && recurring == null && hasSavedCard) {
      recurring = RecurringMethod.savedCard;
    }
    notifyListeners();
  }

  /// Signed in, a payment at the desk for a member (a new membership's first
  /// payment, or a quick payment; never the automatic monthly charge): a card line
  /// may be the member's saved card, charged by the server on confirm, regular or
  /// in installments, as the web's Add Sale "existing card". Needs the server's Z
  /// Credit terminal. A walk-in has no saved card.
  bool get savedCardCharge =>
      onServer && cardBilling && !walkIn && customer != null && (!isSubscription || plan != null);

  /// The saved card pays one line at most (one charge per sale).
  bool savedCardFree(PaymentLine l) =>
      !lines.any((x) => x != l && x.method == PayMethod.card && x.cardSource == CardSource.saved);

  /// A card line was charged on the saved card already (the sale is not saved yet).
  bool get cardCharged => lines.any((l) => l.chargeReceipt != null);

  PaymentLine addLine(PayMethod m) {
    final l = newLine(m, remaining, hasSavedCard: hasSavedCard, defaultCheques: maxCheques >= 3 ? 3 : maxCheques);
    // Signed in: a member with a saved card pays with it (charged by the server on
    // confirm), as the web's Add Sale charges the saved card; else the terminal.
    if (onServer && m == PayMethod.card) {
      l.cardSource = savedCardCharge && hasSavedCard && savedCardFree(l) ? CardSource.saved : CardSource.terminal;
      // The saved card: regular or installments is asked, never assumed.
      if (l.cardSource == CardSource.saved) l.installments = 0;
    }
    lines.add(l);
    notifyListeners();
    return l;
  }

  void removeLine(PaymentLine l) {
    if (l.chargeReceipt != null) return; // charged: it stays as it is
    lines.remove(l);
    notifyListeners();
  }

  void setAmount(PaymentLine l, double v) {
    if (l.chargeReceipt != null) return;
    l.amount = v < 0 ? 0 : round2(v);
    notifyListeners();
  }

  void setCardSource(PaymentLine l, CardSource s) {
    if (l.chargeReceipt != null) return;
    // Signed in, the saved card: regular or installments is asked again (0 = not chosen).
    if (onServer && s == CardSource.saved && l.cardSource != CardSource.saved) l.installments = 0;
    if (onServer && s != CardSource.saved) l.installments = 1;
    l.cardSource = s;
    notifyListeners();
  }

  /// A card line paid with the member's saved card (signed in).
  bool _savedCardLine(PaymentLine l) => l.method == PayMethod.card && l.cardSource == CardSource.saved;

  /// [n]: 1 = regular, 2+ = installments (signed in, the saved card; 0 = not chosen
  /// yet; -1 = installments chosen, the number typed is not 2 or more).
  void setInstallments(PaymentLine l, int n) {
    if (l.chargeReceipt != null) return;
    l.installments = n;
    notifyListeners();
  }

  /// Cheque or transfer details were typed.
  void detailsChanged() => notifyListeners();

  void setCheques(PaymentLine l, int n) {
    l.cheques = n;
    notifyListeners();
  }

  void setRecurring(RecurringMethod m) {
    recurring = m;
    notifyListeners();
  }

  void cardEntered(String last4) {
    newCardLast4 = last4;
    notifyListeners();
  }

  String get itemsDescription {
    final parts = <String>[];
    cart.forEach((id, q) {
      final i = store.items.firstWhere((x) => x.id == id);
      parts.add(q > 1 ? '${i.name} ×$q' : i.name);
    });
    if (customAmount > 0) parts.add(customNote.isEmpty ? t('סכום חופשי') : customNote);
    return parts.join(', ');
  }
}
