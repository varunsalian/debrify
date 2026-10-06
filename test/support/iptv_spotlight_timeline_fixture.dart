import 'dart:async';
import 'dart:collection';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const timelineCapture = ValueKey('timeline-original-capture');
IptvChannel timelineChannel(int index, {bool live = true, String? logo}) =>
    IptvChannel(
      name: 'Channel $index',
      url: 'channel-$index',
      duration: live ? -1 : 90,
      contentType: live ? 'live' : 'vod',
      channelNumber: index + 1,
      logoUrl: logo,
    );
EpgProgramme timelineProgramme(
  String title,
  DateTime start, {
  int minutes = 30,
  bool archive = false,
}) => EpgProgramme(
  title: title,
  description: 'Guide description',
  start: start,
  stop: start.add(Duration(minutes: minutes)),
  hasArchive: archive,
);

class TimelineScheduleCall {
  final IptvChannel channel;
  final completer = Completer<List<EpgProgramme>>();
  TimelineScheduleCall(this.channel);
  void resolve(List<EpgProgramme> programmes) => completer.complete(programmes);
  void fail() => completer.completeError(StateError('offline'));
}

class TimelineScheduleScript {
  final calls = <TimelineScheduleCall>[];
  Future<List<EpgProgramme>> load(IptvChannel channel) {
    final call = TimelineScheduleCall(channel);
    calls.add(call);
    return call.completer.future;
  }

  List<TimelineScheduleCall> forChannel(IptvChannel channel) =>
      calls.where((call) => identical(call.channel, channel)).toList();
}

class TimelineLazyChannels extends ListBase<IptvChannel> {
  @override
  final int length;
  final resident = <int, IptvChannel>{};
  final reads = <int>[];
  Set<int>? allowed;
  TimelineLazyChannels(this.length);
  @override
  IptvChannel operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    if (allowed != null && !allowed!.contains(index)) {
      throw StateError('Unexpected channel read $index');
    }
    reads.add(index);
    return resident.putIfAbsent(index, () => timelineChannel(index));
  }

  @override
  void operator []=(int index, IptvChannel value) =>
      throw UnsupportedError('read-only');
  @override
  set length(int value) => throw UnsupportedError('read-only');
}

/// Public host only: no private State access or production test hooks.
class IptvSpotlightTimelineFixture {
  List<IptvChannel> channels;
  final script = TimelineScheduleScript();
  SpotlightScheduleLoader? loader;
  final selections = <SpotlightTimelineSelection>[];
  final activated = <SpotlightTimelineEntry>[];
  final programmes = <EpgProgramme>[];
  final actions = <SpotlightTimelineEntry>[];
  final exits = <String>[];
  IptvSpotlightTimelineController? controller =
      IptvSpotlightTimelineController();
  String sourceId = 'source';
  int loadGeneration = 1;
  int contextVersion = 0;
  DateTime clock = DateTime(2030, 1, 1, 10, 20);
  int clockReads = 0;
  DateTime? initialWindowStart;
  Duration windowDuration = const Duration(minutes: 90);
  Duration? settleDelay;
  double width = 1280,
      height = 360,
      rowHeight = 68,
      rulerHeight = 42,
      identityWidth = 280;
  double textScale = 1;
  bool dense = false,
      autofocus = true,
      selectBeforeActivate = true,
      enableActions = false;
  TargetPlatform platform = TargetPlatform.macOS;
  String fontFamily = 'Roboto';
  SpotlightChannelActivate? channelCallback, actionsCallback;
  SpotlightProgrammeActivate? programmeCallback;
  ValueChanged<SpotlightTimelineSelection>? selectionCallback;
  VoidCallback? upCallback, leftCallback;
  DateTime Function()? nowCallback;
  IptvSpotlightTimelineFixture({int count = 8, List<IptvChannel>? channels})
    : channels = channels ?? List.generate(count, timelineChannel);
  DateTime now() {
    clockReads++;
    return clock;
  }

  Widget host() => RepaintBoundary(
    key: timelineCapture,
    child: MaterialApp(
      locale: const Locale('en', 'US'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        platform: platform,
        fontFamily: fontFamily,
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SpotlightLiveTimeline(
                  channels: channels,
                  sourceId: sourceId,
                  loadGeneration: loadGeneration,
                  epgContextVersion: contextVersion,
                  controller: controller,
                  scheduleLoader: loader ?? script.load,
                  onChannelActivate: channelCallback ?? activated.add,
                  onProgrammeActivate:
                      programmeCallback ?? (_, p) => programmes.add(p),
                  onSelectionChanged: selectionCallback ?? selections.add,
                  onChannelActions: enableActions
                      ? (actionsCallback ?? actions.add)
                      : null,
                  onExitUp: upCallback ?? () => exits.add('up'),
                  onExitLeft: leftCallback ?? () => exits.add('left'),
                  now: nowCallback ?? now,
                  initialWindowStart: initialWindowStart,
                  windowDuration: windowDuration,
                  viewportSettleDelay:
                      settleDelay ?? const Duration(milliseconds: 375),
                  height: height,
                  rowHeight: rowHeight,
                  rulerHeight: rulerHeight,
                  identityWidth: identityWidth,
                  dense: dense,
                  autofocus: autofocus,
                  selectBeforeActivate: selectBeforeActivate,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 360),
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(settleDelay ?? const Duration(milliseconds: 375));
    await tester.pump();
  }

  ScrollController scroll(WidgetTester tester) => tester
      .widget<ListView>(
        find.byKey(const ValueKey('spotlight-live-timeline-rows')),
      )
      .controller!;
  FocusNode node(WidgetTester tester) => tester
      .widget<Focus>(
        find.byWidgetPredicate(
          (w) =>
              w is Focus &&
              w.focusNode?.debugLabel == 'spotlight-live-timeline',
        ),
      )
      .focusNode!;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  }
}

Future<void> timelineCase(
  WidgetTester tester,
  Future<void> Function(IptvSpotlightTimelineFixture) body, {
  int count = 8,
  List<IptvChannel>? channels,
}) async {
  final f = IptvSpotlightTimelineFixture(count: count, channels: channels);
  try {
    await body(f);
  } finally {
    await f.close(tester);
  }
}
