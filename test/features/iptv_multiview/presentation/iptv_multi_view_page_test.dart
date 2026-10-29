// The multi-view page with fake engines: tiles per selection, the sound tile,
// engine lifetimes (removal, re-adding, late factories, page disposal) and
// profile isolation.
import 'dart:async';

import 'package:debrify/features/iptv_multiview/application/multi_view_selection_notifier.dart';
import 'package:debrify/features/iptv_multiview/presentation/iptv_multi_view_page.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeEngine implements TrailerEngine {
  _FakeEngine(this.url);
  final String url;
  final volumes = <double>[];
  bool opened = false;
  bool detached = false;
  int disposals = 0;

  double get volume => volumes.last;

  @override
  bool get rendersUnderlay => false;
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<void> get errorStream => const Stream.empty();
  @override
  Future<void> get firstFrameRendered => Future.value();
  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    opened = true;
    volumes.add(volume);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  void detach() => detached = true;
  @override
  Future<void> dispose() async {
    detached = true;
    disposals++;
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      Container(key: ValueKey('video-$url'), color: Colors.blue);
}

IptvChannel _ch(String id) =>
    IptvChannel(name: 'Channel $id', url: 'https://tv.test/$id.ts');

void main() {
  late Object owner;
  late ProviderContainer container;
  late List<_FakeEngine> engines;
  Completer<void>? holdFactory;

  MultiViewSelectionNotifier notifier() =>
      container.read(multiViewSelectionProvider.notifier);
  _FakeEngine engineOf(String id) =>
      engines.lastWhere((e) => e.url == 'https://tv.test/$id.ts');

  setUp(() {
    owner = 'profile-a';
    engines = [];
    holdFactory = null;
    container = ProviderContainer(
      overrides: [
        multiViewOwnerProvider.overrideWithValue(() => owner),
        multiViewMaxTilesProvider.overrideWithValue(4),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<TrailerEngine> factory(
    IptvChannel channel, {
    required int tileCount,
  }) async {
    final engine = _FakeEngine(channel.url);
    engines.add(engine);
    await holdFactory?.future;
    return engine;
  }

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: IptvMultiViewPage(
            engineFactory: factory,
            onWatchFullScreen: (_) {},
          ),
        ),
      ),
    );
    // A tile still waiting on its engine spins forever, so settling would
    // never finish; such tests pump frames themselves.
    settle ? await tester.pumpAndSettle() : await tester.pump();
  }

  testWidgets('one tile per channel; only the first has sound', (tester) async {
    for (final id in ['1', '2', '3']) {
      notifier().add(_ch(id));
    }
    await mount(tester);

    for (final id in ['1', '2', '3']) {
      expect(find.byKey(ValueKey('video-https://tv.test/$id.ts')), findsOne);
    }
    expect(engineOf('1').volume, 100);
    expect(engineOf('2').volume, 0);
    expect(engineOf('3').volume, 0);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });

  testWidgets('selecting a tile moves the sound there', (tester) async {
    notifier()
      ..add(_ch('1'))
      ..add(_ch('2'));
    await mount(tester);

    await tester.tap(find.byKey(const ValueKey('video-https://tv.test/2.ts')));
    await tester.pumpAndSettle();

    expect(engineOf('1').volume, 0);
    expect(engineOf('2').volume, 100);
    expect(container.read(multiViewSelectionProvider).audioIndex, 1);
  });

  testWidgets('a removed tile releases its engine; others keep theirs', (
    tester,
  ) async {
    notifier()
      ..add(_ch('1'))
      ..add(_ch('2'));
    await mount(tester);
    final first = engineOf('1');

    notifier().remove(0);
    await tester.pumpAndSettle();

    expect(first.disposals, 1);
    expect(engineOf('2').disposals, 0);
    expect(
      find.byKey(const ValueKey('video-https://tv.test/1.ts')),
      findsNothing,
    );
  });

  testWidgets('a channel removed and added again plays on a new engine', (
    tester,
  ) async {
    notifier()
      ..add(_ch('1'))
      ..add(_ch('2'));
    await mount(tester);
    final old = engineOf('1');

    notifier().remove(0);
    await tester.pumpAndSettle();
    notifier().add(_ch('1'));
    await tester.pumpAndSettle();

    final fresh = engineOf('1');
    expect(identical(fresh, old), isFalse);
    expect(fresh.opened, isTrue);
    expect(fresh.disposals, 0);
    expect(find.byKey(const ValueKey('video-https://tv.test/1.ts')), findsOne);
  });

  testWidgets('an engine that arrives after its tile left is disposed', (
    tester,
  ) async {
    holdFactory = Completer<void>();
    notifier().add(_ch('1'));
    await mount(tester, settle: false);
    expect(engines, hasLength(1));

    notifier().remove(0);
    await tester.pump();
    holdFactory!.complete();
    await tester.pumpAndSettle();

    expect(engines.single.opened, isFalse);
    expect(engines.single.disposals, 1);
  });

  testWidgets('closing the page disposes every engine', (tester) async {
    notifier()
      ..add(_ch('1'))
      ..add(_ch('2'));
    await mount(tester);

    await tester.pumpWidget(const SizedBox());

    expect(engines.every((e) => e.disposals == 1), isTrue);
  });

  testWidgets('empty, or another profile\'s selection, shows the hint', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.text("Add channels to multi-view from a channel's actions."),
      findsOneWidget,
    );

    notifier().add(_ch('1'));
    owner = 'profile-b';
    await tester.pumpAndSettle();
    expect(
      find.text("Add channels to multi-view from a channel's actions."),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video-https://tv.test/1.ts')),
      findsNothing,
    );
  });
}
