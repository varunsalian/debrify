import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/iptv_playlist.dart';
import '../models/stremio_addon.dart';
import 'stremio_service.dart';

/// Bridges installed Stremio addons' live-TV catalogs into the IPTV page.
///
/// Each enabled addon with at least one browsable `tv` catalog appears as a
/// virtual [IptvPlaylist] in the IPTV playlist picker; its catalog metas map
/// to [IptvChannel]s. Unlike M3U channels, a Stremio channel has no stream
/// URL at list time — the channel's `url` field holds a stable synthetic key
/// (`stremio-tv://<addonId>/<metaId>`) that the IPTV favorites machinery can
/// persist as-is, and [resolveCandidates] turns into real stream URLs on
/// demand. Addons may return several streams per channel; callers try them
/// in order until one plays (the serial ladder in the preview stage, the
/// in-app player, and the native TV player all consume the same list).
class StremioIptvService {
  static final StremioIptvService instance = StremioIptvService._internal();
  StremioIptvService._internal();

  final StremioService _stremio = StremioService.instance;

  /// Synthetic channel-URL scheme. Kept distinct from the `stremio://` deep
  /// links some addons emit so the two can never be confused.
  static const String channelUrlScheme = 'stremio-tv://';

  /// Virtual playlist ids are `stremio-addon:<addonId>`; the url mirrors it
  /// under a scheme so [IptvPlaylist.isStremioAddon] can discriminate.
  static const String playlistIdPrefix = 'stremio-addon:';
  static const String playlistUrlScheme = 'stremio-addon://';

  // Pagination guards: addons that ignore `skip` would otherwise loop forever,
  // and a runaway catalog shouldn't OOM the channel list.
  static const int _maxPagesPerCatalog = 20;
  static const int _maxChannelsPerAddon = 5000;

  /// Genre fan-out cap for catalogs whose `genre` extra is *required* (common
  /// for live-TV addons that use genre = country/category).
  static const int _maxRequiredGenres = 30;

  static const Duration _candidatesTtl = Duration(minutes: 5);
  static const Duration _winnerTtl = Duration(minutes: 15);
  static const Duration _channelsTtl = Duration(minutes: 5);

  // Resolved stream candidates per channel key.
  final Map<String, ({List<String> urls, DateTime at})> _candidatesCache = {};
  // In-flight resolves, shared so preview + play can't double-fetch.
  final Map<String, Future<List<String>>> _inFlight = {};
  // Preview-validated (or native-validated) URL per channel key.
  final Map<String, ({String url, DateTime at})> _winners = {};
  // Full channel lists per addon id (the catalog fan-out is expensive).
  final Map<String, ({IptvParseResult result, DateTime at})> _channelsCache =
      {};

  // ── Channel key codec ─────────────────────────────────────────────────────

  static String buildChannelKey(String addonId, String metaId) =>
      '$channelUrlScheme${Uri.encodeComponent(addonId)}/${Uri.encodeComponent(metaId)}';

  static bool isStremioChannelUrl(String url) =>
      url.startsWith(channelUrlScheme);

  /// Split a channel key back into its addon + meta ids. Null for anything
  /// that isn't a well-formed key.
  static ({String addonId, String metaId})? parseChannelKey(String url) {
    if (!isStremioChannelUrl(url)) return null;
    final rest = url.substring(channelUrlScheme.length);
    final slash = rest.indexOf('/');
    if (slash <= 0 || slash == rest.length - 1) return null;
    try {
      return (
        addonId: Uri.decodeComponent(rest.substring(0, slash)),
        metaId: Uri.decodeComponent(rest.substring(slash + 1)),
      );
    } catch (_) {
      return null;
    }
  }

  static String? addonIdFromPlaylist(IptvPlaylist playlist) {
    if (!playlist.id.startsWith(playlistIdPrefix)) return null;
    return playlist.id.substring(playlistIdPrefix.length);
  }

  // ── Virtual playlists ─────────────────────────────────────────────────────

  /// Live-TV catalogs of an addon: type `tv`, browsable without a search
  /// query. (Stremio's `channel` type is YouTube-channel-style video
  /// collections, not live TV, so it stays out of the IPTV page.)
  static List<StremioAddonCatalog> _tvCatalogs(StremioAddon addon) => [
        for (final c in addon.catalogs)
          if (c.type == 'tv' && c.isBrowsable) c,
      ];

  /// One virtual playlist per enabled addon that can serve live TV.
  Future<List<IptvPlaylist>> getVirtualPlaylists() async {
    final addons = await _stremio.getEnabledAddons();
    return [
      for (final addon in addons)
        if (addon.supportsStreams && _tvCatalogs(addon).isNotEmpty)
          IptvPlaylist(
            id: '$playlistIdPrefix${addon.id}',
            name: addon.name,
            url: '$playlistUrlScheme${Uri.encodeComponent(addon.id)}',
            addedAt: addon.addedAt,
          ),
    ];
  }

  // ── Channel list ──────────────────────────────────────────────────────────

  /// Fetch every channel the addon's tv catalogs expose, as an
  /// [IptvParseResult] the IPTV page renders unchanged.
  Future<IptvParseResult> fetchChannels(
    String addonId, {
    bool forceRefresh = false,
  }) async {
    final cached = _channelsCache[addonId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _channelsTtl) {
      return cached.result;
    }

    final addons = await _stremio.getAddons();
    StremioAddon? addon;
    for (final a in addons) {
      if (a.id == addonId) {
        addon = a;
        break;
      }
    }
    if (addon == null) {
      return const IptvParseResult(
        channels: [],
        categories: [],
        error: 'Addon is no longer installed',
      );
    }

    final catalogs = _tvCatalogs(addon);
    if (catalogs.isEmpty) {
      return const IptvParseResult(
        channels: [],
        categories: [],
        error: 'This addon has no live TV catalogs',
      );
    }

    final channels = <IptvChannel>[];
    final seenIds = <String>{};
    final categories = <String>[];
    final multiCatalog = catalogs.length > 1;
    var truncated = false;

    for (final catalog in catalogs) {
      if (channels.length >= _maxChannelsPerAddon) {
        truncated = true;
        break;
      }
      // A required-genre catalog returns nothing when browsed bare — walk its
      // genre options instead, each becoming a category of its own.
      final requiredGenre = catalog.extras.any(
        (e) => e.name == 'genre' && e.isRequired,
      );
      final genreOptions = catalog.genreOptions;
      final genres = requiredGenre && genreOptions.isNotEmpty
          ? genreOptions.take(_maxRequiredGenres).toList()
          : <String?>[null];
      if (requiredGenre && genreOptions.length > _maxRequiredGenres) {
        truncated = true;
      }

      for (final genre in genres) {
        if (channels.length >= _maxChannelsPerAddon) {
          truncated = true;
          break;
        }
        final group = genre ?? (multiCatalog ? catalog.name : null);
        final added = await _fetchCatalogPages(
          addon,
          catalog,
          genre: genre,
          group: group,
          seenIds: seenIds,
          into: channels,
          forceRefresh: forceRefresh,
        );
        if (added > 0 && group != null && !categories.contains(group)) {
          categories.add(group);
        }
      }
    }

    final result = IptvParseResult(
      channels: channels,
      categories: categories,
      error: channels.isEmpty
          ? 'The addon returned no channels — it may be down'
          : null,
      warning: truncated
          ? 'Channel list truncated at $_maxChannelsPerAddon'
          : null,
    );
    if (channels.isNotEmpty) {
      _channelsCache[addonId] = (result: result, at: DateTime.now());
    }
    return result;
  }

  /// Walk one catalog (optionally one genre of it) page by page. Returns the
  /// number of channels appended to [into].
  Future<int> _fetchCatalogPages(
    StremioAddon addon,
    StremioAddonCatalog catalog, {
    required String? genre,
    required String? group,
    required Set<String> seenIds,
    required List<IptvChannel> into,
    required bool forceRefresh,
  }) async {
    var added = 0;
    var skip = 0;
    for (var page = 0; page < _maxPagesPerCatalog; page++) {
      if (into.length >= _maxChannelsPerAddon) break;
      var rawCount = 0;
      final metas = await _stremio.fetchCatalog(
        addon,
        catalog,
        skip: skip,
        genre: genre,
        forceRefresh: forceRefresh,
        onRawCount: (c) => rawCount = c,
      );
      if (metas.isEmpty) break;

      var newThisPage = 0;
      for (final meta in metas) {
        if (into.length >= _maxChannelsPerAddon) break;
        if (!seenIds.add(meta.id)) continue;
        newThisPage++;
        into.add(
          IptvChannel(
            name: meta.name,
            url: buildChannelKey(addon.id, meta.id),
            logoUrl: meta.logo ?? meta.poster,
            group: group,
            contentType: 'live',
          ),
        );
      }
      added += newThisPage;
      // An addon that ignores `skip` serves the same page forever — stop as
      // soon as a page contributes nothing new.
      if (newThisPage == 0) break;
      if (rawCount <= 0) break;
      skip += rawCount;
    }
    return added;
  }

  // ── Stream resolution ─────────────────────────────────────────────────────

  /// Resolve a channel key to its ordered candidate stream URLs (a validated
  /// winner first when one is cached). Empty means "not playable right now" —
  /// callers treat that like a dead M3U channel. Never throws.
  Future<List<String>> resolveCandidates(String channelKey) async {
    final cached = _candidatesCache[channelKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _candidatesTtl) {
      return _winnerFirst(channelKey, cached.urls);
    }
    final inFlight = _inFlight[channelKey];
    if (inFlight != null) return inFlight;

    final future = _resolve(channelKey).whenComplete(() {
      _inFlight.remove(channelKey);
    });
    _inFlight[channelKey] = future;
    return future;
  }

  Future<List<String>> _resolve(String channelKey) async {
    final key = parseChannelKey(channelKey);
    if (key == null) return const [];
    try {
      final addons = await _stremio.getAddons();
      StremioAddon? addon;
      for (final a in addons) {
        if (a.id == key.addonId) {
          addon = a;
          break;
        }
      }
      if (addon == null) return const [];

      final streams = await _stremio.fetchStreamsForContentId(
        addon,
        'tv',
        key.metaId,
      );
      // Live channels only make sense as direct URLs — torrents can't be a
      // live feed and external links can't play in our players. Dedupe
      // preserving the addon's own ordering (its preference order).
      final urls = <String>[];
      for (final s in streams) {
        final url = s.url;
        if (!s.isDirectUrl || url == null) continue;
        if (!urls.contains(url)) urls.add(url);
      }
      _candidatesCache[channelKey] = (urls: urls, at: DateTime.now());
      return _winnerFirst(channelKey, urls);
    } catch (e) {
      debugPrint('StremioIptvService: resolve failed for $channelKey: $e');
      return const [];
    }
  }

  List<String> _winnerFirst(String channelKey, List<String> urls) {
    final winner = cachedWinner(channelKey);
    if (winner == null || !urls.contains(winner) || urls.first == winner) {
      return List.of(urls);
    }
    return [winner, ...urls.where((u) => u != winner)];
  }

  /// A URL from this channel's candidate list actually produced frames —
  /// remember it so the next preview/play starts there.
  void markWinner(String channelKey, String url) {
    _winners[channelKey] = (url: url, at: DateTime.now());
  }

  String? cachedWinner(String channelKey) {
    final w = _winners[channelKey];
    if (w == null) return null;
    if (DateTime.now().difference(w.at) >= _winnerTtl) {
      _winners.remove(channelKey);
      return null;
    }
    return w.url;
  }

  /// The remembered winner failed after all — forget it and drop the cached
  /// candidate list so the next attempt re-fetches fresh (live links expire).
  void invalidate(String channelKey) {
    _winners.remove(channelKey);
    _candidatesCache.remove(channelKey);
  }
}
