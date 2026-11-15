// Undoing a sale on the AURA server, as the web does it (GymController):
//  - Cancel Document: a receipt is cancelled at once; a tax invoice(-receipt) by a
//    credit (TIC) for the whole document, with the money given back in cash, by
//    transfer, or on the terminal.
//  - Refund Card Payment: Z Credit refunds the card (all or part), then the web's
//    TIC and minus receipt are made.

import 'l10n.dart';
import 'models.dart';

/// The web's Refund Card Payment for a sale: the card payment, what was already
/// refunded, refunds still waiting for Z Credit's answer, and what is left.
class CardRefundState {
  const CardRefundState({required this.amount, required this.refunded, required this.waiting, required this.refundable});
  final double amount;
  final double refunded;
  final double waiting;
  final double refundable;
}

/// GET gym/sales/{id}/credit.
class SaleCreditOptions {
  const SaleCreditOptions({
    required this.saleId,
    required this.reference,
    required this.type,
    required this.total,
    required this.paid,
    required this.cancelled,
    required this.allowed,
    this.cancelMode,
    this.refundMethods = const [],
    this.cardRefund,
    this.membershipId,
    this.membershipActive = false,
  });

  final int saleId;
  final String reference;
  final int type;
  final double total;
  final double paid;
  final bool cancelled;

  /// The user may cancel this customer's documents (the web's Cancel Document permission).
  final bool allowed;

  /// 'direct' (a receipt: cancelled at once), 'document' (cancelled by a TIC) or null.
  final String? cancelMode;

  /// How the money of a 'document' cancel is given back; empty when nothing was paid.
  /// [PayMethod.card] = given back on the terminal (the sale was paid by card).
  final List<PayMethod> refundMethods;
  final CardRefundState? cardRefund;
  final String? membershipId;
  final bool membershipActive;

  bool get canCancel => allowed && !cancelled && cancelMode != null;
  bool get canRefundCard => allowed && (cardRefund?.refundable ?? 0) > 0;

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  factory SaleCreditOptions.fromJson(Map j) {
    final card = j['card_refund'];
    final membership = j['membership'];
    return SaleCreditOptions(
      saleId: _d(j['sale_id']).toInt(),
      reference: '${j['reference_no'] ?? ''}',
      type: _d(j['type']).toInt(),
      total: _d(j['grand_total']),
      paid: _d(j['paid_amount']),
      cancelled: j['cancelled'] == true,
      allowed: j['allowed'] == true,
      cancelMode: j['cancel_mode'] is String ? j['cancel_mode'] as String : null,
      refundMethods: [
        for (final m in (j['refund_methods'] is List ? j['refund_methods'] as List : const []))
          if (m == 'cash')
            PayMethod.cash
          else if (m == 'bank')
            PayMethod.bank
          else if (m == 'card')
            PayMethod.card,
      ],
      cardRefund: card is Map
          ? CardRefundState(
              amount: _d(card['amount']),
              refunded: _d(card['refunded']),
              waiting: _d(card['waiting']),
              refundable: _d(card['refundable']),
            )
          : null,
      membershipId: membership is Map && membership['id'] != null ? '${membership['id']}' : null,
      membershipActive: membership is Map && membership['active'] == true,
    );
  }
}

/// A cancel or refund the server did not do; [message] says why, for the desk.
class SaleCreditException implements Exception {
  const SaleCreditException(this.message, {this.unknown = false});
  final String message;

  /// Z Credit gave no clear answer: the refund may have gone through.
  final bool unknown;

  @override
  String toString() => 'SaleCreditException($message)';
}

/// The desk's text for the server's answer (`HTTP 4xx: <message>`), or null.
SaleCreditException? saleCreditError(String detail) {
  final i = detail.indexOf(': ');
  final m = i < 0 ? detail : detail.substring(i + 2);
  if (detail.startsWith('HTTP 403')) return SaleCreditException(t('אין לכם הרשאה לבטל מסמכים'));
  if (m.startsWith('refund_declined')) {
    final why = m.length > 'refund_declined: '.length ? m.substring('refund_declined: '.length) : '';
    return SaleCreditException(t('Z Credit לא אישר את ההחזר: {0}', [why]));
  }
  return switch (m) {
    'already_cancelled' => SaleCreditException(t('המסמך כבר בוטל')),
    'cannot_cancel' => SaleCreditException(t('אי אפשר לבטל את המסמך הזה')),
    'refund_method_required' => SaleCreditException(t('בחרו איך מחזירים את הכסף')),
    'card_refund_unavailable' => SaleCreditException(t('אין החזר לכרטיס למסמך הזה')),
    'amount_too_high' => SaleCreditException(t('הסכום גבוה ממה שאפשר להחזיר')),
    'refund_unknown' => SaleCreditException(
        t('לא התקבלה תשובה ברורה מ-Z Credit. בדקו במערכת Z Credit אם ההחזר עבר לפני שמנסים שוב.'),
        unknown: true),
    _ => null,
  };
}
