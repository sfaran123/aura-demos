// Loads the gym data from the AURA server into the store (read only for now:
// changes made in the app are not sent to the server yet, and the next sync
// replaces them with the server's data).

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/sale_builder.dart';
import '../integration/aura_api.dart';
import '../integration/server_mapping.dart';
import 'auth.dart';
import 'gym_store.dart';

class GymSync extends ChangeNotifier {
  GymSync({required this.auth, required this.store, this.maxSalePages = 10, this.maxGymSalePages = 40});

  final AuthController auth;
  final GymStore store;

  /// Names the business whose data the store holds ([GymStore.serverOwner]).
  static String ownerKey(AuraWorkspace ws) => '${ws.company}.${ws.domain}';

  /// GET /api/sales returns 10 sales a page; the last [maxSalePages] pages are loaded.
  final int maxSalePages;

  /// GET /api/gym/sales returns 300 documents a page; at most this many pages (12,000 documents).
  final int maxGymSalePages;

  bool _syncing = false;
  Object? _error;
  Future<void>? _running;

  bool get syncing => _syncing;
  /// When the data on the screen last came from the server (kept between runs).
  DateTime? get lastSynced => store.lastSynced;

  /// A server that does not have this endpoint yet (404). Any other failure is a
  /// real error: it is shown, never covered by numbers worked out in the app.
  static bool _missing(AuraApiException e) => e.kind == AuraErrorKind.server && e.detail.startsWith('HTTP 404');

  /// The last failure (an [AuraApiException] or anything else); null after a successful sync.
  Object? get error => _error;

  /// Creates a member (a web customer) with the POS app's endpoint, POST /api/customer/store.
  /// When a customer with the same phone already exists on the server, that one
  /// is returned with [existing] true and nothing is created.
  Future<({Customer customer, bool existing})> addMember({
    required String name,
    required String phone,
    String? idNumber,
  }) async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    try {
      final body = await auth.api.postJson(ws, session, '/customer/store', {
        'name': name,
        'phone_number': phone,
        if (idNumber != null && idNumber.isNotEmpty) 'tax_no': idNumber,
        // Same as the POS app's "add customer".
        'customer_group_id': 1,
      });
      final data = body is Map && body['data'] is Map ? (body['data'] as Map) : null;
      final id = data?['id'];
      if (data == null || id == null) throw AuraApiException(AuraErrorKind.server, 'Unexpected answer');
      final existing = body is Map && body['if_existing'] == true;
      final tax = '${data['tax_no'] ?? ''}';
      final customer = store.upsertCustomer(Customer(
        id: '$id',
        name: '${data['name'] ?? name}',
        phone: '${data['phone_number'] ?? phone}',
        idNumber: tax.isEmpty ? null : tax,
      ));
      return (customer: customer, existing: existing);
    } on AuraApiException catch (e) {
      // This endpoint answers 403 "Access denied" only when the token is not accepted.
      final expired = e.kind == AuraErrorKind.sessionExpired || e.kind == AuraErrorKind.forbidden;
      if (expired) {
        await auth.signOut(expired: true);
        throw AuraApiException(AuraErrorKind.sessionExpired);
      }
      rethrow;
    }
  }

  /// Opens a membership on the server (POST /api/gym/memberships): the web
  /// subscription only, no sale, invoice or payment (the payment part stays in
  /// the app for now). Returns it in the app's format with its open charges.
  Future<({Subscription sub, List<Charge> charges, bool duplicate})> createMembership({
    required Customer customer,
    required SubscriptionPlan plan,
    required DateTime start,
    required int discountPct,
    required bool waiveRegistration,
    RecurringMethod? recurring,
  }) async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    String two(int n) => n.toString().padLeft(2, '0');
    try {
      final body = await auth.api.postJson(ws, session, '/gym/memberships', {
        'customer_id': int.tryParse(customer.id) ?? customer.id,
        'plan_id': int.tryParse(plan.id) ?? plan.id,
        'start_date': '${start.year}-${two(start.month)}-${two(start.day)}',
        'discount_percent': discountPct,
        'registration_waived': waiveRegistration,
        if (plan.isRecurring)
          'recurring_method': switch (recurring) {
            RecurringMethod.standingOrder => 'bank_transfer',
            RecurringMethod.manual => 'manual',
            _ => 'credit_card',
          },
      });
      final row = body is Map ? body['data'] : null;
      final mapped = mapMemberships({
        'data': [row]
      }, customers: [...store.customers], plans: [...store.plans], today: store.today);
      if (row is! Map || mapped.subscriptions.isEmpty) {
        throw AuraApiException(AuraErrorKind.server, 'Unexpected answer');
      }
      return (
        sub: mapped.subscriptions.single,
        charges: mapped.charges,
        duplicate: body is Map && body['duplicate'] == true,
      );
    } on AuraApiException catch (e) {
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// Freezes a membership on the server for [days] days from today.
  Future<Subscription> freezeMembership(Subscription sub, int days) =>
      _membershipAction(sub, 'freeze', {'days': days});

  /// Ends the current freeze today; the unused days are given back.
  Future<Subscription> unfreezeMembership(Subscription sub) => _membershipAction(sub, 'unfreeze', {});

  /// Schedules the cancellation on the server (notice, commitment, prepaid month).
  Future<Subscription> cancelMembership(Subscription sub, {String? reason}) =>
      _membershipAction(sub, 'cancel', {if (reason != null && reason.isNotEmpty) 'reason': reason});

  /// POST gym/memberships/{id}/{action}; the answer replaces the membership and its charges in the app.
  Future<Subscription> _membershipAction(Subscription sub, String action, Map<String, Object?> body) async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    try {
      final res = await auth.api.postJson(ws, session, '/gym/memberships/${sub.id}/$action', body);
      final row = res is Map ? res['data'] : null;
      final mapped = mapMemberships({
        'data': [row]
      }, customers: [...store.customers], plans: [...store.plans], today: store.today);
      if (row is! Map || mapped.subscriptions.isEmpty) {
        throw AuraApiException(AuraErrorKind.server, 'Unexpected answer');
      }
      return store.replaceServerMembership(mapped.subscriptions.single, mapped.charges);
    } on AuraApiException catch (e) {
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// Records on the server that [c] was paid at the desk with [method] ([line]
  /// has the cheque or transfer details), then loads everything again:
  ///  - a failed month or a manual monthly payment: a tax invoice-receipt with the
  ///    payment (POST gym/memberships/{id}/collect);
  ///  - an unpaid membership invoice: the payment is added to it (POST gym/sales/{id}/payments).
  /// A card is recorded as taken on another terminal. Returns the document number.
  Future<String> collectCharge(Charge c, PayMethod method, {PaymentLine? line}) async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final details = <String, Object?>{
      'method': switch (method) {
        PayMethod.cash => 'cash',
        PayMethod.card => 'card',
        PayMethod.cheque => 'cheque',
        _ => 'bank',
      },
      if (method == PayMethod.cheque && line != null) ...{
        'cheque_number': line.cheque.number,
        'cheque_bank': line.cheque.bank,
        'cheque_branch': line.cheque.branch,
        'cheque_account': line.cheque.account,
        'cheque_date': day(line.cheque.firstDate ?? store.today),
      },
      if (method == PayMethod.bank && line != null) ...{
        'transfer_reference': line.transfer.reference,
        'transfer_bank': line.transfer.bank,
        if (line.transfer.date != null) 'transfer_date': day(line.transfer.date!),
      },
    };
    try {
      final String reference;
      if (c.id.startsWith('sale-') && c.serverRef != null) {
        final res = await auth.api.postJson(ws, session, '/gym/sales/${c.serverRef}/payments', details);
        final sale = res is Map && res['sale'] is Map ? res['sale'] as Map : null;
        reference = '${sale?['reference_no'] ?? ''}';
      } else {
        final body = {
          ...details,
          if (c.serverRef != null) 'month_key': c.serverRef else 'due_date': day(c.dueDate),
        };
        final res = await auth.api.postJson(ws, session, '/gym/memberships/${c.subscriptionId}/collect', body);
        final doc = res is Map && res['document'] is Map ? res['document'] as Map : null;
        reference = '${doc?['reference_no'] ?? ''}';
      }
      // Paid on the server: off the list now; the sync brings the document and the next month.
      c
        ..status = ChargeStatus.paid
        ..paidWith = method
        ..paidAt = store.now;
      store.touch();
      await pull();
      return reference;
    } on AuraApiException catch (e) {
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// How this server saves a sale (GET gym/pos-settings); loaded once per sign-in.
  Future<PosSettings> posSettings() async {
    final cached = store.posSettings;
    if (cached != null) return cached;
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    try {
      final body = await auth.api.getJson(ws, session, '/gym/pos-settings');
      final data = body is Map && body['data'] is Map ? body['data'] as Map : null;
      if (data == null) throw AuraApiException(AuraErrorKind.server, 'Unexpected answer');
      return store.posSettings = PosSettings.fromJson(data);
    } on AuraApiException catch (e) {
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// Saves a paid sale as the POS app does (POST sales/store-v2): the document
  /// with its lines and payments. [appUuid] stays the same when the save is
  /// tried again: the server then answers 409 and saves nothing twice, and
  /// [saleId] is null (the sale is found by its app_uuid).
  Future<({int? saleId, String reference})> saveSale({
    required List<SaleLine> lines,
    required List<PaymentLine> payments,
    required String appUuid,
    Customer? customer,
    String? note,
  }) async {
    final pos = await posSettings();
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    final body = storeV2Body(
      pos: pos,
      lines: lines,
      payments: payments,
      appUuid: appUuid,
      now: store.now,
      customerId: customer == null ? null : int.tryParse(customer.id),
      note: note,
    );
    try {
      final res = await auth.api.postJson(ws, session, '/sales/store-v2', body);
      final sale = res is Map && res['data'] is Map ? res['data'] as Map : null;
      final id = sale?['id'];
      if (sale == null || id == null) throw AuraApiException(AuraErrorKind.server, 'Unexpected answer');
      return (saleId: id is num ? id.toInt() : int.tryParse('$id'), reference: '${sale['reference_no'] ?? ''}');
    } on AuraApiException catch (e) {
      // Already saved by an earlier try whose answer was lost.
      if (e.kind == AuraErrorKind.server && e.detail.startsWith('HTTP 409')) return (saleId: null, reference: '');
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// Makes the saved sale the membership's sale (POST gym/memberships/{id}/link-sale),
  /// by its id, else by its app_uuid. Returns the sale's document number.
  Future<String> linkSale(String membershipId, {int? saleId, required String appUuid}) async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) throw AuraApiException(AuraErrorKind.sessionExpired);
    try {
      final res = await auth.api.postJson(ws, session, '/gym/memberships/$membershipId/link-sale',
          saleId != null ? {'sale_id': saleId} : {'app_uuid': appUuid});
      final sale = res is Map && res['sale'] is Map ? res['sale'] as Map : null;
      return '${sale?['reference_no'] ?? ''}';
    } on AuraApiException catch (e) {
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
      rethrow;
    }
  }

  /// Loads everything. A second call while one is running waits for that one.
  Future<void> pull() => _running ??= _pull().whenComplete(() => _running = null);

  Future<void> _pull() async {
    final ws = auth.workspace, session = auth.session;
    if (ws == null || session == null) return;
    _syncing = true;
    _error = null;
    notifyListeners();
    try {
      Future<Object?> get(String path, [Map<String, String>? q]) => auth.api.getJson(ws, session, path, query: q);

      // How a sale is saved here; a server without the endpoint yet keeps it null
      // (taking payments then stops with a message).
      try {
        final pos = await get('/gym/pos-settings');
        if (pos is Map && pos['data'] is Map) store.posSettings = PosSettings.fromJson(pos['data'] as Map);
      } on AuraApiException catch (e) {
        if (!_missing(e)) rethrow;
      }

      final results = await Future.wait([get('/gym/members'), get('/gym/plans'), get('/gym/memberships')]);
      final customers = mapMembers(results[0]);
      final plans = mapPlans(results[1]);
      final memberships = mapMemberships(results[2], customers: customers, plans: plans, today: store.today);

      // Same product list as the POS app: the user's warehouse, else the POS default.
      var warehouseId = session.warehouseId;
      if (warehouseId == null) {
        final pos = await get('/sales/get-data-for-pos');
        final setting = pos is Map && pos['data'] is Map ? (pos['data'] as Map)['pos_setting'] : null;
        final w = setting is Map ? setting['warehouse_id'] : null;
        warehouseId = w is num ? w.toInt() : int.tryParse('${w ?? ''}');
      }
      final items = warehouseId == null
          ? <ShopItem>[]
          : mapProducts(await get('/sales/getproduct-v2', {'warehouse_id': '$warehouseId'}),
              planIds: {for (final p in plans) p.id});

      final names = {for (final p in plans) p.id: p.name, for (final i in items) i.id: i.name};
      // Sales for the reports and the sales list: all staff, from the 1st of the
      // month 5 months ago (the summary's 6-month trend), every page.
      final receipts = <Receipt>[];
      final today = store.today;
      final from = DateTime(today.year, today.month - 5, 1);
      String two(int n) => n.toString().padLeft(2, '0');
      try {
        for (var page = 1; page <= maxGymSalePages; page++) {
          final body = await get('/gym/sales', {'from': '${from.year}-${two(from.month)}-01', 'page': '$page'});
          receipts.addAll(mapGymSales(body, names: names));
          final last = body is Map && body['last_page'] is num ? (body['last_page'] as num).toInt() : 1;
          if (page >= last) break;
        }
      } on AuraApiException catch (e) {
        // A server without gym/sales yet: the POS app's list (this user's, latest pages).
        if (!_missing(e)) rethrow;
        receipts.clear();
        for (var page = 1; page <= maxSalePages; page++) {
          final body = await get('/sales', {'page': '$page'});
          receipts.addAll(mapSales(body, names: names));
          final data = body is Map ? body['data'] : null;
          final last = data is Map && data['last_page'] is num ? (data['last_page'] as num).toInt() : 1;
          if (page >= last) break;
        }
      }

      // Home screen numbers. A server without this endpoint yet (404) keeps the
      // home screen on the numbers worked out in the app.
      Map<String, dynamic>? dashboard;
      try {
        final body = await get('/gym/dashboard', {'expiring_days': '${store.settings.renewalReminderDaysBefore}'});
        if (body is Map) dashboard = body.cast<String, dynamic>();
      } on AuraApiException catch (e) {
        if (!_missing(e)) rethrow;
      }

      // Signed out, or another user or business signed in, while this was loading:
      // the answer belongs to nobody on the screen now.
      final nowWs = auth.workspace;
      if (auth.session?.token != session.token || nowWs == null || ownerKey(nowWs) != ownerKey(ws)) return;

      store.lastSynced = DateTime.now();
      store.applyServerData(
        owner: ownerKey(ws),
        dashboardJson: dashboard,
        customers: customers,
        plans: plans,
        subscriptions: memberships.subscriptions,
        // Plus the unpaid membership invoices, so they can be collected too.
        charges: [...memberships.charges, ...invoiceCharges(mapDashboard(dashboard), memberships.subscriptions)],
        items: items,
        receipts: receipts,
      );
    } on AuraApiException catch (e) {
      _error = e;
      if (e.kind == AuraErrorKind.sessionExpired) await auth.signOut(expired: true);
    } catch (e) {
      _error = e;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }
}
