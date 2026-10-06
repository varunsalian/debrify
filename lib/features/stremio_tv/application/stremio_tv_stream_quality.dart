import 'package:debrify/utils/source_quality.dart';

class StremioTvStreamQuality {
  /// Extract normalized quality from a stream/torrent name.
  /// Returns '2160p', '1080p', '720p', '480p', or null.
  static String? extractQuality(String name) {
    switch (sourceQualityForName(name)) {
      case SourceQuality.ultraHd:
        return '2160p';
      case SourceQuality.fullHd:
        return '1080p';
      case SourceQuality.hd:
        return '720p';
      case SourceQuality.sd:
        return '480p';
      case null:
        return null;
    }
  }
}
