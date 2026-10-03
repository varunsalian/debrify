import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/torbox_downloads_source.dart';

String compact(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  final calls =
      jsonDecode(
            File(
              'test/features/torbox_downloads/presentation/legacy_torbox/torbox_call_sites.json',
            ).readAsStringSync(),
          )
          as List;
  final bodies =
      jsonDecode(
            File(
              'test/features/torbox_downloads/presentation/legacy_torbox/torbox_action_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final kind in ['playback', 'download']) {
    test('all seven $kind payloads and inline evaluations stay exact', () {
      final sites = calls.where((site) => site['kind'] == kind).toList();
      expect(sites.length, 7);
      for (final site in sites) {
        expect(
          compact(torboxOriginalMember(site['member'] as String)),
          contains(compact(bodies[site['member']] as String)),
          reason: site['member'] as String,
        );
        final source = compact(torboxOriginalMember(site['member'] as String));
        expect(
          source,
          contains(compact(site['source'] as String)),
          reason: site['member'] as String,
        );
      }
    });
  }
  test('timeout condition registration and individual lifecycle disposal order', () {
    final init = compact(
      torboxOriginalMember('_TorboxDownloadsScreenState.initState'),
    );
    expect(
      init,
      contains(
        'Future.delayed(constDuration(seconds:10),(){if(mounted&&widget.isPushedRoute&&!widget.selectSourceMode&&widget.initialTorrentToOpen!=null&&_isAtRoot)',
      ),
    );
    final ordered = [
      'super.initState()',
      '_scrollController.addListener(_onScroll)',
      '_webDownloadScrollController.addListener(_onWebDownloadScroll)',
      '_loadApiKeyAndTorrents()',
      'MainPageBridge.pushRouteBackHandler(_handleBackNavigation)',
      'MainPageBridge.registerTabBackHandler(\'torbox\',_handleBackNavigation)',
      'MainPageBridge.registerTvContentFocusHandler(5,_tvContentFocusHandler!)',
    ];
    var previous = -1;
    for (final item in ordered) {
      final index = init.indexOf(item);
      expect(index, greaterThan(previous));
      previous = index;
    }
    final dispose = torboxOriginalMember('_TorboxDownloadsScreenState.dispose');
    expect(RegExp(r'\.dispose\(\)').allMatches(dispose).length, 19);
    expect(
      dispose.indexOf('_scrollController.dispose()'),
      lessThan(dispose.indexOf('super.dispose()')),
    );
  });
  test('dormant sheet and dropdown branches and TV handoff remain exact', () {
    final dropdown = torboxOriginalMember(
      '_TorboxDownloadsScreenState._buildViewModeDropdown',
    );
    expect(dropdown, contains('_FolderViewMode.raw'));
    expect(dropdown, contains('_FolderViewMode.sortedAZ'));
    expect(dropdown, isNot(contains('_FolderViewMode.seriesArrange')));
    final sheet = torboxOriginalMember(
      '_TorboxDownloadsScreenState._showTorboxFileSelectionSheet',
    );
    expect(sheet, contains('_buildTorboxSeriesView'));
    final tv = torboxOriginalMember(
      '_TorboxDownloadsScreenState._handleAddToDebrifyTv',
    );
    expect(
      compact(tv),
      contains('DebrifyTvChannelAddBridge.addTorrentsToChannel(context,'),
    );
    expect(tv, contains('_torrentSearchQuery'));
    final reset = torboxOriginalMember(
      '_TorboxDownloadsScreenState._resetListScroll',
    );
    expect(reset.indexOf('removeListener'), lessThan(reset.indexOf('jumpTo')));
    expect(reset.indexOf('jumpTo'), lessThan(reset.indexOf('addListener')));
  });
}
