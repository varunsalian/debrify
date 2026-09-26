enum SourceRowActionKind { torrent, addon, iptv, mediaServer, external }

class SourceRowActions {
  const SourceRowActions({
    required this.kind,
    required this.canPin,
    required this.canCopy,
    required this.canDownload,
  });

  final SourceRowActionKind kind;
  final bool canPin;
  final bool canCopy;
  final bool canDownload;
}
