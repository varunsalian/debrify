import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/debrid_downloads_source.dart';

String compact(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  final bodies =
      jsonDecode(
            File(
              'test/features/debrid_downloads/presentation/legacy_debrid/debrid_action_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final calls =
      jsonDecode(
            File(
              'test/features/debrid_downloads/presentation/legacy_debrid/debrid_call_sites.json',
            ).readAsStringSync(),
          )
          as List;
  for (final kind in ['playback', 'download', 'playlist']) {
    test(
      'all original $kind payloads guards inline evaluations and complete bodies',
      () {
        final sites = calls.where((dynamic s) => s['kind'] == kind).toList();
        expect(
          sites.length,
          kind == 'playback'
              ? 6
              : kind == 'playlist'
              ? 5
              : 4,
        );
        for (final site in sites) {
          expect(
            compact(debridOriginalMember(site['member'] as String)),
            contains(compact(bodies[site['member']] as String)),
            reason: site['member'] as String,
          );
        }
      },
    );
  }
  test(
    'lifecycle registration timer poll and full individual disposal sequence',
    () {
      for (final name in ['initState', 'dispose']) {
        expect(
          compact(debridOriginalMember('_DebridDownloadsScreenState.$name')),
          contains(
            compact(bodies['_DebridDownloadsScreenState.$name'] as String),
          ),
        );
      }
      final dispose = debridOriginalMember(
        '_DebridDownloadsScreenState.dispose',
      );
      expect(RegExp(r'\.dispose\(\)').allMatches(dispose).length, 17);
      final order = [
        '_torrentScrollController',
        '_downloadScrollController',
        '_magnetController',
        '_linkController',
        '_backButtonFocusNode',
        '_refreshButtonFocusNode',
        '_viewModeDropdownFocusNode',
        '_firstItemFocusNode',
        '_deleteButtonFocusNode',
        '_searchController',
        '_searchFocusNode',
        '_searchButtonFocusNode',
        '_searchClearFocusNode',
        '_torrentSearchController',
        '_torrentSearchFocusNode',
        '_torrentSearchClearFocusNode',
        'super',
      ];
      var previous = -1;
      for (final name in order) {
        final index = dispose.indexOf('$name.dispose()');
        expect(index, greaterThan(previous), reason: name);
        previous = index;
      }
    },
  );
  test(
    'dormant dropdown exact reset TV handoff clipboard and auto-paste sites',
    () {
      for (final name in [
        '_resetListScroll',
        '_buildViewModeDropdown',
        '_handleAddTorrentToDebrifyTv',
        '_copyToClipboard',
        '_autoPasteMagnetLink',
        '_autoPasteLink',
        '_copyDownloadLink',
        '_copyNodeDownloadLink',
      ]) {
        expect(
          compact(debridOriginalMember('_DebridDownloadsScreenState.$name')),
          contains(
            compact(bodies['_DebridDownloadsScreenState.$name'] as String),
          ),
          reason: name,
        );
      }
      final dropdown = debridOriginalMember(
        '_DebridDownloadsScreenState._buildViewModeDropdown',
      );
      expect(dropdown, contains('_FolderViewMode.raw'));
      expect(dropdown, contains('_FolderViewMode.sortedAZ'));
      expect(dropdown, isNot(contains('_FolderViewMode.seriesArrange')));
    },
  );
}
