import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/screens/video_player/episode_display_inputs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('construction stores every host read unchanged', () {
    const entries = [
      PlaylistEntry(
        url: 'https://inputs.invalid/e1.mp4',
        title: 'Show.S01E01.mkv',
      ),
      PlaylistEntry(
        url: 'https://inputs.invalid/e2.mp4',
        title: 'Show.S01E02.mkv',
      ),
    ];
    final series = SeriesPlaylist.fromPlaylistEntries(entries);
    final channels = [
      IptvChannel(
        channelNumber: 7,
        name: 'News',
        url: 'https://inputs.invalid/news',
      ),
    ];
    final stremio = [
      <String, dynamic>{'id': 'ch-1', 'name': 'Stremio One'},
    ];

    final inputs = EpisodeDisplayInputs(
      seriesPlaylist: series,
      activePlaylist: entries,
      currentIndex: 1,
      effectiveContentTitle: 'The Show',
      effectiveStremioTvChannels: stremio,
      hasStremioTvGuide: true,
      dynamicTitle: 'Dynamic',
      hasMagicNext: true,
      effectiveIptvChannels: channels,
      title: 'Launch title',
      currentIptvIndex: 0,
      effectiveContentSeason: 1,
      effectiveContentEpisode: 2,
      subtitle: 'Release line',
    );

    expect(inputs.seriesPlaylist, same(series));
    expect(inputs.activePlaylist, same(entries));
    expect(inputs.currentIndex, 1);
    expect(inputs.effectiveContentTitle, 'The Show');
    expect(inputs.effectiveStremioTvChannels, same(stremio));
    expect(inputs.hasStremioTvGuide, isTrue);
    expect(inputs.dynamicTitle, 'Dynamic');
    expect(inputs.hasMagicNext, isTrue);
    expect(inputs.effectiveIptvChannels, same(channels));
    expect(inputs.title, 'Launch title');
    expect(inputs.currentIptvIndex, 0);
    expect(inputs.effectiveContentSeason, 1);
    expect(inputs.effectiveContentEpisode, 2);
    expect(inputs.subtitle, 'Release line');
  });

  test('nullable reads stay null and the object is const-constructible', () {
    const inputs = EpisodeDisplayInputs(
      seriesPlaylist: null,
      activePlaylist: null,
      currentIndex: 0,
      effectiveContentTitle: null,
      effectiveStremioTvChannels: null,
      hasStremioTvGuide: false,
      dynamicTitle: '',
      hasMagicNext: false,
      effectiveIptvChannels: null,
      title: 'Only title',
      currentIptvIndex: 0,
      effectiveContentSeason: null,
      effectiveContentEpisode: null,
      subtitle: null,
    );

    expect(inputs.seriesPlaylist, isNull);
    expect(inputs.activePlaylist, isNull);
    expect(inputs.effectiveContentTitle, isNull);
    expect(inputs.effectiveStremioTvChannels, isNull);
    expect(inputs.hasStremioTvGuide, isFalse);
    expect(inputs.dynamicTitle, isEmpty);
    expect(inputs.hasMagicNext, isFalse);
    expect(inputs.effectiveIptvChannels, isNull);
    expect(inputs.title, 'Only title');
    expect(inputs.effectiveContentSeason, isNull);
    expect(inputs.effectiveContentEpisode, isNull);
    expect(inputs.subtitle, isNull);
  });
}
