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

  test('screen lifecycle owns disposal order and the tab-9 TV hook', () {
    final screen = libFile('lib/screens/stremio_tv/stremio_tv_screen.dart');
    final disposal = screen.substring(
      screen.indexOf('void dispose()'),
      screen.indexOf('Widget build(BuildContext context)'),
    );
    final ordered = [
      'contentRevision.dispose()',
      'searchBtnFocusNode.dispose()',
      'providerFocusNode.dispose()',
      'menuFocusNode.dispose()',
      'submenuFocusNode.dispose()',
      'searchController.dispose()',
      'searchFocusNode.dispose()',
      'node.dispose()',
      'MainPageBridge.watchStremioTvChannel = null',
      'MainPageBridge.unregisterTvContentFocusHandler',
      'super.dispose()',
    ];
    var previous = -1;
    for (final step in ordered) {
      final position = disposal.indexOf(step);
      expect(position, greaterThan(previous), reason: step);
      previous = position;
    }
    expect(screen, contains("AnalyticsService.screenView('stremio_tv')"));
    expect(screen, matches(RegExp(r'registerTvContentFocusHandler\(\s*9,')));
    expect(screen, contains('searchController.addListener(() {'));
  });

  test('play generations and resolve timings are unchanged', () {
    final play = libFile('$_slice/stremio_tv_play_channel.dart');
    expect(
      play,
      contains('final myGeneration = ++_owners.playback.playGeneration;'),
    );
    final selection = libFile('$_slice/stremio_tv_stream_selection.dart');
    expect(
      RegExp(r'playGeneration != myGeneration').allMatches(selection).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      libFile('$_slice/stremio_tv_cloud_resolvers.dart'),
      contains('await Future.delayed(const Duration(seconds: 3));'),
    );
    final actions = libFile('$_slice/stremio_tv_channel_actions.dart');
    expect(actions, contains('waitedMs < 8000'));
    expect(actions, contains('Duration(milliseconds: 120)'));
  });
}
