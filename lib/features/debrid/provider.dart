import 'descriptor.dart';
import 'resolved_playback.dart';

/// One debrid provider, seen the way the app actually uses one.
///
/// Everything that used to be a `switch (provider)` in a screen, a widget, or
/// the playback service lives behind this: identity and branding come off
/// [descriptor], settings come off the account methods, and the add/resolve
/// flow is the provider's own. Adding a provider means implementing this and
/// registering it — no file under `screens/` or `widgets/` should learn its
/// name.
abstract interface class DebridProvider {
  DebridProviderDescriptor get descriptor;

  /// Credentials are present. Says nothing about the integration toggle.
  Future<bool> isConfigured();

  /// The user's integration switch for this provider.
  Future<bool> isEnabled();

  /// Hidden from the nav rail and the cloud hub while still configured.
  Future<bool> isHiddenFromNav();

  /// Ready to be picked as the default provider: the integration is on and a
  /// usable credential is stored.
  Future<bool> isAvailable();

  /// What the app does after a torrent is added: `none`, `choose`, `play`,
  /// `download`, `open`, `playlist`, or `channel`.
  Future<String> postTorrentAction();

  /// Add [magnet] and resolve it to something playable.
  ///
  /// Throws [DebridNotCached] when the provider only serves cached torrents,
  /// [DebridStillProcessing] when the add succeeded but nothing is playable
  /// yet, and [DebridAddFailed] when the provider reports the download failed.
  /// Real-Debrid and AllDebrid instead throw their own client exceptions, which
  /// carry the ids [discardFailedAdd] needs.
  Future<ResolvedPlayback> add(String magnet, DebridAddRequest request);

  /// Queue [magnet] as a plain cloud download after the user answered "add
  /// anyway" to a not-cached torrent. No-op for providers whose add already
  /// created the entry.
  Future<void> queueDownload(String magnet);

  /// Undo the entry a rejected add created, given the exception that add threw.
  /// No-op when the provider left nothing behind.
  Future<void> discardFailedAdd(Object marker);

  /// Subset of [infohashes] the provider reports cached, lowercased. Empty when
  /// [DebridCapabilities.cacheCheck] is false.
  Future<Set<String>> cachedHashes(List<String> infohashes);

  /// Whether this provider is worth attempting for [request] at all — its
  /// integration is on, the torrent isn't one it refuses, and (in Auto mode)
  /// it can serve it instantly.
  Future<bool> canServe(DebridStreamRequest request);

  /// Resolve one torrent to a directly playable URL, picking the requested
  /// episode out of a pack. Null when this provider cannot serve it, including
  /// when it holds no credentials — and any account entry the attempt created
  /// is cleaned up before returning.
  Future<String?> resolveStream(DebridStreamRequest request);

  /// Provider-native identifiers a saved playlist item needs to re-resolve a
  /// fresh link once the direct URL expires. For packs the per-file ids come
  /// off [ResolvedPlayback.playlist]; for singles they ride on the result
  /// itself.
  Map<String, dynamic> playlistItemIds(
    ResolvedPlayback resolved, {
    required bool isPack,
  });

  /// Re-resolve a bound source that was pinned by provider-native id rather
  /// than by infohash — a file or folder the user already has in the provider's
  /// cloud. Null when this provider has no such binding, or the id no longer
  /// resolves.
  Future<ResolvedPlayback?> resolveCloudBinding(DebridCloudBinding binding);

  /// Undo an add whose result a bound-source attempt then rejected. No-op for
  /// providers whose add left nothing behind.
  Future<void> discardAdded(ResolvedPlayback resolved);
}

/// A bound source pinned to a provider-native id instead of an infohash.
class DebridCloudBinding {
  final String sourceId;

  /// The id names a single file rather than a folder.
  final bool isFile;

  /// Display name saved with the binding, used as the fallback title.
  final String name;

  /// Resolve as a season pack rather than picking the largest file.
  final bool isSeries;

  const DebridCloudBinding({
    required this.sourceId,
    required this.isFile,
    required this.name,
    required this.isSeries,
  });
}

/// The torrent being added, reduced to what providers actually read.
class DebridAddRequest {
  final String title;
  final String name;
  final String infohash;
  final int sizeBytes;

  const DebridAddRequest({
    required this.title,
    required this.name,
    required this.infohash,
    required this.sizeBytes,
  });
}

/// One torrent to resolve into a playable URL.
class DebridStreamRequest {
  final String infohash;
  final String name;

  /// `series`, `movie`, or anything else, lowercased.
  final String contentType;
  final int? season;
  final int? episode;

  /// The user picked Auto rather than this provider, so a provider that would
  /// queue work may decline instead.
  final bool autoSelected;

  final bool Function()? isCancelled;

  /// Cached infohashes for the whole candidate list, when the caller already
  /// batched the lookup. Avoids one cache call per torrent.
  final Future<Set<String>> Function()? cachedHashes;

  const DebridStreamRequest({
    required this.infohash,
    required this.name,
    required this.contentType,
    this.season,
    this.episode,
    this.autoSelected = false,
    this.isCancelled,
    this.cachedHashes,
  });

  bool get isSeries => contentType == 'series';
  bool get isMovie => contentType == 'movie';
  bool get cancelled => isCancelled?.call() ?? false;

  String get magnet =>
      'magnet:?xt=urn:btih:$infohash&dn=${Uri.encodeComponent(name)}';
}

/// The provider serves cached torrents only and this one is not cached. The
/// caller offers "add anyway", which routes to [DebridProvider.queueDownload].
class DebridNotCached implements Exception {
  final String providerId;
  const DebridNotCached(this.providerId);
}

/// Added, but nothing is playable yet — the provider is still downloading.
class DebridStillProcessing implements Exception {
  final String providerId;
  final String message;
  const DebridStillProcessing(this.providerId, this.message);
}

/// The provider reported the download itself failed.
class DebridAddFailed implements Exception {
  final String providerId;
  final String message;
  const DebridAddFailed(this.providerId, this.message);
}
