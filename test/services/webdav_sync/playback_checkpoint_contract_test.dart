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
  final player = File(
    'lib/screens/video_player_screen.dart',
  ).readAsStringSync();

  test('pause and settled seek issue explicit persisted checkpoints', () {
    final toggle = _between(
      player,
      'void _togglePlay()',
      'void _setManualSelectionMode',
    );
    final seek = _between(
      player,
      'onSeekBarChangeEnd: () {',
      '// IPTV episode list',
    );

    expect(toggle, contains('_saveResume(positionOverride: _position)'));
    expect(seek, contains('positionOverride: settledPosition'));
    expect(seek, contains('unawaited('));
  });

  test(
    'resume saves serialize and recheck transition guards after queueing',
    () {
      final save = _between(
        player,
        'bool _resumeSaveBlocked(bool debounced)',
        'bool _tvAutoHideBlocked',
      );

      expect(player, contains('final Lock _resumeSaveLock = Lock();'));
      expect(save, contains('if (_resumeSaveBlocked(debounced))'));
      expect(save, contains('if (debounced && _resumeSaveLock.locked)'));
      expect(save, contains('return _resumeSaveLock.synchronized('));
      expect(save, contains('Future<void> _saveResumeLocked('));
      final lockedSave = save.indexOf('Future<void> _saveResumeLocked(');
      expect(
        save.indexOf('if (_resumeSaveBlocked(debounced))', lockedSave),
        greaterThan(lockedSave),
      );
      expect(
        save,
        contains('_effectiveIptvChannels != null && _isTransitioning'),
      );
      expect(save, contains('_isManualEpisodeSelection && debounced'));
    },
  );
}
