// Dejavoo Tap to Pay, copied from the AURA POS app (pos-app lib/services/tap_to_pay_service.dart).
// Changed only where the POS app uses its own modules: the method channel name, the
// logged-in user's TPN / merchant code ([userTpn] / [userMerchantCode], set at sign-in),
// the saved session (a file instead of SharedPreferences), the SDK language (this app's
// language) and the open-table guard (no tables in a gym). Everything else is the same.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'dart:io';

import '../domain/l10n.dart';
import 'payment_report.dart';

export 'payment_report.dart' show DejavooReport, PaymentReport, PaymentDiagnostics;

/// Dejavoo Tap to Pay (TOP SDK), following
/// https://docs.ipospays.com/tap-to-pay-on-android/in-app-sdk-israel
///
/// Flow: register the device (TPN + merchant code) -> keep the session ->
/// performTransaction with the session key; re-register once when the SDK
/// says the session is no longer valid. Every attempt produces a
/// [DejavooReport] (shown to the tester and sent to Crashlytics).
enum TopTransactionType { sale, refund, voidTxn }

extension _TopTransactionTypeX on TopTransactionType {
  String get apiValue {
    switch (this) {
      case TopTransactionType.sale:
        return 'SALE';
      case TopTransactionType.refund:
        return 'REFUND';
      case TopTransactionType.voidTxn:
        return 'VOID';
    }
  }
}

/// TPN + merchant code a device registers with, and the SDK build they are for.
class TapToPayCredentials {
  final String env; // 'sandbox' or 'prod'
  final String tpn;
  final String merchantCode;

  const TapToPayCredentials(this.env, this.tpn, this.merchantCode);
}

class TapToPaySession {
  final String sessionKey;
  final String? authToken;
  final int sessionCreatedTimestamp; // ms since epoch
  final int sessionExpiryMs;

  /// What the session was registered with; null for sessions saved before
  /// these were recorded, which are then treated as not matching.
  final String? env;
  final String? tpn;
  final String? merchantCode;

  TapToPaySession({
    required this.sessionKey,
    this.authToken,
    required this.sessionCreatedTimestamp,
    required this.sessionExpiryMs,
    this.env,
    this.tpn,
    this.merchantCode,
  });

  bool get isExpired {
    final expiresAt = sessionCreatedTimestamp + sessionExpiryMs;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  /// A sandbox session must never be used by a prod build, and a session
  /// for another TPN must not be used after the device's TPN changed.
  bool matches(TapToPayCredentials credentials) =>
      env == credentials.env &&
      tpn == credentials.tpn &&
      merchantCode == credentials.merchantCode;

  TapToPaySession registeredWith(TapToPayCredentials credentials) => TapToPaySession(
        sessionKey: sessionKey,
        authToken: authToken,
        sessionCreatedTimestamp: sessionCreatedTimestamp,
        sessionExpiryMs: sessionExpiryMs,
        env: credentials.env,
        tpn: credentials.tpn,
        merchantCode: credentials.merchantCode,
      );

  Map<String, dynamic> toJson() => {
        'session_key': sessionKey,
        'auth_token': authToken,
        'session_created_timestamp': sessionCreatedTimestamp,
        'session_expiry_in_milliseconds': sessionExpiryMs,
        'env': env,
        'tpn': tpn,
        'merchant_code': merchantCode,
      };

  factory TapToPaySession.fromJson(Map<String, dynamic> json) {
    // The Israel doc uses "session_expire_time"/"session_date" in its sample
    // response and "session_expiry_in_milliseconds"/"session_created_timestamp"
    // in its field table, and shows both seconds and milliseconds. Accept all.
    final createdRaw = json['session_created_timestamp'] ?? json['session_date'];
    final expiryRaw = json['session_expiry_in_milliseconds'] ?? json['session_expire_time'];

    var created = int.tryParse('$createdRaw') ?? DateTime.now().millisecondsSinceEpoch;
    if (created < 100000000000) created *= 1000; // seconds since epoch
    var expiry = int.tryParse('$expiryRaw') ?? 86400000; // default 24h
    if (expiry < 10000000) expiry *= 1000; // seconds

    return TapToPaySession(
      sessionKey: json['session_key'] as String,
      authToken: (json['auth_token'] ?? json['ecomAuthToken']) as String?,
      sessionCreatedTimestamp: created,
      sessionExpiryMs: expiry,
      env: json['env'] as String?,
      tpn: json['tpn'] as String?,
      merchantCode: json['merchant_code'] as String?,
    );
  }
}

class TopTransactionResult {
  final bool approved;
  final Map<String, dynamic> raw;
  final DejavooReport? report;
  TopTransactionResult({required this.approved, required this.raw, this.report});
}

class TopPaymentException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final DejavooReport? report;
  TopPaymentException(this.code, this.message, [this.details, this.report]);

  /// The customer or cashier cancelled on the SDK's own screen (card screen or
  /// manual entry form). Not a failure: no report is made and no error is shown.
  bool get isCancelled => code == TapToPayService.cancelledCode;

  @override
  String toString() => 'TopPaymentException($code): $message';
}

class TapToPayService {
  TapToPayService._internal();
  static final TapToPayService instance = TapToPayService._internal();

  static const MethodChannel _channel =
      MethodChannel('tech.aura.gym/top');

  // Sandbox credentials, used by sandbox builds when the logged-in user has
  // none. Prod builds only use the user's TPN/merchant code.
  static const String _sandboxTpn = '654326998484';
  static const String _sandboxMerchantCode = '548450836402';

  /// TOPParams.TRANSACTION_CANCELLED: what the SDK reports when its card screen or
  /// manual entry form is cancelled (cancel / ✕ / back).
  static const String cancelledCode = '21';

  // Codes the SDK returns when the session key is empty / expired / not matching
  // (TOPParams: USER_SESSION_KEY_NOT_VALID_CODE, SESSION_KEY_EXPIRED_CODE*, SESSION_KEY_NOT_MATCHING).
  static const Set<String> _sessionExpiredCodes = {
    '980', '981', '982', '983', '984', '990', '991',
  };

  // How long to wait for the SDK before giving up, so the payment spinner
  // never hangs when the SDK doesn't answer (seen with Developer options on).
  static const Duration _registerTimeout = Duration(seconds: 60);
  static const Duration _transactionTimeout = Duration(seconds: 120);
  static const Duration _manualEntryTimeout = Duration(seconds: 300);

  // Start-up watchdog for sales: the SDK normally opens its card screen within a
  // second or two. If it opened no screen at all after this long it is stuck
  // before reading a card (no charge is possible), so the sale is re-registered
  // and retried once instead of making the cashier clear the app's data.
  static const Duration _startupTimeout = Duration(seconds: 30);

  /// Called with the report when the SDK approves a payment after the app
  /// already stopped waiting for it: the card is charged but no sale was saved.
  /// Set in main.dart to show the report on screen.
  void Function(DejavooReport report)? onLateResult;

  /// The signed-in user's Tap to Pay TPN and merchant code (web: Users > Setting Info),
  /// from the login answer. Set by the app at sign-in.
  String? userTpn;
  String? userMerchantCode;

  /// Where the Dejavoo session is kept between runs (the app's private files folder).
  File? sessionFile = _defaultSessionFile();

  static File? _defaultSessionFile() {
    try {
      final dir = Directory('${Directory.systemTemp.parent.path}${Platform.pathSeparator}files');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}toppay_session.json');
    } catch (_) {
      return null;
    }
  }

  TapToPaySession? _cachedSession;
  String? _environment;

  /// False when the APK was built without the Dejavoo Maven credentials.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isTopAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The SDK build in this APK: 'sandbox', 'prod', or 'none' (no SDK).
  /// Set by dejavoo.env in android/local.properties at build time.
  Future<String> environment() async {
    if (_environment != null) return _environment!;
    try {
      _environment = await _channel.invokeMethod<String>('topEnvironment') ?? 'none';
    } catch (_) {
      _environment = 'none';
    }
    return _environment!;
  }

  /// The logged-in user's values (saved at login, set per user in the web
  /// Users > Setting Info); sandbox builds fall back to the sandbox pair.
  /// Prod builds without both values set throw TOP_CREDENTIALS_MISSING.
  Future<TapToPayCredentials> _credentials() async {
    final env = await environment();
    final tpn = (userTpn ?? '').trim();
    final merchantCode =
        (userMerchantCode ?? '').trim();

    if (env != 'prod') {
      return TapToPayCredentials(
        env,
        tpn.isNotEmpty ? tpn : _sandboxTpn,
        merchantCode.isNotEmpty ? merchantCode : _sandboxMerchantCode,
      );
    }
    if (tpn.isNotEmpty && merchantCode.isNotEmpty) {
      return TapToPayCredentials(env, tpn, merchantCode);
    }

    final report = await DejavooDiagnostics.record(
      operation: 'TOP registerDevice',
      args: {'env': env, 'tpnSet': tpn.isNotEmpty, 'merchantCodeSet': merchantCode.isNotEmpty},
      outcome: DejavooOutcome.error,
      code: 'TOP_CREDENTIALS_MISSING',
      message: 'Tap to Pay TPN and merchant code are not set for this user',
    );
    throw TopPaymentException('TOP_CREDENTIALS_MISSING', report.message, null, report);
  }

  Future<TapToPaySession?> _loadSession() async {
    if (_cachedSession != null) return _cachedSession;
    final file = sessionFile;
    if (file == null || !file.existsSync()) return null;
    final raw = await file.readAsString();
    try {
      _cachedSession =
          TapToPaySession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _cachedSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(TapToPaySession session) async {
    _cachedSession = session;
    await sessionFile?.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  Future<void> _clearSession() async {
    _cachedSession = null;
    final file = sessionFile;
    if (file != null && file.existsSync()) await file.delete();
  }

  /// Call on first launch, after cache is cleared, or whenever no valid
  /// session is found. Persists the resulting session automatically.
  Future<TapToPaySession> registerDevice() async {
    final credentials = await _credentials();
    final tpn = credentials.tpn;
    final merchantCode = credentials.merchantCode;
    final args = {'tpn': tpn, 'merchantCode': merchantCode};
    final map = await _invoke('TOP registerDevice', 'registerDevice', args,
        timeout: _registerTimeout,
        reportArgs: {
          'env': credentials.env,
          'tpn': tpn,
          'merchantCode': '****${_last4(merchantCode)}',
        });

    try {
      final session = TapToPaySession.fromJson(map).registeredWith(credentials);
      await _saveSession(session);
      return session;
    } catch (e, stack) {
      // Registration "succeeded" but without a usable session key.
      final report = await DejavooDiagnostics.record(
        operation: 'TOP registerDevice',
        args: {'tpn': tpn},
        outcome: DejavooOutcome.error,
        code: 'BAD_REGISTER_RESPONSE',
        message: 'Registration response has no usable session_key',
        response: _withoutDiagnostics(map),
        diagnostics: _diagnosticsOf(map),
        dartError: e,
        dartStack: stack,
      );
      throw TopPaymentException('BAD_REGISTER_RESPONSE', report.message, map, report);
    }
  }

  /// Returns a valid session, registering (or re-registering) if needed.
  Future<TapToPaySession> _ensureValidSession() async {
    final existing = await _loadSession();
    if (existing != null &&
        !existing.isExpired &&
        existing.matches(await _credentials())) {
      return existing;
    }
    return await registerDevice();
  }

  Future<TopTransactionResult> _performTransaction({
    required TopTransactionType type,
    String? amount,
    Map<String, dynamic>? customObject,
    bool isRetry = false,
  }) async {
    final session = await _ensureValidSession();
    final operation = 'TOP ${type.apiValue}';
    final args = {
      'type': type.apiValue,
      if (amount != null) 'amount': amount,
      'sessionKey': session.sessionKey,
      'lang': L10n.lang == AppLang.en ? 'en' : 'iw',
      'customObject': customObject ?? <String, dynamic>{},
    };

    Map<String, dynamic> map;
    try {
      map = await _invoke(operation, 'performTransaction', args,
          timeout: _transactionTimeout,
          startupTimeout: type == TopTransactionType.sale ? _startupTimeout : null,
          notStartedMessage: isRetry
              ? 'Tap to Pay could not open the card screen, even after re-registering this device. '
                  'Please try again or use another payment method.'
              : 'Tap to Pay did not open the card screen within ${_startupTimeout.inSeconds} seconds; '
                  're-registering the device and retrying.',
          chargesCard: true,
          cancelWhenScreensClose: true,
          reportArgs: {...args, 'sessionKey': '…${_last4(session.sessionKey)}'});
    } on TopPaymentException catch (e) {
      // Session no longer valid, or the SDK never opened its card screen (stuck
      // before reading a card, so nothing was charged) -> start from a fresh SDK
      // service and session, re-register once and retry.
      final notStarted = e.code == 'TOP_NOT_STARTED';
      if (!isRetry && (notStarted || _sessionExpiredCodes.contains(e.code))) {
        if (notStarted) await _resetSdkService();
        await _clearSession();
        return _performTransaction(
          type: type,
          amount: amount,
          customObject: customObject,
          isRetry: true,
        );
      }
      rethrow;
    }

    _throwIfCancelResponse(operation, map);
    final responseCode = map['response_code'];
    final approved = _isApproved(map);

    final report = await DejavooDiagnostics.record(
      operation: operation,
      args: {...args, 'sessionKey': '…${_last4(session.sessionKey)}'},
      outcome: approved ? DejavooOutcome.approved : DejavooOutcome.declined,
      code: '${responseCode ?? map['status'] ?? ''}',
      message: '${map['message'] ?? ''}',
      response: _withoutDiagnostics(map),
      diagnostics: _diagnosticsOf(map),
    );
    return TopTransactionResult(
        approved: approved, raw: withCardFallback(_withoutDiagnostics(map)), report: report);
  }

  /// The card screen's own cancel does not come back as error 21: ✕ -> "Abort
  /// Transaction?" -> YES (or that dialog timing out) answers through the normal
  /// response with response_code "33" and the SDK's TRANSACTION_CANCELLED_MESSAGE,
  /// before any card is read (UICardPresentScreen in SDK 3.0.5.6). An issuer decline
  /// 33 (e.g. expired card) carries a transactionResult and the processor's own
  /// message, so it still shows as a decline.
  ///
  /// The manual entry form's ✕ (and its Abort dialog YES) answers the same way, but
  /// with response_code "Failure" and the SDK's localized txn_was_canceled string
  /// (ManualEntryWebViewActivity in SDK 3.0.5.6). Its form timeout uses another
  /// message, so it still shows as an error.
  static bool _isCancelResponse(Map<String, dynamic> map) {
    final code = '${map['response_code']}'.trim().toLowerCase();
    final message = '${map['message']}'.trim().toLowerCase();
    if (code == '33') {
      return message == 'transaction cancelled' && map['transactionResult'] == null;
    }
    return code == 'failure' && _manualEntryCancelMessages.contains(message);
  }

  /// txn_was_canceled in the SDK's values / values-en / values-iw / values-es.
  static const _manualEntryCancelMessages = {
    'transaction canceled',
    'transaction cancelled',
    'עסקה בוטלה',
    'transacción cancelada',
  };

  /// Cancelled on the SDK's screen: not a decline, so no report and no error dialog.
  static void _throwIfCancelResponse(String operation, Map<String, dynamic> map) {
    if (!_isCancelResponse(map)) return;
    debugPrint('$operation cancelled on the Tap to Pay screen (${map['response_code']})');
    throw TopPaymentException(cancelledCode, 'Transaction Cancelled', _withoutDiagnostics(map));
  }

  /// Marks a payment row paid through Tap to Pay (not sent to the server).
  static const String providerKey = 'card_provider';
  static const String providerValue = 'tapToPay';

  /// True for a payment row paid through Tap to Pay: rows made in the app carry
  /// [providerKey]; rows reloaded from a draft are recognised by the SDK's receipt,
  /// which has transaction_title / transaction_mode (other card providers don't).
  static bool isTapToPayPayment(Map<String, dynamic> payment) {
    if (payment[providerKey] == providerValue) return true;
    final receipt = payment['receipt'];
    return receipt is Map &&
        (receipt.containsKey('transaction_title') || receipt.containsKey('transaction_mode'));
  }

  /// Israel doc: response_code "00" = approved, anything else = failure.
  /// Older SDK builds only return "status": "Approved".
  static bool _isApproved(Map<String, dynamic> map) {
    final responseCode = map['response_code'];
    return responseCode != null
        ? '$responseCode'.trim() == '00'
        : '${map['status']}'.toLowerCase() == 'approved';
  }

  /// On declines the SDK leaves the top-level card fields (last_4_digits, mask_pan,
  /// card_type) empty although the card was read; the card is still under
  /// transactionResult (maskedPan holds the last 4 digits). Fill the empty ones in.
  static Map<String, dynamic> withCardFallback(Map<String, dynamic> map) {
    final transactionResult = map['transactionResult'];
    if (transactionResult is! Map) return map;

    final out = Map<String, dynamic>.from(map);
    final masked = _nonEmpty(transactionResult['maskedPan']);
    if (masked != null) {
      final last4 = _last4(masked);
      if (_nonEmpty(out['last_4_digits']) == null) out['last_4_digits'] = last4;
      if (_nonEmpty(out['mask_pan']) == null) out['mask_pan'] = '************$last4';
    }
    if (_nonEmpty(out['card_type']) == null) {
      final cardType = _nonEmpty(transactionResult['applicationPreferredName']) ??
          _nonEmpty(transactionResult['cardType']);
      if (cardType != null) out['card_type'] = cardType;
    }
    return out;
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  /// Calls the native side; errors become [TopPaymentException] with a report.
  /// After [timeout] the call fails with TOP_TIMEOUT instead of waiting forever;
  /// a result the SDK sends later is still reported (see [_reportLateResult]).
  /// With [startupTimeout], the call also fails with TOP_NOT_STARTED when the SDK
  /// opened none of its screens within that time (see [_sdkStartedWithin]).
  /// With [cancelWhenScreensClose], the call counts as cancelled when the SDK's
  /// screens all closed without an answer (see [_sdkClosedWithoutAnswer]).
  Future<Map<String, dynamic>> _invoke(
    String operation,
    String method,
    Map<String, dynamic> args, {
    required Map<String, dynamic> reportArgs,
    required Duration timeout,
    Duration? startupTimeout,
    String? notStartedMessage,
    bool chargesCard = false,
    bool cancelWhenScreensClose = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final call = _channel.invokeMethod(method, args);
    if (startupTimeout != null && !await _sdkStartedWithin(call, startupTimeout)) {
      _reportLateResult(call, operation, reportArgs, startupTimeout, chargesCard);
      final report = await DejavooDiagnostics.record(
        operation: operation,
        args: reportArgs,
        outcome: DejavooOutcome.error,
        code: 'TOP_NOT_STARTED',
        message: notStartedMessage ??
            'Tap to Pay did not open the card screen within ${startupTimeout.inSeconds} seconds.',
      );
      throw TopPaymentException('TOP_NOT_STARTED', report.message, null, report);
    }
    try {
      final remaining = timeout - stopwatch.elapsed;
      final answer = cancelWhenScreensClose ? Future.any([call, _sdkClosedWithoutAnswer(call)]) : call;
      final result = await answer.timeout(remaining > Duration.zero ? remaining : const Duration(seconds: 1));
      if (identical(result, _screensClosed)) {
        // Closed with the system Back button: the SDK never answers this, so
        // stop waiting. An answer that still comes is reported like a late one.
        _reportLateResult(call, operation, reportArgs, timeout, chargesCard,
            reason: 'after the Tap to Pay screen was closed with Back');
        debugPrint('$operation cancelled: Tap to Pay screen closed with Back');
        throw TopPaymentException(cancelledCode, 'Transaction Cancelled');
      }
      return Map<String, dynamic>.from(result as Map);
    } on TopPaymentException {
      rethrow;
    } on TimeoutException catch (e, stack) {
      _reportLateResult(call, operation, reportArgs, timeout, chargesCard);
      final report = await DejavooDiagnostics.record(
        operation: operation,
        args: reportArgs,
        outcome: DejavooOutcome.error,
        code: 'TOP_TIMEOUT',
        message: 'Tap to Pay did not respond within ${timeout.inSeconds} seconds. '
            'Make sure Developer options and USB debugging are off on this device, then try again.',
        dartError: e,
        dartStack: stack,
      );
      throw TopPaymentException('TOP_TIMEOUT', report.message, null, report);
    } on PlatformException catch (e, stack) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      if (e.code == cancelledCode) {
        // Cancelled on the SDK's screen by the user: not an error, so no report.
        debugPrint('$operation cancelled on the Tap to Pay screen');
        throw TopPaymentException(e.code, e.message ?? 'Transaction Cancelled', details);
      }
      final report = await DejavooDiagnostics.record(
        operation: operation,
        args: reportArgs,
        outcome: DejavooOutcome.error,
        code: e.code,
        message: e.message ?? 'Tap to Pay failed',
        response: details == null ? null : _withoutDiagnostics(details),
        diagnostics: details == null ? null : _diagnosticsOf(details),
        dartStack: stack,
      );
      throw TopPaymentException(e.code, e.message ?? 'Tap to Pay failed', details, report);
    } catch (e, stack) {
      final report = await DejavooDiagnostics.record(
        operation: operation,
        args: reportArgs,
        outcome: DejavooOutcome.error,
        code: 'DART_EXCEPTION',
        message: 'Tap to Pay failed: $e',
        dartError: e,
        dartStack: stack,
      );
      throw TopPaymentException('DART_EXCEPTION', report.message, null, report);
    }
  }

  /// True when, within [limit], the SDK opened any of its own screens for this
  /// call (the native side watches for them) or already answered.
  Future<bool> _sdkStartedWithin(Future<dynamic> call, Duration limit) async {
    var answered = false;
    // Only observes the call; its result and errors are still handled by _invoke.
    unawaited(call.then((_) => answered = true, onError: (_) => answered = true));
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      if (answered) return true;
      try {
        if (await _channel.invokeMethod<bool>('topSdkScreenShown') == true) return true;
      } catch (_) {
        return true; // native side without the watchdog: never block the sale on it
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return answered;
  }

  /// What [_sdkClosedWithoutAnswer] completes with.
  static final Object _screensClosed = Object();

  /// Completes with [_screensClosed] once the SDK's screens for this call have
  /// all been closed for [grace] without an answer: the system Back button or
  /// gesture on the card screen closes it without calling back. [grace] leaves
  /// room for an answer the SDK sends just as its last screen closes; it is
  /// short because the cashier waits on the loading meanwhile, and the SDK
  /// cancels the card transaction when its screen goes (an answer arriving
  /// later is still reported by [_reportLateResult]). Never completes once the
  /// call answers.
  Future<Object> _sdkClosedWithoutAnswer(Future<dynamic> call,
      {Duration grace = const Duration(milliseconds: 600)}) async {
    var answered = false;
    // Only observes the call; its result and errors are still handled by _invoke.
    unawaited(call.then((_) => answered = true, onError: (_) => answered = true));
    DateTime? closedSince;
    while (!answered) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (answered) break;
      bool closed;
      try {
        closed = await _channel.invokeMethod<bool>('topSdkScreensClosed') == true;
      } catch (_) {
        break; // older native side: wait for the SDK's answer as before
      }
      if (!closed) {
        closedSince = null;
      } else if (DateTime.now().difference(closedSince ??= DateTime.now()) >= grace) {
        return answered ? Completer<Object>().future : _screensClosed;
      }
    }
    return Completer<Object>().future;
  }

  /// Before an automatic retry: let the native side start from a fresh SDK service.
  Future<void> _resetSdkService() async {
    try {
      await _channel.invokeMethod('resetTopService');
    } catch (_) {
      // Older native side without it: the retry still re-registers the session.
    }
  }

  /// The SDK may still answer after [_invoke] gave up. Record that answer, and
  /// when it approves a payment, raise [onLateResult]: the card was charged
  /// but the app saved no sale, so the cashier must not simply charge again.
  void _reportLateResult(
    Future<dynamic> call,
    String operation,
    Map<String, dynamic> reportArgs,
    Duration timeout,
    bool chargesCard, {
    String? reason,
  }) {
    final lateOperation = '$operation (late, ${reason ?? 'after ${timeout.inSeconds}s timeout'})';
    call.then((result) async {
      if (result is! Map) return;
      final map = Map<String, dynamic>.from(result);
      final approved = chargesCard && _isApproved(map);
      final report = await PaymentDiagnostics.record(
        source: PaymentSource.dejavoo,
        operation: lateOperation,
        args: reportArgs,
        outcome: approved
            ? DejavooOutcome.approved
            : (chargesCard ? DejavooOutcome.declined : DejavooOutcome.error),
        code: '${map['response_code'] ?? map['status'] ?? 'LATE_RESULT'}',
        message: '${map['message'] ?? ''}',
        response: _withoutDiagnostics(map),
        diagnostics: _diagnosticsOf(map),
        warning: approved
            ? 'Tap to Pay approved this payment after the app stopped waiting. '
                'The card was charged but no sale was saved. Check the transaction '
                'before charging the customer again.'
            : null,
      );
      if (approved) onLateResult?.call(report);
    }).catchError((Object error, StackTrace stack) async {
      final details = error is PlatformException && error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null;
      await DejavooDiagnostics.record(
        operation: lateOperation,
        args: reportArgs,
        outcome: DejavooOutcome.error,
        code: error is PlatformException ? error.code : 'LATE_ERROR',
        message: error is PlatformException ? (error.message ?? '') : '$error',
        response: details == null ? null : _withoutDiagnostics(details),
        diagnostics: details == null ? null : _diagnosticsOf(details),
        dartError: error,
        dartStack: stack,
      );
    });
  }

  static Map<String, dynamic> _withoutDiagnostics(Map<String, dynamic> map) =>
      Map<String, dynamic>.from(map)..remove('diagnostics');

  static Map<String, dynamic>? _diagnosticsOf(Map<String, dynamic> map) {
    final diagnostics = map['diagnostics'];
    return diagnostics is Map ? Map<String, dynamic>.from(diagnostics) : null;
  }

  static String _last4(String value) =>
      value.length <= 4 ? value : value.substring(value.length - 4);

  Future<TopTransactionResult> sale({
    required double amount,
    Map<String, dynamic>? customObject,
  }) {
    return _performTransaction(
      type: TopTransactionType.sale,
      amount: amount.toStringAsFixed(2),
      customObject: customObject,
    );
  }

  Future<TopTransactionResult> refund({
    required double amount,
    Map<String, dynamic>? customObject,
  }) {
    return _performTransaction(
      type: TopTransactionType.refund,
      amount: amount.toStringAsFixed(2),
      customObject: customObject,
    );
  }

  Future<TopTransactionResult> voidTransaction({
    Map<String, dynamic>? customObject,
  }) {
    return _performTransaction(type: TopTransactionType.voidTxn, customObject: customObject);
  }

  /// Sale with the card number typed in on the SDK's own form (skinless SDK,
  /// PaymentMode.KEY_IN). Sales only: the SDK has no manual refund / void.
  Future<TopTransactionResult> manualSale({
    required double amount,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
  }) async {
    // Same registration as tap payments, so the TPN is known to the SDK.
    await _ensureValidSession();
    final credentials = await _credentials();
    const operation = 'TOP MANUAL SALE';
    final args = {
      'tpn': credentials.tpn,
      'amount': amount.toStringAsFixed(2),
      'lang': L10n.lang == AppLang.en ? 'en' : 'iw',
      'name': customerName ?? '',
      'phone': customerPhone ?? '',
      'email': customerEmail ?? '',
    };

    final map = await _invoke(operation, 'startManualEntry', args,
        timeout: _manualEntryTimeout, chargesCard: true, reportArgs: args);

    _throwIfCancelResponse(operation, map);
    // Same rule as tap sales: response_code "00" = approved.
    final responseCode = map['response_code'];
    final approved = _isApproved(map);

    final report = await DejavooDiagnostics.record(
      operation: operation,
      args: args,
      outcome: approved ? DejavooOutcome.approved : DejavooOutcome.declined,
      code: '${responseCode ?? map['status'] ?? ''}',
      message: '${map['message'] ?? ''}',
      response: _withoutDiagnostics(map),
      diagnostics: _diagnosticsOf(map),
    );
    return TopTransactionResult(
        approved: approved, raw: withCardFallback(_withoutDiagnostics(map)), report: report);
  }
}
