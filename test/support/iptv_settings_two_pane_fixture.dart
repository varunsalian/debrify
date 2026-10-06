import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const twoPaneCapture = ValueKey('iptv-two-pane-original-capture');

IptvPlaylist twoPaneSource(
  String id, {
  bool xtream = false,
  bool local = false,
  bool shared = false,
  bool redacted = false,
  String password = 'original-password',
  String? epgUrl,
}) => IptvPlaylist(
  id: id,
  name: 'Source $id',
  url: local || xtream ? '' : 'https://fixture.invalid/$id.m3u',
  content: local
      ? '#EXTM3U\n#EXTINF:-1,News\nhttps://fixture.invalid/live.ts\n'
      : null,
  serverUrl: xtream ? 'https://fixture.invalid/panel' : null,
  username: xtream ? 'fixture-user' : null,
  password: password,
  epgUrl: epgUrl,
  addedAt: DateTime.utc(2026, 1, 2),
  connectionReadOnly: shared,
  credentialsRedacted: redacted,
);

class TwoPaneFrameClock {
  int frame = 0;
  int? _scheduled;
  bool _active = true;
  void start() {
    _scheduled = WidgetsBinding.instance.scheduleFrameCallback((_) {
      if (!_active) return;
      frame++;
      start();
    });
  }

  void close() {
    _active = false;
    if (_scheduled != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(_scheduled!);
    }
  }
}

class TwoPaneMethodNode extends FocusNode {
  TwoPaneMethodNode(String label, this.frame) : super(debugLabel: label);
  final int Function() frame;
  final requests = <({int frame, bool attached})>[];
  @override
  void requestFocus([FocusNode? node]) {
    requests.add((frame: frame(), attached: context?.mounted ?? false));
    super.requestFocus(node);
  }
}

/// Exercises only the unchanged public constructor and visible widget tree.
class IptvSettingsTwoPaneFixture {
  final key = GlobalKey<IptvSettingsTwoPaneState>();
  final _frames = TwoPaneFrameClock()..start();
  int get frameNumber => _frames.frame;
  late final url = TwoPaneMethodNode('host-url-method', () => _frames.frame);
  late final file = TwoPaneMethodNode('host-file-method', () => _frames.frame);
  late final xtream = TwoPaneMethodNode(
    'host-xtream-method',
    () => _frames.frame,
  );
  final events = <String>[];
  final escapedKeys = <LogicalKeyboardKey>[];
  List<IptvPlaylist> playlists = [
    twoPaneSource('a'),
    twoPaneSource('b'),
    twoPaneSource('c'),
  ];
  String? defaultId = 'b';
  Set<String> refreshingIds = {};
  List<IptvListMeta> lists = const [
    IptvListMeta(
      id: 'news',
      name: 'News list',
      position: 0,
      isBuiltin: false,
      channelCount: 1,
    ),
    IptvListMeta(
      id: 'sport',
      name: 'Sports list',
      position: 1,
      isBuiltin: false,
      channelCount: 2,
    ),
  ];
  bool openAddSource = false;
  int addMethod = 0;
  int autoRefreshHours = 24;
  bool startupEnabled = false;
  String startupMode = StartupIptvStorage.startupIptvModeLast;
  String startupChannelLabel = 'CH 7 · Pinned';
  String lastLiveChannelLabel = 'CH 9 · Last live';
  bool hasStartupChannel = true;
  bool hasLastLiveChannel = true;
  bool preview = true;
  bool track = true;
  bool appearance = true;
  String iptvStyle = 'command';
  String playerGuideStyle = 'classic';
  bool recording = true;
  bool showEngineToggle = true;
  bool engine = true;
  int scheduledCount = 3;
  int maxConcurrent = 2;
  bool? batteryExempt = true;
  bool autoRefreshAction = true;
  bool hiddenAction = true;
  bool categoryAction = true;
  Map<String, int> hiddenCounts = {};
  String look = 'spotlight';

  late final ValueChanged<bool> toggleStartup = _boolCallback('startup');
  late final ValueChanged<bool> toggleTrack = _boolCallback('track');
  late final ValueChanged<bool> togglePreview = _boolCallback('preview');
  late final ValueChanged<bool> toggleEngine = _boolCallback('engine');
  late final VoidCallback pickAutoRefresh = _callback('auto-refresh');
  late final VoidCallback createList = _callback('create-list');
  late final VoidCallback manageOrder = _callback('channel-order');
  late final VoidCallback pickStartup = _callback('pick-startup');
  late final VoidCallback focusForm = _callback('form-focus');

  ValueChanged<bool> _boolCallback(String action) =>
      (v) => events.add('$action $v');
  VoidCallback _callback(String action) =>
      () => events.add(action);

  IptvSettingsTwoPane widget() => IptvSettingsTwoPane(
    key: key,
    playlists: playlists,
    defaultPlaylistId: defaultId,
    refreshingIds: refreshingIds,
    autoRefreshHours: autoRefreshHours,
    onPickAutoRefresh: autoRefreshAction ? pickAutoRefresh : null,
    customLists: lists,
    startupEnabled: startupEnabled,
    startupMode: startupMode,
    startupChannelLabel: startupChannelLabel,
    lastLiveChannelLabel: lastLiveChannelLabel,
    hasStartupChannel: hasStartupChannel,
    hasLastLiveChannel: hasLastLiveChannel,
    addMethod: addMethod,
    onAddMethodChanged: (v) => events.add('method $v'),
    urlFormBuilder: (_) => const Text('URL FORM'),
    fileFormBuilder: (_) => const Text('FILE FORM'),
    xtreamFormBuilder: (_) => const Text('XTREAM FORM'),
    urlMethodFocusNode: url,
    fileMethodFocusNode: file,
    xtreamMethodFocusNode: xtream,
    onSetDefault: (p) => events.add('default ${p.id}'),
    onRefresh: (p) => events.add('refresh ${p.id}'),
    onEdit: (p) => events.add('edit ${p.id}'),
    onDelete: (p) => events.add('delete ${p.id}'),
    onCreateList: createList,
    onManageChannelOrder: manageOrder,
    onManageCategoryOrder: categoryAction
        ? (p) => events.add('category ${p.id}')
        : null,
    onManageHidden: hiddenAction ? (p) => events.add('hidden ${p.id}') : null,
    hiddenCounts: hiddenCounts,
    onFocusFirstFormField: focusForm,
    onListActions: (l) => events.add('list ${l.id}'),
    onToggleStartup: toggleStartup,
    onStartupModeChanged: (v) => events.add('mode $v'),
    onPickStartupChannel: pickStartup,
    channelPreviewEnabled: preview,
    onToggleChannelPreview: togglePreview,
    trackContinueWatching: track,
    onToggleTrackContinueWatching: toggleTrack,
    showAppearanceSection: appearance,
    iptvStyle: iptvStyle,
    onIptvStyleChanged: (v) => events.add('style $v'),
    playerGuideStyle: playerGuideStyle,
    onPlayerGuideStyleChanged: (v) => events.add('guide $v'),
    showRecordingSection: recording,
    showEngineToggle: showEngineToggle,
    recordingEngineEnabled: engine,
    scheduledCount: scheduledCount,
    onToggleRecordingEngine: toggleEngine,
    onOpenScheduledRecordings: () => events.add('recordings'),
    maxConcurrentRecordings: maxConcurrent,
    onPickMaxConcurrent: () => events.add('max-concurrent'),
    batteryExempt: batteryExempt,
    onRequestBatteryExemption: () => events.add('battery'),
    openAddSource: openAddSource,
  );

  Widget host() => RepaintBoundary(
    key: twoPaneCapture,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en', 'US'),
      theme: ThemeData(
        brightness: Brightness.dark,
        platform: TargetPlatform.macOS,
        fontFamily: 'Inter',
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: AppThemeScope(
            theme: PremiumLooks.byId(look)!.build(),
            child: Scaffold(
              body: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    escapedKeys.add(event.logicalKey);
                  }
                  return KeyEventResult.handled;
                },
                child: widget(),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(host());
    await frame(tester);
  }

  Future<void> frame(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 16));
  Future<void> refresh(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await frame(tester);
  }

  Finder pieces(String suffix) => find.byWidgetPredicate(
    (w) =>
        w.runtimeType.toString() == '_$suffix' ||
        w.runtimeType.toString() == 'IptvTwoPane$suffix',
  );
  Finder get railEntries => pieces('RailEntry');
  Finder get paneRows =>
      pieces('PaneRow').evaluate().isEmpty ? pieces('Row') : pieces('PaneRow');
  Finder row(String title) => find.byWidgetPredicate(
    (w) =>
        (w.runtimeType.toString() == '_PaneRow' ||
            w.runtimeType.toString() == 'IptvTwoPaneRow') &&
        (w as dynamic).title == title,
  );
  List<dynamic> rails(WidgetTester tester) {
    final rail = tester
        .widgetList<ListView>(find.byType(ListView))
        .firstWhere((w) => w.key == null);
    return (rail.childrenDelegate as SliverChildListDelegate).children
        .where(
          (w) =>
              w.runtimeType.toString() == '_RailEntry' ||
              w.runtimeType.toString() == 'IptvTwoPaneRailEntry',
        )
        .cast<dynamic>()
        .toList();
  }

  Future<void> focusIndex(WidgetTester tester, int index) async {
    final dynamic entry = rails(tester)[index];
    final node = entry.focusNode as FocusNode;
    if (node.context == null) {
      final rail = tester
          .widgetList<ListView>(find.byType(ListView))
          .firstWhere((w) => w.key == null);
      rail.controller!.jumpTo(
        (index * 70.0).clamp(0.0, rail.controller!.position.maxScrollExtent),
      );
      await frame(tester);
    }
    expect(node.context, isNotNull, reason: 'rail entry $index attached');
    node.requestFocus();
    await frame(tester);
  }

  Future<void> destination(WidgetTester tester, String title) async {
    final entries = rails(tester);
    final index = entries.indexWhere((e) => e.title == title);
    expect(index, greaterThanOrEqualTo(0));
    await focusIndex(tester, index);
  }

  Future<void> keyEvent(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await frame(tester);
  }

  Future<void> repeat(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await frame(tester);
    await tester.sendKeyRepeatEvent(key);
    await frame(tester);
    await tester.sendKeyUpEvent(key);
  }

  Future<void> mouse(
    WidgetTester tester,
    Offset point, {
    bool click = false,
  }) async {
    final pointer = TestPointer(17, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(
      pointer.addPointer(location: Offset.zero),
    );
    tester.binding.handlePointerEvent(pointer.hover(point));
    if (click) {
      tester.binding.handlePointerEvent(pointer.down(point));
      tester.binding.handlePointerEvent(pointer.up());
    }
    await frame(tester);
    tester.binding.handlePointerEvent(pointer.removePointer());
  }

  List<FocusNode> get methods => [url, file, xtream];
  void clearRequests() {
    for (final node in [url, file, xtream]) {
      node.requests.clear();
    }
  }

  String get paneKey =>
      (find
                      .byType(ListView)
                      .evaluate()
                      .map((e) => e.widget)
                      .where((w) => w.key != null)
                      .single
                      .key!
                  as ValueKey)
              .value
          as String;
  Future<void> close(WidgetTester tester) async {
    _frames.close();
    await tester.pumpWidget(const SizedBox.shrink());
    for (final node in methods) {
      node.dispose();
    }
    tester.view.reset();
  }
}

Future<void> twoPaneCase(
  WidgetTester tester,
  Future<void> Function(IptvSettingsTwoPaneFixture) body,
) async {
  final f = IptvSettingsTwoPaneFixture();
  try {
    await body(f);
  } finally {
    await f.close(tester);
  }
}
