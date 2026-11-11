// Home screen numbers from the AURA server (GET /api/gym/dashboard). Pure Dart.

import 'models.dart';

enum DebtKind { failedCharge, unpaidInvoice }

class DebtItem {
  DebtItem({
    required this.kind,
    required this.id,
    required this.amount,
    required this.customerName,
    this.customerId,
    this.subscriptionId,
    this.saleId,
    this.reference,
    this.description,
    this.date,
  });

  final DebtKind kind;
  final String id;
  final double amount;
  final String customerName;
  final String? customerId;
  final String? subscriptionId;
  final String? saleId;
  final String? reference;
  final String? description;
  final DateTime? date;
}

class ExpiringMembership {
  ExpiringMembership({
    required this.subscriptionId,
    required this.customerName,
    required this.planName,
    required this.endDate,
    this.customerId,
  });

  final String subscriptionId;
  final String? customerId;
  final String customerName;
  final String planName;
  final DateTime endDate;
}

class RecentPayment {
  RecentPayment({
    required this.id,
    required this.amount,
    required this.method,
    required this.methodName,
    this.saleId,
    this.reference,
    this.customerName,
    this.date,
  });

  final String id;
  final double amount;
  final PayMethod method;

  /// The method as the server names it (e.g. "Gift Card"), for methods the app has no icon for.
  final String methodName;
  final String? saleId;
  final String? reference;
  final String? customerName;
  final DateTime? date;
}

class ServerDashboard {
  ServerDashboard({
    required this.businessName,
    required this.activeMembers,
    required this.revenueToday,
    required this.openDebt,
    required this.debts,
    required this.expiring,
    required this.recentPayments,
    required this.documentsMonth,
  });

  final String businessName;
  final int activeMembers;
  final double revenueToday;
  final double openDebt;
  final List<DebtItem> debts;
  final List<ExpiringMembership> expiring;
  final List<RecentPayment> recentPayments;
  final int documentsMonth;
}
