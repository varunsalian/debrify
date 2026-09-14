import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';

import '../utils/json_isolate.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import 'storage_service.dart';
import 'trakt/trakt_episode_model.dart';

/// Profile-scoped, derived "caught up" state for locally watched series.
///
/// A title is caught up when every known regular episode whose release time is
/// now or earlier is in StorageService's finished-episode set. Successful
/// episode metadata loads seed the inventory; Simkl's public bulk calendar can
/// add newly announced episodes without polling every title individually.
class LocalSeriesCompletionService {
  LocalSeriesCompletionService._() {
    StorageService.localCompletionRevision.addListener(_onWatchedRevision);
  }

  static final LocalSeriesCompletionService instance =
      LocalSeriesCompletionService._();

  static const _calendarUris = [
    'https://data.simkl.in/calendar/tv.json',
    'https://data.simkl.in/calendar/anime.json',
  ];
  static const _calendarTtl = Duration(hours: 6);
  static const _calendarFailureBackoff = Duration(minutes: 30);

  Timer? _releaseTimer;
  bool _calendarRefreshing = false;
  final Lock _stateLock = Lock();

  void _onWatchedRevision() {
    // The inventory has already been captured by a successful metadata load,
    // so episode writes can cheaply re-derive status without another request.
    unawaited(caughtUpIds());
  }

  Future<Set<String>> caughtUpIds({bool refreshProgress = true}) =>
      _stateLock.synchronized(() async {
        final state = await _readState();
        final changed = refreshProgress ? await _recalculateAll(state) : false;
        if (changed) {
          await _writeState(state);
          // Derived changes happen after the original playback notification;
          // publish again only once the shelf/badge state is authoritative.
          StorageService.localCompletionRevision.value++;
        }
        _scheduleNextRelease(state);
        return _caughtUpIds(state);
      });

  /// Remove the local completed-episode history that derives a show's
  /// caught-up state. The recorded inventory supplies the canonical title so
  /// installs with pre-IMDb, title-keyed playback records are cleared too.
  Future<void> clearCompletedHistory(String imdbId) async {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) return;
    final title = await _stateLock.synchronized(() async {
      final state = await _readState();
      return state[id]?['title']?.toString();
    });
    await StorageService.unmarkSeriesAsFinished(id, seriesTitle: title);
    // Await the re-derivation so a completed badge cannot survive past the
    // watched action's own Future even if the revision listener is delayed.
    await caughtUpIds();
  }

  /// Records a successfully resolved episode inventory and immediately derives
  /// the local series status. Specials are excluded. Episodes without a date
  /// are conservatively considered already available.
  Future<void> recordEpisodeInventory({
    required String imdbId,
    required String seriesTitle,
    required List<TraktSeason> seasons,
  }) {
    final recordScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty || !id.startsWith('tt')) return Future.value();

    final parsed = <({String key, int? releasedAt})>[];
    for (final season in seasons) {
      if (season.number <= 0) continue;
      for (final episode in season.episodes) {
        if (episode.number <= 0) continue;
        final releasedAt = DateTime.tryParse(episode.firstAired ?? '');
        parsed.add((
          key: '${season.number}-${episode.number}',
          releasedAt: releasedAt?.millisecondsSinceEpoch,
        ));
      }
    }
    // Some addons omit dates for their entire inventory; in that shape the
    // listed episodes are the only usable truth and are treated as available.
    // When dates are otherwise present, an undated announced episode remains
    // unknown rather than incorrectly blocking the caught-up badge.
    final hasDatedEpisodes = parsed.any((entry) => entry.releasedAt != null);
    final episodes = <String, int>{
      for (final entry in parsed)
        if (entry.releasedAt != null || !hasDatedEpisodes)
          entry.key: entry.releasedAt ?? 0,
    };
    if (episodes.isEmpty) return Future.value();

    Future<void> commit() => _stateLock.synchronized(() async {
      final state = await _readState();
      final previous = state[id];
      final inventoryChanged =
          previous == null ||
          previous['title'] != seriesTitle ||
          !mapEquals(_episodeMap(previous['episodes']), episodes);
      final record = <String, dynamic>{
        ...?previous,
        'title': seriesTitle,
        'episodes': episodes,
        'calendarEpisodes': _episodeMap(previous?['calendarEpisodes']),
        'caughtUp': previous?['caughtUp'] == true,
        'validatedAt': inventoryChanged
            ? DateTime.now().millisecondsSinceEpoch
            : previous['validatedAt'],
      };
      state[id] = record;
      final progressChanged = await _recalculateRecord(id, record);
      if (!inventoryChanged && !progressChanged) {
        if (_isCurrentScope(recordScope)) _scheduleNextRelease(state);
        return;
      }
      await _writeState(state);
      if (_isCurrentScope(recordScope)) {
        _scheduleNextRelease(state);
        StorageService.localCompletionRevision.value++;
      }
    });
    return recordScope == null
        ? commit()
        : ProfileRuntime.withCapturedScope(recordScope, commit);
  }

  Future<void> recordRawEpisodeInventory({
    required String imdbId,
    required String seriesTitle,
    required List<Map<String, dynamic>> videos,
  }) {
    final bySeason = <int, List<TraktEpisode>>{};
    for (final video in videos) {
      final season = (video['season'] as num?)?.toInt();
      final episode =
          (video['number'] as num?)?.toInt() ??
          (video['episode'] as num?)?.toInt();
      if (season == null || season <= 0 || episode == null || episode <= 0) {
        continue;
      }
      bySeason
          .putIfAbsent(season, () => [])
          .add(
            TraktEpisode(
              season: season,
              number: episode,
              title: video['title']?.toString() ?? '',
              firstAired: video['released']?.toString(),
            ),
          );
    }
    return recordEpisodeInventory(
      imdbId: imdbId,
      seriesTitle: seriesTitle,
      seasons: [
        for (final entry in bySeason.entries)
          TraktSeason(
            number: entry.key,
            episodeCount: entry.value.length,
            episodes: entry.value,
          ),
      ],
    );
  }

  /// Refreshes Simkl's rolling feeds and, after a longer offline gap, its
  /// recent monthly archives. Failure leaves confirmed inventories untouched.
  Future<Set<String>> refreshCalendarIfDue() async {
    final refreshScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    final knownState = await _stateLock.synchronized(_readState);
    if (!_isCurrentScope(refreshScope)) return <String>{};
    if (knownState.isEmpty) return <String>{};
    final prefs = await ProfilePreferences.instance();
    final checkedAt =
        prefs.getInt(StorageService.localSeriesCalendarCheckedAtKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_calendarRefreshing || now - checkedAt < _calendarTtl.inMilliseconds) {
      return caughtUpIds();
    }
    final attemptedAt =
        prefs.getInt(StorageService.localSeriesCalendarAttemptedAtKey) ?? 0;
    if (now - attemptedAt < _calendarFailureBackoff.inMilliseconds) {
      return caughtUpIds();
    }
    _calendarRefreshing = true;
    try {
      await prefs.setInt(StorageService.localSeriesCalendarAttemptedAtKey, now);
      final calendarItems = <dynamic>[];
      var allFeedsSucceeded = true;
      final urls = _calendarFeedUrls(
        knownState: knownState,
        checkedAt: checkedAt,
        now: now,
      );
      // Monthly TV files are several MB each. Decode one at a time and retain
      // only entries for locally known titles so weak TVs never hold an entire
      // archive window of decoded JSON maps.
      final knownIds = knownState.keys.toSet();
      for (final url in urls) {
        final feed = await _fetchCalendarFeed(url, knownIds);
        if (!_isCurrentScope(refreshScope)) return <String>{};
        if (feed == null) {
          allFeedsSucceeded = false;
          continue;
        }
        calendarItems.addAll(feed);
      }
      final caughtUp = calendarItems.isEmpty
          ? await caughtUpIds()
          : refreshScope == null
          ? await _mergeCalendarItems(calendarItems)
          : await ProfileRuntime.withCapturedScope(
              refreshScope,
              () =>
                  _mergeCalendarItems(calendarItems, notifyScope: refreshScope),
            );
      if (!_isCurrentScope(refreshScope)) return <String>{};
      // A partial monthly failure must remain retryable; successful items are
      // still merged so an available new episode is reflected immediately.
      if (allFeedsSucceeded) {
        await prefs.setInt(StorageService.localSeriesCalendarCheckedAtKey, now);
      }
      return caughtUp;
    } catch (error) {
      debugPrint(
        'LocalSeriesCompletion: calendar refresh failed '
        '(${error.runtimeType})',
      );
      return caughtUpIds();
    } finally {
      _calendarRefreshing = false;
    }
  }

  bool _isCurrentScope(ProfileScope? expected) {
    if (expected == null) {
      return !ProfileRuntime.isInitialized ||
          !ProfileRuntime.isProfileCommitted;
    }
    return ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        ProfileRuntime.scope.value == expected;
  }

  @visibleForTesting
  List<String> debugCalendarFeedUrls({
    required int checkedAt,
    required int now,
  }) => _calendarFeedUrls(knownState: const {}, checkedAt: checkedAt, now: now);

  List<String> _calendarFeedUrls({
    required Map<String, Map<String, dynamic>> knownState,
    required int checkedAt,
    required int now,
  }) {
    final urls = <String>[..._calendarUris];
    final nowDate = DateTime.fromMillisecondsSinceEpoch(now, isUtc: true);
    var startMs = checkedAt;
    if (startMs <= 0 && knownState.isNotEmpty) {
      final validations = knownState.values
          .map((record) => (record['validatedAt'] as num?)?.toInt() ?? now)
          .where((value) => value > 0);
      if (validations.isNotEmpty) {
        startMs = validations.reduce((a, b) => a < b ? a : b);
      }
    }
    if (startMs <= 0 ||
        now - startMs <= const Duration(days: 1).inMilliseconds) {
      return urls;
    }

    var start = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    start = DateTime.utc(start.year, start.month);
    // Simkl publishes monthly archives for the most recent twelve months.
    final oldest = DateTime.utc(nowDate.year, nowDate.month - 11);
    if (start.isBefore(oldest)) start = oldest;
    final end = DateTime.utc(nowDate.year, nowDate.month);
    for (
      var month = start;
      !month.isAfter(end);
      month = DateTime.utc(month.year, month.month + 1)
    ) {
      final segment = '${month.year}/${month.month}';
      urls.add('https://data.simkl.in/calendar/$segment/tv.json');
      urls.add('https://data.simkl.in/calendar/$segment/anime.json');
    }
    return urls;
  }

  Future<bool> _recalculateAll(Map<String, Map<String, dynamic>> state) async {
    var changed = false;
    final finishedIndex = await StorageService.getFinishedSeriesEpisodeIndex();
    for (final entry in state.entries) {
      if (await _recalculateRecord(
        entry.key,
        entry.value,
        finishedIndex: finishedIndex,
      )) {
        changed = true;
      }
    }
    return changed;
  }

  Future<bool> _recalculateRecord(
    String imdbId,
    Map<String, dynamic> record, {
    Map<String, Map<String, Set<int>>>? finishedIndex,
  }) async {
    final title = record['title']?.toString() ?? '';
    if (title.isEmpty) return false;
    final finished = finishedIndex == null
        ? await StorageService.getFinishedEpisodesByImdbId(
            imdbId: imdbId,
            seriesTitle: title,
          )
        : finishedIndex[imdbId] ??
              finishedIndex['title:${title.trim().toLowerCase()}'] ??
              const <String, Set<int>>{};
    final watched = <String>{
      for (final season in finished.entries)
        for (final episode in season.value) '${season.key}-$episode',
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    final required = _allEpisodes(
      record,
    ).entries.where((entry) => entry.value <= now).map((entry) => entry.key);
    final requiredSet = required.toSet();
    final caughtUp =
        requiredSet.isNotEmpty && requiredSet.every(watched.contains);
    final wasCaughtUp = record['caughtUp'] == true;
    if (wasCaughtUp == caughtUp) return false;
    record['caughtUp'] = caughtUp;
    if (caughtUp) {
      final items = await StorageService.getContinueWatchingItems();
      final match = items.where((item) {
        return item['imdbId']?.toString().trim().toLowerCase() == imdbId;
      }).firstOrNull;
      if (match != null) record['continueWatching'] = match;
      await StorageService.removeContinueWatchingItem(imdbId);
    } else if (wasCaughtUp && record['continueWatching'] is Map) {
      final item = Map<String, dynamic>.from(record['continueWatching'] as Map);
      await StorageService.saveContinueWatchingItem(
        imdbId: imdbId,
        title: item['title']?.toString() ?? title,
        contentType: 'series',
        posterUrl: item['posterUrl']?.toString(),
        addonId: item['addonId']?.toString(),
        year: item['year']?.toString(),
      );
    }
    return true;
  }

  void _scheduleNextRelease(Map<String, Map<String, dynamic>> state) {
    _releaseTimer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    int? next;
    for (final record in state.values) {
      if (record['caughtUp'] != true) continue;
      for (final releaseMs in _allEpisodes(record).values) {
        if (releaseMs > now && (next == null || releaseMs < next)) {
          next = releaseMs;
        }
      }
    }
    if (next == null) return;
    final delay =
        Duration(milliseconds: next - now) + const Duration(seconds: 1);
    _releaseTimer = Timer(delay, () => unawaited(caughtUpIds()));
  }

  Set<String> _caughtUpIds(Map<String, Map<String, dynamic>> state) => {
    for (final entry in state.entries)
      if (entry.value['caughtUp'] == true) entry.key,
  };

  Map<String, int> _episodeMap(Object? raw) {
    if (raw is! Map) return <String, int>{};
    return {
      for (final entry in raw.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  Map<String, int> _allEpisodes(Map<String, dynamic> record) => {
    ..._episodeMap(record['episodes']),
    ..._episodeMap(record['calendarEpisodes']),
  };

  @visibleForTesting
  Future<Set<String>> debugMergeCalendarItems(List<dynamic> items) =>
      _mergeCalendarItems(items);

  Future<Set<String>> _mergeCalendarItems(
    List<dynamic> items, {
    ProfileScope? notifyScope,
  }) => _stateLock.synchronized(() async {
    final state = await _readState();
    var changed = false;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final ids = item['ids'];
      final episode = item['episode'];
      if (ids is! Map || episode is! Map) continue;
      final imdb = ids['imdb']?.toString().trim().toLowerCase();
      final record = imdb == null ? null : state[imdb];
      if (record == null) continue;
      final season = (episode['season'] as num?)?.toInt();
      final number = (episode['episode'] as num?)?.toInt();
      if (season == null || season <= 0 || number == null || number <= 0) {
        continue;
      }
      final releaseMs = _simklCalendarDayMs(item['date']);
      if (releaseMs == null) continue;
      final episodes = _episodeMap(record['calendarEpisodes']);
      final key = '$season-$number';
      if (episodes[key] != releaseMs) {
        episodes[key] = releaseMs;
        record['calendarEpisodes'] = episodes;
        changed = true;
      }
    }
    final completionChanged = await _recalculateAll(state);
    if (completionChanged) changed = true;
    if (changed) await _writeState(state);
    if (completionChanged &&
        (notifyScope == null || _isCurrentScope(notifyScope))) {
      StorageService.localCompletionRevision.value++;
    }
    _scheduleNextRelease(state);
    return _caughtUpIds(state);
  });

  int? _simklCalendarDayMs(Object? raw) {
    final value = raw?.toString() ?? '';
    if (value.length < 10) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) return null;
    // Simkl publishes a nominal New York calendar date rather than an exact
    // air-time instant. Apply that Y-M-D in the device's local timezone.
    return DateTime(year, month, day).millisecondsSinceEpoch;
  }

  Future<List<dynamic>?> _fetchCalendarFeed(
    String url,
    Set<String> knownIds,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = await decodeJsonAsync(response.body);
      if (decoded is! List) return null;
      return [
        for (final item in decoded)
          if (item is Map &&
              item['ids'] is Map &&
              knownIds.contains(
                (item['ids'] as Map)['imdb']?.toString().trim().toLowerCase(),
              ))
            item,
      ];
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readState() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(StorageService.localSeriesCompletionStateKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeState(Map<String, Map<String, dynamic>> state) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      StorageService.localSeriesCompletionStateKey,
      jsonEncode(state),
    );
  }
}
