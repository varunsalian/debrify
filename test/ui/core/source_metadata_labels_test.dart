import 'package:debrify/ui/core/source_metadata_labels.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row({
  String name = 'Release',
  StreamType type = StreamType.torrent,
  int bytes = 0,
  int created = 0,
  int seeds = 0,
  int leeches = 0,
  String source = '',
  String? addonName,
  String? coverage,
  int? season,
  String? episode,
}) => Torrent(
  rowid: 0,
  infohash: 'hash',
  name: name,
  sizeBytes: bytes,
  createdUnix: created,
  seeders: seeds,
  leechers: leeches,
  completed: 0,
  scrapedDate: 0,
  source: source,
  streamType: type,
  addonDisplayName: addonName,
  coverageType: coverage,
  seasonNumber: season,
  episodeIdentifier: episode,
);

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);
  for (final (age, label) in [
    (const Duration(days: 365), '1y ago'),
    (const Duration(days: 364), '12mo ago'),
    (const Duration(days: 30), '1mo ago'),
    (const Duration(days: 7), '1w ago'),
    (const Duration(days: 1), '1d ago'),
    (const Duration(hours: 1), '1h ago'),
    (const Duration(minutes: 59), 'Today'),
    (const Duration(days: -1), 'Today'),
  ]) {
    test('torrent upload age $age retains $label', () {
      expect(
        sourceRowSubtitle(
          row(created: now.subtract(age).millisecondsSinceEpoch ~/ 1000),
          now: now,
        ),
        label,
      );
    });
  }

  test('torrent metadata retains order, units and addon label precedence', () {
    expect(
      sourceRowSubtitle(
        row(
          bytes: 1024 * 1024 * 1024,
          seeds: 5,
          leeches: 2,
          source: 'indexer',
          addonName: 'Addon',
          created: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      ),
      '1.0 GB · ↑ 5 · ↓ 2 · ADDON · Today',
    );
    expect(sourceRowSubtitle(row()), '');
    expect(
      sourceRowSubtitle(row(bytes: 100 * 1024, source: 'fallback')),
      '100 KB · FALLBACK',
    );
    expect(sourceRowSubtitle(row(source: 'fallback', addonName: '')), '');
  });

  for (final type in [StreamType.directUrl, StreamType.externalUrl]) {
    test('$type omits peer counts and upload date', () {
      expect(
        sourceRowSubtitle(
          row(
            type: type,
            bytes: 1024,
            seeds: 5,
            leeches: 2,
            source: 'addon',
            created: now.millisecondsSinceEpoch ~/ 1000,
          ),
          now: now,
        ),
        '1.0 KB · ADDON',
      );
    });
  }

  test('quality label preserves pixel precedence over loose UHD', () {
    expect(sourceQualityLabel(row(name: 'UHD BluRay 1080p')), '1080p');
    expect(sourceQualityLabel(row(name: 'Movie 2160p')), '4K');
    expect(sourceQualityLabel(row(name: 'Movie 720p')), '720p');
    expect(sourceQualityLabel(row(name: 'Movie 480p')), isNull);
    expect(sourceQualityLabel(row()), isNull);
  });

  test(
    'coverage keeps pack and episode labels with missing-data fallbacks',
    () {
      expect(
        sourceCoverageLabel(row(coverage: 'completeSeries')),
        'Complete Series',
      );
      expect(
        sourceCoverageLabel(row(coverage: 'multiSeasonPack')),
        'Multi-Season',
      );
      expect(
        sourceCoverageLabel(row(coverage: 'seasonPack', season: 0)),
        'Season 0',
      );
      expect(sourceCoverageLabel(row(coverage: 'seasonPack')), 'Season Pack');
      expect(
        sourceCoverageLabel(row(coverage: 'singleEpisode', episode: 'S02E03')),
        'S02E03',
      );
      expect(sourceCoverageLabel(row(coverage: 'singleEpisode')), isNull);
      expect(sourceCoverageLabel(row(coverage: 'unknown')), isNull);
    },
  );
}
