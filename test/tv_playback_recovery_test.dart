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

  test('recovery deepens state and only creates on a same-process return', () {
    final checkpoint = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint()),
    )!;

    expect(checkpoint.shouldDeepen(null, allowCreate: false), isFalse);
    expect(checkpoint.shouldDeepen(null, allowCreate: true), isTrue);
    expect(
      checkpoint.shouldDeepen({'positionMs': 1_700_000}, allowCreate: false),
      isTrue,
    );
    expect(
      checkpoint.shouldDeepen({'positionMs': 2_100_000}, allowCreate: true),
      isFalse,
    );
  });

  test('completion territory is never resurrected as Continue Watching', () {
    final completed = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(completed: true)),
    )!;
    final nearEnd = TvPlaybackCheckpoint.tryParse(
      jsonEncode(_checkpoint(positionMs: 2_980_000)),
    )!;

    expect(completed.isResumable, isFalse);
    expect(nearEnd.isResumable, isFalse);
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
  int positionMs = 2_084_494,
  bool completed = false,
}) => <String, Object?>{
  'version': 1,
  'sessionId': 7,
  'sequence': 473,
  'profileId': 'adult',
  'dataGeneration': 3,
  'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
  'contentType': 'series',
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
  'localCompleted': false,
};
