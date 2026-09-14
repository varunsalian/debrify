import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'diagnostic_log.dart';
import 'profiles/profile_database_adoption_gate.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

/// Explicitly opted-in local release instrumentation. Never logs content or
/// credentials, and never queries a database or waits for an application lock.
abstract final class LocalValidationDiagnostics {
  static const enabled = bool.fromEnvironment('DEBRIFY_LOCAL_VALIDATION');
  static const build = String.fromEnvironment('DEBRIFY_VALIDATION_BUILD');
  static Timer? _heartbeat;

  static void event(String name, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    try {
      DiagnosticLog.instance.recordEvent(
        source: 'local_validation',
        event: name,
        fields: fields,
      );
    } catch (_) {
      // Instrumentation cannot become an app dependency.
    }
  }

  static void start() {
    if (!enabled || _heartbeat != null) return;
    event('validation_start', {'build': DiagnosticLabel(build)});
    ProfileRuntime.scope.addListener(() {
      final scope = ProfileRuntime.scope.value;
      event('scope_published', {
        'epoch': scope?.sessionEpoch,
        'generation': scope?.dataGeneration,
      });
    });
    final elapsed = Stopwatch()..start();
    var previous = 0;
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = elapsed.elapsedMilliseconds;
      final gap = now - previous;
      previous = now;
      event('heartbeat', {
        'gapMs': gap,
        'lifecycle': DiagnosticLabel(
          WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
        ),
        'rssBytes': ProcessInfo.currentRss,
        'epoch': ProfileRuntime.scope.value?.sessionEpoch,
        'generation': ProfileRuntime.scope.value?.dataGeneration,
        'databaseGateHeld': ProfileDatabaseAdoptionGate.isHeld,
        ...ProfilePreferences.diagnosticMutationState,
      });
    });
  }
}
