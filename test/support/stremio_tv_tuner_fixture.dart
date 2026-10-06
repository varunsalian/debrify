import 'dart:async';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/stremio_tv_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const tunerCapture = ValueKey('tuner-original-capture');

class TunerServiceFake implements StremioTvService {
  final now = <String, StremioTvNowPlaying?>{};
  final next = <String, StremioTvNowPlaying?>{};
  final calls = <(String, String, int?, int)>[];
  @override
  StremioTvNowPlaying? getNowPlaying(
    StremioTvChannel channel, {
    int rotationMinutes = 90,
    int salt = 0,
  }) {
    calls.add(('now', channel.id, rotationMinutes, salt));
    return now[channel.id];
  }

  @override
  StremioTvNowPlaying? getNextPlaying(
    StremioTvChannel channel, {
    int rotationMinutes = 90,
    int salt = 0,
  }) {
    calls.add(('next', channel.id, rotationMinutes, salt));
    return next[channel.id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StremioTvNowPlaying tunerPlaying(
  String id, {
  bool artwork = false,
  bool future = false,
}) => StremioTvNowPlaying(
  item: StremioMeta(
    id: 'item-$id',
    type: 'movie',
    name: 'Broadcast $id',
    description: 'A deterministic broadcast description for $id. ' * 12,
    genres: const ['Drama'],
    year: '2020',
    imdbRating: 7.5,
    background: artwork ? 'https://artwork.test/backdrop-$id.png' : null,
    poster: artwork ? 'https://artwork.test/poster-$id.png' : null,
  ),
  itemIndex: 0,
  slotStart: DateTime.utc(future ? 2035 : 2020, 1, 1),
  slotEnd: DateTime.utc(future ? 2035 : 2020, 1, 1, 1),
);

/// The public host contract; no access to private tuner members.
class StremioTvTunerFixture {
  final tunerKey = GlobalKey();
  final navigatorKey = GlobalKey<NavigatorState>();
  StremioTvTunerController? controller = StremioTvTunerController();
  final service = TunerServiceFake();
  final channels = <StremioTvChannel>[];
  final allChannels = <StremioTvChannel>[];
  final nodes = <FocusNode>[];
  final ownedNodes = <FocusNode>[];
  final events = <String>[];
  final focused = <int>[];
  final haptics = <String>[];
  final periodicTimers = <(Duration, Timer)>[];
  final loading = <String>{};
  final progress = <(String, double)>[];
  bool television = true;
  bool hideNowPlaying = false;
  bool autoRefresh = false;
  bool disableAnimations = false;
  String look = 'spotlight';
  TargetPlatform platform = TargetPlatform.macOS;
  bool localCallbacks = true;
  void _recordHeaderFocus() => events.add('header');
  late final VoidCallback focusHeader = _recordHeaderFocus;

  StremioTvTunerFixture({
    int count = 6,
    bool artwork = false,
    bool duplicate = false,
  }) {
    final addon = StremioAddon(
      id: 'fixture',
      name: 'Fixture',
      manifestUrl: 'https://metadata.test/manifest.json',
      baseUrl: 'https://metadata.test',
    );
    for (var i = 0; i < count; i++) {
      final channel = StremioTvChannel(
        id: 'channel-$i',
        displayName: i == 1 ? 'Local Cinema' : 'Channel ${i + 1}',
        addon: addon,
        catalog: StremioAddonCatalog(
          id: 'catalog-$i',
          type: 'movie',
          name: 'Cinema',
        ),
        channelNumber: i + 1,
        isLocal: i == 1,
        isFavorite: i == 2,
      );
      channels.add(channel);
      service.now[channel.id] = tunerPlaying(channel.id, artwork: artwork);
    }
    if (duplicate) {
      final c = channels[1];
      allChannels.add(
        StremioTvChannel(
          id: c.id,
          displayName: 'Earlier duplicate',
          addon: addon,
          catalog: c.catalog,
          channelNumber: 99,
        ),
      );
    }
    allChannels.addAll(channels);
    for (var i = 0; i < allChannels.length; i++) {
      final node = FocusNode(debugLabel: 'host-row-$i');
      nodes.add(node);
      ownedNodes.add(node);
    }
  }

  Widget tuner() => StremioTvTuner(
    key: tunerKey,
    channels: channels,
    allChannels: allChannels,
    rowFocusNodes: nodes,
    service: service,
    rotationFor: (_) => 37,
    mixSalt: 19,
    hideNowPlaying: hideNowPlaying,
    autoRefresh: autoRefresh,
    isTelevision: television,
    loadingChannelIds: loading,
    ensureLoaded: (c) => events.add('load ${c.id}'),
    onOpenDetail: (c) => events.add('detail ${c.id}'),
    onPlay: (c) => events.add('play ${c.id}'),
    displayProgress: (c, raw) {
      progress.add((c.id, raw));
      return 0.4;
    },
    onToggleFavorite: (c) => events.add('favorite ${c.id}'),
    onShowGuide: (c) => events.add('guide ${c.id}'),
    onEditLocal: localCallbacks ? (c) => events.add('edit ${c.id}') : null,
    onExportLocal: localCallbacks ? (c) => events.add('export ${c.id}') : null,
    onFocusSidebar: () => events.add('sidebar'),
    onFocusHeader: focusHeader,
    onFocusedIndexChanged: focused.add,
    controller: controller,
  );

  Widget host({Widget? child}) => RepaintBoundary(
    key: tunerCapture,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en', 'US'),
      theme: ThemeData(brightness: Brightness.dark, platform: platform),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
            disableAnimations: disableAnimations,
          ),
          child: AppThemeScope(
            theme: PremiumLooks.byId(look)!.build(),
            child: Scaffold(body: child ?? tuner()),
          ),
        ),
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1920, 1080),
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(host());
    await tester.pump();
  }

  Future<void> refresh(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
  }

  Future<void> focus(WidgetTester tester, int index) async {
    nodes[index].requestFocus();
    await tester.pump();
    await tester.pump();
  }

  Finder get cards => find.byWidgetPredicate(
    (w) =>
        w.runtimeType.toString() == '_DialCard' ||
        w.runtimeType.toString() == 'StremioTvTunerDialCard',
  );
  Finder get stages => find.byWidgetPredicate(
    (w) =>
        w.runtimeType.toString() == '_Stage' ||
        w.runtimeType.toString() == 'StremioTvTunerStage',
  );
  Finder card(int index) => find.byKey(ValueKey(channels[index].id));
  Focus focusWidget(int index, WidgetTester tester) => tester.widget<Focus>(
    find.descendant(of: card(index), matching: find.byType(Focus)).first,
  );
  Future<void> close(WidgetTester tester) async {
    while (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final node in ownedNodes) {
      node.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  }
}

Future<void> tunerCase(
  WidgetTester tester,
  Future<void> Function(StremioTvTunerFixture) body, {
  int count = 6,
  bool artwork = false,
  bool duplicate = false,
}) async {
  final fixture = StremioTvTunerFixture(
    count: count,
    artwork: artwork,
    duplicate: duplicate,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      fixture.haptics.add(call.arguments as String);
    }
    return null;
  });
  for (final channel in [
    'plugins.flutter.io/path_provider',
    'com.tekartik.sqflite',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      fail('Artwork loader reached $channel: ${call.method}');
    });
  }
  try {
    await runZoned(
      () => body(fixture),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createPeriodicTimer(zone, duration, callback);
          fixture.periodicTimers.add((duration, timer));
          return timer;
        },
      ),
    );
  } finally {
    await fixture.close(tester);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    for (final channel in [
      'plugins.flutter.io/path_provider',
      'com.tekartik.sqflite',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  }
}
