// Origin pin for the source-alias warmup of
// lib/services/torrent_playback_service.dart (lane T3, PR #238).
//
// Written AFTER a first extraction attempt was already made, and placed BEFORE
// the move by history rewrite so the two-commit rule (pin, then move) reads
// correctly. Recording that here because the reviewer asked for it — the
// earlier source-search pin carries the same note.
//
// What this file EXECUTES on the origin (origin lines 1787-1848):
//
//   TorrentPlaybackService._cachedSourceAliases   static field
//   TorrentPlaybackService._sourceAliasWarmup     static field
//   TorrentPlaybackService._sourceAliases         private getter
//   PlaybackCandidateRanking.warmSourceAliases      public static
//
// plus the two call sites that READ the alias map, so the warmup is observed
// through its actual effect and not through a re-implementation:
//
//   orderCandidatesForRules             origin 1716 (SourcePriority.order)
//                                       origin 1735 (exactOrder ladder grouping)
//   orderCacheCheckedCandidatesForRules origin 1838 (delegates to the above)
//
// How the warmup is made observable — no production seam was added:
//
//  * A REAL alias source. warmSourceAliases delegates to
//    SourcePriority.engineAliases(), which lists TorrentService engines and
//    keeps the indexer-manager ones, mapping `display name` →
//    `engine:<engineId>`. Seeding one Jackett config into
//    'indexer_manager_configs_v1' (plaintext is accepted; SecretVault re-seals
//    on first read) therefore synthesizes a real DynamicEngine named
//    `indexer_manager_pin_hub_ix1` with display name `Pin Hub`. Candidate rows
//    stamped `source: 'Pin Hub'` — which is exactly what an indexer-manager
//    search stamps — can then only reach the priority key
//    `engine:indexer_manager_pin_hub_ix1` THROUGH the warmed alias map.
//    Unwarmed, keyForSource falls back to `engine:pin hub`, which the priority
//    list does not contain.
//
//  * A REAL fetch counter. Every alias fetch ends in
//    IndexerManagerConfigStore.getIndexerManagerConfigs, which debugPrints
//    'Error loading indexer manager config: ...' once per malformed entry in
//    the stored list. Each fixture therefore carries one deliberately
//    malformed entry (it is dropped and does not affect the alias map), and
//    this file counts those lines. One line == one underlying config read ==
//    one alias fetch. That is a genuine count of the work warmSourceAliases
//    does, not a proxy for it.
//
// STATE ISOLATION. _cachedSourceAliases and _sourceAliasWarmup are static and
// process-wide, and the origin exposes NO reset/debug seam for them (grep:
// they are read/written only inside the 1787-1848 block and the two ordering
// call sites). So the cold-start behaviour is proven ONCE, by the first test
// in this file, before anything warms; the later tests drive the cache back to
// a known map instead of resetting it. Do not reorder the tests.
//
// Behaviour pinned deliberately (keep it, do not "fix" it in the move):
//  * warmSourceAliases is SINGLE-FLIGHT but NOT memoized. While a warmup is in
//    flight, every caller gets the identical Future and exactly one fetch
//    runs. Once it completes, `whenComplete` clears the slot, so the NEXT call
//    is a different Future and DOES fetch again — that is what lets an indexer
//    manager added or renamed mid-session be picked up on the next play rather
//    than the next app restart.
//  * _cachedSourceAliases is nevertheless retained between warmups: ordering
//    reads it synchronously and never fetches, so a prefs change made after a
//    warmup is invisible to ordering until something warms again.
//  * The `.then` store is unconditional, so a refreshed fetch that finds no
//    indexer managers OVERWRITES a previously populated map with an empty one.
//  * The `.catchError` branch (`_cachedSourceAliases ??= const {}`) is
//    unreachable from here: SourcePriority.engineAliases swallows its own
//    failures inside a try/catch and returns {}, so the future never rejects.
//    Left unpinned on purpose rather than reached through a fake.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback/playback_candidate_ranking.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/filter_ladder.dart';

// ── fixtures ────────────────────────────────────────────────────────────────

/// One malformed entry rides along in every stored list. It is dropped by
/// IndexerManagerConfigStore and logs exactly one line per read — the fetch
/// counter this file uses.
const String _badEntry = '{ this is not json';

const String _countedLogPrefix = 'Error loading indexer manager config';

/// The stored value for an indexer manager whose display name is [name] and
/// whose row id is [id]. Its synthesized engine id is
/// `indexer_manager_<slug(name)>_<id>`.
Map<String, Object> _indexerPrefs({required String id, required String name}) =>
    {
      'indexer_manager_configs_v1': <String>[
        jsonEncode({
          'id': id,
          'name': name,
          'type': 'jackett',
          'base_url': 'https://jackett-pin.invalid',
          'api_key': 'pin-key',
          'enabled': true,
        }),
        _badEntry,
      ],
    };

var _hashSeed = 0;

String _hash(String tag) {
  _hashSeed++;
  final base = tag.codeUnits.fold<int>(17, (a, c) => (a * 31 + c) & 0xffffff);
  return (base.toRadixString(16) + _hashSeed.toRadixString(16))
      .padLeft(40, 'd')
      .substring(0, 40);
}

Torrent _row(String name, String source, {int seeders = 10}) => Torrent(
  rowid: 0,
  infohash: _hash('$source/$name'),
  name: name,
  sizeBytes: 1 << 30,
  createdUnix: 0,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
);

List<String> _names(List<Torrent> list) => [for (final t in list) t.name];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  final logged = <String>[];
  late DebugPrintCallback savedDebugPrint;

  int fetches() => logged.where((l) => l.startsWith(_countedLogPrefix)).length;

  void resetFetchCount() => logged.clear();

  /// Full profile/storage reset with [prefs] seeded, then the engine registry
  /// re-initialized from an empty on-disk engine directory. Deliberately does
  /// NOT touch the alias cache — the origin has no seam for that, and the test
  /// order below depends on it surviving.
  Future<void> boot([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues({...prefs});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    StremioService.instance.invalidateCache();
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
  }

  /// Replaces the stored indexer-manager list in place, the way Settings would
  /// mid-session — no profile/engine reset, so only a fresh alias fetch can
  /// notice it.
  Future<void> restoreIndexerConfig({
    required String id,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = _indexerPrefs(
      id: id,
      name: name,
    )['indexer_manager_configs_v1']!;
    await prefs.setStringList(
      'indexer_manager_configs_v1',
      (value as List).cast<String>(),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('playback-alias-pin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    savedDebugPrint = debugPrint;
    logged.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logged.add(message);
    };
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  /// Priority list naming the indexer manager by its ENGINE ID. A row stamped
  /// with the manager's display name can only match it through an alias.
  QuickPlayRules rulesFor(List<String> priority) =>
      QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        ranking: QuickPlayRanking.quality,
        useFilters: false,
        sourcePriority: priority,
      );

  const hubEngineKey = 'engine:indexer_manager_pin_hub_ix1';
  const renamedEngineKey = 'engine:indexer_manager_swapped_hub_ix2';

  // ────────────────────────────────────────────────────────────────────────
  // MUST STAY FIRST: the only genuinely cold observation in this process.
  test(
    'cold — an unwarmed alias map leaves the indexer row unlisted',
    () async {
      await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));

      final ordered =
          PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules([
            _row('Alpha 1080p', 'alpha'),
            _row('Hub 1080p', 'Pin Hub'),
          ], rules: rulesFor([hubEngineKey, 'engine:alpha']));

      // Without a warmup keyForSource('Pin Hub') is 'engine:pin hub', which the
      // priority list does not contain, so the hub row sorts as unlisted.
      expect(_names(ordered), ['Alpha 1080p', 'Hub 1080p']);
      // Ordering alone never fetches.
      expect(fetches(), 0);
    },
  );

  test('warming makes the same input order by the aliased engine id', () async {
    await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));

    resetFetchCount();
    await PlaybackCandidateRanking.warmSourceAliases();
    expect(fetches(), 1, reason: 'one warmup performs exactly one alias fetch');

    final ordered = PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules([
      _row('Alpha 1080p', 'alpha'),
      _row('Hub 1080p', 'Pin Hub'),
    ], rules: rulesFor([hubEngineKey, 'engine:alpha']));

    // Only the warmed alias 'pin hub' -> 'engine:indexer_manager_pin_hub_ix1'
    // can promote the display-name row above the plain engine row.
    expect(_names(ordered), ['Hub 1080p', 'Alpha 1080p']);
    // Ordering read the cache synchronously; it did not fetch.
    expect(fetches(), 1);
  });

  test('the warmed map also merges alias and engine-id rows into one exactOrder '
      'ladder group', () async {
    await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));
    await PlaybackCandidateRanking.warmSourceAliases();

    // Ladder active (a quality filter is set) + relaxFilters + exactOrder is
    // the branch that groups by keyForSource(source, aliases: _sourceAliases).
    final ladder = FilterLadder(
      TorrentFilterState(qualities: const {QualityTier.fullHd}),
    );
    final rules = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
      ranking: QuickPlayRanking.exactOrder,
      useFilters: true,
      relaxFilters: true,
      sourcePriority: const <String>[],
    );

    final ordered = PlaybackCandidateRanking.orderCandidatesForRules(
      [
        // display name, fails the 1080p tier
        _row('Hub 720p', 'Pin Hub'),
        // engine id, passes the 1080p tier
        _row('Hub 1080p', 'indexer_manager_pin_hub_ix1'),
      ],
      rules: rules,
      ladder: ladder,
    );

    // Warmed, both rows key to 'engine:indexer_manager_pin_hub_ix1', so they
    // form ONE group and the ladder promotes the 1080p row over the 720p one.
    // Unaliased they would be two groups and the incoming order would stand.
    expect(_names(ordered), ['Hub 1080p', 'Hub 720p']);
  });

  test('the cached map is retained between warmups and refreshed by the next '
      'one', () async {
    await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));
    await PlaybackCandidateRanking.warmSourceAliases();

    // Settings-style mid-session change: the manager is renamed, so its engine
    // id changes too. No profile/engine reset accompanies it.
    await restoreIndexerConfig(id: 'ix2', name: 'Swapped Hub');
    resetFetchCount();

    final candidates = [
      _row('Alpha 1080p', 'alpha'),
      _row('Hub 1080p', 'Swapped Hub'),
    ];
    final rules = rulesFor([renamedEngineKey, 'engine:alpha']);

    // Still the PREVIOUS map: ordering never re-reads, so 'Swapped Hub' is not
    // yet aliased and sorts unlisted.
    expect(
      _names(
        PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
        ),
      ),
      ['Alpha 1080p', 'Hub 1080p'],
    );
    expect(fetches(), 0, reason: 'the retained cache served the ordering');

    // The next warmup refetches (single-flight, not memoized) and the new
    // alias becomes visible.
    await PlaybackCandidateRanking.warmSourceAliases();
    expect(fetches(), 1);
    expect(
      _names(
        PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
        ),
      ),
      ['Hub 1080p', 'Alpha 1080p'],
    );
  });

  test('concurrent warmups share one in-flight future and one fetch', () async {
    await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));
    resetFetchCount();

    // Both calls happen before the first can complete: the config read behind
    // engineAliases awaits SharedPreferences and the SecretVault open, so the
    // window is real and no gate is needed to hold it open.
    final first = PlaybackCandidateRanking.warmSourceAliases();
    final second = PlaybackCandidateRanking.warmSourceAliases();
    expect(
      identical(first, second),
      isTrue,
      reason: 'the second caller joins the in-flight warmup',
    );

    await Future.wait([first, second]);
    expect(fetches(), 1, reason: 'two concurrent warmups cost one fetch');

    // Both awaited the same completion: the map is live for ordering.
    expect(
      _names(
        PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules([
          _row('Alpha 1080p', 'alpha'),
          _row('Hub 1080p', 'Pin Hub'),
        ], rules: rulesFor([hubEngineKey, 'engine:alpha'])),
      ),
      ['Hub 1080p', 'Alpha 1080p'],
    );

    // whenComplete cleared the slot, so this is a NEW future and it refetches.
    final third = PlaybackCandidateRanking.warmSourceAliases();
    expect(identical(third, first), isFalse);
    await third;
    expect(fetches(), 2, reason: 'the warmup is single-flight, not memoized');
  });

  test('a refreshed warmup that finds no indexer managers overwrites the '
      'populated map', () async {
    await boot(_indexerPrefs(id: 'ix1', name: 'Pin Hub'));
    await PlaybackCandidateRanking.warmSourceAliases();

    final candidates = [
      _row('Alpha 1080p', 'alpha'),
      _row('Hub 1080p', 'Pin Hub'),
    ];
    final rules = rulesFor([hubEngineKey, 'engine:alpha']);
    expect(
      _names(
        PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
        ),
      ),
      ['Hub 1080p', 'Alpha 1080p'],
    );

    // The user deletes the indexer manager. `.then` stores unconditionally, so
    // the empty result replaces the populated map rather than being ignored.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('indexer_manager_configs_v1', const <String>[]);
    await PlaybackCandidateRanking.warmSourceAliases();

    expect(
      _names(
        PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
        ),
      ),
      ['Alpha 1080p', 'Hub 1080p'],
    );
  });
}
