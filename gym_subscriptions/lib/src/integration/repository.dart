// Where the app keeps its data.
//
// Today: [FileGymRepository] saves one JSON snapshot on the device, so nothing
// is lost when the app closes. With the AURA backend, replace it with an
// implementation that loads from and writes to the API (see HANDOFF.md); the
// JSON shapes are the ones produced by the models' toJson().

import 'dart:convert';
import 'dart:io';

abstract class GymRepository {
  /// The last saved snapshot, or null when there is none.
  Map<String, dynamic>? load();

  /// Saves the whole snapshot.
  Future<void> save(Map<String, dynamic> snapshot);

  /// Deletes the saved data.
  Future<void> clear();
}

/// Keeps the snapshot in memory only (tests, previews).
class MemoryGymRepository implements GymRepository {
  Map<String, dynamic>? data;

  @override
  Map<String, dynamic>? load() => data == null ? null : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<void> save(Map<String, dynamic> snapshot) async => data = jsonDecode(jsonEncode(snapshot));

  @override
  Future<void> clear() async => data = null;
}

/// One JSON file on the device.
class FileGymRepository implements GymRepository {
  FileGymRepository(this.file);
  final File file;

  /// The app's private files folder on Android (`/data/user/0/<app>/files`).
  /// Falls back to the temp folder elsewhere.
  static FileGymRepository? onDevice() {
    try {
      final base = Directory.systemTemp.parent;
      final dir = Directory('${base.path}${Platform.pathSeparator}files');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return FileGymRepository(File('${dir.path}${Platform.pathSeparator}aura_gym.json'));
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
      return null; // A broken file is ignored; the app starts with demo data.
    }
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    if (file.existsSync()) await file.delete();
  }
}
