import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_source.dart';

String compact(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  final bodies =
      jsonDecode(
            File(
              'test/features/premiumize_files/presentation/legacy_premiumize/premiumize_action_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in bodies.entries) {
    test('original full body payload contexts guards ${entry.key}', () {
      expect(
        compact(premiumizeOriginalMember(entry.key)),
        contains(compact(entry.value as String)),
        reason: entry.key,
      );
    });
  }
  test(
    'three launch sites two enqueue bodies three playlist maps and startup order',
    () {
      String joined(List<String> names) => names
          .map(
            (n) => premiumizeOriginalMember('_PremiumizeFilesScreenState.$n'),
          )
          .join('\n');
      final playback = joined(['_playFile', '_playPremiumizeVideos']);
      expect(
        RegExp(r'VideoPlayerLauncher.push\(').allMatches(playback).length,
        3,
      );
      expect(
        RegExp(
          r'MainPageBridge.notifyPlayerLaunching\(',
        ).allMatches(playback).length,
        3,
      );
      expect(
        RegExp(r'enqueueDownload\(')
            .allMatches(joined(['_downloadFile', '_downloadSelectedFiles']))
            .length,
        2,
      );
      expect(
        RegExp(r'addPlaylistItemRaw\(')
            .allMatches(joined(['_addFileToPlaylist', '_addFolderToPlaylist']))
            .length,
        3,
      );
      final init = premiumizeOriginalMember(
        '_PremiumizeFilesScreenState.initState',
      );
      expect(
        init.indexOf("screenView('premiumize_files')"),
        lessThan(init.indexOf('_loadSettings()')),
      );
      expect(
        init.indexOf('_loadSettings()'),
        lessThan(init.indexOf('pushRouteBackHandler')),
      );
    },
  );
  test(
    'entire fourteen resource disposal sequence and debounce cancellation',
    () {
      final dispose = premiumizeOriginalMember(
        '_PremiumizeFilesScreenState.dispose',
      );
      final resources = [
        '_scrollController',
        '_linkController',
        '_searchController',
        '_refreshButtonFocusNode',
        '_backButtonFocusNode',
        '_retryButtonFocusNode',
        '_settingsButtonFocusNode',
        '_viewModeDropdownFocusNode',
        '_addLinkButtonFocusNode',
        '_firstItemFocusNode',
        '_deleteButtonFocusNode',
        '_searchFocusNode',
        '_searchButtonFocusNode',
        '_searchClearFocusNode',
        'super',
      ];
      expect(RegExp(r'\.dispose\(\)').allMatches(dispose).length, 15);
      var previous = dispose.indexOf('_searchDebounce?.cancel()');
      expect(previous, greaterThanOrEqualTo(0));
      for (final name in resources) {
        final next = dispose.indexOf('$name.dispose()');
        expect(next, greaterThan(previous), reason: name);
        previous = next;
      }
    },
  );
}
