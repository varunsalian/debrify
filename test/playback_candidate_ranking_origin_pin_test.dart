// Origin pin for the pure candidate-ranking / probing surface of
// TorrentPlaybackService (lane T3). Written against the ORIGIN statics in
// lib/services/torrent_playback_service.dart before that logic moves to
// lib/services/torrent_playback/. It must keep passing, unedited, after the
// move.
//
// Deliberately table-driven and complementary to the existing suites:
//   * test/quick_play_rules_test.dart covers profile persistence and the
//     exact-order/provider-priority behaviour,
//   * test/filter_ladder_test.dart covers the ladder tiers, selectDirect and
//     the packTopSafety guards.
// What is pinned here is the part neither exercises exhaustively: the private
// _qualityScore resolution ladder that drives QuickPlayRanking.quality, the
// smallest/readyFirst comparators and their zero-size / stability quirks, the
// merge + post-cache re-order contracts, and a full branch matrix for
// probeAttemptCount and packTopSafety.

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/utils/filter_ladder.dart';

var _hashSeed = 0;

Torrent _t(
  String name, {
  StreamType type = StreamType.torrent,
  int size = 0,
  int seeders = 0,
  String source = 'engine',
  String? infohash,
  String? coverageType,
}) {
  _hashSeed++;
  return Torrent(
    rowid: 0,
    infohash: infohash ?? _hashSeed.toRadixString(16).padLeft(40, '0'),
    name: name,
    sizeBytes: size,
    createdUnix: 0,
    seeders: seeders,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    source: source,
    streamType: type,
    directUrl: type == StreamType.directUrl ? 'https://x.test/$name.mp4' : null,
    coverageType: coverageType,
  );
}

QuickPlayRules _rules(
  QuickPlayRanking ranking, {
  bool allowDirectLinks = true,
  QuickPlaySourceMode sourceMode = QuickPlaySourceMode.together,
}) => QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
  ranking: ranking,
  allowDirectLinks: allowDirectLinks,
  sourceMode: sourceMode,
);

List<String> _names(List<Torrent> torrents) => [for (final t in torrents) t.name];

void main() {
  // ── QuickPlayRanking.quality: the _qualityScore resolution ladder ────────
  group('orderCandidatesForRules — quality ranking', () {
    // (name, expected score tier). 5 = 8K … 0 = untagged. Every spelling the
    // origin regexes accept is represented.
    const table = <(String, int)>[
      ('Show 4320p WEB-DL x265', 5),
      ('Show 8K HDR REMUX', 5),
      ('Show 2160p WEB-DL x265', 4),
      ('Show 4K BluRay HEVC', 4),
      ('Show UHD BluRay REMUX', 4),
      ('Show 1080p WEB-DL x264', 3),
      ('Show 1080i HDTV MPEG2', 3),
      ('Show FHD WEBRip', 3),
      ('Show 720p WEB x264', 2),
      ('Show 720i HDTV', 2),
      ('Show HD WEBRip', 2),
      ('Show 480p DVDRip', 1),
      ('Show 576p PAL DVDRip', 1),
      ('Show SD XviD', 1),
      ('Show WEB-DL x264', 0),
    ];

    test('every spelling lands in its documented tier, highest first', () {
      // Feed them in reverse (worst first) so a no-op would be detected.
      final input = [for (final row in table.reversed) _t(row.$1)];
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        input,
        rules: _rules(QuickPlayRanking.quality),
      );
      final scores = [
        for (final t in ordered)
          table.firstWhere((row) => row.$1 == t.name).$2,
      ];
      // Non-increasing score, and every input survived.
      expect(ordered.length, table.length);
      for (var i = 1; i < scores.length; i++) {
        expect(
          scores[i] <= scores[i - 1],
          isTrue,
          reason: 'score ${scores[i]} followed ${scores[i - 1]}',
        );
      }
      expect(scores.first, 5);
      expect(scores.last, 0);
    });

    test('seeders break a quality tie; size and codec do not', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('A 1080p WEB x264', seeders: 10, size: 900),
          _t('B 1080p WEB x265', seeders: 90, size: 1),
          _t('C 1080p BluRay REMUX', seeders: 50, size: 500),
        ],
        rules: _rules(QuickPlayRanking.quality),
      );
      expect(_names(ordered), [
        'B 1080p WEB x265',
        'C 1080p BluRay REMUX',
        'A 1080p WEB x264',
      ]);
    });

    test('equal score AND seeders keep their original positions', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('first 1080p', seeders: 7),
          _t('second 1080p', seeders: 7),
          _t('third 1080p', seeders: 7),
        ],
        rules: _rules(QuickPlayRanking.quality),
      );
      expect(_names(ordered), ['first 1080p', 'second 1080p', 'third 1080p']);
    });

    test('a lower-resolution torrent outranks a higher-res direct link', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('direct 720p', type: StreamType.directUrl, seeders: 0),
          _t('torrent 2160p', seeders: 1),
        ],
        rules: _rules(QuickPlayRanking.quality),
      );
      expect(_names(ordered), ['torrent 2160p', 'direct 720p']);
    });
  });

  // ── QuickPlayRanking.smallest ────────────────────────────────────────────
  group('orderCandidatesForRules — smallest ranking', () {
    test('ascending by size, with unknown (0) sizes sunk to the end', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('unknown-a', size: 0),
          _t('big', size: 9000),
          _t('unknown-b', size: 0),
          _t('small', size: 10),
          _t('mid', size: 500),
        ],
        rules: _rules(QuickPlayRanking.smallest),
      );
      expect(_names(ordered), [
        'small',
        'mid',
        'big',
        'unknown-a',
        'unknown-b',
      ]);
    });

    test('equal sizes keep their original positions', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [_t('one', size: 42), _t('two', size: 42), _t('three', size: 42)],
        rules: _rules(QuickPlayRanking.smallest),
      );
      expect(_names(ordered), ['one', 'two', 'three']);
    });
  });

  // ── QuickPlayRanking.readyFirst ──────────────────────────────────────────
  group('orderCandidatesForRules — ready-first ranking', () {
    test('direct links lead, then seeders descending inside each half', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('torrent-hi', seeders: 500),
          _t('direct-lo', type: StreamType.directUrl, seeders: 0),
          _t('torrent-lo', seeders: 1),
          _t('direct-hi', type: StreamType.directUrl, seeders: 3),
        ],
        rules: _rules(QuickPlayRanking.readyFirst),
      );
      expect(_names(ordered), [
        'direct-hi',
        'direct-lo',
        'torrent-hi',
        'torrent-lo',
      ]);
    });

    test('external links rank with the non-direct half', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('external', type: StreamType.externalUrl, seeders: 0),
          _t('direct', type: StreamType.directUrl, seeders: 0),
        ],
        rules: _rules(QuickPlayRanking.readyFirst),
      );
      expect(_names(ordered), ['direct', 'external']);
    });
  });

  // ── Order-preserving rankings ────────────────────────────────────────────
  group('orderCandidatesForRules — order-preserving rankings', () {
    for (final ranking in const [
      QuickPlayRanking.debrify,
      QuickPlayRanking.exactOrder,
    ]) {
      test('$ranking never re-sorts an unprioritised list', () {
        final input = [
          _t('z 480p', seeders: 1, size: 900),
          _t('a 2160p', seeders: 900, size: 1),
          _t('m 1080p', seeders: 50, size: 50),
        ];
        // exactOrder + "prefer torrents" would hoist torrents; these are all
        // torrents, so the walk is a pure identity check either way.
        final ordered = TorrentPlaybackService.orderCandidatesForRules(
          input,
          rules: _rules(ranking),
        );
        expect(_names(ordered), _names(input));
      });
    }

    test('duplicate infohashes collapse to the first occurrence', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('winner', infohash: 'b' * 40),
          _t('loser', infohash: 'B' * 40),
          _t('other', infohash: 'c' * 40),
        ],
        rules: _rules(QuickPlayRanking.debrify),
      );
      expect(_names(ordered), ['winner', 'other']);
    });
  });

  // ── Direct-link gate and the torrent-first transport walk ────────────────
  group('orderCandidatesForRules — transport policy', () {
    test('allowDirectLinks:false drops direct rows, keeps external ones', () {
      final ordered = TorrentPlaybackService.orderCandidatesForRules(
        [
          _t('direct', type: StreamType.directUrl),
          _t('external', type: StreamType.externalUrl),
          _t('torrent'),
        ],
        rules: _rules(
          QuickPlayRanking.debrify,
          allowDirectLinks: false,
        ),
      );
      expect(_names(ordered), ['external', 'torrent']);
    });

    const torrentFirstModes = <QuickPlaySourceMode>[
      QuickPlaySourceMode.torrentsThenAddons,
      QuickPlaySourceMode.torrentsOnly,
      QuickPlaySourceMode.together,
    ];
    const addonFirstModes = <QuickPlaySourceMode>[
      QuickPlaySourceMode.addonsThenTorrents,
      QuickPlaySourceMode.addonsOnly,
    ];

    for (final mode in torrentFirstModes) {
      test('$mode hoists torrent rows in exact order', () {
        final ordered = TorrentPlaybackService.orderCandidatesForRules(
          [
            _t('direct', type: StreamType.directUrl),
            _t('torrent'),
          ],
          rules: _rules(QuickPlayRanking.exactOrder, sourceMode: mode),
        );
        expect(_names(ordered), ['torrent', 'direct']);
        expect(TorrentPlaybackService.prefersTorrentCandidates(
          _rules(QuickPlayRanking.exactOrder, sourceMode: mode),
        ), isTrue);
      });
    }

    for (final mode in addonFirstModes) {
      test('$mode leaves the provider transport order alone', () {
        final ordered = TorrentPlaybackService.orderCandidatesForRules(
          [
            _t('direct', type: StreamType.directUrl),
            _t('torrent'),
          ],
          rules: _rules(QuickPlayRanking.exactOrder, sourceMode: mode),
        );
        expect(_names(ordered), ['direct', 'torrent']);
      });
    }
  });

  // ── Post-cache re-order ──────────────────────────────────────────────────
  group('orderCacheCheckedCandidatesForRules', () {
    final input = [
      _t('cached-lo-seed', seeders: 1),
      _t('uncached-hi-seed', seeders: 999),
      _t('cached-direct', type: StreamType.directUrl),
    ];

    test('exact order keeps the cache partition verbatim (copy, not alias)', () {
      final out = TorrentPlaybackService.orderCacheCheckedCandidatesForRules(
        input,
        rules: _rules(QuickPlayRanking.exactOrder),
      );
      expect(_names(out), _names(input));
      expect(identical(out, input), isFalse);
    });

    test('ready-first keeps the partition instead of re-sorting by seeders', () {
      final out = TorrentPlaybackService.orderCacheCheckedCandidatesForRules(
        input,
        rules: _rules(QuickPlayRanking.readyFirst),
      );
      expect(_names(out), _names(input));
    });

    test('other rankings fall through to the full rule ordering', () {
      final out = TorrentPlaybackService.orderCacheCheckedCandidatesForRules(
        input,
        rules: _rules(QuickPlayRanking.smallest),
      );
      expect(
        _names(out),
        _names(
          TorrentPlaybackService.orderCandidatesForRules(
            input,
            rules: _rules(QuickPlayRanking.smallest),
          ),
        ),
      );
    });

    test('an inactive ladder never disturbs ready-first', () {
      final out = TorrentPlaybackService.orderCacheCheckedCandidatesForRules(
        input,
        rules: _rules(QuickPlayRanking.readyFirst),
        ladder: FilterLadder(const TorrentFilterState.empty()),
      );
      expect(_names(out), _names(input));
    });
  });

  // ── mergePreparedTorrentOrder ────────────────────────────────────────────
  group('mergePreparedTorrentOrder', () {
    test('only acquisition-bearing torrent slots are replaced, in order', () {
      final sources = [
        _t('t1'),
        _t('direct', type: StreamType.directUrl),
        _t('t2'),
        _t('external', type: StreamType.externalUrl),
        _t('t3'),
      ];
      final prepared = [_t('p-a'), _t('p-b'), _t('p-c')];
      final merged = TorrentPlaybackService.mergePreparedTorrentOrder(
        sources,
        prepared,
      );
      expect(_names(merged), ['p-a', 'direct', 'p-b', 'external', 'p-c']);
    });

    test('a torrent row without acquisition data is not a slot', () {
      final noAcquisition = Torrent(
        rowid: 0,
        infohash: '',
        name: 'no-acquisition',
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        streamType: StreamType.torrent,
        hasRealInfoHash: false,
      );
      final merged = TorrentPlaybackService.mergePreparedTorrentOrder(
        [noAcquisition, _t('t1')],
        [_t('p-a')],
      );
      expect(_names(merged), ['no-acquisition', 'p-a']);
    });
  });

  // ── probeAttemptCount — full branch matrix ───────────────────────────────
  group('probeAttemptCount branch matrix', () {
    // (provider, tryMultiple, maxRetries, minAttempts, expected)
    const table = <(String, bool, int, int, int)>[
      // PikPak's one-probe safety beats every other input, including floors.
      ('pikpak', true, 10, 2, 1),
      ('pikpak', false, 1, 5, 1),
      // Try-multiple off ⇒ one attempt, unless the pack-top floor raises it.
      ('realdebrid', false, 10, 1, 1),
      ('realdebrid', false, 10, 2, 2),
      // Try-multiple on ⇒ the user's retry count, clamped to 1..10 so a
      // corrupted pref can never produce zero probes.
      ('realdebrid', true, 5, 1, 5),
      ('realdebrid', true, 0, 1, 1),
      ('realdebrid', true, -7, 1, 1),
      ('realdebrid', true, 99, 1, 10),
      // The floor only ever raises, never lowers.
      ('realdebrid', true, 5, 2, 5),
      ('realdebrid', true, 1, 4, 4),
      ('torbox', true, 3, 1, 3),
      ('premiumize', false, 3, 1, 1),
    ];

    for (final row in table) {
      test(
        '${row.$1} tryMultiple=${row.$2} max=${row.$3} floor=${row.$4} '
        '⇒ ${row.$5}',
        () {
          expect(
            TorrentPlaybackService.probeAttemptCount(
              row.$1,
              tryMultiple: row.$2,
              maxRetries: row.$3,
              minAttempts: row.$4,
            ),
            row.$5,
          );
        },
      );
    }
  });

  // ── packTopSafety across mixed season packs ──────────────────────────────
  group('packTopSafety with mixed season packs', () {
    final ladder = FilterLadder(const TorrentFilterState.empty());

    Torrent pack(String coverage) =>
        _t('Show Complete $coverage 1080p WEB', coverageType: coverage);

    test('a complete-series top still yields the probe to the exact single', () {
      final complete = pack('completeSeries');
      final multi = pack('multiSeasonPack');
      final season = pack('seasonPack');
      final single = _t('Show S02E04 1080p WEB x264');
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [complete, multi, season, single],
        provider: 'realdebrid',
        ladder: ladder,
        season: 2,
        episode: 4,
      );
      expect(_names(list), [
        complete.name,
        single.name,
        multi.name,
        season.name,
      ]);
      expect(attempts, 2);
    });

    test('the FIRST exact single wins the hoist, later ones stay put', () {
      final top = pack('seasonPack');
      final first = _t('Show S02E04 720p WEB x264');
      final second = _t('Show S02E04 2160p WEB x265');
      final (list, _) = TorrentPlaybackService.packTopSafety(
        [top, first, second],
        provider: 'realdebrid',
        ladder: ladder,
        season: 2,
        episode: 4,
      );
      expect(_names(list), [top.name, first.name, second.name]);
    });

    test('a pack top whose own name carries the episode is not rescued', () {
      final top = _t(
        'Show S02E04 Complete 1080p WEB',
        coverageType: 'seasonPack',
      );
      final single = _t('Show S02E04 720p WEB x264');
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [top, single],
        provider: 'realdebrid',
        ladder: ladder,
        season: 2,
        episode: 4,
      );
      expect(_names(list), [top.name, single.name]);
      expect(attempts, 1);
    });

    test('a single-element list is never touched', () {
      final top = pack('completeSeries');
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [top],
        provider: 'realdebrid',
        ladder: ladder,
        season: 2,
        episode: 4,
      );
      expect(_names(list), [top.name]);
      expect(attempts, 1);
    });

    test('an unknown coverage top is treated as a single, not a pack', () {
      final top = _t('Show 2160p WEB', coverageType: 'unknown');
      final single = _t('Show S02E04 720p WEB x264');
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [top, single],
        provider: 'realdebrid',
        ladder: ladder,
        season: 2,
        episode: 4,
      );
      expect(_names(list), [top.name, single.name]);
      expect(attempts, 1);
    });
  });

  // ── The pure rule predicates the play flow branches on ───────────────────
  group('rule predicate matrix', () {
    test('addon stream search plan collapses mixed modes to "together"', () {
      const expected = <QuickPlaySourceMode, List<QuickPlaySourceMode>>{
        QuickPlaySourceMode.torrentsThenAddons: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.addonsThenTorrents: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.together: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.torrentsOnly: [QuickPlaySourceMode.torrentsOnly],
        QuickPlaySourceMode.addonsOnly: [QuickPlaySourceMode.addonsOnly],
      };
      for (final entry in expected.entries) {
        expect(
          TorrentPlaybackService.addonStreamSearchPlan(
            _rules(QuickPlayRanking.debrify, sourceMode: entry.key),
          ),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('series pack search plan mirrors it for every mode', () {
      const expected = <QuickPlaySourceMode, List<QuickPlaySourceMode>>{
        QuickPlaySourceMode.torrentsThenAddons: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.addonsThenTorrents: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.together: [QuickPlaySourceMode.together],
        QuickPlaySourceMode.torrentsOnly: [QuickPlaySourceMode.torrentsOnly],
        QuickPlaySourceMode.addonsOnly: [QuickPlaySourceMode.addonsOnly],
      };
      for (final entry in expected.entries) {
        expect(
          TorrentPlaybackService.seriesPackSearchPlan(
            _rules(QuickPlayRanking.debrify, sourceMode: entry.key),
          ),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('pack search errors are read from the stage-specific error map', () {
      const addonStage = QuickPlaySourceMode.addonsOnly;
      const engineStage = QuickPlaySourceMode.torrentsOnly;
      final withAddonErrors = <String, dynamic>{
        'addonErrors': {'a': 'boom'},
        'engineErrors': <String, String>{},
      };
      final withEngineErrors = <String, dynamic>{
        'addonErrors': <String, String>{},
        'engineErrors': {'e': 'boom'},
      };
      expect(
        TorrentPlaybackService.packSearchReportedErrors(
          withAddonErrors,
          addonStage,
        ),
        isTrue,
      );
      expect(
        TorrentPlaybackService.packSearchReportedErrors(
          withAddonErrors,
          engineStage,
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.packSearchReportedErrors(
          withEngineErrors,
          engineStage,
        ),
        isTrue,
      );
      // A missing map is "no errors reported", not a crash.
      expect(
        TorrentPlaybackService.packSearchReportedErrors(
          <String, dynamic>{},
          engineStage,
        ),
        isFalse,
      );
    });

    test('auto-playable candidates exclude external links', () {
      expect(
        TorrentPlaybackService.isAutoPlayableCandidate(
          _t('direct', type: StreamType.directUrl),
        ),
        isTrue,
      );
      expect(
        TorrentPlaybackService.isAutoPlayableCandidate(_t('torrent')),
        isTrue,
      );
      expect(
        TorrentPlaybackService.isAutoPlayableCandidate(
          _t('external', type: StreamType.externalUrl),
        ),
        isFalse,
      );
    });

    test('direct validation budget stays at five for every retry count', () {
      for (final attempts in const [1, 3, 10]) {
        expect(
          TorrentPlaybackService.directValidationBudgetForRules(
            _rules(QuickPlayRanking.debrify).copyWith(maxAttempts: attempts),
          ),
          5,
        );
      }
      expect(TorrentPlaybackService.directValidationBudgetForRules(null), 5);
    });

    test('addon search is allowed everywhere except torrents-only', () {
      for (final mode in QuickPlaySourceMode.values) {
        expect(
          TorrentPlaybackService.allowsAddonSearch(
            _rules(QuickPlayRanking.debrify, sourceMode: mode),
          ),
          mode != QuickPlaySourceMode.torrentsOnly,
          reason: '$mode',
        );
      }
    });

    test('only an addon-only exact-episode route defers the provider prompt', () {
      final addonsOnly = _rules(
        QuickPlayRanking.debrify,
        sourceMode: QuickPlaySourceMode.addonsOnly,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonsOnly,
          isMovie: true,
        ),
        isTrue,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonsOnly,
          isMovie: true,
          hasPreferredProvider: true,
        ),
        isFalse,
      );
      // A series that still wants packs stays on the provider-backed route.
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonsOnly.copyWith(preferSeriesPacks: true),
          isMovie: false,
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonsOnly.copyWith(
            preferSeriesPacks: true,
            packPreference: QuickPlayPackPreference.exactEpisodeOnly,
          ),
          isMovie: false,
        ),
        isTrue,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          _rules(
            QuickPlayRanking.debrify,
            sourceMode: QuickPlaySourceMode.together,
          ),
          isMovie: true,
        ),
        isFalse,
      );
    });

    test('direct-before-torrent follows the torrent-first source modes', () {
      for (final mode in QuickPlaySourceMode.values) {
        final torrentFirst =
            mode == QuickPlaySourceMode.torrentsThenAddons ||
            mode == QuickPlaySourceMode.torrentsOnly;
        expect(
          TorrentPlaybackService.shouldTryDirectBeforeTorrent(
            _rules(QuickPlayRanking.debrify, sourceMode: mode),
          ),
          !torrentFirst,
          reason: '$mode',
        );
      }
      expect(TorrentPlaybackService.shouldTryDirectBeforeTorrent(null), isTrue);
    });
  });
}
