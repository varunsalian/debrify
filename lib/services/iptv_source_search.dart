import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/advanced_search_selection.dart';
import '../models/iptv_playlist.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import '../utils/iptv_title.dart';
import 'iptv_catalog_db.dart';
import 'iptv_catalog_refresh_service.dart';
import 'iptv_catalog_key.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_runtime.dart';
import 'series_source_service.dart';
import 'source_selection_diagnostics.dart';
import 'storage_service.dart';
import 'xtream_codes_service.dart';

class IptvSourceResult {
  const IptvSourceResult(
    this.key,
    this.name,
    this.message,
    this.torrents, {
    this.retryableFailure = false,
  });
  final String key;
  final String name;
  final String message;
  final List<Torrent> torrents;
  final bool retryableFailure;
}

enum IptvEpisodeResolutionStatus { resolved, missing, unavailable }

class IptvEpisodeResolution {
  const IptvEpisodeResolution(this.status, [this.source]);

  final IptvEpisodeResolutionStatus status;
  final Torrent? source;
}

/// Searches cached catalogs; the shared queue prepares missing/stale catalogs.
class IptvSourceSearch {
  static final _authorizations = Expando<Future<void> Function()>();
  static final _episodePatterns = <RegExp>[
    RegExp(r'(?<!\d)[Ss](\d{1,2})[\s._-]*[Ee](?:[Pp])?(\d{1,3})(?!\d)'),
    RegExp(r'(?<!\d)(\d{1,2})[xX](\d{1,3})(?!\d)'),
    RegExp(r'\b[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,3})\b'),
  ];
  static const _audioLanguageTokens = <String, String>{
    'EN': 'en',
    'ENG': 'en',
    'ENGLISH': 'en',
    'ES': 'es',
    'SPA': 'es',
    'SPANISH': 'es',
    'ESPAÑA': 'es',
    'ESPANA': 'es',
    'LATINO': 'es',
    'FR': 'fr',
    'FRE': 'fr',
    'FRENCH': 'fr',
    'FRANCE': 'fr',
    'FRANCAIS': 'fr',
    'FRANÇAIS': 'fr',
    'DE': 'de',
    'GER': 'de',
    'GERMAN': 'de',
    'GERMANY': 'de',
    'DEUTSCH': 'de',
    'IT': 'it',
    'ITA': 'it',
    'ITALIAN': 'it',
    'ITALY': 'it',
    'ITALIANO': 'it',
    'PT': 'pt',
    'POR': 'pt',
    'PORTUGUESE': 'pt',
    'PORTUGAL': 'pt',
    'BR': 'pt',
    'BRAZIL': 'pt',
    'BRASIL': 'pt',
    'RU': 'ru',
    'RUS': 'ru',
    'RUSSIAN': 'ru',
    'RUSSAIN': 'ru',
    'RUSSIA': 'ru',
    'JA': 'ja',
    'JP': 'ja',
    'JPN': 'ja',
    'JAPANESE': 'ja',
    'JAPAN': 'ja',
    'KO': 'ko',
    'KR': 'ko',
    'KOR': 'ko',
    'KOREAN': 'ko',
    'KOREA': 'ko',
    'ZH': 'zh',
    'CN': 'zh',
    'CHI': 'zh',
    'CHINESE': 'zh',
    'CHINA': 'zh',
    'AR': 'ar',
    'ARA': 'ar',
    'ARABIC': 'ar',
    'HI': 'hi',
    'HIN': 'hi',
    'HINDI': 'hi',
    'TE': 'te',
    'TEL': 'te',
    'TELUGU': 'te',
    'NL': 'nl',
    'DUT': 'nl',
    'DUTCH': 'nl',
    'NETHERLANDS': 'nl',
    'PL': 'pl',
    'POL': 'pl',
    'POLISH': 'pl',
    'POLSKA': 'pl',
    'TR': 'tr',
    'TUR': 'tr',
    'TURKISH': 'tr',
    'TURKSIH': 'tr',
    'SV': 'sv',
    'SE': 'sv',
    'SWE': 'sv',
    'SWEDISH': 'sv',
    'SVENSK': 'sv',
    'SVENSKA': 'sv',
    'DA': 'da',
    'DK': 'da',
    'DAN': 'da',
    'DANISH': 'da',
    'DANSK': 'da',
    'NO': 'no',
    'NOR': 'no',
    'NORWEGIAN': 'no',
    'NORSK': 'no',
    'FI': 'fi',
    'FIN': 'fi',
    'FINNISH': 'fi',
    'SUOMI': 'fi',
    // These are not currently selectable in Playback settings, but must still
    // rank as an explicit other language instead of unknown/provider-branded.
    'AL': 'sq',
    'ALBANIAN': 'sq',
    'BG': 'bg',
    'BULGARIAN': 'bg',
    'EL': 'el',
    'GR': 'el',
    'GREEK': 'el',
    'RO': 'ro',
    'ROMANIAN': 'ro',
    'HU': 'hu',
    'HUNGARIAN': 'hu',
    'CS': 'cs',
    'CZ': 'cs',
    'CZECH': 'cs',
    'HE': 'he',
    'IL': 'he',
    'HEBREW': 'he',
    'FA': 'fa',
    'IR': 'fa',
    'PERSIAN': 'fa',
    'UR': 'ur',
    'PK': 'ur',
    'URDU': 'ur',
    'TH': 'th',
    'THAI': 'th',
    'VI': 'vi',
    'VIETNAMESE': 'vi',
    'ID': 'id',
    'INDONESIAN': 'id',
  };
  static const _qualityPrefixTokens = <String>{
    '4K',
    '8K',
    'HD',
    'FHD',
    'UHD',
    'HDR',
    'DV',
    'TOP',
  };
  static const _subtitleTokens = <String>{
    'SUB',
    'SUBS',
    'SUBBED',
    'MULTISUB',
    'MULTISUBS',
  };
  static final _providerPrefix = RegExp(
    r'^([A-Z0-9+]{2,8}(?:-[A-Z0-9+]{1,8}){0,3})\s*(?:-|:|\|)\s+',
    caseSensitive: false,
  );

  static bool owns(Torrent source) => source.source.startsWith('iptv:');

  static bool isDeferredXtreamSeries(Torrent source) =>
      owns(source) &&
      source.iptvCatalogType == 'series' &&
      (source.iptvEntryKey?.startsWith('series:') ?? false) &&
      source.streamType == StreamType.directUrl &&
      (source.directUrl?.isEmpty ?? true);

  /// These short-lived URLs must not outlive their profile/resource capability.
  static Future<void> authorize(Torrent source) async {
    if (!owns(source)) return;
    final check = _authorizations[source];
    if (check == null) {
      logIptvSourceEvent(
        'authorization_rejected',
        source: source,
        outcome: 'missing_ticket',
      );
      throw StateError('Search this IPTV source again');
    }
    try {
      await check();
    } catch (error) {
      logIptvSourceEvent(
        'authorization_rejected',
        source: source,
        outcome: 'capability_changed',
        error: error,
      );
      rethrow;
    }
  }

  static String keyFor(IptvPlaylist playlist) =>
      'iptv:${playlist.id.toLowerCase()}';

  static String normalize(String title) => IptvTitle.comparisonKey(title);

  static List<String> _languageWords(String value) => value
      .toUpperCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toList();

  static Set<String> _languagesFromWords(
    List<String> words, {
    bool allowShortCodes = true,
  }) {
    final languages = <String>{};
    for (var i = 0; i < words.length; i++) {
      if (!allowShortCodes && words[i].length <= 3) continue;
      final language = _audioLanguageTokens[words[i]];
      if (language == null) continue;
      // "SUB EN" / "EN SUBS" describes subtitle availability, not audio.
      final adjacentSubtitle =
          (i > 0 && _subtitleTokens.contains(words[i - 1])) ||
          (i + 1 < words.length && _subtitleTokens.contains(words[i + 1]));
      if (!adjacentSubtitle) languages.add(language);
    }
    return languages;
  }

  static ({Set<String> languages, bool multiAudio}) _audioHints(
    IptvChannel channel,
  ) {
    final groupWords = _languageWords(channel.group ?? '');
    // Strong 8K (and most Xtream panels) put the category language first.
    // Long names are safe anywhere; ambiguous short codes such as IT and NO
    // are only interpreted in that provider-style leading label.
    final groupLeadWords = groupWords
        .skipWhile(_qualityPrefixTokens.contains)
        .take(2)
        .toList();
    final groupLanguages = {
      ..._languagesFromWords(groupLeadWords),
      ..._languagesFromWords(groupWords, allowShortCodes: false),
    };
    final prefix = _providerPrefix.firstMatch(channel.name.trim());
    final prefixWords = prefix == null
        ? const <String>[]
        : prefix
              .group(1)!
              .toUpperCase()
              .split('-')
              .where((word) => !_qualityPrefixTokens.contains(word))
              .toList();
    // Providers commonly use locale-prefixed subtitle rows such as AR-SUBS.
    // Treat those as unknown audio unless the category independently names an
    // audio language.
    final prefixLanguages = prefixWords.any(_subtitleTokens.contains)
        ? const <String>{}
        : _languagesFromWords(prefixWords);
    final allWords = [...prefixWords, ...groupWords];
    final hasSubtitleMarker = allWords.any(_subtitleTokens.contains);
    final multiAudio =
        !hasSubtitleMarker &&
        (allWords.contains('MULTI') ||
            allWords.contains('MULTIAUDIO') ||
            (allWords.contains('DUAL') && allWords.contains('AUDIO')));
    return (
      languages: {...groupLanguages, ...prefixLanguages},
      multiAudio: multiAudio,
    );
  }

  /// Stable catalog preference tier. This never filters a provider row; it
  /// only puts the most likely audio-language rendition first.
  @visibleForTesting
  static int catalogAudioPreferenceTier(
    IptvChannel channel, {
    String? preferredLanguage,
  }) {
    final preferred = preferredLanguage?.trim().toLowerCase();
    final target = preferred == null || preferred.isEmpty ? 'en' : preferred;
    final hints = _audioHints(channel);
    if (hints.languages.contains(target)) return 0;
    if (hints.multiAudio) return 1;
    if (target != 'en' && hints.languages.contains('en')) return 2;
    if (hints.languages.isEmpty) return target == 'en' ? 2 : 3;
    return target == 'en' ? 3 : 4;
  }

  static List<IptvChannel> _orderByAudioPreference(
    List<IptvChannel> channels,
    String preferredLanguage,
  ) {
    final indexed = channels.indexed.toList();
    indexed.sort((a, b) {
      final tier =
          catalogAudioPreferenceTier(
            a.$2,
            preferredLanguage: preferredLanguage,
          ).compareTo(
            catalogAudioPreferenceTier(
              b.$2,
              preferredLanguage: preferredLanguage,
            ),
          );
      return tier != 0 ? tier : a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  static ({int season, int episode, int start})? _episodeOf(String value) {
    for (final pattern in _episodePatterns) {
      final match = pattern.firstMatch(value);
      if (match == null) continue;
      final season = int.tryParse(match.group(1)!);
      final episode = int.tryParse(match.group(2)!);
      if (season != null && episode != null) {
        return (season: season, episode: episode, start: match.start);
      }
    }
    return null;
  }

  static ({int season, int episode, int start})? _episodeOfChannel(
    IptvChannel channel,
  ) {
    final named = _episodeOf(channel.name);
    if (named != null) return named;
    const seasonKeys = ['season', 'season-number', 'season_number'];
    const episodeKeys = ['episode', 'episode-number', 'episode_number'];
    int? firstInt(List<String> keys) {
      for (final key in keys) {
        final value = int.tryParse(channel.attributes[key] ?? '');
        if (value != null) return value;
      }
      return null;
    }

    final season = firstInt(seasonKeys);
    final episode = firstInt(episodeKeys);
    return season == null || episode == null
        ? null
        : (season: season, episode: episode, start: -1);
  }

  static String _genericSeriesStem(IptvChannel channel) {
    final episode = _episodeOf(channel.name);
    if (episode != null) {
      final stem = channel.name.substring(0, episode.start).trim();
      if (stem.isNotEmpty) return stem;
    }
    for (final key in const [
      'series-name',
      'series_name',
      'series-title',
      'series_title',
      'show-title',
      'show_title',
    ]) {
      final value = channel.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return channel.group?.trim() ?? '';
  }

  static bool _genericSeriesMatches(
    IptvChannel channel,
    AdvancedSearchSelection selection,
  ) {
    final parsed = _episodeOfChannel(channel);
    if (parsed == null) return false;
    if (selection.season != null && parsed.season != selection.season) {
      return false;
    }
    if (selection.episode != null && parsed.episode != selection.episode) {
      return false;
    }
    final stem = _genericSeriesStem(channel);
    return matches(stem, selection.title, selection.year) ||
        (channel.group != null &&
            matches(channel.group!, selection.title, selection.year));
  }

  static String _opaqueKey(List<Object?> parts) =>
      sha256.convert(utf8.encode(jsonEncode(parts))).toString();

  static String _genericStreamHint(String url) {
    final uri = Uri.tryParse(url);
    final lastPathSegment = uri == null || uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last;
    // Queries and preceding path components commonly carry rotating tokens or
    // username/password pairs. The final stream/file id is the useful stable
    // discriminator, and only its digest enters the synced pin.
    return _opaqueKey([lastPathSegment]);
  }

  /// Best-effort identity for one generic-M3U rendition of a series. The
  /// title/group pair identifies the show; this discriminator keeps two
  /// language/quality feeds of that show separate when the playlist exposes a
  /// stable series attribute or route. Query strings and all but the first
  /// path segment are excluded because they commonly contain credentials.
  static String _genericSeriesVariantHint(IptvChannel channel) {
    final attributes = <String, String>{};
    for (final key in const [
      'series-id',
      'series_id',
      'series-key',
      'series_key',
      'language',
      'lang',
      'quality',
      'resolution',
    ]) {
      final value = channel.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) attributes[key] = value;
    }
    final uri = Uri.tryParse(channel.url);
    final host = uri?.host.toLowerCase() ?? '';
    final route = uri == null || uri.pathSegments.length < 2
        ? ''
        : uri.pathSegments.first.toLowerCase();
    final fileName = uri == null || uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last;
    final episode = _episodeOf(fileName);
    final filePrefix = episode == null
        ? ''
        : normalize(fileName.substring(0, episode.start));
    return _opaqueKey([host, route, filePrefix, attributes]);
  }

  static String _channelEntryKey(
    IptvPlaylist playlist,
    IptvChannel channel, {
    required bool series,
  }) {
    if (playlist.isXtreamCodes) {
      final id = channel.attributes[series ? 'series_id' : 'stream_id'];
      if (id != null && id.isNotEmpty) {
        return '${series ? 'series' : 'vod'}:$id';
      }
    }
    if (series) {
      return 'm3u-series:${_opaqueKey([normalize(_genericSeriesStem(channel)), normalize(channel.group ?? ''), _genericSeriesVariantHint(channel)])}';
    }
    final attributes = channel.attributes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return 'm3u-vod:${_opaqueKey([
      normalize(channel.name),
      normalize(channel.group ?? ''),
      channel.duration,
      _genericStreamHint(channel.url),
      {for (final entry in attributes) entry.key: entry.value},
    ])}';
  }

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
    bool deferXtreamSeriesEpisodes = false,
  }) async {
    if (selection.isNonImdb) return const [];
    final stopwatch = Stopwatch()..start();
    final scope = ProfileRuntime.scope.value;
    try {
      final savedAudioLanguage = await StorageService.getDefaultAudioLanguage();
      final preferredAudioLanguage =
          savedAudioLanguage?.trim().toLowerCase().isNotEmpty == true
          ? savedAudioLanguage!.trim().toLowerCase()
          : 'en';
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      final playlists = await StorageService.getIptvPlaylists(
        forSettings: false,
      );
      final eligibleCount = playlists.where(_eligiblePlaylist).length;
      logIptvSourceEvent(
        'discovery_started',
        catalogType: selection.isSeries ? 'series' : 'vod',
        season: selection.season,
        episode: selection.episode,
        playlistCount: eligibleCount,
      );
      if (eligibleCount == 0) {
        logIptvSourceEvent(
          'discovery_completed',
          catalogType: selection.isSeries ? 'series' : 'vod',
          outcome: 'no_providers',
          playlistCount: 0,
          resultCount: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return const [];
      }
      await IptvCatalogDb.open();
      final results = <IptvSourceResult>[];
      // Small batches bound episode-info traffic on devices with many providers.
      for (var start = 0; start < playlists.length; start += 3) {
        if (shouldContinue?.call() == false) {
          logIptvSourceEvent(
            'discovery_completed',
            catalogType: selection.isSeries ? 'series' : 'vod',
            outcome: 'cancelled',
            playlistCount: eligibleCount,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
          return const [];
        }
        final batch = playlists.skip(start).take(3).where(_eligiblePlaylist);
        await Future.wait(
          batch.map((playlist) async {
            final result = await _playlist(
              playlist,
              selection,
              shouldContinue,
              preferredAudioLanguage: preferredAudioLanguage,
              deferXtreamSeriesEpisodes: deferXtreamSeriesEpisodes,
            );
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
      if (shouldContinue?.call() == false) {
        logIptvSourceEvent(
          'discovery_completed',
          catalogType: selection.isSeries ? 'series' : 'vod',
          outcome: 'cancelled',
          playlistCount: eligibleCount,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return const [];
      }
      if (ProfileRuntime.scope.value != scope) {
        logIptvSourceEvent(
          'discovery_completed',
          catalogType: selection.isSeries ? 'series' : 'vod',
          outcome: 'profile_changed',
          playlistCount: eligibleCount,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return const [];
      }
      logIptvSourceEvent(
        'discovery_completed',
        catalogType: selection.isSeries ? 'series' : 'vod',
        outcome: 'complete',
        playlistCount: eligibleCount,
        resultCount: results.fold<int>(
          0,
          (count, result) => count + result.torrents.length,
        ),
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      return results;
    } catch (error) {
      // IPTV permission/vault failures must not break torrent/addon discovery.
      logIptvSourceEvent(
        'discovery_completed',
        catalogType: selection.isSeries ? 'series' : 'vod',
        outcome: 'failed',
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: error,
      );
      return const [];
    }
  }

  static bool _eligiblePlaylist(IptvPlaylist playlist) =>
      !playlist.credentialsRedacted &&
      !playlist.isVirtual &&
      !playlist.isLocalFile &&
      (playlist.isXtreamCodes || playlist.url.isNotEmpty);

  static Future<({IptvPlaylist playlist, Future<void> Function() check})?>
  _currentPlaylist(String playlistId) async {
    final playlists = await StorageService.getIptvPlaylists(forSettings: false);
    final matches = playlists.where(
      (playlist) => playlist.id == playlistId && _eligiblePlaylist(playlist),
    );
    if (matches.isEmpty) return null;
    final playlist = matches.first;
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
      final current = await StorageService.getIptvPlaylists(forSettings: false);
      final unchanged = current.any((candidate) {
        if (candidate.id != playlist.id || candidate.credentialsRedacted) {
          return false;
        }
        return playlist.isXtreamCodes
            ? candidate.serverUrl == playlist.serverUrl &&
                  candidate.username == playlist.username &&
                  candidate.password == playlist.password
            : candidate.url == playlist.url;
      });
      if (!unchanged) throw StateError('IPTV connection changed');
    }

    return (playlist: playlist, check: check);
  }

  static Future<IptvSourceResult> _playlist(
    IptvPlaylist playlist,
    AdvancedSearchSelection selection,
    bool Function()? shouldContinue, {
    String? desiredEntryKey,
    String preferredAudioLanguage = 'en',
    bool deferXtreamSeriesEpisodes = false,
    bool catalogRetried = false,
  }) async {
    final key = keyFor(playlist);
    final providerKind = playlist.isXtreamCodes ? 'xtream' : 'm3u';
    final catalogType = selection.isSeries ? 'series' : 'vod';
    final stopwatch = Stopwatch()..start();
    IptvSourceResult result(
      String message, [
      List<Torrent> torrents = const [],
      bool retryableFailure = false,
    ]) => IptvSourceResult(
      key,
      playlist.name,
      message,
      torrents,
      retryableFailure: retryableFailure,
    );
    try {
      final scope = ProfileRuntime.scope.value;
      final current = await _currentPlaylist(playlist.id);
      if (current == null) {
        logIptvSourceEvent(
          'playlist_search_completed',
          playlistId: playlist.id,
          catalogType: catalogType,
          providerKind: providerKind,
          outcome: 'connection_unavailable',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return result('IPTV source unavailable.', const [], true);
      }
      final check = current.check;

      final refresh = catalogRetried
          ? null
          : IptvCatalogRefreshService.instance.refreshCatalog(
              playlist,
              catalogType,
              priority: true,
            );
      var snapshot = IptvCatalogDb.snapshot(
        IptvCatalogKey.forPlaylist(playlist, catalogType)!,
      );
      if (snapshot == null && refresh != null) {
        await refresh.timeout(
          const Duration(seconds: 8),
          onTimeout: () => const IptvParseResult(channels: [], categories: []),
        );
        await check();
        if (ProfileRuntime.scope.value != scope ||
            shouldContinue?.call() == false) {
          return result('Search canceled.', const [], true);
        }
        snapshot = IptvCatalogDb.snapshot(
          IptvCatalogKey.forPlaylist(playlist, catalogType)!,
        );
      }
      if (snapshot == null) {
        logIptvSourceEvent(
          'playlist_search_completed',
          playlistId: playlist.id,
          catalogType: catalogType,
          providerKind: providerKind,
          outcome: 'catalog_missing',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return result(
          '${selection.isSeries ? 'Series' : 'Movies'} catalog is not ready. Automatic updates prepare it in the background; retry shortly, or use Refresh in IPTV settings if updates are off.',
          const [],
          true,
        );
      }
      final words = normalize(selection.title).split(' ')
        ..sort((a, b) => b.length.compareTo(a.length));
      if (words.first.isEmpty) {
        logIptvSourceEvent(
          'playlist_search_completed',
          playlistId: playlist.id,
          catalogType: catalogType,
          providerKind: providerKind,
          outcome: 'empty_query',
          resultCount: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return result('No matching sources.');
      }
      final candidates = <IptvChannel>[];
      bool accepts(IptvChannel channel, {required bool requireTitle}) {
        if (desiredEntryKey != null &&
            _channelEntryKey(playlist, channel, series: selection.isSeries) !=
                desiredEntryKey) {
          return false;
        }
        if (selection.isSeries && !playlist.isXtreamCodes) {
          final parsed = _episodeOfChannel(channel);
          if (parsed == null ||
              (selection.season != null && parsed.season != selection.season) ||
              (selection.episode != null &&
                  parsed.episode != selection.episode)) {
            return false;
          }
          return !requireTitle || _genericSeriesMatches(channel, selection);
        }
        return !requireTitle ||
            matches(channel.name, selection.title, selection.year);
      }

      Future<void> collect({
        required String? search,
        required bool requireTitle,
      }) async {
        // Read bounded pages; hidden IPTV categories remain hidden here too.
        for (var offset = 0; ; offset += 200) {
          final page = snapshot!.page(
            offset: offset,
            limit: 200,
            search: search,
            // Generic M3U providers often mark VOD rows EXTINF:-1 just like
            // live channels. Exact metadata/episode matching below is the safer
            // discriminator; Xtream has a real content-type catalog.
            live: playlist.isXtreamCodes ? false : null,
          );
          candidates.addAll(
            page.where(
              (channel) => accepts(channel, requireTitle: requireTitle),
            ),
          );
          if (page.length < 200) break;
          await Future<void>.delayed(Duration.zero);
          if (ProfileRuntime.scope.value != scope ||
              shouldContinue?.call() == false) {
            throw StateError('Profile changed');
          }
        }
      }

      await collect(search: words.first, requireTitle: true);
      // A durable pin owns a provider ID. Providers may rename/localize the
      // display title between catalog refreshes, so fall back to the stable ID
      // instead of invalidating an otherwise unchanged pin.
      final fallbackScan = candidates.isEmpty && desiredEntryKey != null;
      if (fallbackScan) {
        await collect(search: null, requireTitle: false);
      }
      logIptvSourceEvent(
        'catalog_candidates_collected',
        playlistId: playlist.id,
        entryKey: desiredEntryKey,
        catalogType: catalogType,
        providerKind: providerKind,
        candidateCount: candidates.length,
        fallbackScan: fallbackScan,
      );
      final orderedCandidates = _orderByAudioPreference(
        candidates,
        preferredAudioLanguage,
      );
      if (orderedCandidates.isEmpty && refresh != null) {
        final updated = await refresh.timeout(
          const Duration(seconds: 8),
          onTimeout: () => const IptvParseResult(channels: [], categories: []),
        );
        if (updated.ingest != null &&
            ProfileRuntime.scope.value == scope &&
            shouldContinue?.call() != false &&
            IptvCatalogDb.snapshot(
                  IptvCatalogKey.forPlaylist(playlist, catalogType)!,
                )?.generation !=
                snapshot.generation) {
          return _playlist(
            playlist,
            selection,
            shouldContinue,
            desiredEntryKey: desiredEntryKey,
            preferredAudioLanguage: preferredAudioLanguage,
            deferXtreamSeriesEpisodes: deferXtreamSeriesEpisodes,
            catalogRetried: true,
          );
        }
      }
      final torrents = <Torrent>[];
      final emittedSeriesKeys = <String>{};
      var lookupFailures = 0;
      // One lookup at a time bounds provider traffic without silently dropping
      // language/quality variants after the first three series entries.
      for (final candidate in orderedCandidates) {
        if (shouldContinue?.call() == false) {
          return result('Search canceled.', const [], true);
        }
        if (ProfileRuntime.scope.value != scope) {
          return result('Search canceled.', const [], true);
        }
        final entryKey = _channelEntryKey(
          playlist,
          candidate,
          series: selection.isSeries,
        );
        if (desiredEntryKey != null && entryKey != desiredEntryKey) continue;
        if (selection.isSeries &&
            ((playlist.isXtreamCodes && deferXtreamSeriesEpisodes) ||
                (selection.season == null && selection.episode == null)) &&
            !emittedSeriesKeys.add(entryKey)) {
          continue;
        }
        var url = candidate.url;
        if (selection.isSeries &&
            playlist.isXtreamCodes &&
            selection.season != null &&
            selection.episode != null &&
            !deferXtreamSeriesEpisodes) {
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
              lookupFailures++;
              continue;
            }
            final episodes = info.episodes.where(
              (e) =>
                  e.season == selection.season &&
                  e.episode == selection.episode,
            );
            if (episodes.isEmpty) continue;
            url = episodes.first.url;
          } catch (error) {
            lookupFailures++;
            logIptvSourceEvent(
              'episode_lookup_failed',
              playlistId: playlist.id,
              entryKey: entryKey,
              catalogType: catalogType,
              providerKind: providerKind,
              season: selection.season,
              episode: selection.episode,
              error: error,
            );
            continue;
          }
        } else if (selection.isSeries && playlist.isXtreamCodes) {
          // Bind-mode whole-series rows carry only durable catalog identity.
          // Episode searches may use the same lightweight descriptor so the
          // provider is contacted only if this row is actually attempted.
          url = '';
        }
        if (url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri == null ||
              !{'http', 'https'}.contains(uri.scheme) ||
              uri.host.isEmpty) {
            continue;
          }
        }
        final torrent = Torrent(
          rowid: 0,
          // Stable, playlist-scoped identity without exposing URL credentials.
          // Deferred Xtream rows have no URL yet, so their requested episode
          // must participate in identity or adjacent episode fetches collapse
          // into the stale descriptor retained by SeriesSourceFetcher.
          infohash:
              'iptv_${sha256.convert(utf8.encode(jsonEncode([
                key,
                entryKey,
                url,
                candidate.playbackHeaders,
                if (selection.isSeries && playlist.isXtreamCodes && deferXtreamSeriesEpisodes && selection.season != null && selection.episode != null) ...[selection.season, selection.episode],
              ])))}',
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
          iptvPlaylistId: playlist.id,
          iptvCatalogType: catalogType,
          iptvEntryKey: entryKey,
          coverageType: selection.isSeries && selection.season != null
              ? 'singleEpisode'
              : null,
          seasonNumber: selection.season,
          episodeIdentifier: selection.isSeries && selection.season != null
              ? 'S${selection.season}E${selection.episode}'
              : null,
        );
        _authorizations[torrent] = check;
        torrents.add(torrent);
      }
      await check();
      logIptvSourceEvent(
        'playlist_search_completed',
        playlistId: playlist.id,
        entryKey: desiredEntryKey,
        catalogType: catalogType,
        providerKind: providerKind,
        outcome: torrents.isEmpty
            ? (lookupFailures > 0 ? 'lookup_failed' : 'no_match')
            : 'matched',
        candidateCount: candidates.length,
        resultCount: torrents.length,
        failedCount: lookupFailures,
        fallbackScan: fallbackScan,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      return result(
        torrents.isEmpty
            ? (lookupFailures > 0
                  ? 'Episode lookup failed. Try searching again.'
                  : 'No matching sources.')
            : '${torrents.length} matching sources${lookupFailures > 0 ? ' · Some episode lookups failed. Try searching again.' : ''}',
        torrents,
        torrents.isEmpty && lookupFailures > 0,
      );
    } catch (error) {
      logIptvSourceEvent(
        'playlist_search_completed',
        playlistId: playlist.id,
        entryKey: desiredEntryKey,
        catalogType: catalogType,
        providerKind: providerKind,
        outcome: 'failed',
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: error,
      );
      return result(
        'IPTV source unavailable. Try searching again.',
        const [],
        true,
      );
    }
  }

  /// Resolve one lightweight Xtream series row for its requested episode.
  /// Manual selection can distinguish a genuinely absent episode from a
  /// provider/connection failure; automatic playback treats both as a signal
  /// to continue with the next candidate.
  static Future<IptvEpisodeResolution> resolveXtreamSeriesEpisode(
    Torrent descriptor, {
    int? season,
    int? episode,
  }) async {
    if (!isDeferredXtreamSeries(descriptor)) {
      return IptvEpisodeResolution(
        descriptor.directUrl?.isNotEmpty == true
            ? IptvEpisodeResolutionStatus.resolved
            : IptvEpisodeResolutionStatus.unavailable,
        descriptor.directUrl?.isNotEmpty == true ? descriptor : null,
      );
    }
    season ??= descriptor.seasonNumber;
    final encodedEpisode = descriptor.episodeIdentifier == null
        ? null
        : RegExp(r'[Ee](\d+)').firstMatch(descriptor.episodeIdentifier!);
    episode ??= encodedEpisode == null
        ? null
        : int.tryParse(encodedEpisode.group(1)!);
    if (season == null || episode == null) {
      return const IptvEpisodeResolution(
        IptvEpisodeResolutionStatus.unavailable,
      );
    }
    try {
      await authorize(descriptor);
      await IptvCatalogDb.open();
      final current = await _currentPlaylist(descriptor.iptvPlaylistId!);
      if (current == null || !current.playlist.isXtreamCodes) {
        return const IptvEpisodeResolution(
          IptvEpisodeResolutionStatus.unavailable,
        );
      }
      final result = await _playlist(
        current.playlist,
        AdvancedSearchSelection(
          imdbId: 'iptv-lazy',
          isSeries: true,
          title: descriptor.name,
          season: season,
          episode: episode,
        ),
        null,
        desiredEntryKey: descriptor.iptvEntryKey,
      );
      final resolved = result.torrents
          .where((source) => source.iptvEntryKey == descriptor.iptvEntryKey)
          .firstOrNull;
      if (resolved != null) {
        return IptvEpisodeResolution(
          IptvEpisodeResolutionStatus.resolved,
          resolved,
        );
      }
      return IptvEpisodeResolution(
        result.retryableFailure
            ? IptvEpisodeResolutionStatus.unavailable
            : IptvEpisodeResolutionStatus.missing,
      );
    } catch (error) {
      logIptvSourceEvent(
        'episode_descriptor_resolution_failed',
        source: descriptor,
        season: season,
        episode: episode,
        error: error,
      );
      return const IptvEpisodeResolution(
        IptvEpisodeResolutionStatus.unavailable,
      );
    }
  }

  /// Resolve a durable IPTV pin against the currently saved connection and
  /// current cached catalog. The pin never stores a provider URL or password;
  /// this produces a normal, short-lived authorized [Torrent] for the players.
  static Future<Torrent?> resolvePinned(
    SeriesSource source, {
    required String title,
    String? year,
    int? season,
    int? episode,
  }) async {
    if (!source.isIptvDirect) return null;
    final isSeries = source.iptvCatalogType == 'series';
    final stopwatch = Stopwatch()..start();
    logIptvSourceEvent(
      'pin_resolution_started',
      playlistId: source.iptvPlaylistId,
      entryKey: source.iptvEntryKey,
      catalogType: source.iptvCatalogType,
      season: season,
      episode: episode,
    );
    if (isSeries && (season == null || episode == null)) {
      logIptvSourceEvent(
        'pin_resolution_completed',
        playlistId: source.iptvPlaylistId,
        entryKey: source.iptvEntryKey,
        catalogType: source.iptvCatalogType,
        outcome: 'episode_missing',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      return null;
    }
    try {
      await IptvCatalogDb.open();
      final current = await _currentPlaylist(source.iptvPlaylistId!);
      if (current == null) {
        logIptvSourceEvent(
          'pin_resolution_completed',
          playlistId: source.iptvPlaylistId,
          entryKey: source.iptvEntryKey,
          catalogType: source.iptvCatalogType,
          outcome: 'connection_unavailable',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        return null;
      }
      final result = await _playlist(
        current.playlist,
        AdvancedSearchSelection(
          imdbId: 'iptv-pin',
          isSeries: isSeries,
          title: title,
          year: year,
          season: season,
          episode: episode,
        ),
        null,
        desiredEntryKey: source.iptvEntryKey,
      );
      for (final candidate in result.torrents) {
        if (candidate.iptvEntryKey == source.iptvEntryKey) {
          logIptvSourceEvent(
            'pin_resolution_completed',
            source: candidate,
            outcome: 'resolved',
            season: season,
            episode: episode,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
          return candidate;
        }
      }
    } catch (error) {
      // Saved-source resolution is fail-soft; normal search remains fallback.
      logIptvSourceEvent(
        'pin_resolution_completed',
        playlistId: source.iptvPlaylistId,
        entryKey: source.iptvEntryKey,
        catalogType: source.iptvCatalogType,
        outcome: 'failed',
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: error,
      );
      return null;
    }
    logIptvSourceEvent(
      'pin_resolution_completed',
      playlistId: source.iptvPlaylistId,
      entryKey: source.iptvEntryKey,
      catalogType: source.iptvCatalogType,
      outcome: 'no_match',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    return null;
  }
}
