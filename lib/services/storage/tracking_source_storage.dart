import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/tracking_scrobble_preferences.dart';
import 'package:flutter/foundation.dart';

final class TrackingSourceStorage {
  const TrackingSourceStorage._();
  static const String trackingScrobbleTargetsKey = TrackingScrobblePreferences.key;
  static const String watchProgressSourceKey = 'watch_progress_source';
  static const String homeTickSourcesKey = 'home_tick_sources';

  /// Invalidates policy consumers that keep an in-memory snapshot.
  static final ValueNotifier<int> trackingSourceRevision = ValueNotifier(0);

  // Tracking source policy -------------------------------------------------

  static const Set<TrackingSource> _allTrackingSources = <TrackingSource>{
    TrackingSource.local,
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  };

  /// Reads the new master scrobble switches. On first read, adopt the retired
  /// per-tracker catalog switches once. An absent legacy value means ON: that
  /// matches interactive connection and old Trakt/Simkl restore behavior.
  static Future<Set<TrackingSource>> getTrackingScrobbleTargets({
    bool Function()? canContinue,
  }) => TrackingScrobblePreferences.readCurrent(canContinue: canContinue);

  static Future<void> setTrackingScrobbleTargets(
    Set<TrackingSource> value,
  ) async {
    await TrackingScrobblePreferences.writeCurrent(value);
    trackingSourceRevision.value++;
  }

  /// Turns on scrobbling for a newly connected tracker without disturbing the
  /// user's choices for any other tracker. Connection flows call this after
  /// authentication succeeds so reconnecting restores the provider's default
  /// ON state even when it had previously been unticked.
  static Future<void> enableTrackingScrobbleTarget(
    TrackingSource source,
  ) async {
    final changed = await TrackingScrobblePreferences.enableCurrent(source);
    if (changed) trackingSourceRevision.value++;
  }

  static Future<WatchProgressSource> getWatchProgressSource() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getString(watchProgressSourceKey);
    return WatchProgressSource.values.firstWhere(
      (source) => source.name == stored,
      orElse: () => WatchProgressSource.smart,
    );
  }

  static Future<void> setWatchProgressSource(WatchProgressSource value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(watchProgressSourceKey, value.name);
    trackingSourceRevision.value++;
  }

  static Future<bool> fallbackDisconnectedProgressSource(
    TrackingSource disconnected, {
    bool Function()? canContinue,
  }) async {
    if (!(canContinue?.call() ?? true)) return false;
    final current = await getWatchProgressSource();
    if (!(canContinue?.call() ?? true)) return false;
    final owns = switch (current) {
      WatchProgressSource.trakt => disconnected == TrackingSource.trakt,
      WatchProgressSource.simkl => disconnected == TrackingSource.simkl,
      WatchProgressSource.mdblist => disconnected == TrackingSource.mdblist,
      _ => false,
    };
    if (!owns) return false;
    if (canContinue != null) {
      final prefs = await ProfilePreferences.instance();
      if (!canContinue()) return false;
      await prefs.setString(
        watchProgressSourceKey,
        WatchProgressSource.smart.name,
        canCommit: canContinue,
      );
      if (!canContinue()) return false;
      trackingSourceRevision.value++;
      if (!canContinue()) return false;
      await prefs.setBool(
        'tracking_progress_fallback_notice',
        true,
        canCommit: canContinue,
      );
      return canContinue();
    }
    await setWatchProgressSource(WatchProgressSource.smart);
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tracking_progress_fallback_notice', true);
    return true;
  }

  static Future<bool> takeTrackingProgressFallbackNotice() async {
    final prefs = await ProfilePreferences.instance();
    final pending = prefs.getBool('tracking_progress_fallback_notice') ?? false;
    if (pending) await prefs.remove('tracking_progress_fallback_notice');
    return pending;
  }

  static Future<Set<TrackingSource>> getHomeTickSources() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(homeTickSourcesKey);
    if (stored == null) return Set<TrackingSource>.of(_allTrackingSources);
    return <TrackingSource>{
      for (final value in stored)
        if (TrackingSourceStorageName.parse(value) case final source?) source,
    };
  }

  static Future<void> setHomeTickSources(Set<TrackingSource> value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = value.where(_allTrackingSources.contains).toSet();
    await prefs.setStringList(
      homeTickSourcesKey,
      normalized.map((source) => source.storageName).toList(growable: false),
    );
    trackingSourceRevision.value++;
  }

  static Future<Map<String, dynamic>> buildTrackingPreferencesPayload() async {
    final scrobble = await getTrackingScrobbleTargets();
    final progress = await getWatchProgressSource();
    final ticks = await getHomeTickSources();
    return <String, dynamic>{
      'scrobble_targets': scrobble.map((source) => source.storageName).toList(growable: false),
      'progress_source': progress.name,
      'home_tick_sources': ticks.map((source) => source.storageName).toList(growable: false),
      'hide_watched': await HideWatchedPrefs.read(),
    };
  }

  /// Re-adopts the legacy per-tracker switches after restoring an OLD backup
  /// with no tracking payload. The masters were already seeded on first policy
  /// read at app start, so without this the restored legacy values — notably an
  /// MDBList sync-catalog OFF — would be silently ignored.
  static Future<void> reseedTrackingScrobbleTargetsFromLegacy() async {
    await TrackingScrobblePreferences.reseedCurrentFromLegacy();
    trackingSourceRevision.value++;
  }

  /// Applies only explicitly present new-format preferences. Old backups omit
  /// this object; [reseedTrackingScrobbleTargetsFromLegacy] runs on that
  /// restore path instead so the restored legacy switches are re-adopted by
  /// [getTrackingScrobbleTargets], preserving the absent-key migration rule.
  static Future<void> applyTrackingPreferencesPayload(
    Map<dynamic, dynamic> payload,
  ) async {
    final scrobble = payload['scrobble_targets'];
    if (scrobble is List) {
      await setTrackingScrobbleTargets(<TrackingSource>{
        for (final value in scrobble.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final progress = payload['progress_source'];
    if (progress is String) {
      final parsed = WatchProgressSource.values.where((source) => source.name == progress).firstOrNull;
      if (parsed != null) await setWatchProgressSource(parsed);
    }
    final ticks = payload['home_tick_sources'];
    if (ticks is List) {
      await setHomeTickSources(<TrackingSource>{
        for (final value in ticks.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final hideWatched = payload['hide_watched'];
    if (hideWatched is bool) await HideWatchedPrefs.setEnabled(hideWatched);
  }
}
