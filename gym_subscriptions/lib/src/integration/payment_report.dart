// Reports of card payment attempts (Dejavoo Tap to Pay), as in the AURA POS app
// (pos-app lib/services/payment_diagnostics.dart): what was sent, what came back
// and any error, with card tokens, passwords and long card numbers removed.
// The POS app also sends them to Crashlytics; this app has no Crashlytics, so a
// report is printed to the log and kept in [PaymentDiagnostics.recent], and the
// error message offers to copy it (to send to Dejavoo / support).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum PaymentOutcome { approved, declined, error }

/// Where a report comes from; also gives the Report ID its prefix.
enum PaymentSource {
  dejavoo('Dejavoo', 'DV');

  final String label;
  final String idPrefix;

  const PaymentSource(this.label, this.idPrefix);
}

class PaymentReport {
  final String id;
  final DateTime time;
  final PaymentSource source;
  final String operation;
  final Map<String, dynamic> args;
  final PaymentOutcome outcome;
  final String code;
  final String message;
  final Map<String, dynamic> response;
  final Map<String, dynamic> diagnostics;
  final String? dartError;
  final Map<String, String> environment;

  /// Shown highlighted, e.g. when the card was already charged but the sale could not be saved.
  final String? warning;

  PaymentReport({
    required this.id,
    required this.time,
    required this.source,
    required this.operation,
    required this.args,
    required this.outcome,
    required this.code,
    required this.message,
    required this.response,
    required this.diagnostics,
    required this.environment,
    this.dartError,
    this.warning,
  });

  String toText() {
    const encoder = JsonEncoder.withIndent('  ');
    final buffer = StringBuffer()
      ..writeln('=== ${source.label} report ===')
      ..writeln('Report ID: $id')
      ..writeln('Time: ${time.toIso8601String()}')
      ..writeln('Operation: $operation')
      ..writeln('Outcome: ${outcome.name}')
      ..writeln('Code: $code')
      ..writeln('Message: $message');
    if (warning != null) buffer.writeln('Warning: $warning');
    environment.forEach((k, v) => buffer.writeln('$k: $v'));
    buffer
      ..writeln('--- Request ---')
      ..writeln(encoder.convert(args));
    if (diagnostics.isNotEmpty) {
      buffer
        ..writeln('--- Diagnostics ---')
        ..writeln(encoder.convert(diagnostics));
    }
    if (response.isNotEmpty) {
      buffer
        ..writeln('--- Response ---')
        ..writeln(encoder.convert(response));
    }
    if (dartError != null) {
      buffer
        ..writeln('--- Dart error ---')
        ..writeln(dartError);
    }
    return buffer.toString();
  }
}

class PaymentDiagnostics {
  /// The latest reports, newest first (at most [_keep]).
  static final List<PaymentReport> recent = [];
  static const _keep = 30;

  // Keys whose values must never end up in a report.
  static final _secretKey = RegExp(r'token|password|secret|authorization|cvv', caseSensitive: false);
  static const _maxTextLength = 8000;

  static Future<PaymentReport> record({
    required PaymentSource source,
    required String operation,
    required Map<String, dynamic> args,
    required PaymentOutcome outcome,
    required String code,
    required String message,
    Map<String, dynamic>? response,
    Map<String, dynamic>? diagnostics,
    Object? dartError,
    StackTrace? dartStack,
    String? warning,
  }) async {
    final now = DateTime.now();
    final report = PaymentReport(
      id: '${source.idPrefix}-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      time: now,
      source: source,
      operation: operation,
      args: _sanitize(args),
      outcome: outcome,
      code: code,
      message: message,
      response: _sanitize(response ?? const {}),
      diagnostics: _sanitize(diagnostics ?? const {}),
      environment: _environment(),
      dartError: dartError == null ? null : '$dartError\n${dartStack ?? ''}',
      warning: warning,
    );
    debugPrint(report.toText());
    recent.insert(0, report);
    if (recent.length > _keep) recent.removeRange(_keep, recent.length);
    return report;
  }

  static Map<String, String> _environment() {
    final env = <String, String>{'App': 'AURA Gym'};
    try {
      env['OS'] = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {}
    return env;
  }

  // Card tokens can charge the card again and user tokens open the account,
  // so keep them out of reports; long card numbers keep only the last 4 digits.
  static Map<String, dynamic> _sanitize(Map<String, dynamic> map) =>
      map.map((key, value) => MapEntry(key, _sanitizeValue(key, value)));

  static Object? _sanitizeValue(String key, Object? value) {
    if (value == null) return null;
    if (_secretKey.hasMatch(key)) return '<redacted>';
    if (value is Map) return _sanitize(Map<String, dynamic>.from(value));
    if (value is List) return value.map((item) => _sanitizeValue(key, item)).toList();
    if (key.toLowerCase().contains('card')) {
      final digits = '$value'.replaceAll(RegExp(r'[\s-]'), '');
      if (RegExp(r'^\d{8,}$').hasMatch(digits)) {
        return '****${digits.substring(digits.length - 4)}';
      }
    }
    if (value is String) return value.length <= _maxTextLength ? value : '${value.substring(0, _maxTextLength)}…';
    return value;
  }
}

/// Dejavoo (Tap to Pay) reports are [PaymentReport]s from [PaymentSource.dejavoo];
/// these names are kept so the Tap to Pay service reads as in the POS app.
typedef DejavooReport = PaymentReport;
typedef DejavooOutcome = PaymentOutcome;

class DejavooDiagnostics {
  static Future<DejavooReport> record({
    required String operation,
    required Map<String, dynamic> args,
    required DejavooOutcome outcome,
    required String code,
    required String message,
    Map<String, dynamic>? response,
    Map<String, dynamic>? diagnostics,
    Object? dartError,
    StackTrace? dartStack,
  }) =>
      PaymentDiagnostics.record(
        source: PaymentSource.dejavoo,
        operation: operation,
        args: args,
        outcome: outcome,
        code: code,
        message: message,
        response: response,
        diagnostics: diagnostics,
        dartError: dartError,
        dartStack: dartStack,
      );
}
