import '../../../models/playlist_entry.dart';
import '../../../models/torrent.dart';
import '../../../services/direct_source_authorization.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import 'source_acquisition.dart';
import 'source_magnet.dart';

/// One player's source-switch resolution; the player owns retirement.
class SourcePlaylistResolver {
  const SourcePlaylistResolver({
    required this.owner,
    required this.canContinue,
    required this.chooseProvider,
    this.provider,
    this.acquisition = const SourceAcquisition(),
  });

  final ProfileSessionOwner owner;
  final bool Function() canContinue;
  final Future<String?> Function(bool Function()) chooseProvider;
  final String? provider;
  final SourceAcquisition acquisition;
  bool get isCurrent =>
      owner == ProfileSessionMemory.captureOwner() && canContinue();

  Future<List<PlaylistEntry>?> resolve(
    Torrent source, {
    bool Function()? canContinue,
  }) {
    Future<List<PlaylistEntry>?> run() => _resolve(source, canContinue);
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  Future<List<PlaylistEntry>?> _resolve(
    Torrent source,
    bool Function()? canContinue,
  ) async {
    bool active() => isCurrent && (canContinue?.call() ?? true);
    if (!active()) return null;
    if (IptvSourceSearch.isDeferredXtreamSeries(source)) {
      final resolution = await IptvSourceSearch.resolveXtreamSeriesEpisode(
        source,
      );
      if (!active() || resolution.source == null) return null;
      source = resolution.source!;
    }
    try {
      await DirectSourceAuthorization.authorize(source);
    } catch (_) {
      return null;
    }
    if (!active()) return null;
    if (source.streamType == StreamType.directUrl &&
        (source.directUrl?.isNotEmpty ?? false)) {
      return [
        PlaylistEntry(
          url: source.directUrl!,
          title: source.displayTitle,
          httpHeaders: source.httpHeaders ?? const {},
        ),
      ];
    }
    final selected = provider ?? await chooseProvider(active);
    if (!active() || selected == null) return null;
    final magnet = await sourceMagnet(source);
    if (!active() || magnet == null) return null;
    try {
      final result = await acquisition.acquire(
        selected,
        magnet,
        source,
        owner: owner,
        canContinue: active,
      );
      if (!active()) return null;
      if (result.playlist?.isNotEmpty == true) return result.playlist;
      if (result.playUrl?.isNotEmpty == true) {
        return [
          PlaylistEntry(url: result.playUrl!, title: source.displayTitle),
        ];
      }
    } catch (_) {}
    return null;
  }
}
