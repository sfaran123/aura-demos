// In-memory store with sample data. In the AURA app this is replaced by an
// implementation that calls the AURA API; screens only talk to GymStore.

import 'dart:async';

import '../domain/checkout.dart';
import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/notifier.dart';
import '../domain/sale_builder.dart' show PosSettings;
import '../domain/settings.dart';
import '../domain/dashboard.dart';
import '../domain/visits.dart';
import '../integration/repository.dart';
import '../integration/server_mapping.dart' show mapDashboard;
import 'demo_data.dart';

class GymStore extends SimpleNotifier {
  /// [repository] keeps the data between runs: it is loaded here and saved
  /// after every change. Without one (tests), everything stays in memory.
  GymStore({DateTime Function()? clock, bool seed = true, this.repository}) : _clock = clock ?? DateTime.now {
    final saved = repository?.load();
    if (saved != null && _fromJson(saved)) return;
    if (seed) _seed();
  }

  final GymRepository? repository;
  Timer? _saveTimer;

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (repository != null) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 400), save);
    }
  }

  /// Writes the snapshot now (also called 0.4 s after every change).
  Future<void> save() async {
    _saveTimer?.cancel();
    try {
      await repository?.save(toJson());
      lastSaveError = null;
    } catch (e) {
      lastSaveError = '$e'; // Shown nowhere yet; the backend version reports sync errors.
    }
  }

  /// The last save failure, if any.
  String? lastSaveError;

  /// Everything the app holds, as JSON. This is also the data contract for
  /// the AURA backend (see HANDOFF.md).
  Map<String, dynamic> toJson() => {
        'version': 1,
        'language': L10n.lang.name,
        'receiptNo': _receiptNo,
        'idCounter': _id,
        'settings': settings.toJson(),
        'plans': [for (final x in plans) x.toJson()],
        'customers': [for (final x in customers) x.toJson()],
        'subscriptions': [for (final x in subscriptions) x.toJson()],
        'charges': [for (final x in charges) x.toJson()],
        'receipts': [for (final x in receipts) x.toJson()],
        'links': [for (final x in links) x.toJson()],
        'visits': [for (final x in visits) x.toJson()],
        'items': [for (final x in items) x.toJson()],
        if (_dashboardJson != null) 'dashboard': _dashboardJson,
        if (serverOwner != null) 'serverOwner': serverOwner,
        'serverLoaded': serverLoaded,
        if (lastSynced != null) 'lastSynced': lastSynced!.toIso8601String(),
      };

  /// Signed in: when the data last came from the server.
  DateTime? lastSynced;

  /// Signed in: the business whose data and settings are in the store
  /// ("company.domain"). Null in the demo.
  String? serverOwner;

  /// Signed in: the data of [serverOwner] has been loaded from the server.
  /// Until then the app shows a loading screen, never demo or old data.
  bool serverLoaded = false;

  /// Removes members, plans, memberships, charges, documents, links and the
  /// price list, from the screen and from the device: at sign-out, and before
  /// another business's data is loaded. [settings] also puts the business
  /// settings back to their defaults (another business signs in). The language stays.
  void clearServerData({bool settings = false, String? owner}) {
    for (final l in [plans, customers, subscriptions, charges, receipts, links]) {
      l.clear();
    }
    items = [];
    if (settings || owner != null) {
      visits.clear();
    } else {
      visits.removeWhere((v) => !v.local);
    }
    dashboard = null;
    _dashboardJson = null;
    posSettings = null;
    serverLoaded = false;
    lastSynced = null;
    if (settings) this.settings = BusinessSettings();
    if (owner != null) serverOwner = owner;
    notifyListeners();
  }

  bool _fromJson(Map<String, dynamic> j) {
    try {
      List<Map<String, dynamic>> l(String k) =>
          [for (final x in (j[k] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      final s = BusinessSettings.fromJson((j['settings'] as Map).cast<String, dynamic>());
      final p = [for (final x in l('plans')) SubscriptionPlan.fromJson(x)];
      final c = [for (final x in l('customers')) Customer.fromJson(x)];
      final su = [for (final x in l('subscriptions')) Subscription.fromJson(x)];
      final ch = [for (final x in l('charges')) Charge.fromJson(x)];
      final r = [for (final x in l('receipts')) Receipt.fromJson(x)];
      final li = [for (final x in l('links')) SignupLink.fromJson(x)];
      final it = [for (final x in l('items')) ShopItem.fromJson(x)];
      final vi = [for (final x in l('visits')) Visit.fromJson(x)];
      settings = s;
      plans
        ..clear()
        ..addAll(p);
      customers
        ..clear()
        ..addAll(c);
      subscriptions
        ..clear()
        ..addAll(su);
      charges
        ..clear()
        ..addAll(ch);
      receipts
        ..clear()
        ..addAll(r);
      links
        ..clear()
        ..addAll(li);
      items = it;
      visits
        ..clear()
        ..addAll(vi);
      _dashboardJson = j['dashboard'] is Map ? (j['dashboard'] as Map).cast<String, dynamic>() : null;
      serverOwner = j['serverOwner'] is String ? j['serverOwner'] as String : null;
      serverLoaded = j['serverLoaded'] == true;
      dashboard = _withoutOldDebts(mapDashboard(_dashboardJson));
      lastSynced = j['lastSynced'] is String ? DateTime.tryParse(j['lastSynced'] as String) : null;
      _receiptNo = j['receiptNo'] ?? (r.isEmpty ? 30000 : r.map((x) => x.number).reduce((a, b) => a > b ? a : b));
      _id = j['idCounter'] ?? 1000;
      L10n.lang = AppLang.values.asNameMap()[j['language']] ?? L10n.lang;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Back to the demo data (the saved data is replaced).
  void resetDemo() {
    dashboard = null;
    _dashboardJson = null;
    serverOwner = null;
    serverLoaded = false;
    for (final l in [plans, customers, subscriptions, charges, receipts, links]) {
      l.clear();
    }
    settings = BusinessSettings();
    visits.clear();
    items = [..._defaultItems];
    _id = 100;
    _seed();
    notifyListeners();
  }

  /// Replaces members, plans, memberships, charges, the price list and the
  /// sales with the data from the AURA server, in one change. Business settings,
  /// language and sign-up links stay as they are on the device.
  void applyServerData({
    required List<Customer> customers,
    required List<SubscriptionPlan> plans,
    required List<Subscription> subscriptions,
    required List<Charge> charges,
    required List<ShopItem> items,
    required List<Receipt> receipts,
    Map<String, dynamic>? dashboardJson,
    String? owner,
    List<Visit>? visits,
  }) {
    if (owner != null) serverOwner = owner;
    serverLoaded = true;
    this.plans
      ..clear()
      ..addAll(plans);
    this.customers
      ..clear()
      ..addAll(customers);
    this.subscriptions
      ..clear()
      ..addAll(subscriptions);
    this.charges
      ..clear()
      ..addAll(charges);
    this.receipts
      ..clear()
      ..addAll(receipts..sort((a, b) => a.date.compareTo(b.date)));
    this.items = items;
    // The server's visits replace the ones it sent before; visits kept on this
    // device only stay. Null: a server without visits yet, nothing changes.
    if (visits != null) {
      this.visits
        ..removeWhere((v) => !v.local)
        ..addAll(visits);
    }
    _dashboardJson = dashboardJson;
    dashboard = _withoutOldDebts(mapDashboard(dashboardJson));
    notifyListeners();
  }

  /// Home screen numbers from the AURA server; null when not signed in (or not synced yet).
  ServerDashboard? dashboard;
  Map<String, dynamic>? _dashboardJson;

  /// Signed in: how the AURA server saves a sale (GET gym/pos-settings), loaded by the sync.
  /// Null in the demo: payments are then recorded in the app only.
  /// Its business type sets the document the app issues, as the POS app: an
  /// exempt dealer (1) gets receipts, every other business tax invoice-receipts.
  PosSettings? get posSettings => _posSettings;
  PosSettings? _posSettings;
  set posSettings(PosSettings? v) {
    _posSettings = v;
    if (v != null) settings.docType = DocTypeLabel.forBusinessType(v.businessType);
  }

  final DateTime Function() _clock;
  DateTime get now => _clock();
  DateTime get today => dateOnly(now);

  BusinessSettings settings = BusinessSettings();
  final List<SubscriptionPlan> plans = [];
  final List<Customer> customers = [];
  final List<Subscription> subscriptions = [];
  final List<Charge> charges = [];
  final List<Receipt> receipts = [];
  final List<SignupLink> links = [];
  int _receiptNo = 30187;
  int _id = 100;
  String _next(String p) => '$p${_id++}';

  List<ShopItem> items = [..._defaultItems];

  static final List<ShopItem> _defaultItems = [
    ShopItem('water', t('בקבוק מים'), 8),
    ShopItem('shake', t('שייק חלבון'), 22),
    ShopItem('pt', t('אימון אישי'), 180),
    ShopItem('towel', t('מגבת'), 30),
    ShopItem('locker', t('לוקר חודשי'), 40),
    ShopItem('day', t('כניסה חד-פעמית'), 60),
  ];

  void touch() => notifyListeners();

  /// Adds a product to the price list, or updates the one with the same id.
  void saveItem(ShopItem item) {
    final i = items.indexWhere((x) => x.id == item.id);
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(ShopItem(item.id.isEmpty ? _next('item') : item.id, item.name, item.price,
          taxRate: item.taxRate, taxMethod: item.taxMethod));
    }
    notifyListeners();
  }

  void removeItem(String id) {
    items.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  AppLang get language => L10n.lang;

  void setLanguage(AppLang l) {
    L10n.lang = l;
    for (final c in customers) {
      c.name = retranslate(c.name);
    }
    for (final p in plans) {
      p.name = retranslate(p.name);
      if (p.badge != null) p.badge = retranslate(p.badge!);
    }
    for (final l in links) {
      l.sentTo = retranslate(l.sentTo);
    }
    for (final r in receipts) {
      r.customerName = retranslate(r.customerName);
    }
    items = [
      for (final i in items) ShopItem(i.id, retranslate(i.name), i.price, taxRate: i.taxRate, taxMethod: i.taxMethod)
    ];
    notifyListeners();
  }

  // ---------- lookups ----------
  SubscriptionPlan? plan(String id) => plans.where((p) => p.id == id).firstOrNull;
  Customer? customer(String id) => customers.where((c) => c.id == id).firstOrNull;
  List<SubscriptionPlan> get activePlans => plans.where((p) => p.active).toList();

  Subscription? currentSubscription(String customerId) {
    final list = subscriptions
        .where((s) => s.customerId == customerId && s.status != SubStatus.cancelled && s.status != SubStatus.expired)
        .toList();
    return list.isEmpty ? null : list.last;
  }

  List<Customer> searchCustomers(String q) {
    final t = q.trim();
    if (t.isEmpty) return customers.reversed.toList();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return customers
        .where((c) =>
            c.name.toLowerCase().contains(t.toLowerCase()) ||
            (digits.isNotEmpty && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
        .toList();
  }

  /// A failed charge counts as a debt to collect for this many months. A business
  /// that worked for years on the web system brings every failed charge it ever
  /// had; the older ones are kept apart ("old debts") and are not in the totals.
  static const debtWindowMonths = 3;
  DateTime get debtCutoff => DateTime(today.year, today.month - debtWindowMonths, today.day);

  bool _inactive(String? subscriptionId) {
    final s = subscriptions.where((s) => s.id == subscriptionId).firstOrNull;
    return s != null && (s.status == SubStatus.cancelled || s.status == SubStatus.expired);
  }

  /// Signed in: a failed charge from before the window, or of a membership that is
  /// no longer active.
  bool isOldDebt(Charge c) =>
      serverLoaded &&
      c.status == ChargeStatus.failed &&
      (c.dueDate.isBefore(debtCutoff) || _inactive(c.subscriptionId));

  /// Old failed charges, newest first: shown apart on the collection screen.
  List<Charge> get oldDebts =>
      charges.where((c) => c.isOpen() && isOldDebt(c)).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));

  /// The server's home-screen numbers without the old debts, so the home screen,
  /// the collection list and the reports show the same total.
  ServerDashboard? _withoutOldDebts(ServerDashboard? d) {
    if (d == null) return null;
    bool old(DebtItem x) =>
        x.kind == DebtKind.failedCharge &&
        ((x.date != null && x.date!.isBefore(debtCutoff)) || (x.subscriptionId != null && _inactive(x.subscriptionId)));
    final dropped = d.debts.where(old).fold(0.0, (a, x) => a + x.amount);
    if (dropped == 0) return d;
    final left = round2(d.openDebt - dropped);
    return ServerDashboard(
      businessName: d.businessName,
      activeMembers: d.activeMembers,
      revenueToday: d.revenueToday,
      openDebt: left < 0 ? 0 : left,
      debts: d.debts.where((x) => !old(x)).toList(),
      expiring: d.expiring,
      recentPayments: d.recentPayments,
      documentsMonth: d.documentsMonth,
    );
  }

  /// Open manual charges and failed automatic charges, oldest first.
  List<Charge> get toCollect {
    final l = charges
        .where((c) => c.isOpen() && (c.manual || c.status == ChargeStatus.failed))
        .where((c) => !isOldDebt(c))
        .where((c) => !c.dueDate.isAfter(today.add(Duration(days: settings.manualReminderDaysBefore))))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return l;
  }

  /// Manual monthly payments whose date is still ahead of the reminder window,
  /// soonest first: the rest of the members in manual collection, so the
  /// collection screen lists every one of them with the date of the next payment.
  List<Charge> get upcomingManual {
    final edge = today.add(Duration(days: settings.manualReminderDaysBefore));
    return charges
        .where((c) => c.isOpen() && c.manual && c.status != ChargeStatus.failed && c.dueDate.isAfter(edge))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  double get openDebt => round2(toCollect.where((c) => !c.dueDate.isAfter(today)).fold(0.0, (a, c) => a + c.amount));

  int get activeCount => subscriptions.where((s) => s.status == SubStatus.active).length;

  double get todayRevenue =>
      round2(receipts.where((r) => dateOnly(r.date) == today).fold(0.0, (a, r) => a + r.collectedNow));

  List<Subscription> get expiringSoon => subscriptions
      .where((s) =>
          s.status == SubStatus.active &&
          s.end != null &&
          !s.end!.isBefore(today) &&
          s.end!.difference(today).inDays <= settings.renewalReminderDaysBefore)
      .toList();

  // ---------- check-in ----------
  /// Visits recorded at the desk, oldest first.
  final List<Visit> visits = [];

  /// Today's visits, latest first.
  List<Visit> get visitsToday =>
      visits.where((v) => dateOnly(v.at) == today).toList()..sort((a, b) => b.at.compareTo(a.at));

  /// A membership's visits, latest first.
  List<Visit> visitsOf(String subscriptionId) =>
      visits.where((v) => v.subscriptionId == subscriptionId).toList()..sort((a, b) => b.at.compareTo(a.at));

  /// The week of a weekly limit starts on Sunday.
  DateTime get weekStart => today.subtract(Duration(days: today.weekday % 7));
  int visitsThisWeek(String subscriptionId) =>
      visits.where((v) => v.subscriptionId == subscriptionId && !v.at.isBefore(weekStart)).length;

  /// Entries left on a punch card: the membership's number less the visits kept
  /// on this device only. Null for a membership without entries.
  int? entriesLeft(Subscription s) {
    if (s.entriesLeft == null) return null;
    final left = s.entriesLeft! - visits.where((v) => v.local && v.subscriptionId == s.id).length;
    return left < 0 ? 0 : left;
  }

  /// What is left after a visit, for the row and the confirmation: "6 entries
  /// left", "2 of 3 this week", or nothing for an unlimited membership.
  String visitBalance(Subscription s) {
    final p = plan(s.planId);
    final left = entriesLeft(s);
    if (left != null) {
      return left == 0
          ? t('לא נשארו כניסות')
          : left == 1
              ? t('נשארה כניסה אחת')
              : t('נשארו {0} כניסות', [left]);
    }
    if (p != null && p.weeklyLimit > 0) return t('{0} מתוך {1} השבוע', [visitsThisWeek(s.id), p.weeklyLimit]);
    return '';
  }

  /// May [c] come in now? The first reason that blocks, else the first warning.
  /// With several running memberships: the one that lets the member in (an
  /// unlimited one before a punch card, so no entry is spent for nothing).
  EntryCheck entryCheck(Customer c) {
    final all = entryChecks(c);
    if (all.isEmpty) {
      final had = subscriptions.any((s) => s.customerId == c.id);
      return EntryCheck(
          level: EntryLevel.blocked, message: had ? t('המנוי הסתיים') : t('אין מנוי'), fix: EntryFix.renew);
    }
    int rank(EntryCheck x) => x.level.index * 2 + (x.subscription?.entriesLeft == null ? 0 : 1);
    return all.reduce((a, b) => rank(b) < rank(a) ? b : a);
  }

  /// One answer per running membership of [c] (not cancelled, not ended).
  List<EntryCheck> entryChecks(Customer c) => [
        for (final s in subscriptions)
          if (s.customerId == c.id && s.status != SubStatus.cancelled && s.status != SubStatus.expired)
            entryCheckOn(c, s),
      ];

  /// May [c] come in now on the membership [sub]?
  EntryCheck entryCheckOn(Customer c, Subscription sub) {
    final p = plan(sub.planId);
    final left = entriesLeft(sub);
    final already = visitsToday.any((v) => v.subscriptionId == sub.id);
    EntryCheck res(EntryLevel level, String message, [EntryFix fix = EntryFix.none]) =>
        EntryCheck(level: level, message: message, subscription: sub, fix: fix, alreadyToday: already);

    if (sub.status == SubStatus.frozen) {
      return res(EntryLevel.blocked,
          sub.frozenUntil == null ? t('המנוי מוקפא') : t('המנוי מוקפא עד {0}', [fmtDate(sub.frozenUntil!)]));
    }
    if (sub.status == SubStatus.pendingPayment) {
      return res(EntryLevel.blocked, t('המנוי ממתין לתשלום'), EntryFix.collect);
    }
    if (sub.end != null && sub.end!.isBefore(today)) {
      return res(EntryLevel.blocked, t('המנוי הסתיים ב-{0}', [fmtDate(sub.end!)]), EntryFix.renew);
    }
    if (left != null && left <= 0) return res(EntryLevel.blocked, t('הכרטיסייה נגמרה'), EntryFix.renew);
    if (p != null && p.weeklyLimit > 0 && visitsThisWeek(sub.id) >= p.weeklyLimit) {
      return res(EntryLevel.blocked, t('נוצלו כל {0} הכניסות של השבוע', [p.weeklyLimit]));
    }
    if (entryBlocked(c.id)) return res(EntryLevel.blocked, t('כניסה חסומה: תשלום באיחור'), EntryFix.collect);

    if (left == 1) return res(EntryLevel.warn, t('כניסה אחרונה בכרטיסייה'), EntryFix.renew);
    if (sub.status == SubStatus.paymentFailed || hasOverdue(sub.id)) {
      return res(EntryLevel.warn, t('יש תשלום פתוח'), EntryFix.collect);
    }
    if (sub.end != null && !sub.end!.isAfter(today.add(const Duration(days: 7)))) {
      return res(EntryLevel.warn, t('המנוי מסתיים ב-{0}', [fmtDate(sub.end!)]), EntryFix.renew);
    }
    return res(EntryLevel.ok, '');
  }

  /// Records a visit now. [local] is false when the server recorded it ([id] is its id there).
  Visit checkIn(Subscription sub, {String? id, bool local = true, DateTime? at}) {
    final v = Visit(
        id: id == null || id.isEmpty ? _next('v') : id,
        subscriptionId: sub.id,
        customerId: sub.customerId,
        at: at ?? now,
        local: local);
    visits.add(v);
    notifyListeners();
    return v;
  }

  /// Takes back a visit recorded by mistake: a punch card gets its entry back.
  void undoVisit(Visit v) {
    visits.removeWhere((x) => x.id == v.id);
    notifyListeners();
  }

  bool hasOverdue(String subscriptionId) =>
      charges.any((c) => c.subscriptionId == subscriptionId && c.isOpen() && c.daysOverdue(today) > 0);

  /// Entry is blocked when a charge is overdue past the grace period.
  bool entryBlocked(String customerId) {
    if (!settings.blockEntryWhenOverdue) return false;
    return charges.any((c) => c.customerId == customerId && c.isOpen() && c.daysOverdue(today) > settings.graceDays);
  }

  // ---------- actions ----------
  Customer addCustomer(String name, String phone, {String? idNumber}) {
    final c = Customer(id: _next('c'), name: name.trim(), phone: formatPhone(phone), idNumber: idNumber);
    customers.add(c);
    notifyListeners();
    return c;
  }

  /// Adds a member saved on the AURA server, or updates the one with the same id.
  Customer upsertCustomer(Customer c) {
    final i = customers.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      final old = customers[i];
      // The server's answer has no card or health details: keep what the app already knows.
      c.savedCardLast4 ??= old.savedCardLast4;
      c.healthDeclared = c.healthDeclared || old.healthDeclared;
      c.email ??= old.email;
      customers[i] = c;
    } else {
      customers.add(c);
    }
    notifyListeners();
    return c;
  }

  /// Demo (not signed in): the member's card is saved in the app only.
  void setCustomerCard(Customer c, String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    c.savedCardLast4 = d.length >= 4 ? d.substring(d.length - 4) : d;
    notifyListeners();
  }

  /// A plan as the AURA server saved it: replaces the app's copy, or is added.
  SubscriptionPlan putServerPlan(SubscriptionPlan p) {
    final i = plans.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      plans[i] = p;
    } else {
      plans.add(p);
    }
    notifyListeners();
    return p;
  }

  /// Saves a plan and returns the stored copy (new plans get an id).
  SubscriptionPlan savePlan(SubscriptionPlan p) {
    if (!p.isRecurring) p.prepayLastMonth = false;
    final i = plans.indexWhere((x) => x.id == p.id);
    late SubscriptionPlan saved;
    if (i >= 0) {
      plans[i] = saved = p;
    } else {
      plans.add(saved = p.copy(id: _next('p')));
    }
    notifyListeners();
    return saved;
  }

  Receipt _receipt(String name, String desc, List<PaymentLine> lines, ReceiptKind kind,
      {DateTime? at, String? customerId, String? subscriptionId, String? chargeId, String? reference, int? saleId}) {
    final no = ++_receiptNo;
    final r = Receipt(
        number: no,
        reference: reference,
        saleId: saleId,
        customerId: customerId,
        subscriptionId: subscriptionId,
        chargeId: chargeId,
        customerName: name,
        description: desc,
        kind: kind,
        lines: [
          for (final (i, l) in lines.indexed)
            l.copy()..transactionId = l.method == PayMethod.card ? (l.transactionId ?? 'TX-$no-${i + 1}') : null
        ],
        date: at ?? now);
    receipts.add(r);
    return r;
  }

  /// Schedules the monthly charge due on [due], unless the membership has
  /// ended by then. The last charge of a prepaid membership is already covered.
  void _schedule(Subscription sub, DateTime due, double amount, bool manual) {
    final end = sub.cancelEffective;
    if (end != null && !due.isBefore(end)) return;
    final covered = end != null && sub.prepaidAmount > 0 && !addMonths(due, 1).isBefore(end) && !_hasCovered(sub.id);
    charges.add(Charge(
      id: _next('ch'),
      subscriptionId: sub.id,
      customerId: sub.customerId,
      dueDate: due,
      amount: amount,
      manual: manual,
      status: covered ? ChargeStatus.covered : ChargeStatus.due,
    ));
    if (covered) sub.prepaidAmount = 0;
  }

  bool _hasCovered(String subId) => charges.any((c) => c.subscriptionId == subId && c.status == ChargeStatus.covered);

  /// Opens a subscription and issues one receipt for all payment lines.
  ({Subscription sub, Receipt receipt}) openSubscription({
    required Customer customer,
    required SubscriptionPlan plan,
    required StartOption start,
    required int discountPct,
    required bool waiveRegistration,
    required List<PaymentLine> lines,
    RecurringMethod? recurring,
    String? newCardLast4,
  }) {
    final s0 = startDate(start, now);
    final pending = isPending(lines);
    if (newCardLast4 != null &&
        (lines.any((l) => l.method == PayMethod.card && l.cardSource == CardSource.newCard) ||
            recurring == RecurringMethod.newCard)) {
      customer.savedCardLast4 = newCardLast4;
    }
    final monthly = plan.isRecurring ? planPriceAfterDiscount(plan, discountPct) : null;
    final sub = Subscription(
      id: _next('s'),
      customerId: customer.id,
      planId: plan.id,
      start: s0,
      end: endDate(plan, s0),
      status: pending ? SubStatus.pendingPayment : SubStatus.active,
      discountPct: discountPct,
      registrationWaived: waiveRegistration,
      monthlyAmount: monthly,
      recurringMethod:
          plan.isRecurring ? (recurring == RecurringMethod.newCard ? RecurringMethod.savedCard : recurring) : null,
      entriesLeft: plan.kind == PlanKind.punch ? plan.entries : null,
      nextCharge: plan.isRecurring ? addMonths(s0, 1) : null,
      prepaidAmount: plan.isRecurring && plan.prepayLastMonth ? monthly! : 0,
      joinedAt: now,
    );
    subscriptions.add(sub);
    if (plan.isRecurring) _schedule(sub, addMonths(s0, 1), monthly!, recurring == RecurringMethod.manual);
    final r = _receipt(customer.name, plan.name, lines, ReceiptKind.subscription,
        customerId: customer.id, subscriptionId: sub.id);
    if (lines.any((l) => l.method == PayMethod.link)) {
      final linkPart = lines.where((l) => l.method == PayMethod.link).fold(0.0, (a, l) => a + l.amount);
      links.insert(
          0,
          SignupLink(
              id: _next('l'),
              sentTo: customer.name,
              createdAt: now,
              planId: plan.id,
              customerId: customer.id,
              amount: round2(linkPart)));
    }
    notifyListeners();
    return (sub: sub, receipt: r);
  }

  /// A membership the AURA server has just created ([sub], with its [charges]).
  /// The payment is still recorded in the app, as [openSubscription] does (the
  /// payment part is not connected to the server yet).
  ({Subscription sub, Receipt receipt}) openServerSubscription({
    required Customer customer,
    required SubscriptionPlan plan,
    required Subscription sub,
    required List<Charge> charges,
    required List<PaymentLine> lines,
    RecurringMethod? recurring,
    String? newCardLast4,
    String? reference,
    int? saleId,
  }) {
    if (newCardLast4 != null &&
        (lines.any((l) => l.method == PayMethod.card && l.cardSource == CardSource.newCard) ||
            recurring == RecurringMethod.newCard)) {
      customer.savedCardLast4 = newCardLast4;
    }
    subscriptions
      ..removeWhere((s) => s.id == sub.id)
      ..add(sub);
    this.charges
      ..removeWhere((c) => c.subscriptionId == sub.id)
      ..addAll(charges);
    final r = _receipt(customer.name, plan.name, lines, ReceiptKind.subscription,
        customerId: customer.id, subscriptionId: sub.id, reference: reference, saleId: saleId);
    if (lines.any((l) => l.method == PayMethod.link)) {
      final linkPart = lines.where((l) => l.method == PayMethod.link).fold(0.0, (a, l) => a + l.amount);
      links.insert(
          0,
          SignupLink(
              id: _next('l'),
              sentTo: customer.name,
              createdAt: now,
              planId: plan.id,
              customerId: customer.id,
              amount: round2(linkPart)));
    }
    notifyListeners();
    return (sub: sub, receipt: r);
  }

  /// Replaces a membership (and its open charges) with the server's version
  /// after an action on the server (freeze, end freeze, cancel). Charges already
  /// paid or covered in the app are kept.
  Subscription replaceServerMembership(Subscription sub, List<Charge> charges) {
    final i = subscriptions.indexWhere((s) => s.id == sub.id);
    if (i >= 0) {
      subscriptions[i] = sub;
    } else {
      subscriptions.add(sub);
    }
    this.charges
      ..removeWhere((c) => c.subscriptionId == sub.id && c.isOpen())
      ..addAll(charges);
    notifyListeners();
    return sub;
  }

  Receipt quickPay(
      {Customer? customer,
      required String description,
      required List<PaymentLine> lines,
      String? reference,
      int? saleId}) {
    final r = _receipt(customer?.name ?? t('לקוח מזדמן'), description, lines, ReceiptKind.quickPay,
        customerId: customer?.id, reference: reference, saleId: saleId);
    notifyListeners();
    return r;
  }

  /// Marks a manual (or failed) monthly charge as collected and schedules the next one.
  /// Marks a monthly charge as paid. [line] carries cheque or transfer details.
  Receipt collect(Charge c, PayMethod method, {PaymentLine? line}) {
    c.status = ChargeStatus.paid;
    c.paidWith = method;
    c.paidAt = now;
    final sub = subscriptions.firstWhere((s) => s.id == c.subscriptionId);
    final cust = customer(c.customerId)!;
    if (sub.status == SubStatus.paymentFailed || sub.status == SubStatus.pendingPayment) {
      sub.status = SubStatus.active;
    }
    final next = addMonths(c.dueDate, 1);
    sub.nextCharge = next;
    final hasLater = charges.any((x) => x.subscriptionId == sub.id && x.dueDate.isAfter(c.dueDate));
    if (!hasLater) _schedule(sub, next, c.amount, c.manual);
    final r = _receipt(cust.name, '${plan(sub.planId)?.name ?? t('מנוי')} · ${c.dueDate.month}/${c.dueDate.year}',
        [line ?? PaymentLine(method: method, amount: c.amount)], ReceiptKind.collection,
        customerId: cust.id, subscriptionId: sub.id, chargeId: c.id);
    notifyListeners();
    return r;
  }

  // ---------- credit notes ----------
  /// How a credit is refunded by default: card back to the card, otherwise cash.
  PayMethod defaultRefundMethod(Receipt r) =>
      r.lines.any((l) => l.method == PayMethod.card) ? PayMethod.card : PayMethod.cash;

  /// Issues a credit note (חשבונית זיכוי) for [amount] of [original], refunded
  /// by [method]. A fully credited monthly payment goes back to "to collect";
  /// [cancelMembership] also ends the membership the document paid for.
  Receipt credit(Receipt original,
      {required double amount, required PayMethod method, String reason = '', bool cancelMembership = false}) {
    if (original.isCredit) throw ArgumentError('A credit note cannot be credited');
    final a = round2(amount);
    if (a <= 0 || a > original.creditable + 0.001) {
      throw ArgumentError('Amount must be 0 < amount <= ${original.creditable}');
    }
    final card = original.lines.where((l) => l.method == PayMethod.card).firstOrNull;
    final no = ++_receiptNo;
    final r = Receipt(
      number: no,
      kind: ReceiptKind.credit,
      customerId: original.customerId,
      customerName: original.customerName,
      description: t('זיכוי למסמך {0} · {1}', [original.number, original.description]),
      lines: [
        PaymentLine(
            method: method,
            amount: -a,
            transactionId: method == PayMethod.card
                ? 'RF-$no${card?.transactionId == null ? '' : '/${card!.transactionId}'}'
                : null)
      ],
      date: now,
      creditOf: original.number,
      reason: reason.trim().isEmpty ? null : reason.trim(),
      subscriptionId: original.subscriptionId,
      chargeId: original.chargeId,
    );
    original.credited = round2(original.credited + a);
    final ch = original.chargeId == null ? null : charges.where((c) => c.id == original.chargeId).firstOrNull;
    if (ch != null && original.creditable <= 0.001) {
      ch
        ..status = ChargeStatus.due
        ..paidWith = null
        ..paidAt = null;
    }
    final sub = original.subscriptionId == null
        ? null
        : subscriptions.where((s) => s.id == original.subscriptionId).firstOrNull;
    if (cancelMembership && sub != null) {
      sub
        ..status = SubStatus.cancelled
        ..cancelledAt = now
        ..cancelEffective = today
        ..nextCharge = null;
      charges.removeWhere((c) => c.subscriptionId == sub.id && c.isOpen());
    }
    receipts.add(r);
    notifyListeners();
    return r;
  }

  /// Every document of a customer, newest first.
  List<Receipt> receiptsOf(String customerId) =>
      receipts.where((r) => r.customerId == customerId).toList().reversed.toList();

  /// Records that a receipt was sent. In the AURA app this calls the SMS /
  /// WhatsApp / email provider with a link to the receipt PDF.
  void sendReceipt(Receipt r, Channel channel, String to) {
    r.sent.add((channel.label, to, now));
    notifyListeners();
  }

  void remind(Charge c) {
    c.reminders++;
    notifyListeners();
  }

  /// Sends the customer a payment link for an open charge.
  SignupLink sendChargeLink(Charge c) {
    final cust = customer(c.customerId)!;
    final sub = subscriptions.firstWhere((s) => s.id == c.subscriptionId);
    final l = SignupLink(
        id: _next('l'), sentTo: cust.name, createdAt: now, planId: sub.planId, customerId: cust.id, amount: c.amount);
    links.insert(0, l);
    c.reminders++;
    notifyListeners();
    return l;
  }

  String? freeze(Subscription s, int days) {
    final p = plan(s.planId)!;
    if (days < settings.freezeMinDays) return t('הקפאה מינימלית היא {0} ימים', [settings.freezeMinDays]);
    if (days > freezeDaysLeft(p, s)) return t('נשארו {0} ימי הקפאה השנה', [freezeDaysLeft(p, s)]);
    s.status = SubStatus.frozen;
    s.frozenUntil = today.add(Duration(days: days));
    s.freezeDaysUsed += days;
    if (s.end != null) s.end = s.end!.add(Duration(days: days));
    if (s.nextCharge != null) s.nextCharge = s.nextCharge!.add(Duration(days: days));
    for (final c
        in charges.where((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(today)).toList()) {
      charges[charges.indexOf(c)] = Charge(
          id: c.id,
          subscriptionId: c.subscriptionId,
          customerId: c.customerId,
          dueDate: c.dueDate.add(Duration(days: days)),
          amount: c.amount,
          manual: c.manual);
    }
    notifyListeners();
    return null;
  }

  void unfreeze(Subscription s) {
    if (s.frozenUntil != null && s.frozenUntil!.isAfter(today)) {
      final unused = s.frozenUntil!.difference(today).inDays;
      s.freezeDaysUsed -= unused;
      if (s.end != null) s.end = s.end!.subtract(Duration(days: unused));
    }
    s.status = SubStatus.active;
    s.frozenUntil = null;
    notifyListeners();
  }

  /// Schedules the cancellation. For a prepaid membership, the last month's
  /// charge is marked as already paid.
  DateTime cancel(Subscription s) {
    final p = plan(s.planId)!;
    var d = cancelEffectiveDate(p, s, today);
    if (s.prepaidAmount > 0) {
      // The month paid in advance is always the last month of the membership.
      final open = charges
          .where((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(today) && c.dueDate.isBefore(d))
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      if (open.isNotEmpty) {
        open.last.status = ChargeStatus.covered;
      } else {
        final nd = s.nextCharge ?? addMonths(s.start, 1);
        final end = addMonths(nd, 1);
        if (end.isAfter(d)) d = end;
        final existing = charges.where((c) => c.subscriptionId == s.id && c.dueDate == nd).firstOrNull;
        if (existing != null) {
          existing.status = ChargeStatus.covered;
        } else {
          charges.add(Charge(
              id: _next('ch'),
              subscriptionId: s.id,
              customerId: s.customerId,
              dueDate: nd,
              amount: s.monthlyAmount ?? p.price,
              manual: s.recurringMethod == RecurringMethod.manual,
              status: ChargeStatus.covered));
        }
      }
      s.prepaidAmount = 0;
    }
    s.cancelEffective = d;
    s.cancelledAt = now;
    charges.removeWhere((c) => c.subscriptionId == s.id && c.isOpen() && !c.dueDate.isBefore(d));
    notifyListeners();
    return d;
  }

  // ---------- links ----------
  SignupLink sendSignupLink(String to) {
    final l = SignupLink(id: _next('l'), sentTo: to.trim().isEmpty ? t('לקוח חדש') : to.trim(), createdAt: now);
    links.insert(0, l);
    notifyListeners();
    return l;
  }

  void linkStage(SignupLink l, LinkStage s) {
    l.advance(s, now);
    notifyListeners();
  }

  final Map<String, Timer> _sims = {};

  /// Demo: plays the customer's side of a link, one step every [step], so the
  /// owner sees the stages change live. In production the stages come from the
  /// link page and the card processor's webhook.
  void simulateLink(SignupLink l, {Duration step = const Duration(seconds: 2)}) {
    _sims[l.id]?.cancel();
    _sims[l.id] = Timer.periodic(step, (timer) {
      final next = switch (l.stage) {
        LinkStage.sent => LinkStage.opened,
        LinkStage.opened => LinkStage.details,
        LinkStage.details => LinkStage.signed,
        LinkStage.signed || LinkStage.failed => LinkStage.paid,
        LinkStage.paid => null,
      };
      if (next == null) {
        timer.cancel();
        _sims.remove(l.id);
        return;
      }
      if (next == LinkStage.paid) {
        final plan = l.planId != null ? this.plan(l.planId!)! : activePlans.firstWhere((p) => p.onlineSignup);
        final c = l.customerId != null ? customer(l.customerId!)! : null;
        completeSignup(l,
            name: c?.name ?? (RegExp(r'\d').hasMatch(l.sentTo) ? t('לקוח מהלינק') : l.sentTo),
            phone: c?.phone ?? (isValidPhone(l.sentTo) ? l.sentTo : '050-0000000'),
            plan: plan,
            cardLast4: '4242');
        timer.cancel();
        _sims.remove(l.id);
      } else {
        linkStage(l, next);
      }
    });
  }

  bool isSimulating(SignupLink l) => _sims.containsKey(l.id);

  void stopSimulations() {
    for (final t in _sims.values) {
      t.cancel();
    }
    _sims.clear();
  }

  /// Customer side of the link: registers, pays by card, subscription becomes active.
  Subscription completeSignup(SignupLink link,
      {required String name,
      required String phone,
      String? idNumber,
      required SubscriptionPlan plan,
      required String cardLast4,
      int installments = 1}) {
    Customer? c = link.customerId != null ? customer(link.customerId!) : null;
    c ??= customers
        .where((x) => x.phone.replaceAll(RegExp(r'\D'), '') == phone.replaceAll(RegExp(r'\D'), ''))
        .firstOrNull;
    c ??= addCustomer(name, phone, idNumber: idNumber);
    c.healthDeclared = true;
    c.savedCardLast4 = cardLast4;
    final existing = link.customerId != null
        ? subscriptions.where((s) => s.customerId == c!.id && s.status == SubStatus.pendingPayment).firstOrNull
        : null;
    final amount = link.amount ?? subscriptionDueNow(plan, prepayLastMonth: plan.isRecurring && plan.prepayLastMonth);
    link.customerId ??= c.id;
    link.planId ??= plan.id;
    link.advance(LinkStage.paid, now);
    final line =
        PaymentLine(method: PayMethod.card, amount: amount, installments: installments, cardSource: CardSource.newCard);
    if (existing != null) {
      existing.status = SubStatus.active;
      _receipt(c.name, t('{0} · לינק', [plan.name]), [line], ReceiptKind.link, customerId: c.id);
      notifyListeners();
      return existing;
    }
    final charge = link.customerId != null && link.amount != null
        ? charges.where((x) => x.customerId == c!.id && x.isOpen()).firstOrNull
        : null;
    if (charge != null) {
      collect(charge, PayMethod.card);
      return subscriptions.firstWhere((s) => s.id == charge.subscriptionId);
    }
    final r = openSubscription(
      customer: c,
      plan: plan,
      start: StartOption.today,
      discountPct: 0,
      waiveRegistration: false,
      lines: [line],
      recurring: plan.isRecurring ? RecurringMethod.savedCard : null,
      newCardLast4: cardLast4,
    );
    receipts.remove(r.receipt);
    receipts.add(Receipt(
        number: r.receipt.number,
        customerName: r.receipt.customerName,
        description: r.receipt.description,
        lines: r.receipt.lines,
        date: r.receipt.date,
        customerId: r.receipt.customerId,
        subscriptionId: r.receipt.subscriptionId,
        chargeId: r.receipt.chargeId,
        kind: ReceiptKind.link));
    return r.sub;
  }

  // ---------- sample data ----------
  void _seed() {
    plans.addAll([
      SubscriptionPlan(
          id: 'p1',
          name: t('חודשי ללא הגבלה'),
          kind: PlanKind.recurring,
          price: 199,
          registrationFee: 100,
          freezeDaysPerYear: 30,
          badge: t('הכי נמכר')),
      SubscriptionPlan(
          id: 'p2',
          name: t('חודשי בהתחייבות לשנה'),
          kind: PlanKind.recurring,
          price: 169,
          commitMonths: 12,
          freezeDaysPerYear: 30),
      SubscriptionPlan(
          id: 'p3',
          name: t('פעמיים בשבוע'),
          kind: PlanKind.recurring,
          price: 149,
          registrationFee: 100,
          weeklyLimit: 2,
          freezeDaysPerYear: 14),
      SubscriptionPlan(
          id: 'p7',
          name: t('חודשי + חודש אחרון מראש'),
          kind: PlanKind.recurring,
          price: 179,
          freezeDaysPerYear: 30,
          prepayLastMonth: true),
      SubscriptionPlan(
          id: 'p4',
          name: t('3 חודשים'),
          kind: PlanKind.term,
          price: 540,
          months: 3,
          registrationFee: 100,
          freezeDaysPerYear: 14,
          maxInstallments: 3,
          maxCheques: 3,
          allowCheques: true),
      SubscriptionPlan(
          id: 'p5',
          name: t('שנתי'),
          kind: PlanKind.term,
          price: 1790,
          months: 12,
          freezeDaysPerYear: 60,
          maxInstallments: 12,
          maxCheques: 12,
          allowCheques: true,
          autoRenew: true),
      SubscriptionPlan(
          id: 'p6',
          name: t('כרטיסייה 10 כניסות'),
          kind: PlanKind.punch,
          price: 350,
          entries: 10,
          validMonths: 3,
          maxInstallments: 2),
    ]);
    final td = today;
    Customer c(String id, String n, String ph, [String? card]) {
      final x = Customer(id: id, name: n, phone: ph, savedCardLast4: card, healthDeclared: true);
      customers.add(x);
      return x;
    }

    c('c7', t('יעל אורן'), '052-4417730', '9031');
    c('c8', t('חאלד מנסור'), '054-3302871');
    c('c9', t('מאיה גולן'), '050-7719264', '5512');
    c('c10', t('עומר שלו'), '052-6620043', '3381');
    c('c11', t('לינה סעד'), '058-2201937');
    c('c1', t('נועה לוי'), '052-7781024', '4580');
    c('c2', t('מוחמד חסן'), '054-6120933');
    c('c3', t('דני כהן'), '050-3349182', '1123');
    c('c4', t('רים ח׳ורי'), '058-4410276');
    c('c5', t('אלון ברק'), '052-9917345');
    c('c6', t('סמאח עודה'), '053-2288104', '7702');

    DateTime ago(int days) => td.subtract(Duration(days: days));
    subscriptions.addAll([
      Subscription(id: 's1', customerId: 'c1', planId: 'p5', start: addMonths(td, -8), end: addMonths(td, 4)),
      Subscription(
          id: 's2',
          customerId: 'c3',
          planId: 'p1',
          start: addMonths(td, -3),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          nextCharge: td.add(const Duration(days: 9))),
      Subscription(
          id: 's3',
          customerId: 'c5',
          planId: 'p3',
          start: addMonths(td, -2),
          monthlyAmount: 149,
          recurringMethod: RecurringMethod.manual,
          nextCharge: ago(3)),
      Subscription(
          id: 's4',
          customerId: 'c6',
          planId: 'p1',
          start: addMonths(td, -5),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          status: SubStatus.paymentFailed,
          nextCharge: ago(9)),
      Subscription(
          id: 's5', customerId: 'c2', planId: 'p4', start: addMonths(td, -3), end: td.add(const Duration(days: 6))),
      Subscription(
          id: 's6',
          customerId: 'c7',
          planId: 'p7',
          start: ago(18),
          joinedAt: ago(18),
          monthlyAmount: 179,
          recurringMethod: RecurringMethod.savedCard,
          prepaidAmount: 179,
          nextCharge: addMonths(ago(18), 1)),
      Subscription(
          id: 's7',
          customerId: 'c8',
          planId: 'p1',
          start: ago(25),
          joinedAt: ago(25),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.manual,
          nextCharge: addMonths(ago(25), 1)),
      Subscription(
          id: 's8',
          customerId: 'c9',
          planId: 'p2',
          start: addMonths(td, -4),
          monthlyAmount: 169,
          recurringMethod: RecurringMethod.savedCard,
          status: SubStatus.frozen,
          frozenUntil: td.add(const Duration(days: 12)),
          freezeDaysUsed: 21,
          nextCharge: td.add(const Duration(days: 15))),
      Subscription(
          id: 's9',
          customerId: 'c10',
          planId: 'p1',
          start: addMonths(td, -6),
          monthlyAmount: 199,
          recurringMethod: RecurringMethod.savedCard,
          nextCharge: td.add(const Duration(days: 4)),
          cancelEffective: td.add(const Duration(days: 20)),
          cancelledAt: ago(10)),
      Subscription(
          id: 's10',
          customerId: 'c11',
          planId: 'p4',
          start: ago(12),
          joinedAt: ago(12),
          end: endDate(plan('p4')!, ago(12))),
    ]);
    charges.addAll([
      Charge(
          id: 'ch1', subscriptionId: 's3', customerId: 'c5', dueDate: ago(3), amount: 149, manual: true, reminders: 1),
      Charge(
          id: 'ch2',
          subscriptionId: 's4',
          customerId: 'c6',
          dueDate: ago(9),
          amount: 199,
          manual: false,
          status: ChargeStatus.failed,
          attempts: 2),
      Charge(
          id: 'ch3',
          subscriptionId: 's2',
          customerId: 'c3',
          dueDate: td.add(const Duration(days: 9)),
          amount: 199,
          manual: false),
      Charge(
          id: 'ch4',
          subscriptionId: 's6',
          customerId: 'c7',
          dueDate: addMonths(ago(18), 1),
          amount: 179,
          manual: false),
      Charge(
          id: 'ch5', subscriptionId: 's7', customerId: 'c8', dueDate: addMonths(ago(25), 1), amount: 199, manual: true),
      Charge(
          id: 'ch6',
          subscriptionId: 's8',
          customerId: 'c9',
          dueDate: td.add(const Duration(days: 15)),
          amount: 169,
          manual: false),
      Charge(
          id: 'ch7',
          subscriptionId: 's9',
          customerId: 'c10',
          dueDate: td.add(const Duration(days: 4)),
          amount: 199,
          manual: false),
      Charge(
          id: 'ch8',
          subscriptionId: 's3',
          customerId: 'c5',
          dueDate: addMonths(ago(3), -1),
          amount: 149,
          manual: true,
          status: ChargeStatus.paid,
          paidWith: PayMethod.cash,
          paidAt: addMonths(ago(3), -1)),
    ]);

    final l1 = SignupLink(id: 'l1', sentTo: t('יוסי אברהם'), createdAt: now.subtract(const Duration(hours: 5)));
    final l2 = SignupLink(id: 'l2', sentTo: '054-7781200', createdAt: now.subtract(const Duration(hours: 2)))
      ..advance(LinkStage.opened, now.subtract(const Duration(minutes: 50)));
    final l3 = SignupLink(id: 'l3', sentTo: t('רונית ש.'), createdAt: now.subtract(const Duration(hours: 1)))
      ..advance(LinkStage.opened, now.subtract(const Duration(minutes: 40)))
      ..advance(LinkStage.details, now.subtract(const Duration(minutes: 38)))
      ..advance(LinkStage.signed, now.subtract(const Duration(minutes: 37)))
      ..advance(LinkStage.failed, now.subtract(const Duration(minutes: 36)));
    final l4 =
        SignupLink(id: 'l4', sentTo: t('יעל אורן'), createdAt: ago(18), planId: 'p7', customerId: 'c7', amount: 358)
          ..advance(LinkStage.paid, ago(18));
    links.addAll([l1, l2, l3, l4]);

    final pc = PaymentLine.new;
    Receipt rec(int no, String name, String desc, List<PaymentLine> l, DateTime at, ReceiptKind k) =>
        Receipt(number: no, customerName: name, description: desc, lines: l, date: at, kind: k);
    receipts.addAll([
      rec(30160, t('חאלד מנסור'), t('חודשי ללא הגבלה'), [pc(method: PayMethod.cash, amount: 299)], ago(25),
          ReceiptKind.subscription),
      rec(30163, t('יעל אורן'), t('חודשי + חודש אחרון מראש'), [pc(method: PayMethod.card, amount: 358)], ago(18),
          ReceiptKind.link),
      rec(
          30166,
          t('לינה סעד'),
          t('3 חודשים'),
          [
            pc(
                method: PayMethod.cheque,
                amount: 640,
                cheques: 3,
                cheque: ChequeDetails(number: '0041', bank: '12', branch: '614', account: '338210', firstDate: ago(12)))
          ],
          ago(12),
          ReceiptKind.subscription),
      rec(30170, t('אלון ברק'), t('פעמיים בשבוע · {0}/{1}', [addMonths(ago(3), -1).month, addMonths(ago(3), -1).year]),
          [pc(method: PayMethod.cash, amount: 149)], addMonths(ago(3), -1), ReceiptKind.collection),
      rec(30174, t('דני כהן'), t('אימון אישי'), [pc(method: PayMethod.card, amount: 180)], ago(6),
          ReceiptKind.quickPay),
      rec(30177, t('נועה לוי'), t('שייק חלבון, מגבת'), [pc(method: PayMethod.cash, amount: 52)], ago(2),
          ReceiptKind.quickPay),
      rec(30180, t('שירן מזרחי'), t('שנתי'), [pc(method: PayMethod.card, amount: 1790, installments: 6)],
          now.subtract(const Duration(hours: 3)), ReceiptKind.subscription),
      rec(30181, t('לקוח מזדמן'), t('כניסה חד-פעמית'), [pc(method: PayMethod.cash, amount: 60)],
          now.subtract(const Duration(hours: 1)), ReceiptKind.quickPay),
    ]);
    seedDemoHistory(this);
    // Number every receipt in date order, as a real receipt book would be.
    receipts.sort((a, b) => a.date.compareTo(b.date));
    final numbered = [
      for (var i = 0; i < receipts.length; i++)
        Receipt(
          number: 28001 + i,
          customerId:
              receipts[i].customerId ?? customers.where((c) => c.name == receipts[i].customerName).firstOrNull?.id,
          customerName: receipts[i].customerName,
          description: receipts[i].description,
          lines: [
            for (final (k, l) in receipts[i].lines.indexed)
              l.copy()..transactionId = l.method == PayMethod.card ? 'TX-${28001 + i}-${k + 1}' : null
          ],
          date: receipts[i].date,
          kind: receipts[i].kind,
          subscriptionId: receipts[i].subscriptionId,
          chargeId: receipts[i].chargeId,
        )
    ];
    receipts
      ..clear()
      ..addAll(numbered);
    _receiptNo = 28000 + receipts.length;
  }
}
