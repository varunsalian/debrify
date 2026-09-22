import 'package:debrify/models/media_server_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resources = {'resource-AbCd': 'resource-XyZ'};

  test('mixed-case resource IDs map to canonical Quick Play priority keys', () {
    for (final key in [
      'mediaserver:resource-AbCd',
      SourcePriority.keyForSource('mediaserver:resource-AbCd'),
    ]) {
      expect(
        MediaServerSource.remapPriorityKey(key, resources),
        SourcePriority.keyForSource('mediaserver:resource-XyZ'),
      );
    }
  });

  test('unrelated values and unmatched priority IDs remain unchanged', () {
    for (final value in [
      'resource-AbCd',
      'mediaserver:resource-abcd-suffix',
      'mediaserver:missing',
      'stremio:resource-abcd',
      'https://resource-AbCd.example/video',
      'Title mediaserver:resource-abcd',
    ]) {
      expect(MediaServerSource.remapPriorityKey(value, resources), value);
    }
  });

  test(
    'pin references remain exact and preserve destination resource case',
    () {
      const pin = MediaServerSource(
        serverId: 'resource-AbCd',
        contentId: 'CaseSensitiveContent',
        isMovie: true,
        variant: 'CaseSensitiveVersion',
      );
      final restored = MediaServerSource.tryDecode(
        pin.remap(resources).encode(),
      )!;
      expect(restored.serverId, 'resource-XyZ');
      expect(restored.contentId, pin.contentId);
      expect(restored.variant, pin.variant);
      expect(pin.remap({'resource-abcd': 'other'}).serverId, pin.serverId);
    },
  );

  test('remapped priority actually selects the server ahead of a backup', () {
    Torrent source(String provider) => Torrent(
      rowid: 0,
      infohash: provider,
      name: provider,
      sizeBytes: 0,
      createdUnix: 0,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      source: provider,
    );
    final server = source('mediaserver:resource-xyz');
    final backup = source('stremio:backup');
    final priority = MediaServerSource.remapPriorityKey(
      'mediaserver:resource-abcd',
      resources,
    );
    expect(SourcePriority.order([backup, server], [priority, backup.source]), [
      server,
      backup,
    ]);
  });
}
