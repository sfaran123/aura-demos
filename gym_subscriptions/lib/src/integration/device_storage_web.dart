import 'dart:convert';
import 'dart:js_interop';

import '../state/auth.dart';
import 'repository.dart';

@JS('localStorage.getItem')
external String? _getItem(String key);

@JS('localStorage.setItem')
external void _setItem(String key, String value);

@JS('localStorage.removeItem')
external void _removeItem(String key);

/// One JSON value under [key] in localStorage. A browser that blocks storage
/// (private mode, site data disabled) just starts empty and saves nothing.
class _LocalJson {
  const _LocalJson(this.key);
  final String key;

  Map<String, dynamic>? load() {
    try {
      final text = _getItem(key);
      return text == null ? null : jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void save(Map<String, dynamic> data) {
    try {
      _setItem(key, jsonEncode(data));
    } catch (_) {}
  }

  void clear() {
    try {
      _removeItem(key);
    } catch (_) {}
  }
}

class _WebGymRepository implements GymRepository {
  static const _store = _LocalJson('aura_gym');

  @override
  Map<String, dynamic>? load() => _store.load();

  @override
  Future<void> save(Map<String, dynamic> snapshot) async => _store.save(snapshot);

  @override
  Future<void> clear() async => _store.clear();
}

class _WebAuthStorage implements AuthStorage {
  static const _store = _LocalJson('aura_session');

  @override
  Map<String, dynamic>? load() => _store.load();

  @override
  Future<void> save(Map<String, dynamic> data) async => _store.save(data);
}

GymRepository? deviceGymRepository() => _WebGymRepository();

AuthStorage? deviceAuthStorage() => _WebAuthStorage();
