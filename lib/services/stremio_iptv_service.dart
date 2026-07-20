import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/iptv_playlist.dart';
import '../models/stremio_addon.dart';
import 'stremio_service.dart';

/// One playable link for a Stremio IPTV channel: the stream URL plus the
/// addon's human label for it ("1080p • Server 2"). The label feeds the
/// in-player source pickers; the ladder itself only needs [url].
class StremioIptvCandidate {
  final String url;
  final String label;
  const StremioIptvCandidate({required this.url, required this.label});
}

/// Why a channel resolved to zero playable candidates. Drives the specific
/// user-facing message at the explicit-play sites; the preview stage stays
/// silent regardless of reason.
enum StremioResolveFailure {
  /// The addon behind the channel key is no longer installed.
  notInstalled,

  /// The stream request failed (network down, addon server unreachable).
  unreachable,

  /// The addon answered but has no streams for this channel.
  noStreams,

  /// The addon answered with streams, but none are direct URLs our players
  /// can treat as a live feed (torrents / external links / YouTube ids).
  noDirectStreams,
}

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

  // Safety valves, not practical limits. The real end-of-catalog signals are
  // an empty page and a page that contributes nothing new (addons that ignore
  // `skip` serve the same page forever); these only stop a truly pathological
  // addon from fetching without end. Channels stream to the UI as pages land
  // (see [fetchChannels]), so a huge catalog costs patience, not a spinner.
  static const int _maxPagesPerCatalog = 200;
  static const int _maxChannelsPerAddon = 50000;

  /// Genre fan-out valve for catalogs whose `genre` extra is *required*
  /// (common for live-TV addons that use genre = country/category). Genres
  /// come from the manifest, so this only guards absurd manifests.
  static const int _maxRequiredGenres = 100;

  static const Duration _candidatesTtl = Duration(minutes: 5);
  static const Duration _winnerTtl = Duration(minutes: 15);
  static const Duration _channelsTtl = Duration(minutes: 5);

  // Resolved stream candidates per channel key.
  final Map<String, ({List<StremioIptvCandidate> candidates, DateTime at})>
      _candidatesCache = {};
  // In-flight resolves, shared so preview + play can't double-fetch.
  final Map<String, Future<List<StremioIptvCandidate>>> _inFlight = {};
  // Preview-validated (or native-validated) URL per channel key.
  final Map<String, ({String url, DateTime at})> _winners = {};
  // Full channel lists per addon id (the catalog fan-out is expensive).
  final Map<String, ({IptvParseResult result, DateTime at})> _channelsCache =
      {};
  // Why the latest resolve of a key came back empty (cleared on success) —
  // consumed by [unplayableMessage].
  final Map<String, ({StremioResolveFailure reason, String? addonName})>
      _lastFailure = {};

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
  ///
  /// Catalog pages arrive over the network one at a time. When [onProgress]
  /// is given it fires after every page that contributed channels, with
  /// cumulative snapshots (safe to keep — the service won't mutate them), so
  /// the caller can render the first page immediately and keep growing the
  /// list while the walk continues. [isCancelled] is polled between requests;
  /// once it returns true the walk stops, the partial result is returned
  /// UN-cached, and no further [onProgress] fires.
  Future<IptvParseResult> fetchChannels(
    String addonId, {
    bool forceRefresh = false,
    void Function(List<IptvChannel> channels, List<String> categories)?
        onProgress,
    bool Function()? isCancelled,
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
    // Latched: once cancellation is observed the walk never resumes, even if
    // the caller's predicate were to flap back.
    var cancelled = false;
    bool checkCancelled() =>
        cancelled = cancelled || (isCancelled?.call() ?? false);

    for (final catalog in catalogs) {
      if (checkCancelled()) break;
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
        if (checkCancelled()) break;
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
          isCancelled: checkCancelled,
          // The category must exist by the time its first channels reach the
          // caller, or a mid-load category filter couldn't offer the group.
          onPage: onProgress == null
              ? null
              : () {
                  if (group != null && !categories.contains(group)) {
                    categories.add(group);
                  }
                  onProgress(List.of(channels), List.of(categories));
                },
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
    // A cancelled walk is incomplete — caching it would serve a silently
    // short list for the next 5 minutes.
    if (channels.isNotEmpty && !cancelled) {
      _channelsCache[addonId] = (result: result, at: DateTime.now());
    }
    return result;
  }

  /// Walk one catalog (optionally one genre of it) page by page. Returns the
  /// number of channels appended to [into]. [onPage] fires after every page
  /// that contributed at least one new channel.
  Future<int> _fetchCatalogPages(
    StremioAddon addon,
    StremioAddonCatalog catalog, {
    required String? genre,
    required String? group,
    required Set<String> seenIds,
    required List<IptvChannel> into,
    required bool forceRefresh,
    required bool Function() isCancelled,
    void Function()? onPage,
  }) async {
    var added = 0;
    var skip = 0;
    for (var page = 0; page < _maxPagesPerCatalog; page++) {
      if (into.length >= _maxChannelsPerAddon) break;
      if (isCancelled()) break;
      var rawCount = 0;
      final metas = await _stremio.fetchCatalog(
        addon,
        catalog,
        skip: skip,
        genre: genre,
        forceRefresh: forceRefresh,
        onRawCount: (c) => rawCount = c,
      );
      // Cancellation can land while the request was in flight — drop the
      // page rather than emit progress the caller no longer wants.
      if (isCancelled()) break;
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
      onPage?.call();
      if (rawCount <= 0) break;
      skip += rawCount;
    }
    return added;
  }

  // ── Stream resolution ─────────────────────────────────────────────────────

  /// Resolve a channel key to its ordered candidate streams (a validated
  /// winner first when one is cached). Empty means "not playable right now" —
  /// callers treat that like a dead M3U channel ([unplayableMessage] explains
  /// why). Never throws.
  ///
  /// [refreshIfEmpty] is for explicit play intents (OK press, channel zap):
  /// a cached EMPTY resolve is dropped and the addon asked again — the user
  /// said "try again", so a 5-minute-old "nothing" must not answer for the
  /// addon. Cached non-empty lists are still served as-is, and passive
  /// callers (the preview's focus sweeps) leave the flag off so they can't
  /// hammer the addon.
  Future<List<StremioIptvCandidate>> resolveCandidates(
    String channelKey, {
    bool refreshIfEmpty = false,
  }) async {
    final cached = _candidatesCache[channelKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _candidatesTtl) {
      if (cached.candidates.isNotEmpty || !refreshIfEmpty) {
        return _winnerFirst(channelKey, cached.candidates);
      }
      _candidatesCache.remove(channelKey);
    }
    final inFlight = _inFlight[channelKey];
    if (inFlight != null) return inFlight;

    final future = _resolve(channelKey).whenComplete(() {
      _inFlight.remove(channelKey);
    });
    _inFlight[channelKey] = future;
    return future;
  }

  Future<List<StremioIptvCandidate>> _resolve(String channelKey) async {
    final key = parseChannelKey(channelKey);
    if (key == null) return const [];
    StremioAddon? addon;
    try {
      final addons = await _stremio.getAddons();
      for (final a in addons) {
        if (a.id == key.addonId) {
          addon = a;
          break;
        }
      }
      if (addon == null) {
        _lastFailure[channelKey] =
            (reason: StremioResolveFailure.notInstalled, addonName: null);
        return const [];
      }

      final streams = await _stremio.fetchStreamsForContentId(
        addon,
        'tv',
        key.metaId,
      );
      // Live channels only make sense as direct URLs — torrents can't be a
      // live feed and external links can't play in our players. Dedupe
      // preserving the addon's own ordering (its preference order).
      final candidates = <StremioIptvCandidate>[];
      final seen = <String>{};
      for (final s in streams) {
        final url = s.url;
        if (!s.isDirectUrl || url == null) continue;
        if (!seen.add(url)) continue;
        candidates.add(
          StremioIptvCandidate(
            url: url,
            label: _candidateLabel(s, candidates.length),
          ),
        );
      }
      if (candidates.isEmpty) {
        _lastFailure[channelKey] = (
          reason: streams.isEmpty
              ? StremioResolveFailure.noStreams
              : StremioResolveFailure.noDirectStreams,
          addonName: addon.name,
        );
      } else {
        _lastFailure.remove(channelKey);
      }
      _candidatesCache[channelKey] =
          (candidates: candidates, at: DateTime.now());
      return _winnerFirst(channelKey, candidates);
    } catch (e) {
      debugPrint('StremioIptvService: resolve failed for $channelKey: $e');
      _lastFailure[channelKey] = (
        reason: StremioResolveFailure.unreachable,
        addonName: addon?.name,
      );
      return const [];
    }
  }

  /// User-facing explanation for the latest empty resolve of [channelKey] —
  /// specific when the reason is known, the old generic line otherwise.
  /// [channelName] is the display name the user recognizes.
  String unplayableMessage(String channelKey, String channelName) {
    final failure = _lastFailure[channelKey];
    final addonName = failure?.addonName;
    switch (failure?.reason) {
      case StremioResolveFailure.notInstalled:
        return 'The addon behind $channelName is no longer installed';
      case StremioResolveFailure.unreachable:
        return "Couldn't reach ${addonName ?? 'the addon'} — "
            'check your connection and try again';
      case StremioResolveFailure.noStreams:
        return "${addonName ?? 'The addon'} has no stream for "
            '$channelName right now';
      case StremioResolveFailure.noDirectStreams:
        return "$channelName's streams aren't in a format Debrify can play";
      case null:
        return '$channelName is not playable right now';
    }
  }

  /// Human label for a stream: the addon's short `name` first, else the first
  /// line of its `title`/description, else a positional fallback. Single line,
  /// capped — these render as source-picker rows.
  static String _candidateLabel(StremioStream s, int index) {
    var label = s.name?.trim() ?? '';
    if (label.isEmpty) label = s.title?.trim() ?? '';
    label = label.split('\n').first.trim();
    if (label.isEmpty) return 'Source ${index + 1}';
    return label.length > 80 ? label.substring(0, 80) : label;
  }

  List<StremioIptvCandidate> _winnerFirst(
    String channelKey,
    List<StremioIptvCandidate> candidates,
  ) {
    final winner = cachedWinner(channelKey);
    final winnerIdx = winner == null
        ? -1
        : candidates.indexWhere((c) => c.url == winner);
    if (winnerIdx <= 0) return List.of(candidates);
    return [
      candidates[winnerIdx],
      ...candidates.where((c) => c.url != winner),
    ];
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
