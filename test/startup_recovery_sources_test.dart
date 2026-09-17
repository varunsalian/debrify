import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/startup_recovery_sources.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(String id) => Torrent(
  rowid: 0,
  infohash: id,
  name: '$id.mkv',
  sizeBytes: 100,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

void main() {
  final rules = QuickPlayRules.debrifyDefault(isMovie: false);
  List<String> stages({
    QuickPlayRules? policy,
    String? provider = 'torbox',
    bool movie = false,
  }) => StartupRecoverySources.stages(
    isMovie: movie,
    rules: policy ?? rules,
    provider: provider,
  );

  test('pack-first policy searches packs before episodes', () {
    expect(stages(policy: rules.copyWith(preferSeriesPacks: true)), [
      'packs',
      'episodes',
    ]);
  });
  test('episode-first policy retains a pack fallback', () {
    expect(stages(policy: rules.copyWith(preferSeriesPacks: false)), [
      'episodes',
      'packs',
    ]);
  });
  test('exact-episode policy never searches packs', () {
    expect(
      stages(
        policy: rules.copyWith(
          packPreference: QuickPlayPackPreference.exactEpisodeOnly,
        ),
      ),
      ['episodes'],
    );
  });
  test('PikPak and provider-free playback never acquire fallback packs', () {
    expect(stages(provider: 'pikpak'), ['episodes']);
    expect(stages(provider: null), ['episodes']);
  });
  test('movies keep a single movie search', () {
    expect(stages(movie: true), ['movie']);
  });
  test('automatic exclusions stay visible in manual browsing', () {
    final old = row('old'),
        excluded = row('excluded'),
        allowed = row('allowed');
    final merged = StartupRecoverySources.merge(
      existing: [old],
      fetched: [excluded, allowed],
      automatic: [allowed],
    );
    expect(merged.sources, [old, excluded, allowed]);
    expect(merged.automaticIndices, [2]);
  });
  test('retry order is independent of stable browser indices', () {
    final old = row('old'), a = row('a'), b = row('b');
    final merged = StartupRecoverySources.merge(
      existing: [old, a],
      fetched: [a, b],
      automatic: [b, a],
    );
    expect(merged.sources, [old, a, b]);
    expect(merged.automaticIndices, [2, 1]);
  });
  test('an empty automatic list never removes the manual results', () {
    final a = row('a');
    final merged = StartupRecoverySources.merge(
      existing: [],
      fetched: [a],
      automatic: [],
    );
    expect(merged.sources, [a]);
    expect(merged.automaticIndices, isEmpty);
  });
}
