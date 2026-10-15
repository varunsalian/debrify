import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'recording_driver.dart';

/// Real addon parsing, candidate resolution, IPTV Play and launcher/navigation.
/// The fixture supplies only the IPTV host dependencies, never player State.
class RecordingStremioLaunch {
  RecordingStremioLaunch(this.d);
  final RecordingDriver d;
  static const unresolved = 'stremio-tv://p13-review/unresolved';
  static const manifest = 'https://p13-recording-addon.test/manifest.json';
  static const stream = 'https://p13-recording-addon.test/stream/tv/live.json';
  late StremioAddon addon;
  late String channelKey;
  final preview = IptvPreviewState();
  Future<void>? playing;

  Future<void> launch() async {
    final t = d.t;
    final f = d.f;
    f.network.replies[manifest] = http.Response(
      jsonEncode({
        'id': 'p13-recording-addon',
        'name': 'Recording reachability',
        'version': '1.0.0',
        'types': ['tv'],
        'resources': ['stream'],
        'catalogs': [],
      }),
      200,
    );
    f.network.replies[stream] = http.Response(
      jsonEncode({
        'streams': [
          {'url': unresolved},
        ],
      }),
      200,
    );
    addon = await f.finish(t, StremioService.instance.addAddon(manifest));
    channelKey = StremioIptvService.buildChannelKey(addon.id, 'live');
    StremioIptvService.instance.invalidate(channelKey);
    final channel = d.channel(channelKey, name: 'Unresolved addon live');
    final catalog = IptvCatalogState()
      ..allChannels = [channel]
      ..filteredChannels = [channel];
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    await d.observe(
      () => t.pumpWidget(
        MaterialApp(
          navigatorKey: f.navigator,
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              final playback = IptvPlayback((
                catalogState: catalog,
                playerState: IptvPlayerState(),
                previewState: preview,
                selectionState: IptvSelectionState(),
                settingsState: IptvSettingsState(),
                adoptStartupCategoryValue: (_) async {},
                context: () => context,
                effectiveCategory: () => null,
                flushPreviewRearm: () {},
                fullCategoryList: () => [],
                isTelevision: () => false,
                mounted: () => context.mounted,
                normalizedName: (value) => value.toLowerCase(),
                openSeriesDetail: (_) async => fail('Live must use Play'),
                originPlaylistIdFor: (_) => null,
                playerChannelWithOrigin: (item, _) => item,
                playerListsPayload: () => [],
                playerSourcePayload: () => [],
                providePlayerIptvBrowse: (_) async => null,
                refreshAfterPlayback: () async {},
              ));
              return Scaffold(
                body: TextButton(
                  onPressed: () => playing = playback.playChannel(channel),
                  child: const Text('IPTV Play'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await d.observe(() => t.tap(find.text('IPTV Play')));
    await f.until(t, () => f.controllers.isNotEmpty);
    expect(d.player.readyDelivered, isFalse);
    d.player.deliverReady();
    await f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
    await f.advance(t, const Duration(milliseconds: 400));
    expect(
      f.network.requests.where((r) => r.url.toString() == stream),
      hasLength(1),
    );
    final candidates = await f.finish(
      t,
      StremioIptvService.instance.resolveCandidates(channelKey),
    );
    expect(candidates.map((c) => c.url), [unresolved]);
    final screen = t.widget<VideoPlayerScreen>(find.byType(VideoPlayerScreen));
    expect(screen.videoUrl, unresolved);
    expect(screen.iptvChannels!.single.url, channelKey);
    final opened =
        d.player.calls.singleWhere((c) => c.$1 == 'open').$2
            as (mk.Playable, bool);
    expect((opened.$1 as mk.Media).uri, unresolved);
    expect(d.offered, isTrue);
  }

  /// A competing capture is installed through the real public service API.
  /// HTTP transport maps only this opaque key to a continuous loopback stream;
  /// no capture list, player field or recording collaborator is injected.
  /// This is a lookup boundary fixture, not a claim that the desktop Record
  /// action admits this non-HTTP key as a new capture.
  Future<DesktopRecordingCapture> competingCapture() async {
    final loopback = await d.loopback();
    final capture = await d.f.finish(
      d.t,
      HttpOverrides.runWithHttpOverrides(
        () => DesktopRecordingService.instance.start(
          url: unresolved,
          path: '${d.f.directory.path}/opaque-key-capture.ts',
          channelName: 'Opaque-key boundary',
          headers: const {},
        ),
        _OpaqueCaptureNetwork(Uri.parse(unresolved), Uri.parse(loopback)),
      ),
    );
    expect(capture, isNotNull);
    await d.captured(unresolved);
    return capture!;
  }

  Future<void> close() async {
    StremioIptvService.instance.invalidate(channelKey);
    await d.f.finish(
      d.t,
      StremioService.instance.removeAddon(addon.storageKey),
    );
    if (d.f.navigator.currentState?.canPop() == true) {
      d.f.navigator.currentState!.pop();
      await d.f.finish(d.t, playing!);
    }
    await d.close();
    preview.previewShown.dispose();
    preview.spotlightProgrammeShown.dispose();
    preview.previewShowing.dispose();
    preview.previewEpoch.dispose();
    preview.previewStreamUrl.dispose();
  }
}

class _OpaqueCaptureNetwork extends HttpOverrides {
  _OpaqueCaptureNetwork(this.key, this.loopback);
  final Uri key;
  final Uri loopback;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OpaqueCaptureClient(super.createHttpClient(context), key, loopback);
}

class _OpaqueCaptureClient implements HttpClient {
  _OpaqueCaptureClient(this.client, this.key, this.loopback);
  final HttpClient client;
  final Uri key;
  final Uri loopback;
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      client.getUrl(url == key ? loopback : url);
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected capture HTTP operation: $invocation');
}
