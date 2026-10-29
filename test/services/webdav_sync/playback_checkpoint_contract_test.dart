import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/lib_source.dart';

const _vp = 'lib/features/video_player/presentation/legacy_video_player';

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
    // The play toggle's live declaration, `VpControlsRuntime.togglePlay`.
    // Each form is matched exactly; nothing else satisfies these expectations.
    final toggle = libMember(
      '$_vp/vp_controls_runtime.dart',
      'togglePlay',
      owner: 'VpControlsRuntime',
    );
    expect(toggle, matches(RegExp(r'^void _?togglePlay\(\) \{')));
    final seek = _between(
      player,
      'onSeekBarChangeEnd: () {',
      '// IPTV episode list',
    );

    expect(
      toggle,
      contains(
        RegExp(
          r'unawaited\((?:_resumeSave\.saveResume\(positionOverride: _position\)'
          r'|_host\.saveResume\(positionOverride: _host\.position\))\)',
        ),
      ),
    );
    expect(seek, contains('positionOverride: settledPosition'));
    expect(seek, contains('unawaited('));
  });

  test(
    'resume saves serialize and recheck transition guards after queueing',
    () {
      final save = libMember(
        '$_vp/vp_resume_save.dart',
        'saveResume',
        owner: 'VpResumeSave',
      );
      final locked = libMember(
        '$_vp/vp_resume_save.dart',
        'saveResumeLocked',
        owner: 'VpResumeSave',
      );
      final blocked = libMember(
        '$_vp/vp_resume_save.dart',
        'resumeSaveBlocked',
        owner: 'VpResumeSave',
      );
      const method = '';
      expect(save, contains('Future<void> saveResume('));
      const fields = '_host.';
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
