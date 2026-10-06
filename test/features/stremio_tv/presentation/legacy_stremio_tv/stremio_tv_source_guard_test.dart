import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/stremio_tv_source.dart';

void main() {
  test('C1 (S) verified original lifecycle owns disposal and tab-9 hook', () {
    final source = stremioTvOriginalSource();
    final disposal = source.substring(
      source.indexOf('void dispose()'),
      source.indexOf('Future<void> _loadSettings()'),
    );
    final ordered = [
      '_contentRevision.dispose()',
      '_searchBtnFocusNode.dispose()',
      '_providerFocusNode.dispose()',
      '_menuFocusNode.dispose()',
      '_submenuFocusNode.dispose()',
      '_searchController.dispose()',
      '_searchFocusNode.dispose()',
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
    expect(source, contains('AnalyticsService.screenView(\'stremio_tv\')'));
    expect(
      source,
      contains('registerTvContentFocusHandler(9, _tvContentFocusHandler!)'),
    );
    expect(source, contains('_searchController.addListener(() {'));
  });

  test('C3 (S) frozen P1/P2 ledger accounts for native-only parameters', () {
    stremioTvOriginalSource();
    final ledger =
        jsonDecode(
              File(
                'dev/tool/stremio_tv_handoff_ledger.json',
              ).readAsStringSync(),
            )
            as Map;
    expect((ledger['sites'] as List).map((site) => site['site']), ['P1', 'P2']);
    for (final site in ledger['sites'] as List) {
      expect(site['arguments'], hasLength(19));
      final names = (site['arguments'] as List)
          .map((arg) => arg['name'])
          .toList();
      expect(
        names,
        containsAllInOrder([
          'videoUrl',
          'title',
          'startAtPercent',
          'contentImdbId',
          'contentTitle',
          'contentType',
          'contentSeason',
          'contentEpisode',
          'stremioSources',
          'stremioCurrentSourceIndex',
          'resolveStremioSource',
          'stremioTvChannels',
          'stremioTvCurrentChannelId',
          'stremioTvRotationMinutes',
          'stremioTvSeriesRotationMinutes',
          'stremioTvMixSalt',
          'stremioTvGuideDataProvider',
          'stremioTvChannelSwitchProvider',
          'stremioTvNextProvider',
        ]),
      );
    }
    expect(ledger['native_only_arguments'], [
      'stremioTvRotationMinutes',
      'stremioTvSeriesRotationMinutes',
      'stremioTvMixSalt',
    ]);
  });

  test(
    'C3/C7 (S) cancellation snapshots timing and search exclusions are unchanged',
    () {
      final source = stremioTvOriginalSource();
      expect(RegExp(r'\b_playGeneration\b').allMatches(source), hasLength(15));
      expect(source, contains('final debridProvider = _debridProvider;'));
      expect(
        source,
        contains('await Future.delayed(const Duration(seconds: 3));'),
      );
      expect(source, contains('waitedMs < 8000'));
      expect(source, contains('Duration(milliseconds: 120)'));
      final calls = RegExp(
        r'searchByImdbWithStremio\([\s\S]*?\);',
      ).allMatches(stremioTvCurrentSource()).toList();
      expect(calls, hasLength(2));
      expect(
        calls.every(
          (call) => call.group(0)!.contains('includeMediaServers: false'),
        ),
        isTrue,
      );
      expect(
        calls.first.group(0),
        contains('engineTimeout: const Duration(seconds: 10)'),
      );
      expect(calls.last.group(0), isNot(contains('engineTimeout')));
    },
  );

  test('C9 (S) reader uses declaration owners rather than file presence', () {
    expect(
      stremioTvSourceFiles(),
      contains('lib/screens/stremio_tv/stremio_tv_screen.dart'),
    );
    final current = stremioTvCurrentSource();
    expect(current, contains('class StremioTvScreen extends StatefulWidget'));
    expect(
      current,
      contains('class _ManualSourcePickerSheet extends StatefulWidget'),
    );
  });
}
