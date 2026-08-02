// lib/data/datasources/local/cache_datasource.dart
class CacheDataSource {
  static final Map<String, _CacheEntry> _store = {};

  static const int _maxSize = 200;
  static const Duration _ttl = Duration(minutes: 55);

  void put(String key, String value) {
    if (_store.length >= _maxSize) {
      final oldest = _store.entries.reduce(
          (a, b) => a.value.insertedAt.isBefore(b.value.insertedAt) ? a : b);
      _store.remove(oldest.key);
    }
    _store[key] = _CacheEntry(value: value, insertedAt: DateTime.now());
  }

  String? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.insertedAt) > _ttl) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  void remove(String key) => _store.remove(key);
  void clear() => _store.clear();
}

class _CacheEntry {
  final String value;
  final DateTime insertedAt;
  _CacheEntry({required this.value, required this.insertedAt});
}
