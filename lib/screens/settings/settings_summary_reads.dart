import 'dart:async';

import '../../services/profiles/connection_resource_service.dart';

/// Collects independent local summaries without letting one unavailable
/// provider reject the entire Settings load. Fallbacks are presentation only;
/// they must never be written back to connection storage.
class SettingsSummaryReads {
  SettingsSummaryReads({
    required this.onFailure,
    this.overrides = const {},
    this.timeout = const Duration(seconds: 5),
  });

  final void Function(String label, Object error) onFailure;
  final Map<String, Future<Object?> Function()> overrides;
  final Duration timeout;
  final Set<String> failures = {};
  final Set<String> unavailable = {};

  Future<T> read<T>(String label, Future<T> Function() load, T fallback) async {
    try {
      final override = overrides[label];
      return await (override == null
              ? Future<T>.sync(load)
              : Future<T>.sync(() async => await override() as T))
          .timeout(timeout);
    } catch (error) {
      failures.add(label);
      if (error is ResourceAuthorizationException) unavailable.add(label);
      try {
        onFailure(label, error);
      } catch (_) {
        // Diagnostics are best effort too: a logging failure must not undo
        // the isolation of an unavailable connection.
      }
      return fallback;
    }
  }
}
