import 'dart:convert';

import 'package:debrify/services/playback_recovery_intent.dart';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/tv_playback_recovery.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlaybackRecoveryIntent.debugReset();
    PlaybackRecoveryIntent.debugSupportedOverride = true;
  });
  final scope = ProfileScope(
    profileId: 'adult',
    dataGeneration: 3,
    sessionEpoch: 1,
  );

  tearDown(() {
    TvPlaybackRecovery.debugReset();
    PlaybackRecoveryIntent.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('debrify/tv_playback_recovery'),
          null,
        );
  });

  test(
    'recovery channel failure never prevents allocating a player session',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('debrify/tv_playback_recovery');
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'io_error',
          message: 'journal unavailable',
        );
      });
      final first = await TvPlaybackRecovery.allocateSessionId();
      final second = await TvPlaybackRecovery.allocateSessionId();
      expect(first, inInclusiveRange(1, 0x7fffffff));
      expect(second, inInclusiveRange(1, 0x7fffffff));
      expect(first, isNot(second));
      messenger.setMockMethodCallHandler(channel, (_) async => 37);
      expect(await TvPlaybackRecovery.allocateSessionId(), 37);
    },
  );

  test('invalid native session IDs use the bounded fallback', () async {
    for (final value in [null, 0, -1, 0x80000000]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('debrify/tv_playback_recovery'),
            (_) async => value,
          );
      expect(
        await TvPlaybackRecovery.allocateSessionId(),
        inInclusiveRange(1, 0x7fffffff),
      );
    }
  });

  test('profile continuation is exact-scope and one-shot', () {
    TvPlaybackRecovery.debugSetGateBypass(scope);
    final wrongGeneration = ProfileScope(
      profileId: 'adult',
      dataGeneration: 4,
      sessionEpoch: 1,
    );

    expect(TvPlaybackRecovery.consumeGateBypass(wrongGeneration), isFalse);
    expect(TvPlaybackRecovery.consumeGateBypass(scope), isTrue);
    expect(TvPlaybackRecovery.consumeGateBypass(scope), isFalse);
  });

  test('accepts an owned partial episode checkpoint', () {
    final checkpoint = TvPlaybackCheckpoint.tryParse(jsonEncode(_checkpoint()));

    expect(checkpoint, isNotNull);
    expect(checkpoint!.belongsTo(scope), isTrue);
    expect(checkpoint.isResumable, isTrue);
    expect(checkpoint.seriesTitle, 'The Example Show');
    expect(checkpoint.season, 2);
    expect(checkpoint.episode, 4);
  });

  test('profile and generation both fence recovery writes', () {
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint()),
    )!;

    expect(
      checkpoint.belongsTo(
        ProfileScope(profileId: 'kids', dataGeneration: 3, sessionEpoch: 1),
      ),
      isFalse,
    );
    expect(
      checkpoint.belongsTo(
        ProfileScope(profileId: 'adult', dataGeneration: 4, sessionEpoch: 1),
      ),
      isFalse,
    );
  });

  test(
    'cold recovery only deepens but same-process return is authoritative',
    () {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(_checkpoint()),
      )!;

      expect(checkpoint.shouldApply(null, sameProcessReturn: false), isFalse);
      expect(checkpoint.shouldApply(null, sameProcessReturn: true), isTrue);
      expect(
        checkpoint.shouldApply({
          'positionMs': 1_700_000,
        }, sameProcessReturn: false),
        isTrue,
      );
      // A proven return must preserve an intentional rewind rather than leave
      // the older, deeper bookmark behind.
      expect(
        checkpoint.shouldApply({
          'positionMs': 2_100_000,
        }, sameProcessReturn: true),
        isTrue,
      );
    },
  );

  test('completion territory is never resurrected as Continue Watching', () {
    final completed = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(completed: true)),
    )!;
    final nearEnd = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(positionMs: 2_980_000)),
    )!;
    final crossedLocalThreshold = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(localCompletionEligible: true)),
    )!;
    final crossedThenRewound = TvPlaybackCheckpoint.tryParse(
      jsonEncode(
        _checkpoint(positionMs: 1_500_000, localCompletionReached: true),
      ),
    )!;
    final completedThenFinalTick = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(completed: false, completionReached: true)),
    )!;

    expect(completed.isResumable, isFalse);
    expect(nearEnd.isResumable, isFalse);
    expect(crossedLocalThreshold.isResumable, isFalse);
    expect(crossedThenRewound.shouldPersistCompletion, isTrue);
    expect(crossedThenRewound.isResumable, isFalse);
    expect(completedThenFinalTick.shouldPersistCompletion, isTrue);
  });

  test('only a partial locally tracked movie is a rewatch candidate', () {
    final rewatch = TvPlaybackCheckpoint.tryParse(
      jsonEncode(
        _checkpoint(
          contentType: 'single',
          positionMs: 1_500_000,
          localCompletionTracking: true,
          completionThreshold: 80,
        ),
      ),
    )!;
    final trackerManaged = TvPlaybackCheckpoint.tryParse(
      jsonEncode(
        _checkpoint(
          contentType: 'single',
          positionMs: 1_500_000,
          localCompletionTracking: false,
        ),
      ),
    )!;

    expect(rewatch.isLocalMovieRewatch, isTrue);
    expect(rewatch.shouldPersistCompletion, isFalse);
    expect(trackerManaged.isLocalMovieRewatch, isFalse);
  });

  test(
    'return completes an interrupted persistence after its position write',
    () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(
          _checkpoint(completed: true)
            ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 1000,
        ),
      )!;
      // The old host saved progress, then died before saving the watched marker.
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'The Example Show',
        season: 2,
        episode: 4,
        positionMs: checkpoint.durationMs,
        durationMs: checkpoint.durationMs,
      );
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: true,
        ),
        isTrue,
      );
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 4,
        ),
        isTrue,
      );
    },
  );

  test(
    'retained sessions recover only the newest observation of an item',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'playback_state_v1': jsonEncode({
          'series_the_example_show': {
            'type': 'series',
            'title': 'The Example Show',
            'seasons': {
              '2': {
                '4': {
                  'positionMs': 100,
                  'durationMs': 3122536,
                  'updatedAt': now - 2000,
                },
              },
            },
          },
        }),
      });
      final acked = <int>[];
      await TvPlaybackRecovery.recoverJournal(
        jsonEncode({
          'version': 2,
          'completions': [],
          'latest': [
            _checkpoint(positionMs: 1000)
              ..['sessionId'] = 6
              ..['sequence'] = 900
              ..['updatedAtMs'] = now - 1000,
            _checkpoint(positionMs: 2000)
              ..['sessionId'] = 7
              ..['sequence'] = 1
              ..['updatedAtMs'] = now - 1000,
          ],
        }),
        scope: scope,
        apply: (checkpoint, returning) => TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: returning,
        ),
        acknowledge: (checkpoint) async {
          acked.add(checkpoint.sessionId);
        },
        discard: (_) async => fail('valid journal discarded'),
      );
      expect(acked, [6, 7]);
      expect(
        (await StorageService.getSeriesPlaybackState(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 4,
        ))?['positionMs'],
        2000,
      );
    },
  );

  test('old completion cannot override a later session rewatch', () async {
    final applied = <int>[];
    await TvPlaybackRecovery.recoverJournal(
      jsonEncode({
        'version': 2,
        'completions': [
          _checkpoint(contentType: 'single', completed: true)
            ..['sessionId'] = 6,
        ],
        'latest': [_checkpoint(contentType: 'single')],
      }),
      scope: scope,
      returningSessionId: 7,
      apply: (checkpoint, returning) async {
        expect(checkpoint.shouldPersistCompletion, isFalse);
        expect(returning, isTrue);
        applied.add(checkpoint.sessionId);
        return true;
      },
      acknowledge: (_) async {},
      discard: (_) async => fail('valid journal discarded'),
    );
    expect(applied, [7]);
  });

  test('malformed or unsupported checkpoints fail closed', () {
    expect(TvPlaybackCheckpoint.tryParse('{broken'), isNull);
    expect(
      TvPlaybackCheckpoint.tryParse(
        jsonEncode(_checkpoint()..['contentType'] = 'iptv-live'),
      ),
      isNull,
    );
    expect(
      TvPlaybackCheckpoint.tryParse(
        jsonEncode(_checkpoint()..remove('profileId')),
      ),
      isNull,
    );
  });

  test(
    'binge journal applies all completions then the returning episode',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch - 1000;
      Map<String, Object?> episode(int number, int sequence, bool completed) =>
          _checkpoint(completed: completed)
            ..['episode'] = number
            ..['sequence'] = sequence
            ..['itemIndex'] = number - 1
            ..['resumeId'] = 'episode-$number'
            ..['updatedAtMs'] = now + sequence;
      final acked = <int>[];
      await TvPlaybackRecovery.recoverJournal(
        jsonEncode({
          'version': 2,
          'completions': [episode(4, 1, true), episode(5, 2, true)],
          'latest': [episode(6, 3, false)],
        }),
        scope: scope,
        returningSessionId: 7,
        apply: (checkpoint, returning) => TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: returning,
        ),
        acknowledge: (checkpoint) async {
          acked.add(checkpoint.sequence);
        },
        discard: (_) async => fail('valid journal discarded'),
      );
      expect(acked, [1, 2, 3]);
      expect(
        await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'The Example Show',
          imdbId: 'tt1234567',
        ),
        {
          '2': {4, 5},
        },
      );
      expect(
        (await StorageService.getSeriesPlaybackState(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 6,
        ))?['positionMs'],
        2_084_494,
      );
    },
  );

  test(
    'ACK failure cannot replay a completion after the user unwatches it',
    () async {
      final encoded = jsonEncode(
        _checkpoint(completed: true)
          ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 1000,
      );
      Future<void> recover({required bool ackFails}) =>
          TvPlaybackRecovery.recoverJournal(
            encoded,
            scope: scope,
            apply: (checkpoint, returning) =>
                TvPlaybackRecovery.applyCheckpoint(
                  checkpoint,
                  sameProcessReturn: returning,
                ),
            acknowledge: (_) async {
              if (ackFails) throw StateError('channel detached');
            },
            discard: (_) async => fail('valid checkpoint discarded'),
          );
      await expectLater(recover(ackFails: true), throwsStateError);
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 4,
        ),
        isTrue,
      );
      await StorageService.unmarkEpisodeAsFinished(
        seriesTitle: 'The Example Show',
        season: 2,
        episode: 4,
        imdbId: 'tt1234567',
      );
      await recover(ackFails: false);
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 4,
        ),
        isFalse,
      );
      expect(
        await StorageService.getSeriesPlaybackState(
          seriesTitle: 'The Example Show',
          season: 2,
          episode: 4,
        ),
        isNull,
      );
    },
  );

  test(
    'newer unwatch under a different title alias also fences completion',
    () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(
          _checkpoint(completed: true)
            ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 1000,
        ),
      )!;
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Localized title',
        season: 2,
        episode: 4,
        imdbId: 'tt1234567',
      );
      await StorageService.unmarkEpisodeAsFinished(
        seriesTitle: 'Localized title',
        season: 2,
        episode: 4,
        imdbId: 'tt1234567',
      );
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: false,
        ),
        isFalse,
      );
      expect(
        await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'The Example Show',
          imdbId: 'tt1234567',
        ),
        isEmpty,
      );
    },
  );

  test('newer rewind wins over cold recovery', () async {
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(
        _checkpoint()
          ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 1000,
      ),
    )!;
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'The Example Show',
      season: 2,
      episode: 4,
      positionMs: 1000,
      durationMs: checkpoint.durationMs,
    );
    expect(
      await TvPlaybackRecovery.applyCheckpoint(
        checkpoint,
        sameProcessReturn: false,
      ),
      isFalse,
    );
    expect(
      (await StorageService.getSeriesPlaybackState(
        seriesTitle: 'The Example Show',
        season: 2,
        episode: 4,
      ))?['positionMs'],
      1000,
    );
  });

  test(
    'movie unwatch prevents old completion from marking watched again',
    () async {
      final checkpoint = TvPlaybackCheckpoint.tryParse(
        jsonEncode(
          _checkpoint(contentType: 'single', completed: true)
            ..['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch - 1000,
        ),
      )!;
      await StorageService.markMovieAsFinished('tt1234567');
      await StorageService.unmarkMovieAsFinished('tt1234567');
      expect(
        await TvPlaybackRecovery.applyCheckpoint(
          checkpoint,
          sameProcessReturn: false,
        ),
        isFalse,
      );
      expect(await StorageService.isMovieFinished('tt1234567'), isFalse);
    },
  );

  test(
    'a later item failure ACKs only the already applied completion',
    () async {
      final acked = <int>[];
      await expectLater(
        TvPlaybackRecovery.recoverJournal(
          jsonEncode({
            'version': 2,
            'completions': [_checkpoint(completed: true)..['sequence'] = 1],
            'latest': [
              _checkpoint()
                ..['sequence'] = 2
                ..['episode'] = 5,
            ],
          }),
          scope: scope,
          apply: (checkpoint, _) async {
            if (checkpoint.sequence == 2) {
              throw StateError('transient database error');
            }
            return true;
          },
          acknowledge: (checkpoint) async {
            acked.add(checkpoint.sequence);
          },
          discard: (_) async => fail('valid journal discarded'),
        ),
        throwsStateError,
      );
      expect(acked, [1]);
    },
  );

  test(
    'return proof applies only to its session and other profiles remain pending',
    () async {
      final proof = <int, bool>{};
      final acked = <int>[];
      await TvPlaybackRecovery.recoverJournal(
        jsonEncode({
          'version': 2,
          'completions': [],
          'latest': [
            _checkpoint()
              ..['sessionId'] = 6
              ..['episode'] = 3,
            _checkpoint(),
            _checkpoint()
              ..['sessionId'] = 8
              ..['profileId'] = 'kids',
            _checkpoint()
              ..['sessionId'] = 9
              ..['dataGeneration'] = 2,
          ],
        }),
        scope: scope,
        returningSessionId: 7,
        apply: (checkpoint, returning) async {
          proof[checkpoint.sessionId] = returning;
          return true;
        },
        acknowledge: (checkpoint) async {
          acked.add(checkpoint.sessionId);
        },
        discard: (_) async => fail('valid journal discarded'),
      );
      expect(proof, {6: false, 7: true});
      expect(acked, [6, 7, 9]);
    },
  );

  test(
    'a bad journal entry does not discard valid completions or other profiles',
    () async {
      final acked = <int>[];
      final applied = <int>[];
      final encoded = jsonEncode({
        'version': 2,
        'completions': [
          _checkpoint(completed: true)..['sequence'] = 1,
          {'sequence': 'invalid'},
          _checkpoint(completed: true)..['profileId'] = 'kids',
        ],
        'latest': [
          _checkpoint()
            ..['sequence'] = 2
            ..['episode'] = 5,
          42,
        ],
      });
      await TvPlaybackRecovery.recoverJournal(
        encoded,
        scope: scope,
        apply: (checkpoint, _) async {
          applied.add(checkpoint.sequence);
          return true;
        },
        acknowledge: (checkpoint) async {
          acked.add(checkpoint.sequence);
        },
        discard: (_) async => fail('valid records discarded'),
      );
      expect(applied, [1, 2]);
      expect(acked, [1, 2]);
      expect(
        TvPlaybackJournal.tryParse(
          jsonEncode({
            'version': 2,
            'completions': [42],
            'latest': [],
          }),
        ),
        isNull,
      );
    },
  );

  test(
    'malformed recovery is discarded and intent history is device-local',
    () async {
      var discarded = false;
      await TvPlaybackRecovery.recoverJournal(
        '{broken',
        scope: scope,
        apply: (_, _) async => fail('malformed data applied'),
        acknowledge: (_) async => fail('malformed data ACKed'),
        discard: (value) async {
          expect(value, '{broken');
          discarded = true;
        },
      );
      expect(discarded, isTrue);
      expect(
        ProfilePreferencePortability.allowsKey(
          'remote_tv_playback_recovery_deletions_v1',
        ),
        isFalse,
      );
    },
  );
}

Map<String, Object?> _checkpoint({
  String contentType = 'series',
  int positionMs = 2_084_494,
  bool completed = false,
  bool completionReached = false,
  bool localCompletionEligible = false,
  bool localCompletionReached = false,
  bool localCompletionTracking = true,
  int completionThreshold = 80,
}) => <String, Object?>{
  'version': 1,
  'sessionId': 7,
  'sequence': 473,
  'profileId': 'adult',
  'dataGeneration': 3,
  'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
  'contentType': contentType,
  'title': 'Episode 4',
  'seriesTitle': 'The Example Show',
  'imdbId': 'tt1234567',
  'resumeId': 'episode-4',
  'url': 'https://example.invalid/video',
  'season': 2,
  'episode': 4,
  'itemIndex': 3,
  'positionMs': positionMs,
  'durationMs': 3_122_536,
  'speed': 1.0,
  'aspect': 'contain',
  'completed': completed,
  'completionReached': completionReached,
  'localCompleted': false,
  'localCompletionEligible': localCompletionEligible,
  'localCompletionReached': localCompletionReached,
  'localCompletionTracking': localCompletionTracking,
  'completionThreshold': completionThreshold,
};
