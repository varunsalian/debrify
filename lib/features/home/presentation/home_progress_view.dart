import 'dart:collection';

/// Read-only live progress for legacy grids that retain their input map while
/// the originating controller replaces immutable snapshots. Owns no data.
class HomeProgressView extends MapBase<String, double> {
  HomeProgressView(this._read);

  final Map<String, double> Function() _read;

  @override
  double? operator [](Object? key) => _read()[key];

  @override
  Iterable<String> get keys => _read().keys;

  @override
  void operator []=(String key, double value) =>
      throw UnsupportedError('Progress is owned by its controller');

  @override
  void clear() => throw UnsupportedError('Progress is owned by its controller');

  @override
  double? remove(Object? key) =>
      throw UnsupportedError('Progress is owned by its controller');
}
