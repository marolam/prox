class StreamCache<T> {
  StreamCache(this._factory);

  final Stream<T> Function(String key) _factory;
  final Map<String, Stream<T>> _streams = <String, Stream<T>>{};

  Stream<T> get(String key) {
    final clean = key.trim();
    return _streams.putIfAbsent(clean, () => _factory(clean));
  }

  void clear([String? key]) {
    if (key == null) {
      _streams.clear();
      return;
    }
    _streams.remove(key.trim());
  }
}
