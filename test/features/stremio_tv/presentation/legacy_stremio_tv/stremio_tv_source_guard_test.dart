import 'package:flutter_test/flutter_test.dart';

import '../../../../support/lib_source.dart';

const _slice = 'lib/features/stremio_tv/presentation/legacy_stremio_tv';

List<String> _searches(String source) => [
  for (final match in RegExp(
    r'searchByImdbWithStremio\([\s\S]*?\);',
  ).allMatches(source))
    match.group(0)!,
];

void main() {
  test(
    'channel searches exclude media servers; only playback bounds engines',
    () {
      final all = _searches(
        libJoined(
          libSourceSet(
            files: ['lib/screens/stremio_tv/stremio_tv_screen.dart'],
            directories: ['lib/features/stremio_tv'],
          ),
        ),
      );
      expect(all, hasLength(2));
      expect(
        all.every((call) => call.contains('includeMediaServers: false')),
        isTrue,
      );
      final play = _searches(libFile('$_slice/stremio_tv_play_channel.dart'));
      expect(play, hasLength(1));
      expect(
        play.single,
        contains('engineTimeout: const Duration(seconds: 10)'),
      );
      final resolve = _searches(
        libFile('$_slice/stremio_tv_channel_resolve.dart'),
      );
      expect(resolve, hasLength(1));
      expect(resolve.single, isNot(contains('engineTimeout')));
    },
  );
}
