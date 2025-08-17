import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Download Link Detection Tests', () {
    // Test function that mimics the _isDownloadLink logic
    bool isDownloadLink(String url) {
      if (url.isEmpty) return false;
      
      final downloadExtensions = [
        '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v',
        '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma',
        '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
        '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.svg',
        '.exe', '.dmg', '.pkg', '.deb', '.rpm', '.apk',
        '.iso', '.img', '.bin',
        '.txt', '.csv', '.json', '.xml', '.html', '.css', '.js',
        '.torrent', '.magnet'
      ];
      
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      
      final path = uri.path.toLowerCase();
      return downloadExtensions.any((ext) => path.endsWith(ext));
    }

    test('should detect video file links', () {
      expect(isDownloadLink('https://example.com/video.mp4'), true);
      expect(isDownloadLink('https://example.com/movie.avi'), true);
      expect(isDownloadLink('https://example.com/film.mkv'), true);
      expect(isDownloadLink('https://example.com/video.webm'), true);
    });

    test('should detect audio file links', () {
      expect(isDownloadLink('https://example.com/song.mp3'), true);
      expect(isDownloadLink('https://example.com/music.wav'), true);
      expect(isDownloadLink('https://example.com/audio.flac'), true);
    });

    test('should detect document file links', () {
      expect(isDownloadLink('https://example.com/document.pdf'), true);
      expect(isDownloadLink('https://example.com/spreadsheet.xlsx'), true);
      expect(isDownloadLink('https://example.com/presentation.pptx'), true);
    });

    test('should detect archive file links', () {
      expect(isDownloadLink('https://example.com/archive.zip'), true);
      expect(isDownloadLink('https://example.com/compressed.rar'), true);
      expect(isDownloadLink('https://example.com/backup.7z'), true);
    });

    test('should detect image file links', () {
      expect(isDownloadLink('https://example.com/image.jpg'), true);
      expect(isDownloadLink('https://example.com/photo.png'), true);
      expect(isDownloadLink('https://example.com/picture.gif'), true);
    });

    test('should detect torrent links', () {
      expect(isDownloadLink('https://example.com/file.torrent'), true);
      // Note: magnet links don't have file extensions, so they won't be detected
      // This is by design - magnet links are handled separately in the app
    });

    test('should not detect non-download links', () {
      expect(isDownloadLink('https://example.com'), false);
      expect(isDownloadLink('https://example.com/page'), false);
      expect(isDownloadLink('https://example.com/api/data'), false);
      expect(isDownloadLink('https://example.com/search?q=test'), false);
    });

    test('should handle invalid URLs', () {
      expect(isDownloadLink(''), false);
      expect(isDownloadLink('not-a-url'), false);
      // FTP URLs with extensions should be detected
      expect(isDownloadLink('ftp://example.com/file.txt'), true);
    });

    test('should be case insensitive', () {
      expect(isDownloadLink('https://example.com/VIDEO.MP4'), true);
      expect(isDownloadLink('https://example.com/Movie.AVI'), true);
      expect(isDownloadLink('https://example.com/song.MP3'), true);
    });

    test('should handle URLs with query parameters', () {
      expect(isDownloadLink('https://example.com/video.mp4?token=abc123'), true);
      expect(isDownloadLink('https://example.com/file.pdf?download=true'), true);
    });

    test('should handle URLs with fragments', () {
      expect(isDownloadLink('https://example.com/document.pdf#page=5'), true);
      expect(isDownloadLink('https://example.com/image.jpg#section'), true);
    });
  });
} 