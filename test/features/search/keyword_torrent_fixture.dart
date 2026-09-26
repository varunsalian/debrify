import 'package:debrify/models/torrent.dart';

Torrent keywordTorrent(
  String name, {
  String source = '',
  String? hash,
  StreamType type = StreamType.torrent,
  bool hasRealHash = true,
  String? torrentUrl,
  int seeders = 0,
  int size = 0,
  int date = 0,
}) => Torrent(
  rowid: 0,
  infohash: hash ?? name,
  name: name,
  source: source,
  streamType: type,
  hasRealInfoHash: hasRealHash,
  torrentUrl: torrentUrl,
  sizeBytes: size,
  createdUnix: date,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);
