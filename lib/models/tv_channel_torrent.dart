import 'torrent.dart';

class TVChannelTorrent {
  final String id;
  final String channelId;
  final String magnet;
  final String name;
  final int sizeBytes;
  final int seeders;
  final int leechers;
  final DateTime addedAt;
  final String source; // 'torrents_csv' or 'pirate_bay'

  TVChannelTorrent({
    required this.id,
    required this.channelId,
    required this.magnet,
    required this.name,
    required this.sizeBytes,
    required this.seeders,
    required this.leechers,
    required this.addedAt,
    required this.source,
  });

  factory TVChannelTorrent.fromJson(Map<String, dynamic> json) {
    return TVChannelTorrent(
      id: json['id'] ?? '',
      channelId: json['channelId'] ?? '',
      magnet: json['magnet'] ?? '',
      name: json['name'] ?? '',
      sizeBytes: json['sizeBytes'] ?? 0,
      seeders: json['seeders'] ?? 0,
      leechers: json['leechers'] ?? 0,
      addedAt: DateTime.parse(json['addedAt'] ?? DateTime.now().toIso8601String()),
      source: json['source'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channelId': channelId,
      'magnet': magnet,
      'name': name,
      'sizeBytes': sizeBytes,
      'seeders': seeders,
      'leechers': leechers,
      'addedAt': addedAt.toIso8601String(),
      'source': source,
    };
  }

  factory TVChannelTorrent.fromTorrent(Torrent torrent, String channelId, String source) {
    return TVChannelTorrent(
      id: '${torrent.infohash}_$channelId',
      channelId: channelId,
      magnet: 'magnet:?xt=urn:btih:${torrent.infohash}',
      name: torrent.name,
      sizeBytes: torrent.sizeBytes,
      seeders: torrent.seeders,
      leechers: torrent.leechers,
      addedAt: DateTime.now(),
      source: source,
    );
  }
} 