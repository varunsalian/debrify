import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: 'Missing start marker: $start');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: 'Missing end marker: $end');
  return source.substring(from, to);
}

void main() {
  final playbackStartFile = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvPlaybackStartController.kt',
  );
  // Step 0 runs before extraction; both owners exercise the same assertions.
  final extracted = playbackStartFile.existsSync();
  final nativePlayer = extracted
      ? playbackStartFile.readAsStringSync()
      : File(
          'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt',
        ).readAsStringSync();

  test('native TV auto-advance ignores every saved resume position', () {
    final start = extracted ? 'fun playItem(' : 'private fun playItem(';
    expect(nativePlayer.indexOf(start), isNonNegative);
    expect(nativePlayer.indexOf(start), nativePlayer.lastIndexOf(start));
    final playItem = _between(
      nativePlayer,
      start,
      'private fun resolveAndPlay(',
    );

    expect(
      playItem,
      contains(
        'if (autoAdvance || suppressResume) 0L else item.resumePositionMs',
      ),
    );
    expect(
      playItem,
      contains('if (autoAdvance || suppressTrakt || suppressResume) 0.0'),
    );
  });

  final upNextController = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvUpNextController.kt',
  ).readAsStringSync();

  test('native TV Up Next countdown is treated as an auto-advance', () {
    final triggerUpNext = _between(
      upNextController,
      'fun triggerUpNext()',
      'fun dismissUpNext()',
    );

    final autoAdvance = triggerUpNext.indexOf('host.isAutoAdvancing = true');
    final play = triggerUpNext.indexOf('host.playItem(target)');
    expect(autoAdvance, isNonNegative);
    expect(play, greaterThan(autoAdvance));
  });
}
