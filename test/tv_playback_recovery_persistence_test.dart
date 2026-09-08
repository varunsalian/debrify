import 'dart:convert';

import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tv_playback_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    ProfilePreferenceBudget.debugReset();
    PlaybackRecoveryIntent.debugReset();
    PlaybackRecoveryIntent.debugSupportedOverride = true;
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });
  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    PlaybackRecoveryIntent.debugReset();
    ProfilePreferenceBudget.debugReset();
    IptvMediaStore.debugResetMigration();
    ProfileRuntime.debugReset();
  });

  for (final sameProcessReturn in [false, true]) {
    for (final position in [95000, 99000, 100000]) {
      test(
        'tracker movie at $position recovers both bookmarks (return: $sameProcessReturn)',
        () async {
          final timestamp = DateTime.now().millisecondsSinceEpoch - 1000;
          await StorageService.saveVideoPlaybackState(
            videoTitle: 'episode-4',
            videoUrl: 'https://example.invalid/video',
            positionMs: 5000,
            durationMs: 100000,
            imdbId: 'tt1234',
            recoveryUpdatedAtMs: timestamp - 1000,
          );
          await StorageService.upsertVideoResume('episode-4', {
            'positionMs': 5000,
            'durationMs': 100000,
            'updatedAt': timestamp - 1000,
          });
          final checkpoint = TvPlaybackCheckpoint.tryParse(
            jsonEncode(
              record(type: 'single', completed: position == 100000)
                ..['localCompletionTracking'] = false
                ..['positionMs'] = position
                ..['updatedAtMs'] = timestamp,
            ),
          )!;
          expect(checkpoint.shouldPersistCompletion, isFalse);
          expect(
            await TvPlaybackRecovery.applyCheckpoint(
              checkpoint,
              sameProcessReturn: sameProcessReturn,
            ),
            isTrue,
          );
          final video = await StorageService.getVideoPlaybackState(
            videoTitle: 'episode-4',
            includeFinished: true,
          );
          final resume = await StorageService.getVideoResume('episode-4');
          expect(video?['positionMs'], position);
          expect(video?['updatedAt'], timestamp);
          expect(resume?['positionMs'], position);
          expect(resume?['updatedAt'], timestamp);
          expect(await StorageService.isMovieFinished('tt1234'), isFalse);
        },
      );
    }
  }

  for (final imdbId in [null, 'null', '']) {
    test(
      'unidentified movie $imdbId recovers progress without a null watched ID',
      () async {
        final checkpoint = TvPlaybackCheckpoint.tryParse(
          jsonEncode(
            record(type: 'single', completed: true)
              ..['imdbId'] = imdbId
              ..['seriesTitle'] = imdbId
              ..['positionMs'] = 99000,
          ),
        )!;
        expect(checkpoint.imdbId, isNull);
        expect(checkpoint.seriesTitle, isNull);
        expect(checkpoint.shouldPersistCompletion, isFalse);
        expect(
          await TvPlaybackRecovery.applyCheckpoint(
            checkpoint,
            sameProcessReturn: true,
          ),
          isTrue,
        );
        expect(await StorageService.isMovieFinished('null'), isFalse);
        expect(
          (await StorageService.getVideoPlaybackState(
            videoTitle: 'episode-4',
            includeFinished: true,
          ))?['positionMs'],
          99000,
        );
        expect(
          (await StorageService.getVideoResume('episode-4'))?['positionMs'],
          99000,
        );
      },
    );
  }

  test(
    'retry should finish a checkpoint after its first store was written',
    () async {
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      await db.execute(
        "CREATE TRIGGER fail_resume BEFORE INSERT ON video_resume BEGIN SELECT RAISE(ABORT, 'temporary write failure'); END",
      );
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record(type: 'single')),
      )!;
      await expectLater(
        TvPlaybackRecovery.applyCheckpoint(checkpoint, sameProcessReturn: true),
        throwsA(anything),
      );
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'episode-4'),
        isNotNull,
      );
      await db.execute('DROP TRIGGER fail_resume');
      final encoded = jsonEncode(
        record(type: 'single')..['updatedAtMs'] = checkpoint.updatedAtMs,
      );
      var acknowledged = false;
      await TvPlaybackRecovery.recoverJournal(
        encoded,
        scope: owner,
        apply: (cp, returning) => TvPlaybackRecovery.applyCheckpoint(
          cp,
          sameProcessReturn: returning,
        ),
        acknowledge: (_) async {
          acknowledged = true;
        },
        discard: (_) async => fail('invalid'),
      );
      expect(acknowledged, isTrue);
      expect(
        await StorageService.getVideoResume('episode-4'),
        isNotNull,
        reason:
            'ACK must follow both stores, not discard the retry because of its own first write',
      );
    },
  );

  test(
    'later series playback must not discard a pending watched marker',
    () async {
      final first = record(completed: true, session: 6)
        ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 2000;
      final latest = record(session: 7);
      final acked = <int>[];
      await TvPlaybackRecovery.recoverJournal(
        jsonEncode({
          'version': 2,
          'completions': [first],
          'latest': [latest],
        }),
        scope: owner,
        returningSessionId: 7,
        apply: (cp, returning) => TvPlaybackRecovery.applyCheckpoint(
          cp,
          sameProcessReturn: returning,
        ),
        acknowledge: (cp) async {
          acked.add(cp.sessionId);
        },
        discard: (_) async => fail('invalid'),
      );
      expect(acked, [6, 7]);
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Example Show',
          season: 2,
          episode: 4,
        ),
        isTrue,
        reason:
            'Opening a series episode does not unwatch it in the normal progress path',
      );
      final canonical = await StorageService.getLastPlayedEpisodeByImdbId(
        'tt1234',
      );
      expect(canonical?['episode'], 4);
      expect(canonical?['positionMs'], latest['positionMs']);
      expect(canonical?['durationMs'], latest['durationMs']);
      expect(canonical?['updatedAt'], latest['updatedAtMs']);
      expect(canonical?['finished'], isTrue);
    },
  );

  for (final type in ['series', 'collection']) {
    for (final existingProgress in [false, true]) {
      test(
        '$type binge selects the partial next item (existing progress: $existingProgress)',
        () async {
          final time = DateTime.now().millisecondsSinceEpoch - 10000;
          final season = type == 'collection' ? 0 : 2;
          Map<String, Object?> episode(int number, bool completed) =>
              record(type: type, completed: completed)
                ..['sequence'] = number
                ..['episode'] = number
                ..['itemIndex'] = number - 1
                ..['resumeId'] = 'episode-$number'
                ..['updatedAtMs'] = time + number;
          if (existingProgress) {
            for (final number in [4, 5]) {
              await StorageService.saveSeriesPlaybackState(
                seriesTitle: 'Example Show',
                season: season,
                episode: number,
                positionMs: 1000,
                durationMs: 100000,
                imdbId: 'tt1234',
                recoveryUpdatedAtMs: time - 1000,
              );
            }
          }
          final acked = <int>[];
          await TvPlaybackRecovery.recoverJournal(
            jsonEncode({
              'version': 2,
              'completions': [episode(4, true), episode(5, true)],
              'latest': [episode(6, false)],
            }),
            scope: owner,
            returningSessionId: 7,
            apply: (cp, returning) => TvPlaybackRecovery.applyCheckpoint(
              cp,
              sameProcessReturn: returning,
            ),
            acknowledge: (cp) async {
              acked.add(cp.sequence);
            },
            discard: (_) async => fail('valid journal discarded'),
          );
          expect(acked, [4, 5, 6]);
          final latest = await StorageService.getLastPlayedEpisodeByImdbId(
            'tt1234',
          );
          expect(latest?['season'], season);
          expect(latest?['episode'], 6);
          expect(latest?['positionMs'], 5000);
          expect(latest?['durationMs'], 100000);
          expect(latest?['updatedAt'], time + 6);
          expect(latest?['finished'], isNot(true));
          final map =
              jsonDecode(
                    (await SharedPreferences.getInstance()).getString(
                      'playback_state_v1',
                    )!,
                  )
                  as Map;
          final show = map['series_example_show'] as Map;
          for (final number in [4, 5]) {
            expect(
              show['seasons']['$season']['$number']['updatedAt'],
              time + number,
            );
            expect(
              show['finishedEpisodes']['$season']['$number']['finishedAt'],
              time + number,
            );
          }
        },
      );
    }
  }

  test(
    'an admitted rewatch retry repairs the canonical bookmark without unwatching',
    () async {
      final time = DateTime.now().millisecondsSinceEpoch - 10000;
      final completed = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record(completed: true, session: 6)..['updatedAtMs'] = time),
      )!;
      await TvPlaybackRecovery.applyCheckpoint(
        completed,
        sameProcessReturn: false,
      );
      final rewatch = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record()..['updatedAtMs'] = time + 1000),
      )!;
      // Only the source-specific write finished before the host died.
      await StorageService.saveVideoPlaybackState(
        videoTitle: 'episode-4',
        videoUrl: 'https://example.invalid/video',
        positionMs: rewatch.positionMs,
        durationMs: rewatch.durationMs,
        imdbId: 'tt1234',
        recoveryCheckpointId: rewatch.recoveryId,
        recoveryUpdatedAtMs: rewatch.updatedAtMs,
      );
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          rewatch,
          sameProcessReturn: false,
        ),
        isTrue,
      );
      final canonical = await StorageService.getLastPlayedEpisodeByImdbId(
        'tt1234',
      );
      expect(canonical?['positionMs'], rewatch.positionMs);
      expect(canonical?['updatedAt'], rewatch.updatedAtMs);
      expect(canonical?['finished'], isTrue);
    },
  );

  test('a newer episode bookmark is not an explicit unwatch', () async {
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(record(completed: true)),
    )!;
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Example Show',
      season: 2,
      episode: 4,
      positionMs: 100,
      durationMs: 100000,
      imdbId: 'tt1234',
    );
    final before = await StorageService.getSeriesPlaybackState(
      seriesTitle: 'Example Show',
      season: 2,
      episode: 4,
    );
    expect(
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: false,
      ),
      isTrue,
    );
    expect(
      await StorageService.isEpisodeFinished(
        seriesTitle: 'Example Show',
        season: 2,
        episode: 4,
      ),
      isTrue,
    );
    expect(
      await StorageService.getSeriesPlaybackState(
        seriesTitle: 'Example Show',
        season: 2,
        episode: 4,
      ),
      before,
      reason:
          'An older completion must not overwrite the later rewatch bookmark',
    );
  });

  for (final provenReturn in [false, true]) {
    test(
      'an existing completed bookmark needs return proof for a rewatch (proof: $provenReturn)',
      () async {
        final time = DateTime.now().millisecondsSinceEpoch - 10000;
        await StorageService.saveSeriesPlaybackState(
          seriesTitle: 'Example Show',
          season: 2,
          episode: 4,
          positionMs: 1000,
          durationMs: 100000,
          imdbId: 'tt1234',
          recoveryUpdatedAtMs: time - 1000,
        );
        final completed = TvPlaybackCheckpoint.tryParse(
          jsonEncode(record(completed: true)..['updatedAtMs'] = time),
        )!;
        await TvPlaybackRecovery.applyCheckpoint(
          completed,
          sameProcessReturn: false,
        );
        final rewatch = TvPlaybackCheckpoint.tryParse(
          jsonEncode(record()..['updatedAtMs'] = time + 1000),
        )!;
        await TvPlaybackRecovery.applyCheckpoint(
          rewatch,
          sameProcessReturn: provenReturn,
        );
        final canonical = await StorageService.getLastPlayedEpisodeByImdbId(
          'tt1234',
        );
        expect(canonical?['positionMs'], provenReturn ? 5000 : 100000);
        expect(canonical?['updatedAt'], provenReturn ? time + 1000 : time);
        expect(canonical?['finished'], isTrue);
        // A retained/duplicate completion cannot clobber the restored rewatch.
        await TvPlaybackRecovery.applyCheckpoint(
          completed,
          sameProcessReturn: false,
        );
        expect(
          await StorageService.getLastPlayedEpisodeByImdbId('tt1234'),
          canonical,
        );
      },
    );
  }

  test('a movie rewatch retries both stores before unmarking watched', () async {
    await StorageService.markMovieAsFinished('tt1234');
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(record(type: 'single')),
    )!;
    final db = DebrifyTvDatabase.debugDatabaseOverride!;
    await db.execute(
      "CREATE TRIGGER fail_resume BEFORE INSERT ON video_resume BEGIN SELECT RAISE(ABORT, 'temporary write failure'); END",
    );
    await expectLater(
      TvPlaybackRecovery.applyCheckpoint(checkpoint, sameProcessReturn: true),
      throwsA(anything),
    );
    expect(await StorageService.isMovieFinished('tt1234'), isTrue);
    await db.execute('DROP TRIGGER fail_resume');
    expect(
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: false,
      ),
      isTrue,
    );
    expect(await StorageService.isMovieFinished('tt1234'), isFalse);
    expect(
      (await StorageService.getVideoResume('episode-4'))?['positionMs'],
      5000,
    );
    expect(
      (await StorageService.getVideoPlaybackState(
        videoTitle: 'episode-4',
      ))?['positionMs'],
      5000,
    );
  });

  test(
    'movie completion retries a failed database delete before cleanup',
    () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record(type: 'single', completed: true)),
      )!;
      await StorageService.saveVideoPlaybackState(
        videoTitle: 'episode-4',
        videoUrl: 'https://example.invalid/video',
        positionMs: 1000,
        durationMs: 100000,
        imdbId: 'tt1234',
        recoveryUpdatedAtMs: checkpoint.updatedAtMs - 1000,
      );
      await StorageService.upsertVideoResume('episode-4', {
        'positionMs': 1000,
        'durationMs': 100000,
        'updatedAt': checkpoint.updatedAtMs - 1000,
      });
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      await db.execute(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON video_resume BEGIN SELECT RAISE(ABORT, 'temporary delete failure'); END",
      );
      await expectLater(
        TvPlaybackRecovery.applyCheckpoint(checkpoint, sameProcessReturn: true),
        throwsA(anything),
      );
      expect(await StorageService.isMovieFinished('tt1234'), isFalse);
      await db.execute('DROP TRIGGER fail_delete');
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: false,
        ),
        isTrue,
      );
      expect(await StorageService.isMovieFinished('tt1234'), isTrue);
      expect(await StorageService.getVideoResume('episode-4'), isNull);
    },
  );

  for (final action in ['rewind', 'unwatch', 'clear']) {
    test('a newer $action fences an interrupted checkpoint retry', () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record(type: 'single')),
      )!;
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      await db.execute(
        "CREATE TRIGGER fail_resume BEFORE INSERT ON video_resume BEGIN SELECT RAISE(ABORT, 'temporary write failure'); END",
      );
      await expectLater(
        TvPlaybackRecovery.applyCheckpoint(checkpoint, sameProcessReturn: true),
        throwsA(anything),
      );
      await db.execute('DROP TRIGGER fail_resume');
      switch (action) {
        case 'rewind':
          await StorageService.saveVideoPlaybackState(
            videoTitle: 'episode-4',
            videoUrl: 'https://example.invalid/video',
            positionMs: 100,
            durationMs: 100000,
            imdbId: 'tt1234',
          );
        case 'unwatch':
          await StorageService.markMovieAsFinished('tt1234');
          await StorageService.unmarkMovieAsFinished('tt1234');
        case 'clear':
          await StorageService.clearAllPlaybackData();
      }
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: false,
        ),
        isFalse,
      );
      expect(await StorageService.getVideoResume('episode-4'), isNull);
      expect(
        (await StorageService.getVideoPlaybackState(
          videoTitle: 'episode-4',
        ))?['positionMs'],
        action == 'rewind' ? 100 : isNull,
      );
    });
  }

  test('a later collection rewatch retains the earlier completion', () async {
    final first = record(type: 'collection', completed: true, session: 6)
      ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 2000;
    await TvPlaybackRecovery.recoverJournal(
      jsonEncode({
        'version': 2,
        'completions': [first],
        'latest': [record(type: 'collection')],
      }),
      scope: owner,
      returningSessionId: 7,
      apply: (cp, returning) =>
          TvPlaybackRecovery.applyCheckpoint(cp, sameProcessReturn: returning),
      acknowledge: (_) async {},
      discard: (_) async => fail('invalid'),
    );
    expect(
      await StorageService.isEpisodeFinished(
        seriesTitle: 'Example Show',
        season: 0,
        episode: 4,
      ),
      isTrue,
    );
  });

  test(
    'tvOS must be able to clear playback when its preference budget is full',
    () async {
      final playback = jsonEncode({
        'series_example_show': {
          'type': 'series',
          'title': 'Example Show',
          'imdbId': 'tt1234',
          'seasons': {
            '1': {
              for (var episode = 1; episode <= 200; episode++)
                '$episode': {'positionMs': 10, 'durationMs': 100},
            },
          },
        },
      });
      final base =
          ProfilePreferenceBudget.entryFootprint(
            'playback_state_v1',
            playback,
          ) +
          ProfilePreferenceBudget.entryFootprint('padding', '');
      SharedPreferences.setMockInitialValues({
        'playback_state_v1': playback,
        'padding': 'x' * (ProfilePreferenceBudget.limitBytes - base - 10),
      });
      ProfilePreferenceBudget.debugEnforcedOverride = true;
      PlaybackRecoveryIntent.debugSupportedOverride = false;
      await StorageService.clearPlaylistProgress(title: 'Example Show');
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'remote_tv_playback_recovery_deletions_v1',
        ),
        isFalse,
      );
      expect(
        await StorageService.getSeriesPlaybackState(
          seriesTitle: 'Example Show',
          season: 1,
          episode: 1,
        ),
        isNull,
      );
    },
  );

  test(
    'bulk clear must prevent a retained movie completion from resurrecting',
    () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(record(type: 'single', completed: true)),
      )!;
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: true,
      );
      expect(await StorageService.isMovieFinished('tt1234'), isTrue);
      // Native ACK failed, then the user chose Settings > Clear playback data.
      await StorageService.clearAllPlaybackData();
      expect(await StorageService.isMovieFinished('tt1234'), isFalse);
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: false,
      );
      expect(await StorageService.isMovieFinished('tt1234'), isFalse);
    },
  );

  test('bulk clear fences absent items but permits later playback', () async {
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(record(completed: true)),
    )!;
    await StorageService.clearAllPlaybackData(recordSyncDeletions: false);
    expect(
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: false,
      ),
      isFalse,
    );
    final later = TvPlaybackCheckpoint.tryParse(
      jsonEncode(
        record(completed: true)
          ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch + 1,
      ),
    )!;
    expect(
      await TvPlaybackRecovery.applyCheckpoint(later, sameProcessReturn: true),
      isTrue,
    );
  });
}

final owner = ProfileScope(
  profileId: 'adult',
  dataGeneration: 3,
  sessionEpoch: 1,
);
Map<String, Object?> record({
  String type = 'series',
  bool completed = false,
  int session = 7,
}) => {
  'version': 1,
  'sessionId': session,
  'sequence': 50,
  'profileId': 'adult',
  'dataGeneration': 3,
  'updatedAtMs': DateTime.now().millisecondsSinceEpoch - 1000,
  'contentType': type,
  'title': 'Example Show',
  'seriesTitle': 'Example Show',
  'imdbId': 'tt1234',
  'resumeId': 'episode-4',
  'url': 'https://example.invalid/video',
  'season': 2,
  'episode': 4,
  'itemIndex': 3,
  'positionMs': completed ? 100000 : 5000,
  'durationMs': 100000,
  'speed': 1.0,
  'aspect': 'contain',
  'completed': completed,
  'localCompletionTracking': true,
  'completionThreshold': 80,
};
