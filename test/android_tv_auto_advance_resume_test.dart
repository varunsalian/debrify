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
  final nativePlayer = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt',
  ).readAsStringSync();

  test('native TV auto-advance ignores every saved resume position', () {
    final playItem = _between(
      nativePlayer,
      'private fun playItem(',
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
      contains(
        'if (autoAdvance || suppressTrakt || suppressResume) 0.0',
      ),
    );
  });

  test('native TV Up Next countdown is treated as an auto-advance', () {
    final triggerUpNext = _between(
      nativePlayer,
      'private fun triggerUpNext()',
      'private fun dismissUpNext()',
    );

    final autoAdvance = triggerUpNext.indexOf('isAutoAdvancing = true');
    final play = triggerUpNext.indexOf('playItem(target)');
    expect(autoAdvance, isNonNegative);
    expect(play, greaterThan(autoAdvance));
  });
}
