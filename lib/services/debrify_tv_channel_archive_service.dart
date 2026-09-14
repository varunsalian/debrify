import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/debrify_tv_cache.dart';
import '../models/debrify_tv_channel_record.dart';
import 'community/channel_yaml_builder.dart';

/// One coherent Debrify TV channel snapshot for a portable ZIP archive.
///
/// The caller reads the record and cache entry from one captured profile;
/// archive encoding can then move to a worker isolate without touching the
/// profile database again.
class DebrifyTvChannelArchiveSource {
  const DebrifyTvChannelArchiveSource({
    required this.channel,
    required this.cacheEntry,
  });

  final DebrifyTvChannelRecord channel;
  final DebrifyTvChannelCacheEntry? cacheEntry;

  int get savedHashCount => cacheEntry?.torrents.length ?? 0;

  Map<String, Object?> _toMessage() => <String, Object?>{
    'channel': <String, Object?>{
      'channelId': channel.channelId,
      'name': channel.name,
      'keywords': channel.keywords,
      'avoidNsfw': channel.avoidNsfw,
      'channelNumber': channel.channelNumber,
      'createdAt': channel.createdAt.millisecondsSinceEpoch,
      'updatedAt': channel.updatedAt.millisecondsSinceEpoch,
    },
    'cacheEntry': cacheEntry?.toJson(),
  };
}

/// Produces the same multi-YAML ZIP format already accepted by the Debrify TV
/// ZIP importer. Each selected channel gets one YAML member carrying its
/// definition, keyword statistics, and complete saved torrent pool.
class DebrifyTvChannelArchiveService {
  DebrifyTvChannelArchiveService._();

  static Future<Uint8List> buildZip(
    List<DebrifyTvChannelArchiveSource> sources,
  ) {
    if (sources.isEmpty) {
      throw ArgumentError.value(sources, 'sources', 'must not be empty');
    }
    return compute(
      _buildDebrifyTvChannelZip,
      sources.map((source) => source._toMessage()).toList(growable: false),
    );
  }
}

Uint8List _buildDebrifyTvChannelZip(List<Map<String, Object?>> messages) {
  final archive = Archive();
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    final channelRaw = Map<String, dynamic>.from(message['channel']! as Map);
    final channel = DebrifyTvChannelRecord(
      channelId: channelRaw['channelId'] as String,
      name: channelRaw['name'] as String,
      keywords: List<String>.from(channelRaw['keywords'] as List),
      avoidNsfw: channelRaw['avoidNsfw'] as bool,
      channelNumber: channelRaw['channelNumber'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        channelRaw['createdAt'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        channelRaw['updatedAt'] as int,
      ),
    );
    final cacheRaw = message['cacheEntry'];
    final cacheEntry = cacheRaw is Map
        ? DebrifyTvChannelCacheEntry.fromJson(
            Map<String, dynamic>.from(cacheRaw),
          )
        : null;
    final yaml = ChannelYamlBuilder.buildFromEntry(channel, cacheEntry);
    final bytes = utf8.encode(yaml);
    archive.addFile(
      ArchiveFile(_archiveMemberName(channel.name, index), bytes.length, bytes),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _archiveMemberName(String channelName, int index) {
  var safe = channelName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '-')
      .replaceAll(RegExp(r'[- _]{2,}'), '-')
      .replaceAll(RegExp(r'^[. -]+|[. -]+$'), '');
  if (safe.isEmpty) safe = 'channel';
  if (safe.length > 64) safe = safe.substring(0, 64);
  final prefix = (index + 1).toString().padLeft(3, '0');
  return '$prefix-$safe.yaml';
}
