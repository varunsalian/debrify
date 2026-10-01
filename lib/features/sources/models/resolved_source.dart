import 'package:flutter/foundation.dart';

import 'acquired_source.dart';

class ResolvedSource extends AcquiredSource {
  final VoidCallback? openInTab;
  const ResolvedSource({
    this.openInTab,
    required super.title,
    super.httpHeaders,
    super.playUrl,
    super.downloadUrls,
    super.playlist,
    super.startIndex,
    super.fileName,
    super.isRarArchive,
    super.torboxTorrentId,
    super.rdTorrentId,
    super.pikpakFileId,
    super.restrictedLink,
    super.torboxFileId,
    super.premiumizePath,
    super.allDebridLink,
    super.pikpakVideoFileId,
  });
}
