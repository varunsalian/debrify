import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/torrent.dart';

Torrent torrent({
  String infohash = '',
  String name = 'Example release',
  StreamType streamType = StreamType.torrent,
  String? directUrl,
  String? magnetUrl,
  String? torrentUrl,
  bool hasRealInfoHash = true,
}) => Torrent(
  rowid: 0,
  infohash: infohash,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: streamType,
  directUrl: directUrl,
  magnetUrl: magnetUrl,
  torrentUrl: torrentUrl,
  hasRealInfoHash: hasRealInfoHash,
);

void main() {
  group('Torrent.copyLink', () {
    test('uses a direct stream URL', () {
      expect(
        torrent(
          streamType: StreamType.directUrl,
          directUrl: ' https://stream.example/video ',
          hasRealInfoHash: false,
        ).copyLink,
        'https://stream.example/video',
      );
    });

    test('prefers an indexer magnet over other torrent acquisition data', () {
      const magnet = 'magnet:?xt=urn:btih:explicit';
      expect(
        torrent(
          infohash: 'fallback',
          magnetUrl: magnet,
          torrentUrl: 'https://indexer.example/file.torrent',
        ).copyLink,
        magnet,
      );
    });

    test('creates a usable magnet from a real infohash and name', () {
      expect(
        torrent(infohash: 'ABC123', name: 'A release & extras').copyLink,
        'magnet:?xt=urn:btih:ABC123&dn=A%20release%20%26%20extras',
      );
    });

    test('falls back to a provider URL when no real hash exists', () {
      expect(
        torrent(
          infohash: 'synthetic',
          torrentUrl: 'https://indexer.example/download/1',
          hasRealInfoHash: false,
        ).copyLink,
        'https://indexer.example/download/1',
      );
    });

    test('returns null when the source exposes no usable link', () {
      expect(torrent(hasRealInfoHash: false).copyLink, isNull);
    });
  });
}
