class FileUtils {
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
  ];

  static bool isVideoFile(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();
    return _videoExtensions.contains(extension);
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
} 