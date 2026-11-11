// Server JSON (AURA web) -> gym app models. Pure functions, no I/O.
//
//   members      GET /api/gym/members      -> Customer
//   plans        GET /api/gym/plans        -> SubscriptionPlan   (subscription products)
//   memberships  GET /api/gym/memberships  -> Subscription (+ failed / upcoming Charge)
//   products     GET /api/sales/getproduct-v2 -> ShopItem        (same list as the POS app)
//   sales        GET /api/sales            -> Receipt            (same list as the POS app)
//
// Ids keep the server id as a string, so a record has the same id after every sync.

import '../domain/dashboard.dart';
import '../domain/models.dart';

class ServerData {
  ServerData({
    required this.customers,
    required this.plans,
    required this.subscriptions,
    required this.charges,
    required this.items,
    required this.receipts,
  });

  final List<Customer> customers;
  final List<SubscriptionPlan> plans;
  final List<Subscription> subscriptions;
  final List<Charge> charges;
  final List<ShopItem> items;
  final List<Receipt> receipts;
}

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
bool _b(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime? _date(Object? v) {
  final s = _s(v).trim();
  if (s.isEmpty || s.startsWith('0000')) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<Map<String, dynamic>> _list(Object? v) => [
      if (v is List)
        for (final x in v)
          if (x is Map) x.cast<String, dynamic>()
    ];

/// GET gym/members -> customers. The POS walk-in customer is left out.
List<Customer> mapMembers(Object? body) {
  final data = body is Map ? body['data'] : null;
  return [
    for (final m in _list(data))
      if (!_b(m['is_walk_in']))
        Customer(
          id: _s(m['id']),
          name: _s(m['name']),
          phone: _s(m['phone']),
          idNumber: _s(m['id_number']).isEmpty ? null : _s(m['id_number']),
          // The app shows "saved card ••1234"; the card token itself never leaves the server.
          savedCardLast4: _b(m['has_saved_card']) ? (_s(m['card_last4']).isEmpty ? '••••' : _s(m['card_last4'])) : null,
          healthDeclared: m['health_declaration_signed_at'] != null,
        ),
  ];
}

PlanKind _kind(Object? type) => switch (_s(type)) {
      'fixed_term' => PlanKind.term,
      'punch_card' => PlanKind.punch,
      _ => PlanKind.recurring,
    };

/// GET gym/plans -> plans. products.subscription_duration is the term length,
/// and the validity of a punch card.
List<SubscriptionPlan> mapPlans(Object? body) {
  final data = body is Map ? body['data'] : null;
  return [
    for (final p in _list(data))
      () {
        final s = (p['settings'] is Map ? (p['settings'] as Map).cast<String, dynamic>() : <String, dynamic>{});
        final duration = _i(p['duration_months']);
        return SubscriptionPlan(
          id: _s(p['id']),
          name: _s(p['name']),
          kind: _kind(s['plan_type']),
          price: _d(p['price']),
          months: duration > 0 ? duration : 1,
          entries: _i(s['entries_count'], 10),
          validMonths: duration > 0 ? duration : 3,
          commitMonths: _i(s['commitment_months']),
          cancelNoticeDays: _i(s['cancellation_notice_days']),
          registrationFee: _d(s['registration_fee']),
          weeklyLimit: _i(s['weekly_entry_limit']),
          freezeDaysPerYear: _i(s['freeze_days_per_year']),
          maxInstallments: _i(s['max_installments'], 1),
          maxCheques: _i(s['max_cheques']),
          autoRenew: _b(s['auto_renew']),
          allowCash: s.containsKey('allow_cash') ? _b(s['allow_cash']) : true,
          allowCheques: _b(s['allow_cheques']),
          onlineSignup: _b(s['online_signup']),
          active: true,
          badge: _s(s['badge']).isEmpty ? null : _s(s['badge']),
          prepayLastMonth: _b(s['prepay_last_month']),
        );
      }(),
  ];
}

SubStatus _status(Object? s) => switch (_s(s)) {
      'cancelled' => SubStatus.cancelled,
      'ended' => SubStatus.expired,
      'frozen' => SubStatus.frozen,
      'payment_failed' => SubStatus.paymentFailed,
      'awaiting_payment' => SubStatus.pendingPayment,
      _ => SubStatus.active,
    };

RecurringMethod _recurring(Object? type) => switch (_s(type)) {
      'bank_transfer' => RecurringMethod.standingOrder,
      'manual' => RecurringMethod.manual,
      _ => RecurringMethod.savedCard,
    };

/// GET gym/memberships -> memberships plus their open charges. A membership
/// whose member or plan is not in [customers] / [plans] (deactivated on the web)
/// gets a stand-in, added to those lists, so every screen can show it.
({List<Subscription> subscriptions, List<Charge> charges}) mapMemberships(
  Object? body, {
  required List<Customer> customers,
  required List<SubscriptionPlan> plans,
  required DateTime today,
}) {
  final data = body is Map ? body['data'] : null;
  final subs = <Subscription>[];
  final charges = <Charge>[];
  final customerIds = {for (final c in customers) c.id};
  final planIds = {for (final p in plans) p.id};

  for (final m in _list(data)) {
    final items = _list(m['items']);
    if (items.isEmpty) continue; // nothing to show without a product
    final item = items.first;
    final start = _date(item['start_date']);
    if (start == null) continue;

    final id = _s(m['id']);
    final customerId = _s(m['customer_id']);
    final planId = _s(item['product_id']);
    if (!customerIds.contains(customerId)) {
      customers.add(Customer(id: customerId, name: _s(m['customer_name']), phone: _s(m['customer_phone'])));
      customerIds.add(customerId);
    }
    if (!planIds.contains(planId)) {
      plans.add(SubscriptionPlan(
        id: planId,
        name: _s(item['product_name']),
        kind: PlanKind.recurring,
        price: _d(item['total']),
        active: false,
      ));
      planIds.add(planId);
    }

    final plan = plans.firstWhere((p) => p.id == planId);
    final unlimited = _i(item['periods']) == 0;
    // One payment for the whole period (Add Sale "One Time Payment") = not charged monthly.
    final monthly = plan.isRecurring || _i(item['payments_total']) != 1;
    final method = _recurring(m['auto_payment_type']);
    final freezes = _list(m['freezes']);
    final yearStart = DateTime(today.year);
    var freezeDays = 0;
    for (final f in freezes) {
      final a = _date(f['start_date']), b = _date(f['end_date']);
      if (a == null || b == null || b.isBefore(yearStart)) continue;
      final from = a.isBefore(yearStart) ? yearStart : a;
      freezeDays += _dayOnly(b).difference(_dayOnly(from)).inDays + 1;
    }
    final cancelRequested = _date(m['cancel_requested_at']);
    final end = unlimited ? null : _date(item['end_date']);
    // A scheduled cancellation moves the end date on the server, also for "until cancelled" memberships.
    final cancelOn = cancelRequested != null ? _date(item['end_date']) : null;
    final lastDay = end ?? cancelOn;

    final sub = Subscription(
      id: id,
      customerId: customerId,
      planId: planId,
      start: start,
      end: end,
      status: _status(m['status']),
      discountPct: _d(m['discount_percent']).round(),
      monthlyAmount: monthly ? _d(item['total']) : null,
      recurringMethod: monthly ? method : null,
      entriesLeft: m['entries_remaining'] == null ? null : _i(m['entries_remaining']),
      frozenUntil: _date(m['frozen_until']),
      freezeDaysUsed: freezeDays,
      nextCharge: _date(item['next_payment_date']),
      cancelEffective: cancelOn,
      prepaidAmount: _d(m['prepaid_amount']),
      joinedAt: _date(m['created_at']) ?? start,
      cancelledAt: _date(m['cancelled_at']) ?? cancelRequested,
    );
    subs.add(sub);

    for (final f in _list(m['failed_payments'])) {
      charges.add(Charge(
        id: 'failed-${_s(f['id'])}',
        subscriptionId: id,
        customerId: customerId,
        dueDate: _dayOnly(_date(f['date']) ?? today),
        amount: _d(f['amount']),
        manual: method == RecurringMethod.manual,
        status: ChargeStatus.failed,
        attempts: 1,
      ));
    }
    // The next monthly charge of a running membership.
    final next = sub.nextCharge;
    final running = sub.status != SubStatus.cancelled && sub.status != SubStatus.expired;
    if (monthly && running && next != null && (lastDay == null || next.isBefore(lastDay))) {
      charges.add(Charge(
        id: 'next-$id',
        subscriptionId: id,
        customerId: customerId,
        dueDate: _dayOnly(next),
        amount: _d(item['total']),
        manual: method == RecurringMethod.manual,
      ));
    }
  }
  return (subscriptions: subs, charges: charges);
}

/// GET sales/getproduct-v2 (a plain list) -> price list, without the plans.
List<ShopItem> mapProducts(Object? body, {required Set<String> planIds}) {
  final seen = <String>{};
  return [
    for (final p in _list(body))
      if (!planIds.contains(_s(p['id'])) && seen.add(_s(p['id']))) ShopItem(_s(p['id']), _s(p['name']), _d(p['price'])),
  ];
}

PayMethod _payMethod(Object? m) => switch (_s(m).toLowerCase()) {
      'credit card' || 'card' => PayMethod.card,
      'cheque' || 'check' => PayMethod.cheque,
      'bank transfer' || 'bank_transfer' || 'transfer' => PayMethod.bank,
      _ => PayMethod.cash,
    };

/// One page of GET sales -> receipts. [names] maps product ids to names for the description.
List<Receipt> mapSales(Object? body, {required Map<String, String> names}) {
  final data = body is Map ? body['data'] : null;
  final rows = data is Map ? _list(data['sale_data']) : const <Map<String, dynamic>>[];
  return [
    for (final row in rows)
      if (row['sale'] is Map)
        () {
          final sale = (row['sale'] as Map).cast<String, dynamic>();
          final customer = row['customer'] is Map ? (row['customer'] as Map).cast<String, dynamic>() : null;
          final total = _d(sale['grand_total']);
          final payments = _list(row['payment']);
          final lines = [
            for (final p in payments)
              if (_d(p['amount']) != 0) PaymentLine(method: _payMethod(p['paying_method']), amount: _d(p['amount'])),
          ];
          final products = _list(row['product_sale']);
          final description =
              products.map((x) => names[_s(x['product_id'])] ?? '#${_s(x['product_id'])}').toSet().join(', ');
          final subscriptionId = _s(sale['subscription_id']);
          return Receipt(
            number: _i(sale['id']),
            reference: _s(sale['reference_no']).isEmpty ? null : _s(sale['reference_no']),
            kind: total < 0
                ? ReceiptKind.credit
                : subscriptionId.isNotEmpty
                    ? ReceiptKind.subscription
                    : ReceiptKind.quickPay,
            customerId: customer == null ? null : _s(customer['id']),
            customerName: _s(customer?['name'] ?? sale['customer_name']),
            subscriptionId: subscriptionId.isEmpty ? null : subscriptionId,
            description: description,
            // Unpaid documents (e.g. a tax invoice) have no payment lines yet.
            lines: lines,
            date: _date(sale['created_at']) ?? DateTime.now(),
          );
        }(),
  ];
}

/// GET gym/dashboard -> home screen numbers; null when the answer has no data.
ServerDashboard? mapDashboard(Object? body) {
  final d = body is Map && body['data'] is Map ? (body['data'] as Map).cast<String, dynamic>() : null;
  if (d == null) return null;
  String? opt(Object? v) => _s(v).isEmpty ? null : _s(v);
  return ServerDashboard(
    businessName: _s(d['business_name']),
    activeMembers: _i(d['active_members']),
    revenueToday: _d(d['revenue_today']),
    openDebt: _d(d['open_debt']),
    debts: [
      for (final x in _list(d['debts']))
        DebtItem(
          kind: _s(x['kind']) == 'unpaid_invoice' ? DebtKind.unpaidInvoice : DebtKind.failedCharge,
          id: _s(x['id']),
          amount: _d(x['amount']),
          customerName: _s(x['customer_name']),
          customerId: opt(x['customer_id']),
          subscriptionId: opt(x['subscription_id']),
          saleId: opt(x['sale_id']),
          reference: opt(x['reference_no']),
          description: opt(x['description']),
          date: _date(x['date']),
        ),
    ],
    expiring: [
      for (final x in _list(d['expiring']))
        if (_date(x['end_date']) != null)
          ExpiringMembership(
            subscriptionId: _s(x['subscription_id']),
            customerId: opt(x['customer_id']),
            customerName: _s(x['customer_name']),
            planName: _s(x['plan_name']),
            endDate: _date(x['end_date'])!,
          ),
    ],
    recentPayments: [
      for (final x in _list(d['recent_payments']))
        RecentPayment(
          id: _s(x['id']),
          amount: _d(x['amount']),
          method: _payMethod(x['paying_method']),
          methodName: _s(x['paying_method']),
          saleId: opt(x['sale_id']),
          reference: opt(x['reference_no']),
          customerName: opt(x['customer_name']),
          date: _date(x['created_at']),
        ),
    ],
    documentsMonth: _i(d['documents_month']),
  );
}

/// One page of GET gym/sales -> receipts (all staff, from a date; see GymController::sales).
/// [names] is used when a product has no name in the answer.
List<Receipt> mapGymSales(Object? body, {Map<String, String> names = const {}}) {
  final data = body is Map ? body['data'] : null;
  return [
    for (final d in _list(data))
      () {
        final products = _list(d['products']);
        final description = products
            .map((p) => _s(p['name']).isNotEmpty ? _s(p['name']) : (names[_s(p['id'])] ?? '#${_s(p['id'])}'))
            .toSet()
            .join(', ');
        final lines = [
          for (final p in _list(d['payments']))
            if (_d(p['amount']) != 0)
              PaymentLine(
                method: _payMethod(p['paying_method']),
                amount: _d(p['amount']),
                cheques: 1,
                cheque: _payMethod(p['paying_method']) == PayMethod.cheque
                    ? ChequeDetails(
                        number: _s(p['cheque_number']),
                        bank: _s(p['cheque_bank']),
                        branch: _s(p['cheque_branch']),
                        firstDate: _date(p['cheque_date']) ?? _date(p['created_at']),
                      )
                    : null,
              ),
        ];
        final subscriptionId = _s(d['subscription_id']);
        return Receipt(
          number: _i(d['id']),
          reference: _s(d['reference_no']).isEmpty ? '#${_s(d['id'])}' : _s(d['reference_no']),
          kind: _b(d['is_credit'])
              ? ReceiptKind.credit
              : subscriptionId.isNotEmpty
                  ? ReceiptKind.subscription
                  : ReceiptKind.quickPay,
          customerId: d['customer_id'] == null ? null : _s(d['customer_id']),
          customerName: _s(d['customer_name']),
          subscriptionId: subscriptionId.isEmpty ? null : subscriptionId,
          description: description,
          lines: lines,
          date: _date(d['created_at']) ?? DateTime.now(),
          docType: d['type'] == null ? null : _i(d['type']),
          docTotal: d['grand_total'] == null ? null : _d(d['grand_total']),
          vat: d['total_tax'] == null ? null : _d(d['total_tax']),
          cancelled: _b(d['is_cancelled']),
          allocationNumber: _s(d['allocation_number']).isEmpty ? null : _s(d['allocation_number']),
        );
      }(),
  ];
}
