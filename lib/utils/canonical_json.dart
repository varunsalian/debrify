import 'dart:convert';

String encodeCanonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException('Non-finite WebDAV sync number');
    }
    return value;
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonical(item)];
  }
  if (value is Map) {
    final keys = value.keys.toList(growable: false);
    if (keys.any((key) => key is! String)) {
      throw const FormatException('WebDAV sync maps require string keys');
    }
    final sorted = keys.cast<String>()..sort();
    return <String, Object?>{
      for (final key in sorted) key: _canonical(value[key]),
    };
  }
  throw const FormatException('Unsupported WebDAV sync JSON value');
}
