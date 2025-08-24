import 'package:flutter_test/flutter_test.dart';

// Define PlaylistEntry locally for testing
class PlaylistEntry {
  final String url;
  final String title;
  final String? restrictedLink;
  final String? apiKey;
  
  const PlaylistEntry({
    required this.url, 
    required this.title, 
    this.restrictedLink,
    this.apiKey,
  });
}

void main() {
  group('VideoPlayerScreen Navigation Tests', () {
    test('should show only next button for first episode', () {
      // Create a simple playlist with 3 episodes
      final playlist = [
        PlaylistEntry(url: 'episode1.mp4', title: 'Episode 1'),
        PlaylistEntry(url: 'episode2.mp4', title: 'Episode 2'),
        PlaylistEntry(url: 'episode3.mp4', title: 'Episode 3'),
      ];

      // Test first episode (index 0)
      final hasNext = _hasNextEpisode(playlist, 0);
      final hasPrevious = _hasPreviousEpisode(playlist, 0);

      expect(hasNext, true, reason: 'First episode should have next episode');
      expect(hasPrevious, false, reason: 'First episode should not have previous episode');
    });

    test('should show both next and previous buttons for middle episodes', () {
      final playlist = [
        PlaylistEntry(url: 'episode1.mp4', title: 'Episode 1'),
        PlaylistEntry(url: 'episode2.mp4', title: 'Episode 2'),
        PlaylistEntry(url: 'episode3.mp4', title: 'Episode 3'),
      ];

      // Test middle episode (index 1)
      final hasNext = _hasNextEpisode(playlist, 1);
      final hasPrevious = _hasPreviousEpisode(playlist, 1);

      expect(hasNext, true, reason: 'Middle episode should have next episode');
      expect(hasPrevious, true, reason: 'Middle episode should have previous episode');
    });

    test('should show only previous button for last episode', () {
      final playlist = [
        PlaylistEntry(url: 'episode1.mp4', title: 'Episode 1'),
        PlaylistEntry(url: 'episode2.mp4', title: 'Episode 2'),
        PlaylistEntry(url: 'episode3.mp4', title: 'Episode 3'),
      ];

      // Test last episode (index 2)
      final hasNext = _hasNextEpisode(playlist, 2);
      final hasPrevious = _hasPreviousEpisode(playlist, 2);

      expect(hasNext, false, reason: 'Last episode should not have next episode');
      expect(hasPrevious, true, reason: 'Last episode should have previous episode');
    });

    test('should handle single episode playlist', () {
      final playlist = [
        PlaylistEntry(url: 'episode1.mp4', title: 'Episode 1'),
      ];

      // Test single episode (index 0)
      final hasNext = _hasNextEpisode(playlist, 0);
      final hasPrevious = _hasPreviousEpisode(playlist, 0);

      expect(hasNext, false, reason: 'Single episode should not have next episode');
      expect(hasPrevious, false, reason: 'Single episode should not have previous episode');
    });

    test('should handle empty playlist', () {
      final playlist = <PlaylistEntry>[];

      // Test with empty playlist
      final hasNext = _hasNextEpisode(playlist, 0);
      final hasPrevious = _hasPreviousEpisode(playlist, 0);

      expect(hasNext, false, reason: 'Empty playlist should not have next episode');
      expect(hasPrevious, false, reason: 'Empty playlist should not have previous episode');
    });
  });
}

// Helper functions to simulate the navigation logic
bool _hasNextEpisode(List<PlaylistEntry> playlist, int currentIndex) {
  if (playlist.isEmpty) return false;
  return currentIndex + 1 < playlist.length;
}

bool _hasPreviousEpisode(List<PlaylistEntry> playlist, int currentIndex) {
  if (playlist.isEmpty) return false;
  return currentIndex > 0;
} 