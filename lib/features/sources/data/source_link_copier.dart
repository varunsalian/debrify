import '../../../models/iptv_source_result.dart';
import '../../../models/torrent.dart';

enum SourceLinkCopyResult {
  copied,
  chooseEpisode,
  missingEpisode,
  unavailableEpisode,
  noLink,
  retired,
}

/// Stateless explicit action: resolve a deferred episode, then copy its link.
/// No links or profile-owned results are retained between calls.
class SourceLinkCopier {
  const SourceLinkCopier({
    required this.isDeferredEpisode,
    required this.resolveEpisode,
    required this.writeText,
  });

  final bool Function(Torrent) isDeferredEpisode;
  final Future<IptvEpisodeResolution> Function(Torrent) resolveEpisode;
  final Future<void> Function(String) writeText;

  bool _hasEpisodeTarget(Torrent torrent) =>
      torrent.seasonNumber != null &&
      RegExp(
        r'^S\d+E\d+$',
        caseSensitive: false,
      ).hasMatch(torrent.episodeIdentifier ?? '');

  bool canCopy(Torrent torrent) =>
      torrent.copyLink != null ||
      (isDeferredEpisode(torrent) && _hasEpisodeTarget(torrent));

  Future<SourceLinkCopyResult> copy(
    Torrent torrent, {
    required bool Function() canContinue,
    required void Function() onResolving,
  }) async {
    if (!canContinue()) return SourceLinkCopyResult.retired;
    if (isDeferredEpisode(torrent)) {
      if (!_hasEpisodeTarget(torrent)) {
        return SourceLinkCopyResult.chooseEpisode;
      }
      onResolving();
      if (!canContinue()) return SourceLinkCopyResult.retired;
      final resolution = await resolveEpisode(torrent);
      if (!canContinue()) return SourceLinkCopyResult.retired;
      if (resolution.source == null) {
        return resolution.status == IptvEpisodeResolutionStatus.missing
            ? SourceLinkCopyResult.missingEpisode
            : SourceLinkCopyResult.unavailableEpisode;
      }
      torrent = resolution.source!;
    }
    final link = torrent.copyLink;
    if (link == null) return SourceLinkCopyResult.noLink;
    await writeText(link);
    return canContinue()
        ? SourceLinkCopyResult.copied
        : SourceLinkCopyResult.retired;
  }
}
