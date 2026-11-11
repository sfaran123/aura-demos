// Sign-in state: which business this device is connected to (domain screen)
// and who is signed in (login screen). Both are kept on the device.
//
// Like the AURA POS app, signing out keeps the business, so the next person
// goes straight to the login screen; "Change" on the login screen goes back
// to the domain screen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../integration/aura_api.dart';

enum AuthStage { domain, login, signedIn }

abstract class AuthStorage {
  Map<String, dynamic>? load();
  Future<void> save(Map<String, dynamic> data);
}

class MemoryAuthStorage implements AuthStorage {
  MemoryAuthStorage([this.data]);
  Map<String, dynamic>? data;

  @override
  Map<String, dynamic>? load() => data;

  @override
  Future<void> save(Map<String, dynamic> d) async => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
}

/// One JSON file in the app's private files folder, next to the gym data.
class FileAuthStorage implements AuthStorage {
  FileAuthStorage(this.file);
  final File file;

  static FileAuthStorage? onDevice() {
    try {
      final base = Directory.systemTemp.parent;
      final dir = Directory('${base.path}${Platform.pathSeparator}files');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return FileAuthStorage(File('${dir.path}${Platform.pathSeparator}aura_session.json'));
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, dynamic>? load() {
    try {
      if (!file.existsSync()) return null;
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

class AuthController extends ChangeNotifier {
  AuthController({AuthStorage? storage, AuraApi? api})
      : _storage = storage ?? MemoryAuthStorage(),
        api = api ?? AuraApi() {
    final saved = _storage.load();
    _workspace = AuraWorkspace.fromJson(saved?['workspace']);
    _session = _workspace == null ? null : AuraSession.fromJson(saved?['session']);
  }

  final AuthStorage _storage;
  final AuraApi api;

  AuraWorkspace? _workspace;
  AuraSession? _session;
  bool _busy = false;

  AuraWorkspace? get workspace => _workspace;
  AuraSession? get session => _session;
  bool get busy => _busy;

  AuthStage get stage => _workspace == null
      ? AuthStage.domain
      : _session == null
          ? AuthStage.login
          : AuthStage.signedIn;

  /// Domain screen: checks the company with /verify, then saves it.
  Future<void> connect({required String domain, required String company}) => _run(() async {
        final ws = AuraWorkspace(domain: AuraConfig.normalizeDomain(domain), company: AuraConfig.normalizeCompany(company));
        await api.verifyCompany(domain: ws.domain, company: ws.company);
        _workspace = ws;
        _session = null;
        await _save();
      });

  /// Login screen.
  Future<void> signIn({required String name, required String password}) => _run(() async {
        final ws = _workspace;
        if (ws == null) return;
        _session = await api.login(ws, name: name.trim(), password: password);
        _sessionExpired = false;
        await _save();
      });

  /// Back to the domain screen (the business is forgotten).
  Future<void> changeWorkspace() async {
    _session = null;
    _workspace = null;
    _sessionExpired = false;
    await _save();
    notifyListeners();
  }

  /// Forgets the user but keeps the business. [expired]: the server no longer
  /// accepts the token; the login screen says so.
  Future<void> signOut({bool expired = false}) async {
    _session = null;
    _sessionExpired = expired;
    await _save();
    notifyListeners();
  }

  bool _sessionExpired = false;

  /// The last sign-out happened because the server rejected the token.
  bool get sessionExpired => _sessionExpired;

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await f();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _save() => _storage.save({
        if (_workspace != null) 'workspace': _workspace!.toJson(),
        if (_session != null) 'session': _session!.toJson(),
      });
}
