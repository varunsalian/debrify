import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/tv_channel.dart';
import 'package:debrify/models/tv_channel_torrent.dart';
import 'package:debrify/services/tv_playback_service.dart';

void main() {
  group('TV Playback Service Tests', () {
    test('getRandomTorrent prioritizes known playable torrents', () {
      final channel = TVChannel(
        id: 'test_channel',
        name: 'Test Channel',
        keywords: ['test'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
        playableTorrentIds: ['torrent1', 'torrent2'],
        failedTorrentIds: ['torrent3'],
      );

      final torrents = [
        TVChannelTorrent(
          id: 'torrent1',
          channelId: 'test_channel',
          magnet: 'magnet:test1',
          name: 'Playable Torrent 1',
          sizeBytes: 1000000,
          seeders: 10,
          leechers: 5,
          addedAt: DateTime.now(),
          source: 'test',
        ),
        TVChannelTorrent(
          id: 'torrent2',
          channelId: 'test_channel',
          magnet: 'magnet:test2',
          name: 'Playable Torrent 2',
          sizeBytes: 2000000,
          seeders: 15,
          leechers: 3,
          addedAt: DateTime.now(),
          source: 'test',
        ),
        TVChannelTorrent(
          id: 'torrent3',
          channelId: 'test_channel',
          magnet: 'magnet:test3',
          name: 'Failed Torrent',
          sizeBytes: 500000,
          seeders: 2,
          leechers: 10,
          addedAt: DateTime.now(),
          source: 'test',
        ),
        TVChannelTorrent(
          id: 'torrent4',
          channelId: 'test_channel',
          magnet: 'magnet:test4',
          name: 'Unknown Torrent',
          sizeBytes: 1500000,
          seeders: 8,
          leechers: 4,
          addedAt: DateTime.now(),
          source: 'test',
        ),
      ];

      final randomTorrent = TVPlaybackService.getRandomTorrent(channel, torrents);
      
      // Should return one of the playable torrents
      expect(['torrent1', 'torrent2'], contains(randomTorrent.id));
    });

    test('getRandomTorrent avoids known failed torrents when no playable ones', () {
      final channel = TVChannel(
        id: 'test_channel',
        name: 'Test Channel',
        keywords: ['test'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
        playableTorrentIds: [], // No known playable torrents
        failedTorrentIds: ['torrent1'],
      );

      final torrents = [
        TVChannelTorrent(
          id: 'torrent1',
          channelId: 'test_channel',
          magnet: 'magnet:test1',
          name: 'Failed Torrent',
          sizeBytes: 1000000,
          seeders: 2,
          leechers: 10,
          addedAt: DateTime.now(),
          source: 'test',
        ),
        TVChannelTorrent(
          id: 'torrent2',
          channelId: 'test_channel',
          magnet: 'magnet:test2',
          name: 'Unknown Torrent',
          sizeBytes: 2000000,
          seeders: 15,
          leechers: 3,
          addedAt: DateTime.now(),
          source: 'test',
        ),
      ];

      final randomTorrent = TVPlaybackService.getRandomTorrent(channel, torrents);
      
      // Should return the non-failed torrent
      expect(randomTorrent.id, equals('torrent2'));
    });

    test('getRandomTorrent returns any torrent when all have failed', () {
      final channel = TVChannel(
        id: 'test_channel',
        name: 'Test Channel',
        keywords: ['test'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
        playableTorrentIds: [], // No known playable torrents
        failedTorrentIds: ['torrent1', 'torrent2'], // All torrents have failed
      );

      final torrents = [
        TVChannelTorrent(
          id: 'torrent1',
          channelId: 'test_channel',
          magnet: 'magnet:test1',
          name: 'Failed Torrent 1',
          sizeBytes: 1000000,
          seeders: 2,
          leechers: 10,
          addedAt: DateTime.now(),
          source: 'test',
        ),
        TVChannelTorrent(
          id: 'torrent2',
          channelId: 'test_channel',
          magnet: 'magnet:test2',
          name: 'Failed Torrent 2',
          sizeBytes: 2000000,
          seeders: 1,
          leechers: 15,
          addedAt: DateTime.now(),
          source: 'test',
        ),
      ];

      final randomTorrent = TVPlaybackService.getRandomTorrent(channel, torrents);
      
      // Should return one of the torrents (even though they've failed)
      expect(['torrent1', 'torrent2'], contains(randomTorrent.id));
    });

    test('getRandomTorrent throws exception for empty torrent list', () {
      final channel = TVChannel(
        id: 'test_channel',
        name: 'Test Channel',
        keywords: ['test'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      expect(
        () => TVPlaybackService.getRandomTorrent(channel, []),
        throwsException,
      );
    });
  });
} 