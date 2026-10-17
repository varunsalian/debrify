import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'iptv_output_observation.dart';
import 'fake_player.dart';
import 'player_actions.dart';
import 'trakt_transport.dart';
import 'video_player_environment.dart';

export 'package:debrify/models/iptv_playlist.dart';
export 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
export 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
export 'package:debrify/screens/video_player_screen.dart';
export 'package:debrify/services/iptv_epg_service.dart';
export 'package:debrify/services/stremio_iptv_service.dart';
export 'package:flutter/material.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:http/http.dart' show Response, Request;
export 'fake_player.dart';
export 'player_actions.dart';
export 'video_player_environment.dart';

IptvChannel iptvChannel(
  int id, {
  String? group = 'News',
  bool live = true,
  String? url,
  Map<String, String> attributes = const {},
  Map<String, String> headers = const {},
}) => IptvChannel(
  name: 'P15 channel $id',
  url: url ?? 'https://p15.test/$id.ts',
  contentType: live ? 'live' : 'vod',
  group: group,
  channelNumber: id,
  attributes: attributes,
  httpHeaders: headers,
);

Map<String, dynamic> iptvPage(
  List<IptvChannel> channels, {
  int offset = 0,
  int? total,
  String? category = 'News',
  List<String> categories = const ['News'],
  String? source = 'ring-source',
}) => {
  'channels': [
    for (final c in channels)
      {
        'url': c.url,
        'name': c.name,
        'group': c.group,
        'contentType': c.contentType,
        'channelNumber': c.channelNumber,
      },
  ],
  'pageOffset': offset,
  'totalChannels': total ?? offset + channels.length,
  'selectedCategory': category,
  'categories': categories,
  'sourceId': source,
};

/// Public callers only. Open acknowledgement and later probe events are
/// deliberately independent; the default fake emits its frame before return.
class IptvWorkflowDriver {
  IptvWorkflowDriver(
    this.t, {
    bool native = false,
    void Function(FakePlayer)? configurePlayer,
  }) : f = VideoPlayerEnvironment(
         native: native,
         configurePlayer: configurePlayer,
       ) {
    addTearDown(() {
      expect(
        _requestBudgetExceeded,
        false,
        reason:
            'Finite fixture inputs must not issue an unbounded page sequence',
      );
    });
  }
  final WidgetTester t;
  final outputObservation = IptvOutputObservation();
  final VideoPlayerEnvironment f;
  final errors = <Object>[];
  final timed = <(Duration, Timer)>[];
  final periodic = <(Duration, Timer)>[];
  final timerCreatedAt = <Timer, DateTime>{};
  final timerOwners = <Timer, String>{};
  final browse = <Map<String, dynamic>>[];
  final addonAliases = <String, String>{};
  final gates = <Completer<void>>[];
  FutureOr<Map<String, dynamic>?> Function(Map<String, dynamic>)? provider;
  FutureOr<http.Response> Function(http.Request)? response;
  bool disposed = false;
  bool _requestBudgetExceeded = false;
  FakePlayer get player => f.player;
  List<(String, Object?)> calls(String name) =>
      player.calls.where((c) => c.$1 == name).toList();
  List<String> get opened => calls(
    'open',
  ).map((c) => ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri).toList();
  String get playingUrl => player.state.playlist.medias.single.uri;
  T observe<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (s, p, z, e, st) => errors.add(e),
      createTimer: (s, p, z, d, cb) {
        final timer = p.createTimer(z, d, cb);
        timed.add((d, timer));
        timerCreatedAt[timer] = t.binding.clock.now();
        timerOwners[timer] = StackTrace.current
            .toString()
            .split('\n')
            .firstWhere(
              (v) => v.contains('package:debrify/'),
              orElse: () => 'fixture',
            );
        return timer;
      },
      createPeriodicTimer: (s, p, z, d, cb) {
        final timer = p.createPeriodicTimer(z, d, cb);
        periodic.add((d, timer));
        return timer;
      },
    ),
  );
  Future<void> initialize() async {
    await t.runAsync(f.initialize);
    TraktTestTransport.instance.attach(f);
    SecretVault.debugReset(deviceIdOverride: 'p15-fixture-device');
    await t.runAsync(SecretVault.warmUp);
    f.network.handler = (r) => response?.call(r) ?? http.Response('{}', 404);
  }

  VideoPlayerScreen screen(
    List<IptvChannel> channels, {
    int index = 0,
    bool paged = false,
    String? source = 'launch-source',
    String? initialUrl,
  }) => VideoPlayerScreen(
    videoUrl: initialUrl ?? channels[index].url,
    title: channels[index].name,
    iptvChannels: channels,
    iptvStartIndex: index,
    iptvSourceId: source,
    iptvBrowseProvider: !paged
        ? null
        : (request) async {
            browse.add(Map<String, dynamic>.from(request));
            // The original fixtures issue at most five requests. A malformed
            // paging loop must yield to the test clock instead of starving
            // both Flutter's timeout and the teardown assertion. This is a
            // fixture transport budget, never an application retry policy.
            if (browse.length > 32) {
              _requestBudgetExceeded = true;
              final pause = Completer<void>();
              gates.add(pause);
              await pause.future;
              return null;
            }
            return await provider?.call(request);
          },
  );
  Future<void> mount(
    List<IptvChannel> channels, {
    int index = 0,
    bool paged = false,
    String? source = 'launch-source',
    String? initialUrl,
  }) async {
    await observe(
      () => f.mount(
        t,
        screen(
          channels,
          index: index,
          paged: paged,
          source: source,
          initialUrl: initialUrl,
        ),
      ),
    );
    await f.until(
      t,
      () => periodic.any((v) => v.$1 == const Duration(seconds: 6)),
    );
    await settle();
  }

  Future<void> settle() => f.actions.settle(t);
  Future<void> advance(Duration d) => f.advance(t, d);
  Future<void> timerAge(Timer timer, Duration age) {
    final remaining =
        age - t.binding.clock.now().difference(timerCreatedAt[timer]!);
    expect(remaining.isNegative, false);
    return advance(remaining);
  }

  Future<IptvChannelSheet> guide() async {
    final open = playerControls(t).onShowIptvChannels;
    expect(open, isNotNull, reason: 'The player must expose its IPTV guide');
    open!();
    await f.advance(t, const Duration(milliseconds: 350));
    expect(find.byType(IptvChannelSheet), findsOneWidget);
    return t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
  }

  Future<void> closeGuide(IptvChannelSheet sheet) async {
    sheet.onClose();
    await f.advance(t, const Duration(milliseconds: 350));
  }

  Future<SourceSheet> sources() async {
    expect(playerControls(t).onShowStremioSources, isNotNull);
    playerControls(t).onShowStremioSources!();
    await f.advance(t, const Duration(milliseconds: 350));
    return t.widget<SourceSheet>(find.byType(SourceSheet));
  }

  Future<void> zap(int direction) async {
    final controls = playerControls(t);
    final press = direction > 0 ? controls.onNext : controls.onPrevious;
    expect(
      press,
      isNotNull,
      reason: 'The player must expose the requested IPTV zap direction',
    );
    observe(press!);
    await settle();
  }

  Future<void> pick(List<IptvChannel> channels, int index) async {
    final sheet = await guide();
    await f.finish(t, observe(() => sheet.onChannelSelected(channels, index)));
    await settle();
  }

  Completer<void> holdOperation(String name, {String? url}) {
    final gate = Completer<void>();
    gates.add(gate);
    final previous = player.beforeOperation;
    player.heldOperation = (n, v) => n == name;
    player.beforeOperation = (n, v) async {
      await previous?.call(n, v);
      final matches =
          url == null ||
          n == 'open' && ((v as (mk.Playable, bool)).$1 as mk.Media).uri == url;
      if (n == name && matches && !gate.isCompleted) {
        await gate.future;
      }
    };
    return gate;
  }

  void probeMode() {
    player.onOpen = () {};
  }

  Future<void> probeEvent(String event) async {
    if (event == 'width') {
      player.emit<int?>('width', 1280);
    }
    if (event == 'position') {
      player.emit('position', const Duration(milliseconds: 80));
    }
    if (event == 'error') {
      player.emit('error', 'probe failure');
    }
    await settle();
  }

  Future<IptvChannel> installAddon(
    String id, {
    List<String> urls = const [
      'https://probe.test/first.ts',
      'https://probe.test/second.ts',
    ],
  }) async {
    final service = StremioService.instance;
    service.invalidateCache();
    service.debugManifestFetcher = (url) async => StremioAddon.fromManifest({
      'id': 'p15.$id',
      'name': 'P15 $id',
      'version': '1.0.0',
      'resources': ['stream'],
      'types': ['tv'],
      'catalogs': [],
    }, url);
    final installed = await t.runAsync(
      () => service.addAddon('https://p15-$id.test/manifest.json'),
    );
    service.debugManifestFetcher = null;
    response = (r) => r.url.path.contains('/stream/tv/')
        ? http.Response(
            jsonEncode({
              'streams': [
                for (var i = 0; i < urls.length; i++)
                  {'url': urls[i], 'name': 'Candidate $i'},
              ],
            }),
            200,
          )
        : http.Response('{}', 404);
    addonAliases[installed!.id] =
        'fixture-addon-${addonAliases.length + 1}-$id';
    return iptvChannel(
      100,
      url: StremioIptvService.buildChannelKey(installed.id, id),
      headers: const {'X-P15': 'channel-header'},
    );
  }

  Future<void> retire() async {
    await t.pumpWidget(const SizedBox.shrink());
    disposed = true;
    await f.until(t, () => f.players.every((p) => p.disposed.isCompleted));
  }

  Future<void> close() async {
    try {
      outputObservation.capture(t, f.players, browse, banners, addonAliases);
    } finally {
      for (final g in gates) {
        if (!g.isCompleted) {
          g.complete();
        }
      }
      // Retire first so the recovery watchdog cannot start another probe while
      // finite issued probes drain. Streams and transport stay open until then.
      if (!disposed) {
        await retire();
      }
      await advance(const Duration(seconds: 13));
      await settle();
      await f.close(t);
      TraktTestTransport.instance.recorder = null;
    }
  }

  List<IptvZapBanner> get banners =>
      t.widgetList<IptvZapBanner>(find.byType(IptvZapBanner)).toList();
}

EpgProgramme iptvProgramme({
  String title = 'P15 replay',
  bool airing = false,
  bool archive = true,
}) {
  final now = DateTime.now();
  return EpgProgramme(
    title: title,
    description: '',
    start: airing
        ? now.subtract(const Duration(minutes: 20))
        : DateTime(2020, 1, 1, 1),
    stop: airing
        ? now.add(const Duration(minutes: 40))
        : DateTime(2020, 1, 1, 2),
    hasArchive: archive,
  );
}

http.Response iptvPanelReply(
  http.Request request, {
  String title = 'P15 current programme',
  bool archive = true,
  DateTime? stop,
}) {
  if (request.url.path.contains('/timeshift/')) {
    return http.Response('', 200);
  }
  if (request.url.path == '/player_api.php') {
    final now = DateTime.now();
    final start = now.subtract(const Duration(minutes: 20));
    final end = stop ?? now.add(const Duration(minutes: 40));
    return http.Response(
      jsonEncode({
        'epg_listings': [
          {
            'id': '1',
            'title': base64Encode(utf8.encode(title)),
            'description': '',
            'start_timestamp': '${start.millisecondsSinceEpoch ~/ 1000}',
            'stop_timestamp': '${end.millisecondsSinceEpoch ~/ 1000}',
            'has_archive': archive ? 1 : 0,
          },
        ],
      }),
      200,
    );
  }
  return http.Response('{}', 404);
}
