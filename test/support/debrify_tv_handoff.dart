import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Typed accessors cover every ORIGINAL constructor parameter. This is a test
// boundary: no player is mounted and no production seam is added.
Map<String, Object?> debrifyTvPlayerFields(VideoPlayerScreen p) => {
  'key': p.key,
  'videoUrl': p.videoUrl,
  'audioUrl': p.audioUrl,
  'title': p.title,
  'subtitle': p.subtitle,
  'playlist': p.playlist,
  'startIndex': p.startIndex,
  'rdTorrentId': p.rdTorrentId,
  'torboxTorrentId': p.torboxTorrentId,
  'pikpakCollectionId': p.pikpakCollectionId,
  'requestMagicNext': p.requestMagicNext,
  'requestNextChannel': p.requestNextChannel,
  'requestChannelById': p.requestChannelById,
  'channelDirectory': p.channelDirectory,
  'initialContinuousShuffle': p.initialContinuousShuffle,
  'startFromRandom': p.startFromRandom,
  'randomStartMaxPercent': p.randomStartMaxPercent,
  'startAtPercent': p.startAtPercent,
  'hideSeekbar': p.hideSeekbar,
  'showChannelName': p.showChannelName,
  'channelName': p.channelName,
  'channelNumber': p.channelNumber,
  'showVideoTitle': p.showVideoTitle,
  'hideOptions': p.hideOptions,
  'hideBackButton': p.hideBackButton,
  'httpHeaders': p.httpHeaders,
  'disableAutoResume': p.disableAutoResume,
  'viewMode': p.viewMode,
  'contentImdbId': p.contentImdbId,
  'contentType': p.contentType,
  'contentSeason': p.contentSeason,
  'contentEpisode': p.contentEpisode,
  'contentTitle': p.contentTitle,
  'resumePolicy': p.resumePolicy,
  'iptvChannels': p.iptvChannels,
  'iptvStartIndex': p.iptvStartIndex,
  'iptvCategories': p.iptvCategories,
  'iptvSourceId': p.iptvSourceId,
  'iptvSourceName': p.iptvSourceName,
  'iptvSelectedCategory': p.iptvSelectedCategory,
  'iptvContentType': p.iptvContentType,
  'iptvSources': p.iptvSources,
  'iptvBrowseProvider': p.iptvBrowseProvider,
  'stremioSources': p.stremioSources,
  'stremioCurrentSourceIndex': p.stremioCurrentSourceIndex,
  'resolveStremioSource': p.resolveStremioSource,
  'resolveSourceToPlaylist': p.resolveSourceToPlaylist,
  'startupFailoverEnabled': p.startupFailoverEnabled,
  'startupResolverProvider': p.startupResolverProvider,
  'onStremioSourceCommitted': p.onStremioSourceCommitted,
  'onStartupSourcesExhausted': p.onStartupSourcesExhausted,
  'seriesSourceFetcher': p.seriesSourceFetcher,
  'stremioTvChannels': p.stremioTvChannels,
  'stremioTvCurrentChannelId': p.stremioTvCurrentChannelId,
  'stremioTvGuideDataProvider': p.stremioTvGuideDataProvider,
  'stremioTvChannelSwitchProvider': p.stremioTvChannelSwitchProvider,
  'stremioTvNextProvider': p.stremioTvNextProvider,
  'traktScrobble': p.traktScrobble,
  'traktProgressPercent': p.traktProgressPercent,
  'simklScrobble': p.simklScrobble,
  'simklProgressPercent': p.simklProgressPercent,
  'mdblistScrobble': p.mdblistScrobble,
  'mdblistProgressPercent': p.mdblistProgressPercent,
  'initialSubtitles': p.initialSubtitles,
};

void expectDebrifyTvPlayer(
  VideoPlayerScreen p,
  String site,
  Map<String, Object?> supplied,
) {
  final ledger =
      jsonDecode(
            File('dev/tool/debrify_tv_handoff_ledger.json').readAsStringSync(),
          )
          as Map;
  final entry = (ledger['sites'] as List).cast<Map>().singleWhere(
    (e) => e['site'] == site,
  );
  final passed = (entry['arguments'] as List)
      .cast<Map>()
      .map((a) => a['name'])
      .toSet();
  expect(
    supplied.keys.toSet(),
    passed,
    reason: '$site accounts for each named argument',
  );
  final fields = debrifyTvPlayerFields(p);
  final defaults = ledger['constructor_defaults'] as Map;
  for (final name in fields.keys) {
    if (passed.contains(name)) {
      final expected = supplied[name];
      expect(
        fields[name],
        expected is Matcher ? expected : equals(expected),
        reason: '$site passes $name',
      );
    } else {
      final raw = defaults[name];
      final Object? expected = switch (raw) {
        null => null,
        'false' => false,
        'true' => true,
        '40' => 40,
        'PlaybackResumePolicy.sourceSpecific' =>
          PlaybackResumePolicy.sourceSpecific,
        _ => throw StateError(
          'Unclassified ORIGINAL constructor default: $name=$raw',
        ),
      };
      expect(
        fields[name],
        expected,
        reason: '$site retains constructor default $name',
      );
    }
  }
}
