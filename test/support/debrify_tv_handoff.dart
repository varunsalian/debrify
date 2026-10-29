import 'dart:io';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Typed accessors cover every constructor parameter. This is a test
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

/// The player constructor's own defaults: only the required URL and title are
/// supplied, so every other field holds the value an omitted argument gets.
final Map<String, Object?> _constructorDefaults = debrifyTvPlayerFields(
  VideoPlayerScreen(videoUrl: '', title: ''),
);
const _requiredFields = {'videoUrl', 'title'};

/// Every named parameter of the current `VideoPlayerScreen` constructor.
Set<String> playerConstructorParameters() {
  final source = File(
    'lib/screens/video_player_screen.dart',
  ).readAsStringSync();
  final start = source.indexOf('const VideoPlayerScreen({');
  final end = source.indexOf('})', start);
  if (start < 0 || end < 0) {
    throw StateError('Missing VideoPlayerScreen constructor');
  }
  return RegExp(
    r'\b(?:this|super)\.(\w+)',
  ).allMatches(source.substring(start, end)).map((match) => match[1]!).toSet();
}

/// [site] built [p] from exactly [supplied]; every other field keeps the
/// constructor default.
void expectDebrifyTvPlayer(
  VideoPlayerScreen p,
  String site,
  Map<String, Object?> supplied,
) {
  final fields = debrifyTvPlayerFields(p);
  expect(
    fields.keys.toSet(),
    playerConstructorParameters(),
    reason: 'typed observer covers every constructor field',
  );
  expect(
    fields.keys.toSet(),
    containsAll(supplied.keys),
    reason: '$site supplies only player fields',
  );
  for (final name in fields.keys) {
    if (supplied.containsKey(name)) {
      final expected = supplied[name];
      expect(
        fields[name],
        expected is Matcher ? expected : equals(expected),
        reason: '$site passes $name',
      );
    } else {
      expect(
        _requiredFields,
        isNot(contains(name)),
        reason: '$site must supply required $name',
      );
      expect(
        fields[name],
        _constructorDefaults[name],
        reason: '$site retains constructor default $name',
      );
    }
  }
}
