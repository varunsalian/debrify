import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../features/video_player/support/vp_source_reader.dart';

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

    expect(
      toggle,
      contains(
        RegExp(
          r'(?:_saveResume|_resumeSave\.saveResume)\(positionOverride: _position\)',
        ),
      ),
    );
    expect(seek, contains('positionOverride: settledPosition'));
    expect(seek, contains('unawaited('));
  });

  test(
    'resume saves serialize and recheck transition guards after queueing',
    () {
      final save = vpSourceDeclaration('_VideoPlayerScreenState._saveResume');
      final locked = vpSourceDeclaration(
        '_VideoPlayerScreenState._saveResumeLocked',
      );
      final blocked = vpSourceDeclaration(
        '_VideoPlayerScreenState._resumeSaveBlocked',
      );
      final method = save.contains('Future<void> _saveResume(') ? '_' : '';
      final fields = save.contains('_host.resumeSaveLock') ? '_host.' : '_';
      expect(player, contains('final Lock _resumeSaveLock = Lock();'));
      expect(save, contains('if (${method}resumeSaveBlocked(debounced))'));
      expect(
        save,
        contains('if (debounced && ${fields}resumeSaveLock.locked)'),
      );
      expect(save, contains('return ${fields}resumeSaveLock.synchronized('));
      expect(save, contains('${method}saveResumeLocked('));
      final recheck = locked.indexOf(
        'if (${method}resumeSaveBlocked(debounced))',
      );
      final position = locked.indexOf('var pos = positionOverride ??');
      expect(recheck, isNonNegative);
      expect(position, greaterThan(recheck));
      expect(
        blocked,
        contains(
          '${fields}effectiveIptvChannels != null && ${fields}isTransitioning',
        ),
      );
      expect(
        blocked,
        contains('${fields}isManualEpisodeSelection && debounced'),
      );
    },
  );
}
