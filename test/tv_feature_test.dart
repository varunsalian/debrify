import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_search_app/models/tv_channel.dart';
import 'package:torrent_search_app/models/tv_channel_torrent.dart';
import 'package:torrent_search_app/services/tv_service.dart';

void main() {
  group('TV Feature Tests', () {
    test('TVChannel model serialization', () {
      final channel = TVChannel(
        id: 'test_id',
        name: 'Test Channel',
        keywords: ['movie', 'series'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      final json = channel.toJson();
      final fromJson = TVChannel.fromJson(json);

      expect(fromJson.id, channel.id);
      expect(fromJson.name, channel.name);
      expect(fromJson.keywords, channel.keywords);
    });

    test('TVChannelTorrent model serialization', () {
      final torrent = TVChannelTorrent(
        id: 'test_torrent_id',
        channelId: 'test_channel_id',
        magnet: 'magnet:?xt=urn:btih:test',
        name: 'Test Torrent',
        sizeBytes: 1024 * 1024 * 100, // 100MB
        seeders: 10,
        leechers: 5,
        addedAt: DateTime.now(),
        source: 'torrents_csv',
      );

      final json = torrent.toJson();
      final fromJson = TVChannelTorrent.fromJson(json);

      expect(fromJson.id, torrent.id);
      expect(fromJson.channelId, torrent.channelId);
      expect(fromJson.magnet, torrent.magnet);
      expect(fromJson.name, torrent.name);
      expect(fromJson.sizeBytes, torrent.sizeBytes);
      expect(fromJson.seeders, torrent.seeders);
      expect(fromJson.leechers, torrent.leechers);
      expect(fromJson.source, torrent.source);
    });

    test('TVChannel copyWith method', () {
      final original = TVChannel(
        id: 'original_id',
        name: 'Original Name',
        keywords: ['original'],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      final updated = original.copyWith(
        name: 'Updated Name',
        keywords: ['updated', 'keywords'],
      );

      expect(updated.id, original.id);
      expect(updated.name, 'Updated Name');
      expect(updated.keywords, ['updated', 'keywords']);
      expect(updated.createdAt, original.createdAt);
    });
  });
} 