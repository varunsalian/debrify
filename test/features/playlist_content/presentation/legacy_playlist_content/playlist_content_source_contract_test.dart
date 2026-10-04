import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_source.dart';

String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');
void main() {
  final bodies =
      jsonDecode(
            File(
              'test/features/playlist_content/presentation/legacy_playlist_content/playlist_content_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final method in [
    'initState',
    'dispose',
    '_initializeScreen',
    '_loadContent',
    '_playFile',
    '_playEpisode',
    '_playRealDebridPlaylist',
    '_playAllDebridPlaylist',
    '_playTorboxPlaylist',
    '_playPikPakPlaylist',
    '_playPremiumizePlaylist',
    '_playWebDavPlaylist',
    '_parseSeriesPlaylist',
    '_showFixMetadataDialog',
    '_toggleWatchedState',
    '_getProgressForFile',
    '_buildOTTView',
    '_buildEpisodeCard',
    '_buildMobileEpisodeCard',
    '_buildDesktopEpisodeCard',
    '_buildSearchBar',
    '_buildEpisodeList',
    '_scrollToEpisode',
  ]) {
    test('original complete contract body $method', () {
      expect(
        compact(
          playlistContentOriginalMember(
            '_PlaylistContentViewScreenState.$method',
          ),
        ),
        compact(bodies[method] as String),
      );
    });
  }
  test(
    'seven launcher sites fourteen entry constructions and thirty-nine prints',
    () {
      final methods = [
        '_playRealDebridPlaylist',
        '_playAllDebridPlaylist',
        '_playTorboxPlaylist',
        '_playPikPakPlaylist',
        '_playPremiumizePlaylist',
        '_playWebDavPlaylist',
      ];
      final playback = methods
          .map(
            (m) => playlistContentOriginalMember(
              '_PlaylistContentViewScreenState.$m',
            ),
          )
          .join('\n');
      expect(
        RegExp(r'VideoPlayerLauncher\.push\(').allMatches(playback),
        hasLength(7),
      );
      expect(RegExp(r'PlaylistEntry\(').allMatches(playback), hasLength(13));
      expect(
        RegExp(r'PlaylistEntry\(').allMatches(
          playlistContentOriginalMember(
            '_PlaylistContentViewScreenState._parseSeriesPlaylist',
          ),
        ),
        hasLength(1),
      );
      final screen = File(
        'lib/screens/playlist_content_view_screen.dart',
      ).readAsStringSync();
      final destinations = Directory('lib/features/playlist_content');
      final combined =
          screen +
          (destinations.existsSync()
              ? destinations
                    .listSync(recursive: true)
                    .whereType<File>()
                    .where((f) => f.path.endsWith('.dart'))
                    .map((f) => f.readAsStringSync())
                    .join('\n')
              : '');
      expect(RegExp(r'\bprint\(').allMatches(combined), hasLength(39));
      for (final forbidden in [
        'onPlayerHandoff:',
        'sourceOwner:',
        'canContinue:',
        'retainSourceSession:',
      ]) {
        expect(playback, isNot(contains(forbidden)));
      }
    },
  );
  test(
    'both caller constructions preserve dialog-popping callback ownership',
    () {
      final playlist = File(
        'lib/screens/playlist_screen.dart',
      ).readAsStringSync();
      expect(
        compact(playlist),
        contains(
          'PlaylistContentViewScreen(playlistItem:item,onPlaybackStarted:()=>Navigator.of(context).pop(),)',
        ),
      );
      final home = File(
        'lib/features/home/presentation/home_playlist_actions.dart',
      ).readAsStringSync();
      expect(
        compact(home),
        contains('PlaylistContentViewScreen(playlistItem:item)'),
      );
    },
  );
  test('metadata clear order retains transitive plus direct series clear', () {
    final body = compact(
      playlistContentOriginalMember(
        '_PlaylistContentViewScreenState._showFixMetadataDialog',
      ),
    );
    final calls = [
      'TVMazeService.clearShowCache(oldShowId)',
      'EpisodeInfoService.clearShowCache(oldShowId)',
      "EpisodeInfoService.clearSeriesCache(_seriesPlaylist?.seriesTitle??'',)",
      "TVMazeService.clearSeriesCache(_seriesPlaylist?.seriesTitle??'')",
      'TvMazeMappingStorage.saveTVMazeSeriesMapping(',
    ];
    var position = -1;
    for (final call in calls) {
      final next = body.indexOf(call);
      expect(next, greaterThan(position), reason: call);
      position = next;
    }
    expect(
      File('lib/services/episode_info_service.dart').readAsStringSync(),
      contains('await TVMazeService.clearSeriesCache(seriesTitle)'),
    );
  });
}
