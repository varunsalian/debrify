import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:media_kit/media_kit.dart' as mk;
// Resolved by flutter_test; app dependencies stay frozen.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:test_api/src/backend/invoker.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:test_api/src/backend/state.dart' as test_state;

import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_player.dart';

/// Only public rendered inputs, dispatched requests and player operations.
/// Captured before fixture cleanup; checked after a successful test body.
/// A prior assertion/runtime failure never acquires snapshot mutation credit.
class IptvOutputObservation {
  IptvOutputObservation() : test = Invoker.current!.liveTest.test.name {
    addTearDown(() {
      if (Invoker.current!.liveTest.state.result != test_state.Result.success) {
        return;
      }
      expect(value, isNotNull, reason: 'Original-caller fixture must close');
      final expected =
          jsonDecode(
                File(
                  'test/features/video_player/support/fixtures/iptv_original_outputs.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        expected,
        contains(test),
        reason: 'Missing original characterization',
      );
      expect(
        value,
        expected[test],
        reason: 'Original public IPTV outputs: $test',
      );
    });
  }
  final String test;
  Map<String, Object?>? value;
  Map<String, String> addonAliases = {};

  Object? normalize(Object? input) {
    if (input is String) {
      for (final entry in addonAliases.entries) {
        if (input == entry.key) {
          return entry.value;
        }
        final prefix = 'stremio-tv://${entry.key}/';
        if (input.startsWith(prefix)) {
          return input.replaceFirst(prefix, 'stremio-tv://${entry.value}/');
        }
      }
    }
    if (input is String && input.startsWith('http')) {
      return input.replaceAll(
        RegExp(r'\d{4}-\d{2}-\d{2}[:T]\d{2}[-:]\d{2}(?:[-:]\d{2})?'),
        '<programme-start>',
      );
    }
    if (input is List) {
      return input.map(normalize).toList();
    }
    if (input is Map) {
      return <String, Object?>{
        for (final entry in input.entries)
          entry.key as String: normalize(entry.value),
      };
    }
    return input;
  }

  void capture(
    WidgetTester tester,
    List<FakePlayer> players,
    List<Map<String, dynamic>> browse,
    List<IptvZapBanner> banners,
    Map<String, String> aliases,
  ) {
    addonAliases = Map<String, String>.from(aliases);
    final controls = tester.widgetList<Controls>(find.byType(Controls));
    final television = tester.widgetList<TvControls>(find.byType(TvControls));
    final guides = tester.widgetList<IptvChannelSheet>(
      find.byType(IptvChannelSheet),
    );
    value = {
      'browse': [for (final r in browse) Map<String, dynamic>.from(r)],
      'players': [
        for (final p in players)
          {
            'opens': [
              for (final (openIndex, c)
                  in p.calls.where((c) => c.$1 == 'open').indexed)
                for (final media
                    in ((c.$2 as (mk.Playable, bool)).$1 is mk.Media
                        ? [((c.$2 as (mk.Playable, bool)).$1 as mk.Media)]
                        : ((c.$2 as (mk.Playable, bool)).$1 as mk.Playlist)
                              .medias))
                  {
                    'uri': media.uri,
                    // Startup chooses headers on two original asynchronous paths.
                    // Manual boundary assertions retain startup header coverage;
                    // this snapshot compares headers on subsequent opens.
                    if (openIndex > 0) 'headers': media.httpHeaders,
                    'play': (c.$2 as (mk.Playable, bool)).$2,
                  },
            ],
            'audio': [
              for (final c in p.calls.where((c) => c.$1 == 'audio'))
                (c.$2 as mk.AudioTrack).id,
            ],
            'subtitles': [
              for (final c in p.calls.where((c) => c.$1 == 'subtitle'))
                (c.$2 as mk.SubtitleTrack).id,
            ],
          },
      ],
      'controls': [
        for (final c in controls)
          {
            'next': c.onNext != null,
            'previous': c.onPrevious != null,
            'hasNext': c.hasNext,
            'nextChannel': c.onNextChannel != null,
            'hasNextChannel': c.hasNextChannel,
            'hasPrevious': c.hasPrevious,
            'guide': c.onShowIptvChannels != null,
            'hasGuide': c.hasIptvChannels,
            'sources': c.onShowStremioSources != null,
            'hasSources': c.hasStremioSources,
            'liveEdge': c.onLiveEdgeAction != null,
            'liveEdgeActive': c.liveEdgeActionActive,
            'liveEdgeLoading': c.liveEdgeActionLoading,
            'timeline': c.onToggleStartOverTimeline != null,
            'timelineVisible': c.startOverTimelineVisible,
            'hideSeekbar': c.hideSeekbar,
            'hideSpeed': c.hideSpeed,
            'record': c.onRecord != null,
            'hasRecord': c.hasRecord,
          },
      ],
      'tv': [
        for (final c in television)
          {
            'next': c.onNext != null,
            'previous': c.onPrevious != null,
            'nextChannel': c.onNextChannel != null,
            'previousChannel': c.onPreviousChannel != null,
            'guide': c.onShowIptvChannels != null,
            'sources': c.onShowSources != null,
            'live': c.isLive,
            'transitioning': c.isTransitioning,
            'liveEdge': c.onLiveEdgeAction != null,
            'liveEdgeActive': c.liveEdgeActionActive,
            'liveEdgeLoading': c.liveEdgeActionLoading,
            'timeline': c.onToggleStartOverTimeline != null,
            'timelineVisible': c.startOverTimelineVisible,
            'progressFocusable': c.progressFocusable,
          },
      ],
      'guides': [
        for (final g in guides)
          {
            'index': g.currentIndex,
            'channels': [
              for (final c in g.channels)
                {
                  'url': c.url,
                  'name': c.name,
                  'number': c.channelNumber,
                  'group': c.group,
                  'type': c.contentType,
                },
            ],
            'categories': g.categories,
            'category': g.selectedCategory,
            'source': g.sourceId,
            'sourceName': g.sourceName,
            'type': g.contentType,
          },
      ],
      'sources': [
        for (final sheet in tester.widgetList<SourceSheet>(
          find.byType(SourceSheet),
        ))
          {
            'index': sheet.currentSourceIndex,
            'names': [for (final source in sheet.sources) source.name],
          },
      ],
      'banners': [
        for (final b in banners)
          {
            'url': b.channel.url,
            'name': b.channel.name,
            'number': b.channel.channelNumber,
            'group': b.channel.group,
            'flush': b.flush,
            'loading': b.epgLoading,
            'now': b.epg?.now?.title,
            'next': b.epg?.next?.title,
            'archive': b.epg?.now?.hasArchive,
          },
      ],
      'identity': [
        for (final b in tester.widgetList<DebrifyTvBanner>(
          find.byType(DebrifyTvBanner),
        ))
          {
            'number': b.channelNumber,
            'name': b.channelName,
            'title': b.title,
            'flush': b.flush,
          },
      ],
      'reconnecting': find.text('Reconnecting…').evaluate().isNotEmpty,
      'lost': find.text('Stream lost').evaluate().isNotEmpty,
    };
    value = Map<String, Object?>.from(normalize(value) as Map);
  }
}
