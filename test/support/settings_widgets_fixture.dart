import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

const settingsWidgetsCapture = ValueKey('settings-widgets-original-capture');

class SettingsUrlLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  final options = <LaunchOptions>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    this.options.add(options);
    return true;
  }
}

class SettingsRevealCall {
  final double target;
  final Duration duration;
  final Curve curve;
  final SchedulerPhase phase;
  SettingsRevealCall(this.target, this.duration, this.curve, this.phase);
}

class SettingsRecordingScrollController extends ScrollController {
  final calls = <SettingsRevealCall>[];
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SettingsRecordingPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    calls: calls,
  );
}

class _SettingsRecordingPosition extends ScrollPositionWithSingleContext {
  final List<SettingsRevealCall> calls;
  _SettingsRecordingPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.calls,
  });
  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    calls.add(
      SettingsRevealCall(
        to,
        duration,
        curve,
        SchedulerBinding.instance.schedulerPhase,
      ),
    );
    return super.animateTo(to, duration: duration, curve: curve);
  }
}

/// Owns only host resources; borrowed production focus nodes stay host-owned.
class SettingsWidgetsFixture {
  final nodes = <FocusNode>[];
  final events = <KeyEvent>[];
  final callbacks = <String>[];
  final changes = <bool>[];
  final navigator = GlobalKey<NavigatorState>();
  final scroll = SettingsRecordingScrollController();
  final launcher = SettingsUrlLauncher();
  AppTheme app = AppThemes.legacy;
  ThemeData base = ThemeData.dark().copyWith(platform: TargetPlatform.android);
  bool scrollable = false;
  bool blockIgnoredArrows = false;
  double? width;

  FocusNode node(String label) {
    final node = FocusNode(debugLabel: label);
    nodes.add(node);
    return node;
  }

  ConnectionInfo info(
    String title, {
    bool connected = true,
    String status = 'Active',
  }) => ConnectionInfo(
    title: title,
    connected: connected,
    status: status,
    caption: 'Configure $title',
    onTap: () async {
      callbacks.add(title);
    },
  );

  ConnectionsSummary summary({
    bool media = false,
    bool mdblist = false,
    FocusNode? first,
  }) => ConnectionsSummary(
    realDebrid: info('Real Debrid'),
    torbox: info('TorBox'),
    premiumize: info('Premiumize'),
    allDebrid: info('AllDebrid'),
    pikpak: info('PikPak'),
    webDav: info('WebDAV'),
    mediaServers: media ? info('Media servers') : null,
    indexerManagers: info('Indexers'),
    iptv: info('IPTV'),
    tracking: info('Policy'),
    trakt: info('Trakt'),
    simkl: info('Simkl'),
    mdblist: mdblist ? info('MDBList') : null,
    firstCardFocusNode: first,
  );

  Widget host(Widget child) => MaterialApp(
    navigatorKey: navigator,
    locale: const Locale('en', 'US'),
    supportedLocales: const [Locale('en', 'US')],
    theme: base,
    builder: (context, child) => AppThemeScope(
      theme: app,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
    ),
    home: Scaffold(
      body: RepaintBoundary(
        key: settingsWidgetsCapture,
        child: SizedBox.expand(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) {
                  events.add(event);
                  return blockIgnoredArrows &&
                          {
                            LogicalKeyboardKey.arrowLeft,
                            LogicalKeyboardKey.arrowRight,
                            LogicalKeyboardKey.arrowUp,
                            LogicalKeyboardKey.arrowDown,
                          }.contains(event.logicalKey)
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored;
                },
                child: scrollable
                    ? SingleChildScrollView(controller: scroll, child: child)
                    : child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> settingsWidgetsCase(
  WidgetTester tester,
  Future<void> Function(SettingsWidgetsFixture) body, {
  Size size = const Size(1280, 1000),
  bool spotlight = false,
}) async {
  final sidebar = MainPageBridge.focusTvSidebar;
  final androidTv = PlatformUtil.isAndroidTvCached;
  final tvos = PlatformUtil.isTvOS;
  final reason = ProfileBootstrap.legacyReason;
  final launcher = UrlLauncherPlatform.instance;
  final fixture = SettingsWidgetsFixture();
  fixture.app = spotlight ? AppThemes.byId('spotlight') : AppThemes.legacy;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  PlatformUtil.debugSetAndroidTvCached(false);
  PlatformUtil.debugSetTvOS(false);
  MainPageBridge.focusTvSidebar = null;
  UrlLauncherPlatform.instance = fixture.launcher;
  ParallaxTravel.resetForTest();
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    fixture.scroll.dispose();
    for (final node in fixture.nodes) {
      node.dispose();
    }
    MainPageBridge.focusTvSidebar = sidebar;
    PlatformUtil.debugSetAndroidTvCached(androidTv);
    PlatformUtil.debugSetTvOS(tvos);
    ProfileBootstrap.legacyReason = reason;
    UrlLauncherPlatform.instance = launcher;
    ParallaxTravel.resetForTest();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
