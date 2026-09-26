import '../../../models/torrent.dart';
import '../models/source_row_actions.dart';

/// Live row eligibility with injected classification and profile permission.
class SourceRowActionPolicy {
  const SourceRowActionPolicy({
    required this.isMediaServer,
    required this.isIptv,
    required this.downloadsAllowed,
  });

  final bool Function(Torrent) isMediaServer;
  final bool Function(Torrent) isIptv;
  final bool Function() downloadsAllowed;

  SourceRowActions project(
    Torrent torrent, {
    required bool Function(Torrent) canCopy,
    required bool Function(Torrent) supportsDownload,
  }) {
    final stream = torrent.isDirectStream || torrent.isExternalStream;
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
