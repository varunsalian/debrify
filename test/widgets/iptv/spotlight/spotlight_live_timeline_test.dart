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
