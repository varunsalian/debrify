import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/torrent_curation.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/widgets/torrent_result_row.dart'
    show TorrentQualityExtension;

// All assertion names below are REAL release names captured from the wild
// (apibay, 2026-07-15) — they live in test/fixtures/release_names.json, which
// the corpus-level tests load in full. See QUICK_PLAY_FILTERS_PLAN.md §5.

Torrent t(
  String name, {
  StreamType type = StreamType.torrent,
  int seeders = 0,
  String? coverageType,
}) => Torrent(
  rowid: 0,
  infohash: 'a' * 40,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
  directUrl: type == StreamType.directUrl ? 'http://x/v.mp4' : null,
  coverageType: coverageType,
);

/// The standard preset used throughout: 1080p + (WEB|BluRay) + English.
final p1 = TorrentFilterState(
  qualities: {QualityTier.fullHd},
  ripSources: {RipSourceCategory.web, RipSourceCategory.bluRay},
  languages: {AudioLanguage.english},
);

List<String> loadCorpus() {
  final raw =
      jsonDecode(File('test/fixtures/release_names.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final e in raw.entries)
      if (e.key != '_meta') ...(e.value as List).cast<String>(),
  ];
}

void main() {
  // ── Step 0: shared classifier fix (bare .WEB. token) ──────────────────────
  group('detectRipSource — bare WEB fix (§3.2c)', () {
    test('dotted bare .WEB. names classify as web', () {
      // Real names that the pre-fix classifier called `other`.
      expect(
        TorrentFilterMatcher.detectRipSource(
          'The.Penguin.S01E01.WEB.x264-TORRENTGALAXY',
        ),
        RipSourceCategory.web,
      );
      expect(
        TorrentFilterMatcher.detectRipSource(
          'The.Penguin.S01E01.DV.HDR.2160p.WEB.h265-ETHEL[TGx]',
        ),
        RipSourceCategory.web,
      );
      expect(
        TorrentFilterMatcher.detectRipSource(
          'Godzilla.Minus.One.2023.MULTi.FRENCH.1080p.WEB.H264-FW.mkv',
        ),
        RipSourceCategory.web,
      );
    });

    test('bluray family still wins over a bare web token', () {
      // "UHD BluRay" + no web token: bluray. And a name carrying both
      // families keeps the existing precedence (bluray checked first).
      expect(
        TorrentFilterMatcher.detectRipSource(
          'Oppenheimer 2023 IMAX UHD BluRay 1080p DD Atmos 5 1 DoVi HDR10 x265-SM737',
        ),
        RipSourceCategory.bluRay,
      );
    });

    test('existing families unchanged on real names', () {
      expect(
        TorrentFilterMatcher.detectRipSource(
          'Dune Part Two (2024) [1080p] [WEBRip] 88',
        ),
        RipSourceCategory.web,
      );
      expect(
        TorrentFilterMatcher.detectRipSource(
          'Oppenheimer.2023.1080p.NEW.V3.TELESYNC.H.264.AAC-HushRips',
        ),
        RipSourceCategory.cam,
      );
      expect(
        TorrentFilterMatcher.detectRipSource(
          'Oppenheimer.2023.1080p.HDCAM.English.1XBET.',
        ),
        RipSourceCategory.cam,
      );
    });

    test(
        'bare-web is checked LAST: a title word "Web" never steals a real '
        'rip token (synthetic names)', () {
      expect(
        TorrentFilterMatcher.detectRipSource('Charlottes.Web.2006.DVDRip.x264'),
        RipSourceCategory.dvdrip,
      );
      expect(
        TorrentFilterMatcher.detectRipSource('Web.of.Lies.S01E03.HDTV.x264'),
        RipSourceCategory.hdrip,
      );
      // Only with no other rip token does bare "web" win (accepted false
      // positive for actual web releases like ".WEB.").
      expect(
        TorrentFilterMatcher.detectRipSource('Charlottes.Web.2006.x264'),
        RipSourceCategory.web,
      );
    });

    test('corpus: at least 10 previously-unclassifiable bare-WEB names', () {
      final bareWeb = loadCorpus().where((n) {
        final s = n.toLowerCase();
        final oldTokens = [
          'bluray', 'blu-ray', 'bdrip', 'brrip', 'remux', // bluray family
          'webrip', 'web-dl', 'webdl', 'webhd', 'webmux', 'web ', 'amzn',
          'nf.web',
        ];
        return !oldTokens.any(s.contains) &&
            RegExp(r'\bweb\b').hasMatch(s) &&
            TorrentFilterMatcher.detectRipSource(n) == RipSourceCategory.web;
      }).length;
      expect(bareWeb, greaterThanOrEqualTo(10));
    });
  });

  // ── Quality classifier assumptions the ladder relies on ──────────────────
  group('qualityTier on real names', () {
    test('pixel token beats UHD source tag', () {
      // "UHD BluRay 1080p" is a 1080p encode of a UHD source.
      expect(
        t('Oppenheimer 2023 IMAX UHD BluRay 1080p DD Atmos 5 1 DoVi HDR10 x265-SM737')
            .qualityTier,
        QualityTier.fullHd,
      );
      expect(
        t('Interstellar 2014 IMAX Hybrid 1080p UHD BluRay DD+5.1 DV HDR x265-HiDt')
            .qualityTier,
        QualityTier.fullHd,
      );
    });
    test('2160p and untagged', () {
      expect(
        t('The.Penguin.S01E01.2160p.WEB-DL.DV.HDR.ENG.LATINO.HINDI.Atmos.H265.MP4-BTM')
            .qualityTier,
        QualityTier.ultraHd,
      );
      // No quality token at all → sd (documented default).
      expect(
        t('Oppenheimer.2023.BDRip.x264-PiGNUS').qualityTier,
        QualityTier.sd,
      );
    });
  });

  // ── §3.3 + §3.3b: ladder language matching ────────────────────────────────
  group('FilterLadder.langMatches', () {
    test('untagged name counts as English when English is selected (§3.3)', () {
      const untagged = 'John Wick Chapter 2 (2017) [1080p] [BluRay] ';
      expect(
        FilterLadder.langMatches(untagged, {AudioLanguage.english}),
        isTrue,
      );
      expect(
        FilterLadder.langMatches(untagged, {AudioLanguage.hindi}),
        isFalse,
      );
      expect(
        FilterLadder.langMatches(
          untagged,
          {AudioLanguage.english, AudioLanguage.hindi},
        ),
        isTrue,
      );
    });

    test('multi-language tag lists match ANY listed language (§3.3b)', () {
      // detectAudioLanguage returns `hindi` for this (first match wins) —
      // the ladder must still accept it for an English filter.
      const dual =
          'Dune.Part.Two.2024.1080p.AMZN.WEB-DL.ENG.LATINO.HINDI.H264-BEN.THE.MEN';
      expect(
        TorrentFilterMatcher.detectAudioLanguage(dual),
        AudioLanguage.hindi,
      );
      expect(FilterLadder.langMatches(dual, {AudioLanguage.english}), isTrue);
      expect(FilterLadder.langMatches(dual, {AudioLanguage.hindi}), isTrue);
      expect(FilterLadder.langMatches(dual, {AudioLanguage.spanish}), isTrue);
      expect(FilterLadder.langMatches(dual, {AudioLanguage.german}), isFalse);
    });

    test('an explicit multi-audio tag satisfies any selection', () {
      const multi =
          'Jawan 2023 1080p S-Print Hindi (Clean Audio) + Multi Audio x264 AVC [Love Rul';
      expect(FilterLadder.langMatches(multi, {AudioLanguage.german}), isTrue);
      expect(FilterLadder.langMatches(multi, {AudioLanguage.english}), isTrue);
    });

    test('a tagged foreign-only name does not match English', () {
      const french =
          'Dune.Part.Two.2024.FRENCH.FANSUB.1080p.WEBRip.x265.10bit.AAC-NBDY.mkv';
      expect(
        FilterLadder.langMatches(french, {AudioLanguage.english}),
        isFalse,
      );
      expect(FilterLadder.langMatches(french, {AudioLanguage.french}), isTrue);
    });
  });

  // ── Tier assignment (P1 preset) on real names ─────────────────────────────
  group('FilterLadder.tierOfName — P1: 1080p + WEB/BluRay + English', () {
    late FilterLadder ladder;
    setUp(() => ladder = FilterLadder(p1));

    test('ladder shape: 4 tiers, cam floor beyond', () {
      expect(ladder.isActive, isTrue);
      expect(ladder.tierCount, 4);
    });

    test('tier 0: full match', () {
      expect(
        ladder.tierOfName(
          'The Penguin S01E01 After Hours 1080p AMZN WEB-DL DDP5 1 Atmos H 264-FLUX',
        ),
        0,
      );
      expect(
        ladder.tierOfName(
          'Breaking.Bad.Complete.S01-S05.1080p.10bit.BluRay.x265.HEVC.6CH-M',
        ),
        0,
      );
      // Dual-audio with ENG in the tag list — §3.3b keeps it tier 0.
      expect(
        ladder.tierOfName(
          'Dune.Part.Two.2024.1080p.AMZN.WEB-DL.ENG.LATINO.HINDI.H264-BEN.THE.MEN',
        ),
        0,
      );
    });

    test('tier 1: right quality+rip, wrong (tagged foreign) language', () {
      expect(
        ladder.tierOfName(
          'Dune.Part.Two.2024.FRENCH.FANSUB.1080p.WEBRip.x265.10bit.AAC-NBDY.mkv',
        ),
        1,
      );
    });

    test('tier 2: right quality, wrong rip source', () {
      // 1080p HDTV — quality matches, rip family doesn't.
      expect(
        ladder.tierOfName('Game of Thrones S02E05 1080i HDTV DD5.1 MPEG2 [PublicHD]'),
        2,
      );
    });

    test('tier 3: wrong quality', () {
      // 2160p when the filter says 1080p — relaxed all the way.
      expect(
        ladder.tierOfName(
          'The.Penguin.S01E01.2160p.WEB-DL.DV.HDR.ENG.LATINO.HINDI.Atmos.H265.MP4-BTM',
        ),
        3,
      );
      expect(
        ladder.tierOfName(
          'To.End.All.War.Oppenheimer.and.the.Atomic.Bomb.2023.720p.WEB',
        ),
        3,
      );
    });

    test('cam floor (§3.3c): cams sink below every tier, even 1080p ones', () {
      final cam = ladder.tierOfName(
        'Oppenheimer.2023.1080p.NEW.V3.TELESYNC.H.264.AAC-HushRips',
      );
      expect(cam, greaterThanOrEqualTo(ladder.tierCount));
      expect(
        ladder.tierOfName('Oppenheimer.2023.720p.HDCAM-C1NEM4'),
        greaterThanOrEqualTo(ladder.tierCount),
      );
    });

    test('cam floor lifts when the user selected cam', () {
      final camOk = FilterLadder(
        TorrentFilterState(ripSources: {RipSourceCategory.cam}),
      );
      expect(
        camOk.tierOfName('Oppenheimer.2023.720p.HDCAM-C1NEM4'),
        0,
      );
    });

    test(
        'cam floor exempts non-torrent streams — an IPTV ".ts" label is a '
        'transport stream, not a telesync', () {
      // \b(ts)\b false-positives on stream labels; via tierOf a direct
      // stream never sinks to the floor (it relaxes normally instead).
      const name = 'Channel One 1080p live.ts';
      expect(
        ladder.tierOfName(name),
        greaterThanOrEqualTo(ladder.tierCount),
        reason: 'name-only classification still cam-floors',
      );
      final stream = t(name, type: StreamType.directUrl);
      expect(ladder.tierOf(stream), lessThan(ladder.tierCount));
    });
  });

  // ── Dynamic ladder shapes ─────────────────────────────────────────────────
  group('ladder shape follows active dimensions', () {
    test('quality-only filter → 2 tiers', () {
      final l = FilterLadder(
        TorrentFilterState(qualities: {QualityTier.ultraHd}),
      );
      expect(l.tierCount, 2);
      expect(
        l.tierOfName(
          'Dune.Part.Two.2024.2160p.WEB-DL.DV.HDR10.PLUS.ENG.LATINO.H265.MKV-BEN.THE.MEN',
        ),
        0,
      );
      expect(
        l.tierOfName('Dune Part Two (2024) [1080p] [WEBRip] 88'),
        1,
      );
    });

    test('language-only filter → 2 tiers', () {
      final l = FilterLadder(
        TorrentFilterState(languages: {AudioLanguage.hindi}),
      );
      expect(l.tierCount, 2);
      expect(
        l.tierOfName(
          'Jawan 2023 1080p S-Print Hindi (Clean Audio) + Multi Audio x264 AVC [Love Rul',
        ),
        0,
      );
      expect(
        l.tierOfName('John Wick Chapter 2 (2017) [1080p] [BluRay] '),
        1,
      );
    });

    test('empty filters → inactive single tier, order() is identity', () {
      final l = FilterLadder(const TorrentFilterState.empty());
      expect(l.isActive, isFalse);
      final list = [
        t('Oppenheimer.2023.720p.HDCAM-C1NEM4'),
        t('The Penguin S01E01 After Hours 1080p AMZN WEB-DL DDP5 1 Atmos H 264-FLUX'),
      ];
      // No reordering AT ALL when no filters are set — including no cam
      // demotion (byte-identical to today's behavior).
      expect(l.order(list), same(list));
    });
  });

  // ── Ordering semantics ────────────────────────────────────────────────────
  group('FilterLadder.order', () {
    test('stable tier sort with cam floor, real names', () {
      final ladder = FilterLadder(p1);
      final a = t('Oppenheimer.2023.1080p.NEW.V3.TELESYNC.H.264.AAC-HushRips'); // cam
      final b = t('To.End.All.War.Oppenheimer.and.the.Atomic.Bomb.2023.720p.WEB'); // t3
      final c = t('Game of Thrones S02E05 1080i HDTV DD5.1 MPEG2 [PublicHD]'); // t2
      final d = t('Oppenheimer (2023) BluRay 1080p.H264 Ita Eng AC3 5.1 Sub Ita Eng ...'); // t0
      final e = t('The Penguin S01E01 After Hours 1080p AMZN WEB-DL DDP5 1 Atmos H 264-FLUX'); // t0
      final ordered = ladder.order([a, b, c, d, e]);
      expect(ordered, [d, e, c, b, a]);
      // Stability: d before e (input order preserved within tier 0).
    });

    test('counts() reports per-tier totals for the overlay note', () {
      final ladder = FilterLadder(p1);
      final counts = ladder.counts([
        t('The Penguin S01E01 After Hours 1080p AMZN WEB-DL DDP5 1 Atmos H 264-FLUX'),
        t('Game of Thrones S02E05 1080i HDTV DD5.1 MPEG2 [PublicHD]'),
        t('Oppenheimer.2023.720p.HDCAM-C1NEM4'),
      ]);
      expect(counts[0], 1);
      expect(counts[2], 1);
      expect(counts[ladder.tierCount], 1); // cam floor bucket
    });
  });

  // ── Pack-top safety (§3.4b.3) — the probe-order guarantee ────────────────
  group('TorrentPlaybackService.packTopSafety', () {
    final ladder = FilterLadder(p1);
    final pack = t(
      'Breaking.Bad.Complete.S01-S05.1080p.10bit.BluRay.x265.HEVC.6CH-M',
      coverageType: 'completeSeries',
    );
    final pack2 = t(
      'Breaking Bad S01-S05 Seasons 1-5 Complete 1080p H264 BluRay-MIXE',
      coverageType: 'multiSeasonPack',
    );
    final single = t('Breaking.Bad.S01E01.720p.HDTV.x264');

    test('standard provider: single moves to index 1, two probes floor', () {
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [pack, pack2, single],
        provider: 'debrid',
        ladder: ladder,
        season: 1,
        episode: 1,
      );
      expect(list, [pack, single, pack2]);
      expect(attempts, 2);
    });

    test('pikpak: single takes index 0 — the ONE probe is never a pack', () {
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [pack, pack2, single],
        provider: 'pikpak',
        ladder: ladder,
        season: 1,
        episode: 1,
      );
      expect(list, [single, pack, pack2]);
      expect(attempts, 1);
    });

    test('no-ops: single already on top / no single / movie', () {
      final (l1, a1) = TorrentPlaybackService.packTopSafety(
        [single, pack],
        provider: 'debrid',
        ladder: ladder,
        season: 1,
        episode: 1,
      );
      expect(l1, [single, pack]);
      expect(a1, 1);

      final (l2, a2) = TorrentPlaybackService.packTopSafety(
        [pack, pack2],
        provider: 'debrid',
        ladder: ladder,
        season: 1,
        episode: 1,
      );
      expect(l2, [pack, pack2]);
      expect(a2, 1);

      final (l3, a3) = TorrentPlaybackService.packTopSafety(
        [pack, single],
        provider: 'debrid',
        ladder: ladder,
        season: null,
        episode: null,
      );
      expect(l3, [pack, single]);
      expect(a3, 1);
    });

    test(
        'a top WITHOUT pack coverage is not a pack — episode-scoped addon '
        'streams and token-less singles are left alone (round-2 guard)', () {
      // Anime-style episode-scoped names carry no S/E token; treating them
      // as packs would redirect PikPak\'s only probe.
      final animeTop = t('[SubsPlease] Show - 05 (1080p) [WEB]');
      final tokenSingle = t('Show S01E05 1080p WEB x264');
      final (l1, a1) = TorrentPlaybackService.packTopSafety(
        [animeTop, tokenSingle],
        provider: 'pikpak',
        ladder: ladder,
        season: 1,
        episode: 5,
      );
      expect(l1, [animeTop, tokenSingle]);
      expect(a1, 1);

      final directTop = t('1080p WEB-DL', type: StreamType.directUrl);
      final (l2, a2) = TorrentPlaybackService.packTopSafety(
        [directTop, tokenSingle],
        provider: 'pikpak',
        ladder: ladder,
        season: 1,
        episode: 5,
      );
      expect(l2, [directTop, tokenSingle]);
      expect(a2, 1);
    });

    test('a cam-floored single is never hoisted (would defeat §3.3c)', () {
      final camSingle = t('Show S01E05 1080p HDCAM x264');
      final (list, attempts) = TorrentPlaybackService.packTopSafety(
        [pack, camSingle],
        provider: 'pikpak',
        ladder: ladder,
        season: 1,
        episode: 5,
      );
      expect(list, [pack, camSingle]);
      expect(attempts, 1);
    });
  });

  // ── selectDirect — the instant-play pick + dead-end rescue ───────────────
  group('TorrentPlaybackService.selectDirect', () {
    final ladder = FilterLadder(p1);
    // Tier 0 torrent, tier-3 direct (720p fails the 1080p filter).
    final t0torrent = t('Movie 2024 1080p WEB-DL x264');
    final relaxedDirect =
        t('Movie 720p WEB stream', type: StreamType.directUrl);
    final t0direct =
        t('Movie 1080p WEB stream', type: StreamType.directUrl);
    final external =
        t('Movie 1080p WEB external', type: StreamType.externalUrl);

    test('legacy (no ladder): first direct wins regardless of position', () {
      final (direct, fallback) = TorrentPlaybackService.selectDirect(
        [t0torrent, relaxedDirect],
        null,
      );
      expect(direct, relaxedDirect);
      expect(fallback, relaxedDirect);
    });

    test('active ladder: best-tier direct plays now', () {
      final ordered = ladder.order([t0direct, t0torrent, relaxedDirect]);
      final (direct, _) = TorrentPlaybackService.selectDirect(ordered, ladder);
      expect(direct, t0direct);
    });

    test(
        'active ladder: relaxed-tier direct behind a tier-0 torrent is only '
        'the fallback', () {
      final ordered = ladder.order([t0torrent, relaxedDirect]);
      final (direct, fallback) =
          TorrentPlaybackService.selectDirect(ordered, ladder);
      expect(direct, isNull);
      expect(fallback, relaxedDirect);
    });

    test('unplayable tier-0 noise cannot suppress the instant play', () {
      // externalUrl streams are not probeable and not direct-playable —
      // they must not define the best tier.
      final ordered = ladder.order([external, relaxedDirect]);
      final (direct, fallback) =
          TorrentPlaybackService.selectDirect(ordered, ladder);
      expect(direct, relaxedDirect);
      expect(fallback, relaxedDirect);
    });

    test('no direct at all → (null, null)', () {
      final (direct, fallback) =
          TorrentPlaybackService.selectDirect([t0torrent], ladder);
      expect(direct, isNull);
      expect(fallback, isNull);
    });
  });

  // ── probeAttemptCount — the PikPak-always-1 clamp ────────────────────────
  group('TorrentPlaybackService.probeAttemptCount', () {
    test('pikpak is 1 no matter what', () {
      expect(
        TorrentPlaybackService.probeAttemptCount('pikpak',
            tryMultiple: true, maxRetries: 10, minAttempts: 2),
        1,
      );
    });
    test('minAttempts floors the single-attempt default', () {
      expect(
        TorrentPlaybackService.probeAttemptCount('debrid',
            tryMultiple: false, maxRetries: 5, minAttempts: 2),
        2,
      );
    });
    test('try-multiple wins when higher; corrupted pref clamps to 1..10', () {
      expect(
        TorrentPlaybackService.probeAttemptCount('torbox',
            tryMultiple: true, maxRetries: 5, minAttempts: 2),
        5,
      );
      expect(
        TorrentPlaybackService.probeAttemptCount('torbox',
            tryMultiple: true, maxRetries: 0),
        1,
      );
      expect(
        TorrentPlaybackService.probeAttemptCount('torbox',
            tryMultiple: true, maxRetries: 99),
        10,
      );
    });
  });

  // ── ladderNote — every narration branch ──────────────────────────────────
  group('TorrentPlaybackService.ladderNote', () {
    test('inactive or empty → null (filterless plays stay silent)', () {
      final inactive = FilterLadder(const TorrentFilterState.empty());
      expect(TorrentPlaybackService.ladderNote(inactive, [t('x')]), isNull);
      expect(TorrentPlaybackService.ladderNote(FilterLadder(p1), []), isNull);
    });

    test('tier 0: summary + singular/plural counts', () {
      final ladder = FilterLadder(p1);
      final match =
          t('The Penguin S01E01 After Hours 1080p AMZN WEB-DL H 264-FLUX');
      expect(
        TorrentPlaybackService.ladderNote(ladder, [match]),
        'Matching your filters (1080p · WEB · Blu-ray · English) · 1 source',
      );
      expect(
        TorrentPlaybackService.ladderNote(ladder, [match, match]),
        'Matching your filters (1080p · WEB · Blu-ray · English) · 2 sources',
      );
    });

    test('middle tier: "trying without …" copy', () {
      final ladder = FilterLadder(p1);
      final french = t(
        'Dune.Part.Two.2024.FRENCH.FANSUB.1080p.WEBRip.x265.10bit.AAC-NBDY.mkv',
      );
      expect(
        TorrentPlaybackService.ladderNote(ladder, [french]),
        'No full filter match — trying without language match · 1 source',
      );
    });

    test('unrestricted tier and cam floor copy', () {
      final ladder = FilterLadder(p1);
      final wrongQuality =
          t('To.End.All.War.Oppenheimer.and.the.Atomic.Bomb.2023.720p.WEB');
      expect(
        TorrentPlaybackService.ladderNote(ladder, [wrongQuality]),
        'Nothing matches your filters (1080p · WEB · Blu-ray · English) — '
        'playing best available',
      );
      final cam = t('Oppenheimer.2023.720p.HDCAM-C1NEM4');
      expect(
        TorrentPlaybackService.ladderNote(ladder, [cam]),
        'Only cam-quality sources found — playing best available',
      );
    });
  });

  // ── nameHasExactEpisode — token formats + digit boundaries ───────────────
  group('nameHasExactEpisode', () {
    test('all four spellings match', () {
      expect(nameHasExactEpisode('Show S01E05 720p', 1, 5), isTrue);
      expect(nameHasExactEpisode('Show S1E5 720p', 1, 5), isTrue);
      expect(nameHasExactEpisode('Breaking Bad 1x05 HDTV', 1, 5), isTrue);
      expect(nameHasExactEpisode('Breaking Bad 1x5 HDTV', 1, 5), isTrue);
    });
    test('digit boundaries: no wrong-episode substring hits', () {
      expect(nameHasExactEpisode('Show S01E015 720p', 1, 1), isFalse);
      expect(nameHasExactEpisode('Show S1E10 720p', 1, 1), isFalse);
      expect(nameHasExactEpisode('Show 21x05 HDTV', 1, 5), isFalse);
      expect(nameHasExactEpisode('Show S01E05 720p', 1, 4), isFalse);
    });
  });

  // ── loadLadder / fromSavedDefaults — prefs parsing + kill switch ─────────
  group('loadLadder & fromSavedDefaults (mocked prefs)', () {
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    test('parses saved enum names, ignores unknown values', () async {
      SharedPreferences.setMockInitialValues({
        'default_filter_qualities_v1': jsonEncode(['fullHd', 'bogus']),
        'default_filter_rip_sources_v1': jsonEncode(['web', 'nonsense']),
        'default_filter_languages_v1': jsonEncode(['english']),
      });
      final ladder = await FilterLadder.fromSavedDefaults();
      expect(ladder.isActive, isTrue);
      expect(ladder.filters.qualities, {QualityTier.fullHd});
      expect(ladder.filters.ripSources, {RipSourceCategory.web});
      expect(ladder.filters.languages, {AudioLanguage.english});
      expect(ladder.tierCount, 4);
    });

    test('no saved filters → inactive ladder', () async {
      SharedPreferences.setMockInitialValues({});
      final ladder = await FilterLadder.fromSavedDefaults();
      expect(ladder.isActive, isFalse);
    });

    test('kill switch off → inactive ladder even with filters saved',
        () async {
      SharedPreferences.setMockInitialValues({
        'default_filter_qualities_v1': jsonEncode(['fullHd']),
        'quick_play_honors_filters_v1': false,
      });
      final ladder = await TorrentPlaybackService.loadLadder();
      expect(ladder.isActive, isFalse);
    });

    test('kill switch defaults ON', () async {
      SharedPreferences.setMockInitialValues({
        'default_filter_qualities_v1': jsonEncode(['fullHd']),
      });
      expect(await StorageService.getQuickPlayHonorsFilters(), isTrue);
      final ladder = await TorrentPlaybackService.loadLadder();
      expect(ladder.isActive, isTrue);
    });
  });

  // ── Corpus-level guarantees (the real-world numbers from the plan) ───────
  group('corpus-level distributions (1014 real names)', () {
    late List<String> corpus;
    setUpAll(() => corpus = loadCorpus());

    test('fixture is intact', () {
      expect(corpus.length, greaterThanOrEqualTo(900));
    });

    test('most names carry no language token — §3.3 premise', () {
      final untagged = corpus
          .where((n) => TorrentFilterMatcher.detectAudioLanguage(n) == null)
          .length;
      expect(untagged / corpus.length, greaterThan(0.8));
    });

    test('P1 preset finds a healthy tier-0 pool', () {
      final ladder = FilterLadder(p1);
      final tier0 =
          corpus.where((n) => ladder.tierOfName(n) == 0).length;
      // Measured 240/689 pre-fix on the movie corpus; the web fix and the
      // series names push it higher. Floor keeps the test robust to
      // future fixture additions.
      expect(tier0, greaterThanOrEqualTo(200));
    });

    test('every corpus name lands in SOME bucket (nothing is unplayable)',
        () {
      final ladder = FilterLadder(p1);
      for (final n in corpus) {
        final tier = ladder.tierOfName(n);
        expect(tier >= 0 && tier <= ladder.tierCount, isTrue,
            reason: 'out-of-range tier $tier for "$n"');
      }
    });

    test('ordering the full corpus never loses or duplicates candidates', () {
      final ladder = FilterLadder(p1);
      final list = [for (final n in corpus) t(n)];
      final ordered = ladder.order(list);
      expect(ordered.length, list.length);
      expect(ordered.toSet(), list.toSet());
      // Monotonic non-decreasing tiers.
      for (var i = 1; i < ordered.length; i++) {
        expect(
          ladder.tierOf(ordered[i]) >= ladder.tierOf(ordered[i - 1]),
          isTrue,
        );
      }
    });
  });
}
