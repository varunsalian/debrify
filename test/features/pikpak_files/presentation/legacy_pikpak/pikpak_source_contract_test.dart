import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/pikpak_files_source.dart';

String compact(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  final bodies =
      jsonDecode(
            File(
              'test/features/pikpak_files/presentation/legacy_pikpak/pikpak_action_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in {
    'playback': ['_playFile', '_playPikPakVideos'],
    'download': [
      '_downloadFile',
      '_downloadSelectedPikPakFiles',
      '_downloadFolder',
    ],
    'playlist': ['_addSingleFileToPlaylist', '_addFolderToPlaylist'],
  }.entries) {
    test('all original ${entry.key} sites full bodies payloads and guards', () {
      for (final name in entry.value) {
        final key = '_PikPakFilesScreenState.$name';
        expect(
          compact(pikpakOriginalMember(key)),
          contains(compact(bodies[key] as String)),
          reason: key,
        );
      }
      final joined = entry.value
          .map((name) => bodies['_PikPakFilesScreenState.$name'] as String)
          .join('\n');
      expect(
        RegExp(
          entry.key == 'playback'
              ? r'VideoPlayerLauncher.push\('
              : entry.key == 'download'
              ? r'enqueueDownload\('
              : r'addPlaylistItemRaw\(',
        ).allMatches(joined).length,
        entry.key == 'playlist'
            ? 3
            : entry.key == 'download'
            ? 2
            : 3,
      );
    });
  }
  test(
    'lifecycle registration timer poll and full individual disposal sequence',
    () {
      for (final name in ['initState', 'dispose']) {
        expect(
          compact(pikpakOriginalMember('_PikPakFilesScreenState.$name')),
          contains(compact(bodies['_PikPakFilesScreenState.$name'] as String)),
        );
      }
      final dispose = pikpakOriginalMember('_PikPakFilesScreenState.dispose');
      expect(RegExp(r'\.dispose\(\)').allMatches(dispose).length, 15);
      final order = [
        '_scrollController',
        '_linkController',
        '_refreshButtonFocusNode',
        '_backButtonFocusNode',
        '_retryButtonFocusNode',
        '_settingsButtonFocusNode',
        '_viewModeDropdownFocusNode',
        '_addLinkButtonFocusNode',
        '_firstItemFocusNode',
        '_searchController',
        '_searchFocusNode',
        '_searchButtonFocusNode',
        '_searchClearFocusNode',
        '_deleteButtonFocusNode',
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
  test('dormant dropdown reset aliasing pop sites and paging guards', () {
    for (final name in [
      '_resetListScroll',
      '_buildViewModeDropdown',
      '_autoPasteLink',
      '_addLink',
      '_selectBoundSource',
      '_loadFiles',
      '_loadMoreFiles',
      '_setViewMode',
      '_applySeriesArrangeView',
      '_performSearch',
      '_buildFileCard',
      '_navigateIntoVirtualFolder',
    ]) {
      expect(
        compact(pikpakOriginalMember('_PikPakFilesScreenState.$name')),
        contains(compact(bodies['_PikPakFilesScreenState.$name'] as String)),
        reason: name,
      );
    }
    final dropdown = pikpakOriginalMember(
      '_PikPakFilesScreenState._buildViewModeDropdown',
    );
    expect(dropdown, contains('_FolderViewMode.raw'));
    expect(dropdown, contains('_FolderViewMode.sortedAZ'));
    expect(dropdown, isNot(contains('_FolderViewMode.seriesArrange')));
  });
}
