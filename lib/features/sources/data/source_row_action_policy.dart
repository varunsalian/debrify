import '../../../models/torrent.dart';
import '../../../services/webdav_source_tickets.dart';
import '../models/source_row_actions.dart';

/// Live row eligibility with injected classification and profile permission.
class SourceRowActionPolicy {
  const SourceRowActionPolicy({
    required this.isMediaServer,
    required this.isIptv,
    required this.downloadsAllowed,
    this.isWebDav = WebDavSourceTickets.owns,
  });

  final bool Function(Torrent) isMediaServer;
  final bool Function(Torrent) isIptv;
  final bool Function() downloadsAllowed;

  /// WebDAV rows play only in Debrify: their sign-in header cannot follow a
  /// copied link, a download or a pin, so those actions are not offered.
  final bool Function(Torrent) isWebDav;

  SourceRowActions project(
    Torrent torrent, {
    required bool Function(Torrent) canCopy,
    required bool Function(Torrent) supportsDownload,
  }) {
    final stream = torrent.isDirectStream || torrent.isExternalStream;
    if (torrent.isDirectStream && isWebDav(torrent)) {
      return const SourceRowActions(
        kind: SourceRowActionKind.webDav,
        canPin: false,
        canCopy: false,
        canDownload: false,
      );
    }
    return SourceRowActions(
      kind: !stream
          ? SourceRowActionKind.torrent
          : torrent.isExternalStream
          ? SourceRowActionKind.external
          : isMediaServer(torrent)
          ? SourceRowActionKind.mediaServer
          : isIptv(torrent)
          ? SourceRowActionKind.iptv
          : SourceRowActionKind.addon,
      canPin: !torrent.isExternalStream,
      canCopy: stream || canCopy(torrent),
      canDownload: stream && downloadsAllowed() && supportsDownload(torrent),
    );
  }
}
