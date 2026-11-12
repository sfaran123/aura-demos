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

  void setPlan(SubscriptionPlan p) {
    plan = p;
    if (p.registrationFee == 0) waiveRegistration = false;
    if (discountPct > store.settings.staffMaxDiscountPct) discountPct = 0;
    _resetPayment();
    notifyListeners();
  }

  void setStart(StartOption s) {
    start = s;
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

  PaymentLine addLine(PayMethod m) {
    final l = newLine(m, remaining, hasSavedCard: hasSavedCard, defaultCheques: maxCheques >= 3 ? 3 : maxCheques);
    lines.add(l);
    notifyListeners();
    return l;
  }

  void removeLine(PaymentLine l) {
    lines.remove(l);
    notifyListeners();
  }

  void setAmount(PaymentLine l, double v) {
    l.amount = v < 0 ? 0 : round2(v);
    notifyListeners();
  }

  void setCardSource(PaymentLine l, CardSource s) {
    l.cardSource = s;
    notifyListeners();
  }

  void setInstallments(PaymentLine l, int n) {
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
