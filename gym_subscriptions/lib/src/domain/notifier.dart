/// Minimal change notification without Flutter, so the store can be tested
/// with plain Dart. The UI adapts it with [StoreScope].
class SimpleNotifier {
  final List<void Function()> _listeners = [];

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);

  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
