import 'dart:convert';

import 'package:crypto/crypto.dart';

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

/// Hash canonical JSON without a cloned object graph, complete JSON string, or
/// complete UTF-8 buffer. String fragments stay below 64 KiB of encoded data.
({String sha256, int bytes}) measureCanonicalJson(Object? value) {
  final result = _CanonicalDigestSink();
  final digest = sha256.startChunkedConversion(result);
  var length = 0;
  for (final text in canonicalJsonFragments(value)) {
    final bytes = utf8.encode(text);
    length += bytes.length;
    digest.add(bytes);
  }
  digest.close();
  return (sha256: result.value!.toString(), bytes: length);
}

Iterable<String> canonicalJsonFragments(Object? value) sync* {
  if (value is String) {
    yield '"';
    var start = 0;
    while (start < value.length) {
      var end = (start + 16384).clamp(0, value.length);
      if (end < value.length &&
          value.codeUnitAt(end - 1) >= 0xd800 &&
          value.codeUnitAt(end - 1) <= 0xdbff &&
          value.codeUnitAt(end) >= 0xdc00 &&
          value.codeUnitAt(end) <= 0xdfff) {
        end--;
      }
      final escaped = jsonEncode(value.substring(start, end));
      yield escaped.substring(1, escaped.length - 1);
      start = end;
    }
    yield '"';
  } else if (value == null || value is bool || value is num) {
    if (value is double && !value.isFinite) {
      throw const FormatException('Non-finite WebDAV sync number');
    }
    yield jsonEncode(value);
  } else if (value is List) {
    yield '[';
    var first = true;
    for (final item in value) {
      if (!first) yield ',';
      first = false;
      yield* canonicalJsonFragments(item);
    }
    yield ']';
  } else if (value is Map) {
    final keys = value.keys.toList(growable: false);
    if (keys.any((key) => key is! String)) {
      throw const FormatException('WebDAV sync maps require string keys');
    }
    final sorted = keys.cast<String>()..sort();
    yield '{';
    var first = true;
    for (final key in sorted) {
      if (!first) yield ',';
      first = false;
      yield* canonicalJsonFragments(key);
      yield ':';
      yield* canonicalJsonFragments(value[key]);
    }
    yield '}';
  } else {
    throw const FormatException('Unsupported WebDAV sync JSON value');
  }
}

final class _CanonicalDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
