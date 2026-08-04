class FileUtils {
  /// What counts as a playable video anywhere in the app. This ONE list is
  /// what every cloud browser (Real-Debrid, TorBox, PikPak, Premiumize,
  /// AllDebrid, playlists, Debrify TV) asks before offering Play instead of
  /// download-only — so a format missing here isn't "unsupported", it's
  /// invisible.
  static const List<String> _videoExtensions = [
    '.mp4',
    '.avi',
    '.mkv',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.3gp',
    '.ts',
    '.mts',
    '.m2ts',
    // MPEG program stream — one container under four names (.vob is a DVD
    // rip's). Both players read it: the phone/desktop player decodes it in
    // software through libmpv, and the TV player's default extractor set
    // includes PsExtractor with the MP1/MP2/AC3 audio covered by the bundled
    // ffmpeg decoders. The one gap is MPEG-2 *video* on Android TV, which
    // needs the device's own decoder (the bundled ffmpeg video renderer is a
    // stub) — the TV player says so plainly when a box hasn't got one.
    '.mpg',
    '.mpeg',
    '.m2p',
    '.vob',
  ];

  // Well-supported formats that work reliably
  static const List<String> _wellSupportedFormats = [
    '.mp4',
    '.m4v',
    '.webm',
    '.3gp',
  ];

  // Problematic formats that might not work
  static const List<String> _problematicFormats = [
    '.wmv',
    '.avi',
    '.flv',
  ];

  static bool isVideoFile(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();
    return _videoExtensions.contains(extension);
  }

  static bool isVideoMimeType(String mimeType) {
    return mimeType.startsWith('video/');
  }

  static String _getFileExtension(String fileName) {
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1) return '';
    return fileName.substring(lastDotIndex);
  }

  static String getFileName(String filePath) {
    final lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex == -1) return filePath;
    return filePath.substring(lastSlashIndex + 1);
  }

  static String getFileExtension(String fileName) {
    return _getFileExtension(fileName);
  }

  static bool isWellSupportedVideo(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();
    return _wellSupportedFormats.contains(extension);
  }

  static bool isProblematicVideo(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();
    return _problematicFormats.contains(extension);
  }

  static String getVideoFormatWarning(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();

    if (_problematicFormats.contains(extension)) {
      return 'This format (${extension.toUpperCase()}) may not play properly on mobile devices.';
    }

    return '';
  }

  /// Clean title for playlist display by removing everything after the first slash
  /// This prevents weird display like "Series/Season 1/S01E01.mkv" showing as full path
  /// Example: "Impractical Jokers (2011) S01-S11/Series/Season 1/S01E01.mkv"
  /// becomes "Impractical Jokers (2011) S01-S11"
  static String cleanPlaylistTitle(String title) {
    final slashIndex = title.indexOf('/');
    if (slashIndex == -1) return title;
    return title.substring(0, slashIndex).trim();
  }
} 