import 'dart:async';
import 'dart:collection';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/channel_entry.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'player_actions.dart';
import 'subtitle_apply_driver.dart';

const tvDirectory = [
  {'id': 'a', 'name': 'Alpha', 'channelNumber': 7, 'isCurrent': true},
  {'id': 'b', 'name': 'Beta', 'channelNumber': 9},
];

Torrent episodeSource(
  String name, {
  StreamType type = StreamType.directUrl,
  String? coverage,
  int? season,
  int? start,
  int? end,
}) => Torrent(
  rowid: 0,
  infohash: type == StreamType.torrent ? name : '',
  name: RegExp(r'S\d+E\d+$', caseSensitive: false).hasMatch(name)
      ? '$name.mkv'
      : name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'p17',
  streamType: type,
  directUrl: 'https://player.test/${Uri.encodeComponent(name)}.mp4',
  transformedTitle: RegExp(r'S\d+E\d+$', caseSensitive: false).hasMatch(name)
      ? '$name.mkv'
      : null,
  coverageType: coverage,
  seasonNumber: season,
  startSeason: start,
  endSeason: end,
  episodeIdentifier: RegExp(
    r'S\d+E\d+',
    caseSensitive: false,
  ).firstMatch(name)?.group(0),
);

class P17ObservedErrors extends ListBase<Object> {
  final _values = <Object>[];
  @override
  int get length => _values.length;
  @override
  set length(int value) => _values.length = value;
  @override
  Object operator [](int index) => _values[index];
  @override
  void operator []=(int index, Object value) => _values[index] = value;
  @override
  void add(Object value) {
    // Mutation receipts distinguish captured runtime errors from assertions.
    // ignore: avoid_print
    print('P17_CAPTURED_ERROR ${value.runtimeType}');
    _values.add(value);
  }
}

class TvEpisodeDriver extends SubtitleApplyDriver {
  TvEpisodeDriver(super.t, {super.configurePlayer});
  final _observedErrors = P17ObservedErrors();
  @override
  List<Object> get errors => _observedErrors;
  @override
  T observe<T>(T Function() body) => runZoned(
    () => super.observe(body),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        logs.add(line);
        parent.print(zone, line);
      },
    ),
  );
  List<mk.Media> get opens => player.calls
      .where((c) => c.$1 == 'open')
      .map((c) => (c.$2 as (mk.Playable, bool)).$1 as mk.Media)
      .toList();
  List<bool> get openAutoplay => player.calls
      .where((c) => c.$1 == 'open')
      .map((c) => (c.$2 as (mk.Playable, bool)).$2)
      .toList();
  List<Duration> get seeks => player.calls
      .where((c) => c.$1 == 'seek')
      .map((c) => c.$2 as Duration)
      .toList();
  Future<ChannelGuide> debrifyGuide() async {
    playerControls(t).onShowGuide!();
    await f.until(t, () => find.byType(ChannelGuide).evaluate().isNotEmpty);
    return t.widget<ChannelGuide>(find.byType(ChannelGuide));
  }

  Future<StremioTvGuideSheet> stremioGuide() async {
    playerControls(t).onShowGuide!();
    await f.until(
      t,
      () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
    );
    return t.widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet));
  }

  Future<void> byId(ChannelGuide guide, ChannelEntry channel) async {
    final dynamic callback = guide.onChannelSelected;
    await f.finish<dynamic>(t, observe<dynamic>(() => callback(channel)));
    await f.advance(t);
  }

  Future<dynamic> beginNextChannel() {
    final dynamic callback = playerControls(t).onNextChannel!;
    return observe<dynamic>(() => callback()) as Future<dynamic>;
  }

  Future<void> nextChannel() async {
    await f.finish<dynamic>(t, beginNextChannel());
    await f.advance(t);
  }

  Future<void> stremioPick(
    StremioTvGuideSheet guide,
    String id, {
    String? url,
    double? startAtPercent,
    String? imdbId,
    int? season,
    int? episode,
    Map<String, dynamic>? nowPlaying,
    Map<String, dynamic>? nextUp,
    List<Torrent>? sources,
    int? sourceIndex,
    Future<String?> Function(Torrent)? resolver,
  }) async {
    final dynamic callback = guide.onChannelSwitched;
    await f.finish<dynamic>(
      t,
      observe<dynamic>(
        () => callback(
          id,
          url ?? 'https://player.test/$id.mp4',
          'Channel $id',
          contentImdbId: imdbId,
          contentType: 'series',
          contentSeason: season,
          contentEpisode: episode,
          startAtPercent: startAtPercent,
          nowPlaying: nowPlaying,
          nextUp: nextUp,
          newSources: sources,
          newSourceIndex: sourceIndex,
          sourceResolver: resolver,
        ),
      ),
    );
    await f.advance(t);
  }

  Future<SeriesBrowser> browser() async {
    playerControls(t).onShowPlaylist();
    await f.until(t, () => find.byType(SeriesBrowser).evaluate().isNotEmpty);
    return t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
  }

  Future<SourceSheet> sourceSheet() async {
    playerControls(t).onShowStremioSources!();
    await f.until(t, () => find.byType(SourceSheet).evaluate().isNotEmpty);
    return t.widget<SourceSheet>(find.byType(SourceSheet));
  }
}
