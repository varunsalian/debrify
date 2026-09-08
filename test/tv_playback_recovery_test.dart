import 'dart:convert';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/tv_playback_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scope = ProfileScope(
    profileId: 'adult',
    dataGeneration: 3,
    sessionEpoch: 1,
  );

  tearDown(TvPlaybackRecovery.debugReset);

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
