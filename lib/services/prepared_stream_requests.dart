/// Shares active requests and optionally retains one speculative result.
/// Foreground reads consume preparation so playback retries always fetch fresh.
class PreparedStreamRequests<T> {
  PreparedStreamRequests({DateTime Function()? now, this.onEvent})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final void Function(String event)? onEvent;
  final _pending = <Object, Future<T>>{};
  final _foreground = <Object>{};
  final _prepared = <Object, ({T value, DateTime expires})>{};
  int _generation = 0;

  void clear() {
    _generation++;
    _prepared.clear();
  }

  Future<T> get(
    Object requestKey,
    Future<T> Function() load, {
    bool prepare = false,
    Duration lifetime = const Duration(minutes: 2),
    DateTime? Function(T)? expiresAt,
  }) async {
    final generation = _generation;
    final key = (generation, requestKey);
    _prepared.removeWhere((_, entry) => !entry.expires.isAfter(_now()));
    final ready = prepare ? _prepared[key] : _prepared.remove(key);
    if (ready != null) {
      onEvent?.call('prepared_hit');
      return ready.value;
    }
    if (!prepare) _foreground.add(key);
    final running = _pending[key];
    if (running != null) {
      onEvent?.call('request_join');
      return running;
    }
    final request = Future<T>.sync(load);
    _pending[key] = request;
    try {
      final value = await request;
      if (prepare && generation == _generation && !_foreground.contains(key)) {
        var expiry = _now().add(lifetime);
        final explicit = expiresAt?.call(value);
        if (explicit != null && explicit.isBefore(expiry)) expiry = explicit;
        if (expiry.isAfter(_now())) {
          while (_prepared.length >= 4) {
            _prepared.remove(_prepared.keys.first);
          }
          _prepared[key] = (value: value, expires: expiry);
          onEvent?.call('prepared_ready');
        }
      }
      return value;
    } finally {
      _pending.remove(key);
      _foreground.remove(key);
    }
  }
}
