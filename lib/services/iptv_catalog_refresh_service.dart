import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/iptv_playlist.dart';
import '../models/profiles/profile_policy.dart';
import 'iptv_catalog_db.dart';
import 'iptv_catalog_key.dart';
import 'iptv_service.dart';
import 'iptv_load_phase.dart';
import 'player_visibility.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';
import 'storage_service.dart';
import 'xtream_codes_service.dart';

/// One download/ingest at a time, shared by launch, settings and source search.
/// Catalog generations remain readable until the service publishes a complete
/// replacement. No timer or retry deletes existing catalog rows.
class IptvCatalogRefreshService with WidgetsBindingObserver {
  IptvCatalogRefreshService._();
  static final instance = IptvCatalogRefreshService._();
  static const intervalKey = 'iptv_catalog_refresh_hours_v1';
  static const intervals = [0, 6, 12, 24, 48];
  final _pending = <_CatalogRefreshJob>[];
  final _jobs = <String, _CatalogRefreshJob>{};
  final _retryAfter = <String, DateTime>{};
  final _failures = <String, int>{};
  final revision = ValueNotifier<int>(0);
  Timer? _timer;
  Timer? _launchTimer;
  bool _running = false;
  bool _checking = false;
  bool _started = false;
  bool _foreground = true;

  static Future<int> getIntervalHours() async {
    final value = (await ProfilePreferences.instance()).getInt(intervalKey);
    return intervals.contains(value) ? value! : 24;
  }

  static Future<void> setIntervalHours(int hours) async {
    if (!intervals.contains(hours)) throw ArgumentError.value(hours);
    await (await ProfilePreferences.instance()).setInt(intervalKey, hours);
    if (hours != 0) unawaited(instance.refreshDue());
  }

  void start() {
    if (_started || kIsWeb) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    ProfileRuntime.scope.addListener(_scopeChanged);
    PlayerVisibility.visible.addListener(_playerChanged);
    // Let first paint, startup navigation and profile activation settle.
    _launchTimer = Timer(const Duration(seconds: 15), () {
      unawaited(refreshDue());
    });
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_foreground) unawaited(refreshDue());
    });
  }

  void _scopeChanged() {
    _launchTimer?.cancel();
    _retryAfter.clear();
    _failures.clear();
    _launchTimer = Timer(const Duration(seconds: 15), () {
      if (_foreground) unawaited(refreshDue());
    });
  }

  void _playerChanged() {
    if (!PlayerVisibility.visible.value) unawaited(_pump());
  }

  void dispose() {
    _timer?.cancel();
    _launchTimer?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      ProfileRuntime.scope.removeListener(_scopeChanged);
      PlayerVisibility.visible.removeListener(_playerChanged);
    }
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(refreshDue());
      unawaited(_pump());
    }
  }

  /// A due check is cheap: only catalog metadata is read, never channel lists.
  Future<void> refreshDue() async {
    if (kIsWeb || _checking || (_started && !_foreground)) return;
    _checking = true;
    final scope = ProfileRuntime.scope.value;
    try {
      if (await getIntervalHours() == 0) return;
      // Refresh uses connection-use authorization, not settings visibility:
      // shared/restricted profiles need usable credentials, and disabled
      // connections must not be scheduled.
      final playlists = await StorageService.getIptvPlaylists(
        forSettings: false,
      );
      if (scope != ProfileRuntime.scope.value || playlists.isEmpty) return;
      for (final playlist in playlists) {
        if (playlist.isLocalFile || playlist.isVirtual) continue;
        // VOD discovery must work even if the IPTV screen is never opened.
        for (final type
            in playlist.isXtreamCodes
                ? const ['vod', 'series', 'live']
                : const ['live']) {
          unawaited(refreshCatalog(playlist, type));
        }
      }
    } catch (error) {
      debugPrint('IPTV refresh discovery failed (${error.runtimeType})');
    } finally {
      _checking = false;
    }
  }

  Future<IptvParseResult> refreshCatalog(
    IptvPlaylist playlist,
    String contentType, {
    bool force = false,
    bool priority = false,
    IptvLoadPhase? onPhase,
  }) async {
    final scope = ProfileRuntime.scope.value;
    final catalogKey = IptvCatalogKey.forPlaylist(playlist, contentType);
    if (kIsWeb || catalogKey == null) return _failure('Source cannot refresh');
    try {
      final hours = await getIntervalHours();
      if (!force && hours == 0) return _failure('Automatic updates are off');
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      if (scope != ProfileRuntime.scope.value) {
        return _failure('Profile changed');
      }
      // A queued job must never capture the destination profile after a switch.
      final id = '${scope?.profileId}:${scope?.sessionEpoch}:$catalogKey';
      final existing = _jobs[id];
      if (existing != null) {
        if (onPhase != null) existing.listeners.add(onPhase);
        if (force) existing.force = true;
        if (priority && _pending.remove(existing)) {
          _pending.insert(0, existing);
        }
        unawaited(_pump());
        return existing.done.future;
      }
      if (!force && (_retryAfter[id]?.isAfter(DateTime.now()) ?? false)) {
        return _failure('Refresh will retry later');
      }
      late final _CatalogRefreshJob job;
      job = _CatalogRefreshJob(id, () async {
        bool current() =>
            scope == ProfileRuntime.scope.value &&
            (job.force || !PlayerVisibility.visible.value);
        Future<IptvParseResult> perform() async {
          if (!current()) return _failure('Profile changed');
          final hours = await getIntervalHours();
          if (!job.force && hours == 0) {
            return _failure('Automatic updates are off');
          }
          await IptvCatalogDb.open();
          if (!current() || !IptvCatalogDb.isOpen) {
            return _failure('Catalog database unavailable');
          }
          // Recheck at execution time: a manual/page refresh may have run while
          // this job was queued. Never fall back to an in-memory catalog load.
          final snapshot = IptvCatalogDb.snapshot(catalogKey);
          if (!job.force &&
              !isDue(snapshot?.ingestedAt, hours, DateTime.now())) {
            return IptvParseResult(
              channels: const [],
              categories: snapshot!.categories,
              epgUrl: snapshot.epgUrl,
              ingest: CatalogIngestReceipt(
                catalogKey: catalogKey,
                channelCount: snapshot.channelCount,
                contentDigest: snapshot.contentDigest,
              ),
            );
          }
          if (playlist.isXtreamCodes) {
            job.didFetch = true;
            final service = XtreamCodesService.instance;
            service.clearCache(playlist.serverUrl);
            final fetch = switch (contentType) {
              'vod' => service.fetchVodStreams,
              'series' => service.fetchSeriesStreams,
              _ => service.fetchLiveStreams,
            };
            // Preserve stable live numbering; the method signatures otherwise
            // share the same authorization and cancellation arguments.
            if (contentType == 'live') {
              return service.fetchLiveStreams(
                playlist.serverUrl!,
                playlist.username ?? '',
                playlist.password ?? '',
                numberingSourceKey: playlist.id,
                connectionResourceId: playlist.connectionResourceId,
                connectionResourceRevision: playlist.connectionResourceRevision,
                isCurrent: current,
                onPhase: job.report,
              );
            }
            return fetch(
              playlist.serverUrl!,
              playlist.username ?? '',
              playlist.password ?? '',
              connectionResourceId: playlist.connectionResourceId,
              connectionResourceRevision: playlist.connectionResourceRevision,
              isCurrent: current,
              onPhase: job.report,
            );
          }
          job.didFetch = true;
          return IptvService.instance.fetchPlaylist(
            playlist.url,
            forceRefresh: true,
            numberingSourceKey: playlist.id,
            connectionResourceId: playlist.connectionResourceId,
            connectionResourceRevision: playlist.connectionResourceRevision,
            isCurrent: current,
            onPhase: job.report,
          );
        }

        return capability == null
            ? perform()
            : capability.runIfCurrent(perform);
      }, force: force);
      if (onPhase != null) job.listeners.add(onPhase);
      _jobs[id] = job;
      if (priority) {
        _pending.insert(0, job);
      } else {
        _pending.add(job);
      }
      unawaited(_pump());
      return job.done.future;
    } catch (error) {
      return _failure('Refresh unavailable (${error.runtimeType})');
    }
  }

  @visibleForTesting
  static bool isDue(int? updatedAt, int hours, DateTime now) =>
      hours > 0 &&
      (updatedAt == null ||
          now.millisecondsSinceEpoch - updatedAt >=
              Duration(hours: hours).inMilliseconds);

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        if (_pending.first.automatic &&
            ((_started && !_foreground) || PlayerVisibility.visible.value)) {
          break;
        }
        final job = _pending.removeAt(0);
        IptvParseResult result;
        try {
          result = await job.run();
        } catch (error) {
          result = _failure('Refresh failed (${error.runtimeType})');
        }
        if (result.hasError) {
          final failures = (_failures[job.id] ?? 0) + 1;
          _failures[job.id] = failures.clamp(1, 6);
          _retryAfter[job.id] = DateTime.now().add(
            Duration(minutes: 5 * (1 << (failures.clamp(1, 6) - 1))),
          );
        } else {
          _failures.remove(job.id);
          _retryAfter.remove(job.id);
          if (job.didFetch && result.ingest != null) revision.value++;
        }
        _jobs.remove(job.id);
        job.done.complete(result);
        // Yield between providers/catalogs even with an instantaneous mock or
        // cache hit. UI work and pending cancellation get an execution turn.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _running = false;
    }
  }

  static IptvParseResult _failure(String message) =>
      IptvParseResult(channels: const [], categories: const [], error: message);
}

class _CatalogRefreshJob {
  _CatalogRefreshJob(this.id, this.run, {required this.force});
  final String id;
  final Future<IptvParseResult> Function() run;
  bool force;
  bool didFetch = false;
  bool get automatic => !force;
  final done = Completer<IptvParseResult>();
  final listeners = <IptvLoadPhase>[];
  void report(String phase, {int? bytes, int? totalBytes}) {
    for (final listener in List<IptvLoadPhase>.of(listeners)) {
      try {
        listener(phase, bytes: bytes, totalBytes: totalBytes);
      } catch (_) {}
    }
  }
}
