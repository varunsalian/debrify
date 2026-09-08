import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/metadata_preferences.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

/// Reads the current profile facade, memoizing only decoding of unchanged JSON.
abstract final class MetadataPreferencesService {
  static const key = 'metadata_providers_v1';
  static final revision = ValueNotifier<int>(0);

  static String? _decodedRaw;
  static Object? _decodedScope;
  static MetadataPreferences? _decoded;

  static Future<MetadataPreferences> load() async {
    final scope = ProfileRuntime.scope.value;
    final prefs = await ProfilePreferences.instance();
    if (scope != ProfileRuntime.scope.value) {
      throw StateError('Profile changed while loading metadata preferences');
    }
    final raw = prefs.getString(key);
    if (_decoded != null && _decodedScope == scope && _decodedRaw == raw) {
      return _decoded!;
    }
    final decoded = _decode(raw);
    _decodedScope = scope;
    _decodedRaw = raw;
    return _decoded = decoded;
  }

  static MetadataPreferences _decode(String? raw) {
    if (raw == null) return MetadataPreferences();
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        return MetadataPreferences.fromJson(data);
      }
    } on FormatException {
      // A malformed imported preference must not break browsing.
    }
    return MetadataPreferences();
  }

  /// Optional background work must stop on unavailable or invalidated policy,
  /// rather than assume defaults or leak an unhandled asynchronous exception.
  static Future<MetadataPreferences?> loadForBackground({
    required bool Function() isCurrent,
    @visibleForTesting Future<MetadataPreferences> Function()? read,
  }) async {
    if (!isCurrent()) return null;
    try {
      final preferences = await (read ?? load)();
      return isCurrent() ? preferences : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MetadataPreferences value) async {
    final scope = ProfileRuntime.scope.value;
    final prefs = await ProfilePreferences.instance();
    if (scope != ProfileRuntime.scope.value) {
      throw StateError('Profile changed while saving metadata preferences');
    }
    if (!await prefs.setString(key, jsonEncode(value.toJson()))) {
      throw StateError('Could not save metadata preferences');
    }
    revision.value++;
  }
}
