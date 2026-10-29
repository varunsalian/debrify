// The once-a-day addon auto-update pass: due rule, enable switch, permission
// gate, last-run bookkeeping, and per-addon refresh with profile-switch
// cancellation. Scheduling lives with the caller (no timers in this file).
import 'package:flutter/foundation.dart';

import '../models/profiles/profile_policy.dart';
import '../models/stremio_addon.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';
import 'stremio_service.dart';

enum AddonAutoUpdateOutcome {
  disabled,
  notDue,
  unchanged,
  updated,
  failed,
  cancelled,
}

/// What one pass needs; the defaults use [StremioService] and the profile
/// runtime. Every hook is injectable so tests can drive a full pass without
/// network or profile infrastructure.
final class AddonAutoUpdateDeps {
  const AddonAutoUpdateDeps({
    required this.allowed,
    required this.listAddons,
    required this.fetchManifest,
    required this.refreshAddon,
    required this.stillCurrent,
  });

  /// Whether the active profile may manage addons at all.
  final Future<bool> Function() allowed;

  /// The addons currently installed (management view).
  final Future<List<StremioAddon>> Function() listAddons;

  /// Fetches the live manifest for one addon; throws when unreachable.
  final Future<StremioAddon> Function(String manifestUrl) fetchManifest;

  /// Re-reads and saves one addon; null means the refresh failed.
  final Future<StremioAddon?> Function(String manifestUrl) refreshAddon;

  /// Whether the pass is still running for the profile it started on.
  final bool Function() stillCurrent;

  /// The production wiring: [StremioService.instance] plus the profile
  /// runtime. [stillCurrent] compares [ProfileRuntime.scope] with its value
  /// when this factory ran, so a profile switch mid-pass cancels the rest.
  static AddonAutoUpdateDeps production() {
    final startedScope = ProfileRuntime.scope.value;
    return AddonAutoUpdateDeps(
      allowed: () async {
        try {
          final authorization = await ProfileAsyncAuthorization.capture(
            ProfileFeature.addonsAndEngines,
          );
          // Null means legacy unscoped compatibility mode: management stays
          // allowed there, exactly like the rest of StremioService.
          return authorization == null || authorization.isCurrentlyActive;
        } catch (_) {
          return false;
        }
      },
      listAddons: () => StremioService.instance.getAddonsForManagement(),
      fetchManifest: (manifestUrl) =>
          StremioService.instance.fetchManifest(manifestUrl),
      refreshAddon: (manifestUrl) =>
          StremioService.instance.refreshAddon(manifestUrl),
      stillCurrent: () => ProfileRuntime.scope.value == startedScope,
    );
  }
}

/// The pass itself: stateless, never rethrows, and records the run time
/// before fetching so a failed pass waits a full interval before retrying.
final class AddonAutoUpdate {
  const AddonAutoUpdate._();

  static const enabledKey = 'stremio_addons_auto_update_v1';
  static const lastRunKey = 'stremio_addons_auto_update_last_ms_v1';
  static const interval = Duration(hours: 24);

  /// Due when never run, when [interval] has passed, or when the stored time
  /// is more than [interval] in the future (the clock moved back).
  static bool isDue({required int? lastRunMs, required DateTime now}) {
    if (lastRunMs == null) return true;
    final elapsed = now.difference(
      DateTime.fromMillisecondsSinceEpoch(lastRunMs),
    );
    if (elapsed.isNegative) {
      return elapsed.abs() > interval;
    }
    return elapsed >= interval;
  }

  static Future<bool> isEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(enabledKey, enabled);
  }

  /// Runs one pass. Never rethrows: any unexpected exception yields
  /// [AddonAutoUpdateOutcome.failed].
  static Future<AddonAutoUpdateOutcome> runIfDue({
    DateTime Function() now = DateTime.now,
    AddonAutoUpdateDeps? deps,
  }) async {
    try {
      return await _run(
        now: now,
        deps: deps ?? AddonAutoUpdateDeps.production(),
      );
    } catch (error, stack) {
      debugPrint('AddonAutoUpdate: unexpected failure: $error\n$stack');
      return AddonAutoUpdateOutcome.failed;
    }
  }

  static Future<AddonAutoUpdateOutcome> _run({
    required DateTime Function() now,
    required AddonAutoUpdateDeps deps,
  }) async {
    if (!await isEnabled()) return AddonAutoUpdateOutcome.disabled;
    if (!await deps.allowed()) return AddonAutoUpdateOutcome.disabled;

    final prefs = await ProfilePreferences.instance();
    final timestamp = now();
    if (!isDue(lastRunMs: prefs.getInt(lastRunKey), now: timestamp)) {
      return AddonAutoUpdateOutcome.notDue;
    }

    // Record before fetching: a crash or a failed pass must wait a full
    // interval before the next attempt.
    await prefs.setInt(lastRunKey, timestamp.millisecondsSinceEpoch);

    final addons = await deps.listAddons();
    var updated = 0;
    var failures = 0;
    for (final addon in addons) {
      if (!addon.canManage) continue;
      if (!deps.stillCurrent()) return AddonAutoUpdateOutcome.cancelled;
      final url = addon.manifestUrl;
      StremioAddon? fetched;
      try {
        fetched = await deps.fetchManifest(url);
      } catch (_) {
        failures++;
        continue;
      }
      if (fetched.version == addon.version) continue;
      final refreshed = await deps.refreshAddon(url);
      if (refreshed == null) {
        failures++;
      } else {
        updated++;
      }
    }

    if (updated > 0) return AddonAutoUpdateOutcome.updated;
    if (failures > 0) return AddonAutoUpdateOutcome.failed;
    return AddonAutoUpdateOutcome.unchanged;
  }
}
