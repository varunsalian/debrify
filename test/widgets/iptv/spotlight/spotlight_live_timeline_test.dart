import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Tristate;

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long channel names have two readable lines beside the logo', (
    tester,
  ) async {
    const name = '4K: SKY SPORTS MAIN EVENTS UHD';
    await tester.pumpWidget(
      _host(
        channels: [
          IptvChannel(
            name: name,
            url: 'test-channel',
            duration: -1,
            contentType: 'live',
            channelNumber: 14,
          ),
        ],
        loader: (_) async => const [],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final label = tester.renderObject<RenderParagraph>(find.text(name));
    expect(label.size.width, greaterThanOrEqualTo(200));
    expect(label.didExceedMaxLines, isFalse);
    expect(find.text('Channel 14'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dense rows keep long names visible at larger text sizes', (
    tester,
  ) async {
    final controller = IptvSpotlightTimelineController();
    final channels = List.generate(
      12,
      (i) => IptvChannel(
        name: '4K: SKY SPORTS MAIN EVENTS UHD $i',
        url: 'channel-$i',
        duration: -1,
        contentType: 'live',
        channelNumber: i,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SpotlightLiveTimeline(
              channels: channels,
              sourceId: 'source',
              loadGeneration: 0,
              epgContextVersion: 0,
              scheduleLoader: (_) async => const [],
              onChannelActivate: (_) {},
              onProgrammeActivate: (_, __) {},
              controller: controller,
              identityWidth: 300,
              rowHeight: 46,
              rulerHeight: 32,
              dense: true,
              height: 240,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    controller.focusChannelAt(6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final labelFinder = find.text(channels[6].name);
    final label = tester.renderObject<RenderParagraph>(labelFinder);
    expect(label.maxLines, 2);
    expect(label.size.width, greaterThan(220));
    expect(label.size.height, greaterThan(30));
    final guide = tester.getRect(find.byType(SpotlightLiveTimeline));
    final labelRect = tester.getRect(labelFinder);
    expect(guide.contains(labelRect.topLeft), isTrue);
    expect(guide.contains(labelRect.bottomRight), isTrue);
    expect(controller.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scaled names fit and focused rows remain visible after scaling',
    (tester) async {
      final controller = IptvSpotlightTimelineController();
      final channels = List.generate(
        12,
        (i) => IptvChannel(
          name: '4K: SKY SPORTS MAIN EVENTS UHD $i',
          url: 'channel-$i',
          duration: -1,
          contentType: 'live',
          channelNumber: i,
        ),
      );
      Widget host(double scale) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SpotlightLiveTimeline(
              channels: channels,
              sourceId: 'source',
              loadGeneration: 0,
              epgContextVersion: 0,
              scheduleLoader: (_) async => const [],
              onChannelActivate: (_) {},
              onProgrammeActivate: (_, __) {},
              controller: controller,
              identityWidth: 260,
              rowHeight: 64,
              height: 240,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(1));
      controller.focusChannelAt(6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(host(1.3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final label = tester.getRect(find.text(channels[6].name));
      final guide = tester.getRect(find.byType(SpotlightLiveTimeline));
      expect(guide.contains(label.topLeft), isTrue);
      expect(guide.contains(label.bottomRight), isTrue);
      expect(controller.hasFocus, isTrue);
      final rows = tester.widget<ListView>(
        find.descendant(
          of: find.byType(SpotlightLiveTimeline),
          matching: find.byType(ListView),
        ),
      );
      expect(rows.itemExtent, greaterThan(64));
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('spotlightProgrammeGeometry', () {
    test('uses epoch duration for variable width and clips to the window', () {
      final window = DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000);
      final halfHour = spotlightProgrammeGeometry(
        programmeStart: window.add(const Duration(minutes: 30)),
        programmeStop: window.add(const Duration(hours: 1)),
        windowStart: window,
        windowDuration: const Duration(hours: 4),
        viewportWidth: 800,
      );
      final ninetyMinutes = spotlightProgrammeGeometry(
        programmeStart: window.add(const Duration(hours: 1)),
        programmeStop: window.add(const Duration(hours: 2, minutes: 30)),
        windowStart: window,
        windowDuration: const Duration(hours: 4),
        viewportWidth: 800,
      );
      final clipped = spotlightProgrammeGeometry(
        programmeStart: window.subtract(const Duration(minutes: 30)),
        programmeStop: window.add(const Duration(minutes: 15)),
        windowStart: window,
        windowDuration: const Duration(hours: 4),
        viewportWidth: 800,
      );

      expect(halfHour!.left, 100);
      expect(halfHour.width, 100);
      expect(ninetyMinutes!.left, 200);
      expect(ninetyMinutes.width, 300);
      expect(clipped!.left, 0);
      expect(clipped.width, 50);
    });

    test('rejects gaps, reversed programmes, and empty viewports', () {
      final start = DateTime.fromMillisecondsSinceEpoch(10_000);
      expect(
        spotlightProgrammeGeometry(
          programmeStart: start.subtract(const Duration(seconds: 2)),
          programmeStop: start.subtract(const Duration(seconds: 1)),
          windowStart: start,
          windowDuration: const Duration(hours: 1),
          viewportWidth: 500,
        ),
        isNull,
      );
      expect(
        spotlightProgrammeGeometry(
          programmeStart: start.add(const Duration(minutes: 2)),
          programmeStop: start.add(const Duration(minutes: 1)),
          windowStart: start,
          windowDuration: const Duration(hours: 1),
          viewportWidth: 500,
        ),
        isNull,
      );
      expect(
        spotlightProgrammeGeometry(
          programmeStart: start,
          programmeStop: start.add(const Duration(minutes: 1)),
          windowStart: start,
          windowDuration: const Duration(hours: 1),
          viewportWidth: 0,
        ),
        isNull,
      );
    });
  });

  test('ruler marks align to local half hours in quarter-hour zones', () {
    const nepalOffset = Duration(hours: 5, minutes: 45);
    final marks = spotlightRulerMarks(
      windowStart: DateTime.utc(2030, 1, 1, 4, 22),
      windowDuration: const Duration(hours: 1),
      utcOffset: nepalOffset,
    );

    expect(marks, [
      DateTime.utc(2030, 1, 1, 4, 45),
      DateTime.utc(2030, 1, 1, 5, 15),
    ]);
    expect(marks.map((mark) => mark.add(nepalOffset).minute), [30, 0]);
  });

  testWidgets(
    'touch selects before playback, even on the focused startup row',
    (tester) async {
      final channels = [_channel('One', 'one'), _channel('Two', 'two')];
      final played = <String>[];
      final selections = <SpotlightTimelineSelection>[];
      await tester.pumpWidget(
        _host(
          channels: channels,
          height: 178,
          autofocus: true,
          loader: (_) async => [],
          onChannel: (entry) => played.add(entry.channel.name),
          onSelection: selections.add,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('One'));
      await tester.pump();
      expect(played, isEmpty);
      expect(selections.last.entry.channel.name, 'One');
      expect(selections.last.fromPointer, isTrue);
      expect(find.text('Tap again to watch'), findsOneWidget);
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(played, isEmpty);
      expect(selections.last.entry.channel.name, 'Two');
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(played, ['Two']);
    },
  );

  testWidgets(
    'programme tap previews first and restores the same cell after leaving',
    (tester) async {
      final start = DateTime(2030, 1, 1, 10);
      final controller = IptvSpotlightTimelineController();
      final played = <String>[];
      final selections = <SpotlightTimelineSelection>[];
      await tester.pumpWidget(
        _host(
          channels: [_channel('One', 'one')],
          loader: (_) async => [
            _programme('Morning news', start, const Duration(hours: 1)),
          ],
          controller: controller,
          initialWindowStart: start,
          onProgramme: (_, programme) => played.add(programme.title),
          onSelection: selections.add,
        ),
      );
      await tester.pump(const Duration(milliseconds: 375));
      await tester.pump();
      await tester.tap(find.text('Morning news'));
      await tester.pump();
      expect(played, isEmpty);
      expect(selections.last.programme?.title, 'Morning news');
      await tester.dragFrom(const Offset(600, 80), const Offset(-500, 0));
      await tester.pump();
      expect(find.text('Morning news'), findsNothing);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(controller.restoreFocus(), isTrue);
      await tester.pump();
      expect(selections.last.programme?.title, 'Morning news');
      expect(find.text('Morning news'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(played, ['Morning news']);
    },
  );

  testWidgets(
    'guide edges exit explicitly and bottom/right do not lose focus',
    (tester) async {
      var up = 0;
      var left = 0;
      final controller = IptvSpotlightTimelineController();
      await tester.pumpWidget(
        _host(
          channels: [_channel('One', 'one')],
          loader: (_) async => [],
          autofocus: true,
          controller: controller,
          onExitUp: () => up++,
          onExitLeft: () => left++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 375));
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(up, 1);
      expect(left, 1);
      expect(controller.hasFocus, isTrue);
    },
  );

  testWidgets(
    'horizontal swipe pans programmes, Now restores, vertical swipe scrolls channels',
    (tester) async {
      final start = DateTime(2030, 1, 1, 10);
      final played = <String>[];
      final channels = List.generate(
        20,
        (i) => _channel('Channel $i', 'url-$i'),
      );
      await tester.pumpWidget(
        _host(
          channels: channels,
          height: 246,
          now: () => start,
          loader: (_) async => [
            _programme('Current', start, const Duration(hours: 1)),
            _programme(
              'Later',
              start.add(const Duration(hours: 3)),
              const Duration(hours: 1),
            ),
          ],
          onChannel: (entry) => played.add(entry.channel.name),
          onProgramme: (_, programme) => played.add(programme.title),
        ),
      );
      await tester.pump(const Duration(milliseconds: 375));
      await tester.pump();
      final before = tester.getTopLeft(find.text('Current').first);
      await tester.dragFrom(const Offset(600, 80), const Offset(-150, 0));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('spotlight-jump-to-now')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Current').first).dx,
        lessThan(before.dx),
      );
      expect(played, isEmpty);
      await tester.tap(find.byKey(const ValueKey('spotlight-jump-to-now')));
      await tester.pump();
      expect(find.byKey(const ValueKey('spotlight-jump-to-now')), findsNothing);
      expect(tester.getTopLeft(find.text('Current').first).dx, before.dx);
      await tester.dragFrom(const Offset(100, 200), const Offset(0, -140));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('spotlight-live-timeline-rows')),
      );
      expect(list.controller!.offset, greaterThan(0));
      expect(played, isEmpty);
    },
  );

  testWidgets(
    'short OK plays, held OK and touch long press open channel actions',
    (tester) async {
      final played = <String>[];
      final menus = <String>[];
      await tester.pumpWidget(
        _host(
          channels: [_channel('One', 'one'), _channel('Two', 'two')],
          height: 178,
          loader: (_) async => [],
          autofocus: true,
          onChannel: (entry) => played.add(entry.channel.name),
          onActions: (entry) => menus.add(entry.channel.name),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(played, ['One']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect(menus, ['One']);
      expect(played, ['One']);
      await tester.longPress(find.text('Two'));
      await tester.pump();
      expect(menus, ['One', 'Two']);
      expect(played, ['One']);
    },
  );

  for (final activateKey in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.enter,
  ]) {
    testWidgets(
      'DPAD reaches Now and returns to the guide with ${activateKey.keyLabel}',
      (tester) async {
        final now = DateTime(2030, 1, 1, 10);
        final controller = IptvSpotlightTimelineController();
        var played = 0;
        var menus = 0;
        var upExits = 0;
        var leftExits = 0;
        await tester.pumpWidget(
          _host(
            channels: [_channel('One', 'one')],
            controller: controller,
            now: () => now,
            initialWindowStart: now.add(const Duration(hours: 3)),
            loader: (_) async => [
              _programme('Current show', now, const Duration(hours: 1)),
            ],
            onChannel: (_) => played++,
            onActions: (_) => menus++,
            onExitUp: () => upExits++,
            onExitLeft: () => leftExits++,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.focusFirstChannel(), isTrue);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'spotlight-now');
        final nowButton = tester.widget<TextButton>(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
        );
        expect(nowButton.focusNode!.hasPrimaryFocus, isTrue);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'One, Live' &&
                w.properties.focused == true,
          ),
          findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(upExits, 1);
        expect(leftExits, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'spotlight-live-timeline',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.sendKeyDownEvent(activateKey);
        await tester.pump();
        await tester.sendKeyRepeatEvent(activateKey);
        await tester.sendKeyUpEvent(activateKey);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsNothing,
        );
        expect(find.text('Current show'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'spotlight-live-timeline',
        );
        expect(played, 0);
        expect(menus, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final programmeCell in [false, true]) {
    testWidgets(
      'hover disarms a previously tapped ${programmeCell ? 'programme' : 'channel'}',
      (tester) async {
        final selections = <SpotlightTimelineSelection>[];
        final played = <String>[];
        final start = DateTime(2030, 1, 1, 10);
        await tester.pumpWidget(
          _host(
            channels: [_channel('One', 'one'), _channel('Two', 'two')],
            height: 178,
            now: () => start,
            initialWindowStart: programmeCell ? start : null,
            loader: (channel) async => programmeCell
                ? [
                    _programme(
                      '${channel.name} show',
                      start,
                      const Duration(hours: 1),
                    ),
                  ]
                : [],
            onSelection: selections.add,
            onChannel: (entry) => played.add(entry.channel.name),
            onProgramme: (_, programme) => played.add(programme.title),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final first = find.text(programmeCell ? 'One show' : 'One');
        final second = find.text(programmeCell ? 'Two show' : 'Two');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(0, 0));
        Future<void> clickFirst() async {
          await mouse.moveTo(tester.getCenter(first));
          await mouse.down(tester.getCenter(first));
          await mouse.up();
          await tester.pump();
        }

        await clickFirst();
        expect(played, isEmpty);
        await mouse.moveTo(tester.getCenter(second));
        await tester.pump(const Duration(milliseconds: 400));
        expect(selections.last.entry.channel.name, 'Two');
        await clickFirst();
        expect(played, isEmpty);
        expect(selections.last.entry.channel.name, 'One');
        await clickFirst();
        expect(played, [programmeCell ? 'One show' : 'One']);
      },
    );
  }

  for (final scroll in [
    (
      delta: const Offset(120, 1),
      shift: false,
      kind: PointerDeviceKind.mouse,
      pan: true,
    ),
    (
      delta: const Offset(-120, 1),
      shift: false,
      kind: PointerDeviceKind.mouse,
      pan: true,
    ),
    (
      delta: const Offset(1, 120),
      shift: false,
      kind: PointerDeviceKind.mouse,
      pan: false,
    ),
    (
      delta: const Offset(120, 0),
      shift: false,
      kind: PointerDeviceKind.mouse,
      pan: true,
    ),
    (
      delta: const Offset(0, 120),
      shift: false,
      kind: PointerDeviceKind.mouse,
      pan: false,
    ),
    (
      delta: const Offset(1, 120),
      shift: true,
      kind: PointerDeviceKind.mouse,
      pan: true,
    ),
    (
      delta: const Offset(1, 120),
      shift: true,
      kind: PointerDeviceKind.trackpad,
      pan: false,
    ),
  ]) {
    testWidgets(
      'wheel chooses one axis for ${scroll.delta}, shift=${scroll.shift}, ${scroll.kind}',
      (tester) async {
        final now = DateTime(2030, 1, 1, 10);
        await tester.pumpWidget(
          _host(
            channels: List.generate(
              20,
              (i) => _channel('Channel $i', 'url-$i'),
            ),
            height: 246,
            now: () => now,
            loader: (channel) async => [
              _programme(
                'Show ${channel.name}',
                now.add(const Duration(hours: 1)),
                const Duration(minutes: 30),
              ),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final programmeX = tester.getTopLeft(find.text('Show Channel 0')).dx;
        final list = tester.widget<ListView>(
          find.byKey(const ValueKey('spotlight-live-timeline-rows')),
        );
        expect(list.controller!.offset, 0);
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsNothing,
        );
        if (scroll.shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(600, 80),
            scrollDelta: scroll.delta,
            kind: scroll.kind,
          ),
        );
        await tester.pump();
        if (scroll.shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        if (scroll.pan) {
          expect(
            find.byKey(const ValueKey('spotlight-jump-to-now')),
            findsOneWidget,
          );
          expect(list.controller!.offset, 0);
          final horizontal = scroll.shift ? scroll.delta.dy : scroll.delta.dx;
          expect(
            tester.getTopLeft(find.text('Show Channel 0')).dx,
            closeTo(programmeX - horizontal, 0.01),
          );
        } else {
          expect(
            find.byKey(const ValueKey('spotlight-jump-to-now')),
            findsNothing,
          );
          expect(list.controller!.offset, closeTo(scroll.delta.dy, 0.01));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('settles for 375ms and only loads visible live rows', (
    tester,
  ) async {
    final calls = <IptvChannel>[];
    final channels = List.generate(
      10,
      (index) => _channel('Channel $index', 'url-$index'),
    );

    await tester.pumpWidget(
      _host(
        channels: channels,
        height: 178,
        loader: (channel) async {
          calls.add(channel);
          return const [];
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 374));
    expect(calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(calls, hasLength(2));
    expect(calls, [channels[0], channels[1]]);
    expect(find.text('No programme information'), findsNWidgets(2));
  });

  testWidgets('does not materialize a large lazy channel list', (tester) async {
    final channels = _CountingLazyChannels(50000);

    await tester.pumpWidget(
      _host(channels: channels, height: 110, loader: (_) async => const []),
    );

    expect(channels.reads, lessThan(20));
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    expect(channels.reads, lessThan(30));
  });

  testWidgets('rejects a result for a recycled source ordinal', (tester) async {
    final oldChannel = _channel('Old channel', 'old-url');
    final newChannel = _channel('New channel', 'new-url');
    final oldResult = Completer<List<EpgProgramme>>();
    final channels = ValueNotifier<List<IptvChannel>>([oldChannel]);
    final generation = ValueNotifier<int>(1);
    final window = DateTime(2030, 1, 1, 10);

    Future<List<EpgProgramme>> loader(IptvChannel channel) {
      if (identical(channel, oldChannel)) return oldResult.future;
      return Future.value([
        _programme('New programme', window, const Duration(hours: 1)),
      ]);
    }

    Widget build() => ValueListenableBuilder<List<IptvChannel>>(
      valueListenable: channels,
      builder: (context, value, _) => ValueListenableBuilder<int>(
        valueListenable: generation,
        builder: (context, valueGeneration, _) => _host(
          channels: value,
          loadGeneration: valueGeneration,
          initialWindowStart: window,
          loader: loader,
        ),
      ),
    );

    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 375));
    expect(find.text('Loading guide…'), findsOneWidget);

    channels.value = [newChannel];
    generation.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    expect(find.text('New programme'), findsOneWidget);

    oldResult.complete([
      _programme('Stale programme', window, const Duration(hours: 1)),
    ]);
    await tester.pump();
    expect(find.text('New programme'), findsOneWidget);
    expect(find.text('Stale programme'), findsNothing);
  });

  testWidgets('epgContextVersion retries visible rows', (tester) async {
    final version = ValueNotifier<int>(0);
    final channel = _channel('News', 'news-url');
    final window = DateTime(2030, 1, 1, 10);
    var calls = 0;

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: version,
        builder: (context, currentVersion, _) => _host(
          channels: [channel],
          epgContextVersion: currentVersion,
          initialWindowStart: window,
          loader: (_) async {
            calls++;
            return [
              _programme(
                'Guide version $calls',
                window,
                const Duration(hours: 1),
              ),
            ];
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    expect(find.text('Guide version 1'), findsOneWidget);

    version.value = 1;
    await tester.pump();
    expect(find.text('Loading guide…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Guide version 2'), findsOneWidget);
    expect(find.text('Guide version 1'), findsNothing);
  });

  testWidgets('guide refresh republishes a same-start programme instance', (
    tester,
  ) async {
    final version = ValueNotifier<int>(0);
    final channel = _channel('News', 'news-url');
    final channels = <IptvChannel>[channel];
    final window = DateTime(2030, 1, 1, 10);
    final original = _programme(
      'Original title',
      window,
      const Duration(hours: 1),
    );
    final refreshed = _programme(
      'Refreshed title',
      window,
      const Duration(hours: 1),
    );
    final selections = <SpotlightTimelineSelection>[];

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: version,
        builder: (context, currentVersion, _) => _host(
          channels: channels,
          epgContextVersion: currentVersion,
          autofocus: true,
          initialWindowStart: window,
          loader: (_) async => currentVersion == 0 ? [original] : [refreshed],
          onSelection: selections.add,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(identical(selections.last.programme, original), isTrue);
    selections.clear();

    version.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();

    expect(selections, hasLength(1));
    expect(identical(selections.single.programme, refreshed), isTrue);
    expect(selections.single.programme!.title, 'Refreshed title');
  });

  testWidgets('failed guide refresh restores the playable channel cursor', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final version = ValueNotifier<int>(0);
    final channel = _channel('News', 'news-url');
    final window = DateTime(2030, 1, 1, 10);
    final selections = <SpotlightTimelineSelection>[];
    final activated = <String>[];

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: version,
        builder: (context, currentVersion, _) => _host(
          channels: [channel],
          epgContextVersion: currentVersion,
          autofocus: true,
          initialWindowStart: window,
          loader: (_) async {
            if (currentVersion > 0) throw StateError('offline');
            return [
              _programme('Current show', window, const Duration(hours: 1)),
            ];
          },
          onChannel: (entry) => activated.add(entry.channel.name),
          onSelection: selections.add,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selections.last.programme?.title, 'Current show');
    selections.clear();

    version.value = 1;
    await tester.pump();
    expect(find.text('Loading guide…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();

    expect(find.text('Guide unavailable  ·  Retry'), findsOneWidget);
    expect(selections, isNotEmpty);
    expect(selections.last.programme, isNull);
    final identity = find.bySemanticsLabel('News, Live, Guide unavailable');
    expect(identity, findsOneWidget);
    expect(
      tester
          .getSemantics(identity)
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, ['News']);
    semantics.dispose();
  });

  testWidgets('shows empty and error states and retries errors by click', (
    tester,
  ) async {
    final empty = _channel('Empty', 'empty-url');
    final error = _channel('Error', 'error-url');
    var errorCalls = 0;
    final retryResult = Completer<List<EpgProgramme>>();

    await tester.pumpWidget(
      _host(
        channels: [empty, error],
        height: 178,
        loader: (channel) async {
          if (identical(channel, error)) {
            errorCalls++;
            if (errorCalls == 1) throw StateError('offline');
            return retryResult.future;
          }
          return const [];
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();

    expect(find.text('No programme information'), findsOneWidget);
    expect(find.text('Guide unavailable  ·  Retry'), findsOneWidget);

    await tester.tap(find.text('Guide unavailable  ·  Retry'));
    await tester.pump();
    expect(find.text('Loading guide…'), findsOneWidget);
    retryResult.complete(const []);
    await tester.pump();
    expect(errorCalls, 2);
    expect(find.text('No programme information'), findsNWidgets(2));
  });

  testWidgets('identity stays playable and RIGHT exposes TV guide retry', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final channel = _channel('Error', 'error-url');
    final activated = <String>[];
    var calls = 0;

    await tester.pumpWidget(
      _host(
        channels: [channel],
        autofocus: true,
        loader: (_) async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return const [];
        },
        onChannel: (entry) => activated.add(entry.channel.name),
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();

    final retryIdentity = find.bySemanticsLabel(
      'Error, Live, Guide unavailable',
    );
    expect(retryIdentity, findsOneWidget);
    final semanticsData = tester.getSemantics(retryIdentity).getSemanticsData();
    expect(
      semanticsData.hint,
      'Press OK to play the channel or RIGHT to retry the guide',
    );
    expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
    await tester.pump();
    expect(calls, 1);
    expect(activated, ['Error']);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
    await tester.pump();
    final retryMessage = find.bySemanticsLabel('Guide unavailable  ·  Retry');
    expect(retryMessage, findsOneWidget);
    expect(
      tester
          .getSemantics(retryMessage)
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
    await tester.pump();
    expect(calls, 2);
    expect(activated, ['Error']);
    expect(find.text('No programme information'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('source projection change republishes the new identity', (
    tester,
  ) async {
    final first = _channel('First', 'first-url');
    final second = _channel('Second', 'second-url');
    var channels = <IptvChannel>[first];
    var generation = 1;
    final rebuild = ValueNotifier<int>(0);
    final selections = <SpotlightTimelineSelection>[];

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (context, _, _) => _host(
          channels: channels,
          loadGeneration: generation,
          loader: (_) async => const [],
          onSelection: selections.add,
        ),
      ),
    );
    await tester.pump();
    selections.clear();

    channels = [second];
    generation = 2;
    rebuild.value++;
    await tester.pump();
    await tester.pump();

    expect(selections, isNotEmpty);
    expect(selections.last.entry.channel, same(second));
    expect(selections.last.programme, isNull);
  });

  testWidgets('pending pointer dwell rejects an in-place recycled row', (
    tester,
  ) async {
    final first = _channel('First', 'first-url');
    final hovered = _channel('Hovered', 'hovered-url');
    final replacement = _channel('Replacement', 'replacement-url');
    final channels = <IptvChannel>[first, hovered];
    final rebuild = ValueNotifier<int>(0);
    final selections = <SpotlightTimelineSelection>[];

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (context, _, _) => _host(
          channels: channels,
          height: 178,
          loader: (_) async => const [],
          onSelection: selections.add,
        ),
      ),
    );
    selections.clear();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(find.text('Hovered')));
    await tester.pump(const Duration(milliseconds: 200));

    channels[1] = replacement;
    rebuild.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));

    expect(selections.where((selection) => selection.fromPointer), isEmpty);
    await mouse.removePointer();
  });

  testWidgets('pending pointer dwell is canceled on source context changes', (
    tester,
  ) async {
    final first = _channel('First', 'first-url');
    final hovered = _channel('Hovered', 'hovered-url');
    var channels = <IptvChannel>[first, hovered];
    var sourceId = 'source-a';
    var contextVersion = 0;
    final rebuild = ValueNotifier<int>(0);
    final selections = <SpotlightTimelineSelection>[];

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (context, _, _) => _host(
          channels: channels,
          sourceId: sourceId,
          epgContextVersion: contextVersion,
          height: 178,
          loader: (_) async => const [],
          onSelection: selections.add,
        ),
      ),
    );
    selections.clear();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(find.text('Hovered')));
    await tester.pump(const Duration(milliseconds: 200));

    channels = <IptvChannel>[first, hovered];
    sourceId = 'source-b';
    contextVersion++;
    rebuild.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));

    expect(selections.where((selection) => selection.fromPointer), isEmpty);
    await mouse.removePointer();
  });

  testWidgets('DPAD keeps one cursor and selects nearest time vertically', (
    tester,
  ) async {
    final now = DateTime.now();
    final window = now.subtract(const Duration(hours: 1));
    final first = _channel('First', 'first-url');
    final second = _channel('Second', 'second-url');
    final firstNow = _programme(
      'First now',
      now.subtract(const Duration(minutes: 20)),
      const Duration(minutes: 40),
    );
    final firstNext = _programme(
      'First next',
      now.add(const Duration(minutes: 20)),
      const Duration(minutes: 40),
    );
    final secondNearest = _programme(
      'Second nearest',
      now.subtract(const Duration(minutes: 30)),
      const Duration(minutes: 25),
    );
    final secondLater = _programme(
      'Second later',
      now.add(const Duration(minutes: 30)),
      const Duration(minutes: 30),
    );
    final activatedProgrammes = <String>[];
    final activatedChannels = <String>[];

    await tester.pumpWidget(
      _host(
        channels: [first, second],
        height: 178,
        autofocus: true,
        initialWindowStart: window,
        loader: (channel) async => identical(channel, first)
            ? [firstNow, firstNext]
            : [secondNearest, secondLater],
        onChannel: (entry) => activatedChannels.add(entry.channel.name),
        onProgramme: (entry, programme) =>
            activatedProgrammes.add(programme.title),
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activatedProgrammes, ['Second nearest']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activatedChannels, ['Second']);
  });

  testWidgets(
    'vertical move into a cached guide error restores channel focus',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final first = _channel('First', 'first-url');
      final failed = _channel('Failed', 'failed-url');
      final now = DateTime.now();
      final selections = <SpotlightTimelineSelection>[];
      final activated = <String>[];
      var failedLoads = 0;

      await tester.pumpWidget(
        _host(
          channels: [first, failed],
          height: 178,
          autofocus: true,
          loader: (channel) async {
            if (identical(channel, failed)) {
              failedLoads++;
              throw StateError('offline');
            }
            return [_programme('Current show', now, const Duration(hours: 1))];
          },
          onSelection: selections.add,
          onChannel: (entry) => activated.add(entry.channel.name),
        ),
      );
      await tester.pump(const Duration(milliseconds: 375));
      await tester.pump();
      expect(failedLoads, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selections.last.programme, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selections.last.entry.channel, same(failed));
      expect(selections.last.programme, isNull);
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel('Failed, Live, Guide unavailable'),
            )
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activated, ['Failed']);
      expect(failedLoads, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Guide unavailable  ·  Retry'))
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(failedLoads, 2);
      expect(activated, ['Failed']);
      semantics.dispose();
    },
  );

  testWidgets('holding Enter activates the logical cursor only once', (
    tester,
  ) async {
    final channel = _channel('News', 'news-url');
    final activated = <String>[];

    await tester.pumpWidget(
      _host(
        channels: [channel],
        autofocus: true,
        loader: (_) async => const [],
        onChannel: (entry) => activated.add(entry.channel.name),
      ),
    );

    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter), isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activated, ['News']);
  });

  testWidgets('alternate TV activation keys work and repeats are swallowed', (
    tester,
  ) async {
    final channel = _channel('News', 'news-url');
    final activated = <String>[];

    await tester.pumpWidget(
      _host(
        channels: [channel],
        autofocus: true,
        loader: (_) async => const [],
        onChannel: (entry) => activated.add(entry.channel.name),
      ),
    );

    for (final key in const [
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.space,
    ]) {
      expect(await tester.sendKeyDownEvent(key), isTrue);
      expect(await tester.sendKeyRepeatEvent(key), isTrue);
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();

    expect(activated, ['News', 'News', 'News']);
  });

  testWidgets('follow-now advances the unselected programme time anchor', (
    tester,
  ) async {
    var now = DateTime(2030, 1, 1, 10, 20);
    final channel = _channel('News', 'news-url');
    final early = _programme(
      'Early show',
      DateTime(2030, 1, 1, 10),
      const Duration(minutes: 30),
    );
    final current = _programme(
      'Current show',
      DateTime(2030, 1, 1, 10, 30),
      const Duration(minutes: 30),
    );
    final selections = <SpotlightTimelineSelection>[];

    await tester.pumpWidget(
      _host(
        channels: [channel],
        autofocus: true,
        now: () => now,
        loader: (_) async => [early, current],
        onSelection: selections.add,
      ),
    );
    await tester.pump(const Duration(milliseconds: 375));
    await tester.pump();
    selections.clear();

    // The periodic timer fires after 30 real test seconds, while the injected
    // wall clock crosses into the next programme without expiring the guide.
    now = DateTime(2030, 1, 1, 10, 40);
    await tester.pump(const Duration(seconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(selections.last.programme, same(current));
  });

  testWidgets(
    'controller hands focus to a channel and identity stays playable',
    (tester) async {
      final controller = IptvSpotlightTimelineController();
      final first = _channel('One', 'one-url');
      final second = _channel('Two', 'two-url');
      final activated = <String>[];

      await tester.pumpWidget(
        _host(
          channels: [first, second],
          height: 178,
          controller: controller,
          loader: (_) async => const [],
          onChannel: (entry) => activated.add(entry.channel.name),
        ),
      );
      expect(controller.hasFocus, isFalse);
      expect(controller.focusChannel(second), isTrue);
      await tester.pump();
      expect(controller.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activated, ['Two']);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasFocus, isFalse);
      expect(controller.focusFirstChannel(), isFalse);
    },
  );

  testWidgets('controller focuses a lazy-list index without scanning', (
    tester,
  ) async {
    final controller = IptvSpotlightTimelineController();
    final channels = _CountingLazyChannels(50000);
    final activated = <String>[];

    await tester.pumpWidget(
      _host(
        channels: channels,
        height: 110,
        controller: controller,
        loader: (_) async => const [],
        onChannel: (entry) => activated.add(entry.channel.name),
      ),
    );
    final readsBefore = channels.reads;

    expect(controller.focusChannelAt(-1), isFalse);
    expect(controller.focusChannelAt(channels.length), isFalse);
    expect(controller.focusChannelAt(40000), isTrue);
    expect(channels.reads - readsBefore, lessThan(5));

    await tester.pump();
    expect(controller.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(activated, ['Lazy 40000']);
  });
}

Widget _host({
  required List<IptvChannel> channels,
  required SpotlightScheduleLoader loader,
  String sourceId = 'source',
  int loadGeneration = 1,
  int epgContextVersion = 0,
  double height = 110,
  bool autofocus = false,
  DateTime Function() now = DateTime.now,
  DateTime? initialWindowStart,
  IptvSpotlightTimelineController? controller,
  SpotlightChannelActivate? onChannel,
  SpotlightProgrammeActivate? onProgramme,
  ValueChanged<SpotlightTimelineSelection>? onSelection,
  VoidCallback? onExitUp,
  VoidCallback? onExitLeft,
  SpotlightChannelActivate? onActions,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 900,
          child: SpotlightLiveTimeline(
            channels: channels,
            sourceId: sourceId,
            loadGeneration: loadGeneration,
            epgContextVersion: epgContextVersion,
            height: height,
            autofocus: autofocus,
            now: now,
            initialWindowStart: initialWindowStart,
            controller: controller,
            scheduleLoader: loader,
            onChannelActivate: onChannel ?? (_) {},
            onProgrammeActivate: onProgramme ?? (_, _) {},
            onSelectionChanged: onSelection,
            onExitUp: onExitUp,
            onExitLeft: onExitLeft,
            onChannelActions: onActions,
          ),
        ),
      ),
    ),
  );
}

IptvChannel _channel(String name, String url) =>
    IptvChannel(name: name, url: url, duration: -1, contentType: 'live');

EpgProgramme _programme(String title, DateTime start, Duration duration) =>
    EpgProgramme(
      title: title,
      description: '',
      start: start,
      stop: start.add(duration),
    );

class _CountingLazyChannels extends ListBase<IptvChannel> {
  @override
  final int length;
  final Map<int, IptvChannel> _resident = {};
  int reads = 0;

  _CountingLazyChannels(this.length);

  @override
  IptvChannel operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    reads++;
    return _resident.putIfAbsent(
      index,
      () => _channel('Lazy $index', 'lazy-url-$index'),
    );
  }

  @override
  void operator []=(int index, IptvChannel value) =>
      throw UnsupportedError('read-only');

  @override
  set length(int value) => throw UnsupportedError('read-only');
}
