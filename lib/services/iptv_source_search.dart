import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/advanced_search_selection.dart';
import '../models/iptv_playlist.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import '../utils/iptv_title.dart';
import 'iptv_catalog_db.dart';
import 'iptv_catalog_key.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_runtime.dart';
import 'storage_service.dart';
import 'xtream_codes_service.dart';

class IptvSourceResult {
  const IptvSourceResult(this.key, this.name, this.message, this.torrents);
  final String key;
  final String name;
  final String message;
  final List<Torrent> torrents;
}

/// Manual source discovery only. Never fetches or refreshes whole catalogs.
class IptvSourceSearch {
  static final _authorizations = Expando<Future<void> Function()>();

  static bool owns(Torrent source) => source.source.startsWith('iptv:');

  /// These short-lived URLs must not outlive their profile/resource capability.
  static Future<void> authorize(Torrent source) async {
    if (!owns(source)) return;
    final check = _authorizations[source];
    if (check == null) throw StateError('Search this IPTV source again');
    await check();
  }

  static String keyFor(IptvPlaylist playlist) =>
      'iptv:${playlist.id.toLowerCase()}';

  static String normalize(String title) => IptvTitle.comparisonKey(title);

  static bool matches(String candidate, String title, String? year) {
    final firstYear = RegExp(r'^(\d{4})(?:\D|$)').firstMatch(year ?? '');
    return IptvTitle.matches(
      candidate,
      title,
      year: firstYear == null ? null : int.parse(firstYear.group(1)!),
    );
  }

  static Future<List<IptvSourceResult>> search(
    AdvancedSearchSelection selection, {
    void Function(IptvSourceResult)? onResult,
    bool Function()? shouldContinue,
  }) async {
    if (selection.isNonImdb) return const [];
    final scope = ProfileRuntime.scope.value;
    try {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      final playlists = await StorageService.getIptvPlaylists(
        forSettings: false,
      );
      await IptvCatalogDb.open();
      final results = <IptvSourceResult>[];
      // Small batches bound episode-info traffic on devices with many providers.
      for (var start = 0; start < playlists.length; start += 3) {
        if (shouldContinue?.call() == false) return const [];
        final batch = playlists
            .skip(start)
            .take(3)
            .where((p) => p.isXtreamCodes && !p.credentialsRedacted);
        await Future.wait(
          batch.map((playlist) async {
            final result = await _playlist(playlist, selection, shouldContinue);
            if (ProfileRuntime.scope.value != scope ||
                shouldContinue?.call() == false) {
              return;
            }
            if (capability != null) await capability.run(() async {});
            results.add(result);
            onResult?.call(result);
          }),
        );
      }
      return ProfileRuntime.scope.value == scope ? results : const [];
    } catch (_) {
      // IPTV permission/vault failures must not break torrent/addon discovery.
      return const [];
    }
  }

  static Future<IptvSourceResult> _playlist(
    IptvPlaylist playlist,
    AdvancedSearchSelection selection,
    bool Function()? shouldContinue,
  ) async {
    final key = keyFor(playlist);
    IptvSourceResult result(
      String message, [
      List<Torrent> torrents = const [],
    ]) => IptvSourceResult(key, playlist.name, message, torrents);
    try {
      final scope = ProfileRuntime.scope.value;
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
        resourceId: playlist.connectionResourceId,
        resourceAuthorizationRevision: playlist.connectionResourceRevision,
      );
      Future<void> check() async {
        if (ProfileRuntime.scope.value != scope) {
          throw StateError('Profile changed');
        }
        if (capability != null) await capability.run(() async {});
        final current = await StorageService.getIptvPlaylists(
          forSettings: false,
        );
        if (!current.any(
          (p) =>
              p.id == playlist.id &&
              p.serverUrl == playlist.serverUrl &&
              p.username == playlist.username &&
              p.password == playlist.password,
        )) {
          throw StateError('IPTV connection changed');
        }
      }

      final type = selection.isSeries ? 'series' : 'vod';
      final snapshot = IptvCatalogDb.snapshot(
        IptvCatalogKey.forPlaylist(playlist, type)!,
      );
      if (snapshot == null) {
        return result(
          'Catalog not loaded. Open IPTV → ${playlist.name} → ${selection.isSeries ? 'Series' : 'Movies'} once to download it.',
        );
      }
      if (selection.isSeries &&
          (selection.season == null || selection.episode == null)) {
        return result('Select a specific episode to search this playlist.');
      }
      final words = normalize(selection.title).split(' ')
        ..sort((a, b) => b.length.compareTo(a.length));
      if (words.first.isEmpty) return result('No matching sources.');
      final candidates = <IptvChannel>[];
      // Read bounded pages; hidden IPTV categories remain hidden here too.
      for (var offset = 0; ; offset += 200) {
        final page = snapshot.page(
          offset: offset,
          limit: 200,
          search: words.first,
          live: false,
        );
        candidates.addAll(
          page.where((c) => matches(c.name, selection.title, selection.year)),
        );
        if (page.length < 200) break;
        await Future<void>.delayed(Duration.zero);
        if (ProfileRuntime.scope.value != scope ||
            shouldContinue?.call() == false) {
          throw StateError('Profile changed');
        }
      }
      final torrents = <Torrent>[];
      var lookupFailed = false;
      // One lookup at a time bounds provider traffic without silently dropping
      // language/quality variants after the first three series entries.
      for (final candidate in candidates) {
        if (shouldContinue?.call() == false) return result('Search canceled.');
        if (ProfileRuntime.scope.value != scope) {
          return result('Search canceled.');
        }
        var url = candidate.url;
        if (selection.isSeries) {
          try {
            final id = candidate.attributes['series_id'];
            if (id == null) continue;
            final info = await XtreamCodesService.instance
                .fetchSeriesInfo(
                  playlist.serverUrl!,
                  playlist.username ?? '',
                  playlist.password ?? '',
                  id,
                  connectionResourceId: playlist.connectionResourceId,
                  connectionResourceRevision:
                      playlist.connectionResourceRevision,
                )
                .timeout(const Duration(seconds: 12));
            if (info == null) {
              lookupFailed = true;
              continue;
            }
            final episodes = info.episodes.where(
              (e) =>
                  e.season == selection.season &&
                  e.episode == selection.episode,
            );
            if (episodes.isEmpty) continue;
            url = episodes.first.url;
          } catch (_) {
            lookupFailed = true;
            continue;
          }
        }
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty) {
          continue;
        }
        final torrent = Torrent(
          rowid: 0,
          // Stable, playlist-scoped identity without exposing URL credentials.
          infohash:
              'iptv_${sha256.convert(utf8.encode(jsonEncode([key, url, candidate.playbackHeaders])))}',
          name: candidate.name,
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: key,
          streamType: StreamType.directUrl,
          directUrl: url,
          httpHeaders: candidate.playbackHeaders,
          hasRealInfoHash: false,
          addonDisplayName: playlist.name,
          coverageType: selection.isSeries ? 'singleEpisode' : null,
          seasonNumber: selection.season,
          episodeIdentifier: selection.isSeries
              ? 'S${selection.season}E${selection.episode}'
              : null,
        );
        _authorizations[torrent] = check;
        torrents.add(torrent);
      }
      await check();
      return result(
        torrents.isEmpty
            ? (lookupFailed
                  ? 'Episode lookup failed. Try searching again.'
                  : 'No matching sources.')
            : '${torrents.length} matching sources${lookupFailed ? ' · Some episode lookups failed. Try searching again.' : ''}',
        torrents,
      );
    } catch (_) {
      return result('IPTV source unavailable. Try searching again.');
    }
  }
}
