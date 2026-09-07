import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/collection_focus_playback.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/collections/collection_focus_art.dart';
import 'package:debrify/widgets/collections/collection_focus_glow.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/serialized_trailer_engine.dart';
import 'package:debrify/widgets/trailer_engine.dart';

const _video = 'https://example.test/focus.mp4';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  navigatorObservers: [appRouteObserver],
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: SizedBox(width: 320, height: 180, child: child),
  ),
);

Future<void> _start(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 351));
  await tester.pump();
}

void main() {
  tearDown(CollectionFocusPlayback.reset);

  test(
    'hover ownership restores keyboard focus and ignores stale releases',
    () {
      final focused = Object();
      final hovered = Object();
      CollectionFocusPlayback.claim(focused);
      CollectionFocusPlayback.claim(hovered);
      CollectionFocusPlayback.claim(
        focused,
      ); // dependency rebuild is not activation
      expect(CollectionFocusPlayback.allows(hovered), isTrue);
      CollectionFocusPlayback.release(hovered);
      expect(CollectionFocusPlayback.allows(focused), isTrue);
      CollectionFocusPlayback.claim(hovered);
      CollectionFocusPlayback.release(focused);
      expect(CollectionFocusPlayback.allows(hovered), isTrue);
      CollectionFocusPlayback.release(hovered);
      expect(CollectionFocusPlayback.allows(null), isTrue);
    },
  );

  test(
    'visual settings survive import, copy, inventory-shaped JSON and export',
    () {
      final source = {
        'id': 'c',
        'title': 'Streaming',
        'focusGlowEnabled': false,
        'folders': [
          {
            'id': 'f',
            'title': 'Brand',
            'focusVideoUrl': _video,
            'focusVideoEnabled': false,
          },
        ],
      };
      final parsed = HomeCollectionParser.parse(jsonEncode(source)).single;
      final copied = parsed.copyWith(enabled: false, importedAtMs: 42);
      final restored = HomeCollection.fromJson(
        jsonDecode(jsonEncode(copied.toJson())),
      )!;
      expect(restored.focusGlowEnabled, isFalse);
      expect(restored.enabled, isFalse);
      expect(
        restored.folders.single.copyWith(sources: []).focusVideoUrl,
        _video,
      );
      expect(restored.folders.single.focusVideoEnabled, isFalse);
      final defaults = HomeCollection.fromJson({
        'title': 'Default',
        'folders': [],
      })!;
      expect(defaults.focusGlowEnabled, isTrue);
    },
  );

  test(
    'only enabled HTTP(S) focus videos reach tiles; absent flag permits URL',
    () {
      for (final (url, enabled, expected) in [
        (_video, true, _video),
        (_video, false, null),
        ('file:///tmp/video.mp4', true, null),
        ('https:', true, null),
        ('  $_video  ', true, _video),
        ('', true, null),
      ]) {
        final collection = HomeCollection.fromJson({
          'title': 'c',
          'folders': [
            {
              'title': 'f',
              'focusVideoUrl': url,
              if (!enabled) 'focusVideoEnabled': false,
            },
          ],
        })!;
        final row = HomeCollectionSection(collection: collection);
        expect(row.focusVideoOf(row.items.single), expected);
      }
    },
  );

  testWidgets('dwell cancels on blur without constructing a decoder', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    var creates = 0;
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async {
            creates++;
            return FakeFocusEngine();
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(creates, 0);
    expect(CollectionFocusPlayback.owner.value, isNull);
  });

  testWidgets(
    'focus video loops muted from frame zero and retains cover floor',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      final engine = FakeFocusEngine();
      await tester.pumpWidget(
        _app(
          Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(key: ValueKey('cover'), color: Colors.red),
              ),
              Positioned.fill(
                child: CollectionFocusArt(
                  videoUrl: _video,
                  engineFactory: () async => engine,
                ),
              ),
            ],
          ),
        ),
      );
      await _start(tester);
      expect(engine.openedUrl, _video);
      expect(engine.volume, 0);
      expect(engine.loop, isTrue);
      expect(find.byKey(const ValueKey('cover')), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      engine.frame.complete();
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(engine.seeks, isEmpty);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(engine.detached, isTrue);
      expect(engine.disposed, isTrue);
    },
  );

  testWidgets('video failure restores cover and releases ambient ownership', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    final engine = FakeFocusEngine();
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(videoUrl: _video, engineFactory: () async => engine),
      ),
    );
    await _start(tester);
    engine.frame.complete();
    await tester.pump();
    await tester.pump();
    engine.errors.add(null);
    await tester.pump();
    await tester.pump();
    expect(engine.disposed, isTrue);
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    expect(CollectionFocusPlayback.owner.value, isNull);
  });

  testWidgets('no-frame watchdog releases failed preview without retry storm', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    var creates = 0;
    final engine = FakeFocusEngine();
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async {
            creates++;
            return engine;
          },
        ),
      ),
    );
    await _start(tester);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(engine.disposed, isTrue);
    expect(creates, 1);
    expect(CollectionFocusPlayback.owner.value, isNull);
  });

  testWidgets('route push releases preview and pop resumes after dwell', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    final engines = <FakeFocusEngine>[];
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async {
            final e = FakeFocusEngine();
            engines.add(e);
            return e;
          },
        ),
      ),
    );
    await _start(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
    );
    await tester.pumpAndSettle();
    expect(engines.single.disposed, isTrue);
    expect(CollectionFocusPlayback.owner.value, isNull);
    nav.pop();
    await tester.pumpAndSettle();
    await _start(tester);
    expect(engines, hasLength(2));
    expect(engines.last.openedUrl, _video);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background releases preview and resume starts a fresh decoder', (
    tester,
  ) async {
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    final engines = <FakeFocusEngine>[];
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async {
            final e = FakeFocusEngine();
            engines.add(e);
            return e;
          },
        ),
      ),
    );
    await _start(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(engines.single.disposed, isTrue);
    expect(CollectionFocusPlayback.owner.value, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _start(tester);
    expect(engines, hasLength(2));
    MainPageBridge.notifyPlayerLaunching();
    await tester.pump();
    expect(engines.last.disposed, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(engines, hasLength(2));
  });

  testWidgets('failed engine creation releases the slot and restores cover', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async => throw StateError('decoder unavailable'),
        ),
      ),
    );
    await _start(tester);
    await tester.pump();
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    expect(CollectionFocusPlayback.owner.value, isNull);
    final next = FakeFocusEngine();
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: 'https://example.test/next.mp4',
          engineFactory: () async => next,
        ),
      ),
    );
    await _start(tester);
    expect(next.openedUrl, 'https://example.test/next.mp4');
  });

  testWidgets(
    'reduced motion prevents playback and tears down existing video',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      final engine = FakeFocusEngine();
      var creates = 0;
      Widget view(bool reduced) => _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () async {
            creates++;
            return engine;
          },
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(view(true));
      await _start(tester);
      expect(creates, 0);
      await tester.pumpWidget(view(false));
      await _start(tester);
      expect(creates, 1);
      await tester.pumpWidget(view(true));
      await tester.pump();
      expect(engine.disposed, isTrue);
      expect(CollectionFocusPlayback.owner.value, isNull);
    },
  );

  testWidgets('preview takes over Home trailer and releases it on blur', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    final heroes = <FakeFocusEngine>[];
    final preview = FakeFocusEngine();
    Widget view(bool focused) => _app(
      Stack(
        children: [
          HeroTrailerBackdrop(
            key: const ValueKey('hero'),
            imageUrl: null,
            videoUrl: 'https://example.test/hero.mp4',
            enabled: true,
            startDelay: Duration.zero,
            engineFactory: () async {
              final e = FakeFocusEngine();
              heroes.add(e);
              return e;
            },
          ),
          if (focused)
            CollectionFocusArt(
              videoUrl: _video,
              engineFactory: () async => preview,
            ),
        ],
      ),
    );
    await tester.pumpWidget(view(false));
    await _start(tester);
    expect(heroes, hasLength(1));
    await tester.pumpWidget(view(true));
    await _start(tester);
    expect(heroes.first.disposed, isTrue);
    expect(preview.openedUrl, _video);
    await tester.pumpWidget(view(false));
    await _start(tester);
    expect(preview.disposed, isTrue);
    expect(heroes, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale pending creation never opens after focus URL changes', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    final pending = Completer<TrailerEngine>();
    final old = FakeFocusEngine();
    final next = FakeFocusEngine();
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: _video,
          engineFactory: () => pending.future,
        ),
      ),
    );
    await _start(tester);
    await tester.pumpWidget(
      _app(
        CollectionFocusArt(
          videoUrl: 'https://example.test/new.mp4',
          engineFactory: () async => next,
        ),
      ),
    );
    await _start(tester);
    pending.complete(old);
    await tester.pump();
    await tester.pump();
    expect(old.openedUrl, isNull);
    expect(old.disposed, isTrue);
    expect(next.openedUrl, 'https://example.test/new.mp4');
    await tester.pumpWidget(const SizedBox());
  });

  test('decoder handoff waits for native disposal AND pending open', () async {
    final closing = Completer<void>();
    final opening = Completer<void>();
    final first = FakeFocusEngine(opening: opening, closing: closing);
    final a = (await SerializedTrailerEngine.create(
      () async => first,
      () => true,
    ))!;
    unawaited(a.open(videoUrl: _video, volume: 0, loop: true));
    final disposal = a.dispose();
    var created = false;
    final successor = SerializedTrailerEngine.create(() async {
      created = true;
      return FakeFocusEngine();
    }, () => true);
    await Future<void>.delayed(Duration.zero);
    expect(created, isFalse);
    closing.complete();
    await Future<void>.delayed(Duration.zero);
    expect(created, isFalse);
    opening.complete();
    await disposal;
    final b = await successor;
    expect(created, isTrue);
    await b!.dispose();
  });

  testWidgets('glow responds to row switch and focus, leaving child intact', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    Widget view(bool active, bool enabled) => _app(
      CollectionFocusGlow(
        active: active,
        enabled: enabled,
        child: const SizedBox(key: ValueKey('tile'), width: 200, height: 120),
      ),
    );
    double alpha() =>
        (tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration)
            .boxShadow!
            .single
            .color
            .a;
    await tester.pumpWidget(view(true, true));
    expect(alpha(), greaterThan(0));
    await tester.pumpWidget(view(true, false));
    expect(alpha(), 0);
    expect(find.byKey(const ValueKey('tile')), findsOneWidget);
    await tester.pumpWidget(view(false, true));
    expect(alpha(), 0);
  });
}

class FakeFocusEngine implements TrailerEngine {
  final frame = Completer<void>();
  final errors = StreamController<void>.broadcast();
  final Completer<void>? opening;
  final Completer<void>? closing;
  FakeFocusEngine({this.opening, this.closing});
  String? openedUrl;
  double? volume;
  bool? loop;
  bool detached = false;
  bool disposed = false;
  final seeks = <Duration>[];
  @override
  bool get rendersUnderlay => false;
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<void> get errorStream => errors.stream;
  @override
  Future<void> get firstFrameRendered => frame.future;
  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    openedUrl = videoUrl;
    this.volume = volume;
    this.loop = loop;
    if (opening != null) await opening!.future;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  void detach() {
    detached = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (closing != null) await closing!.future;
    await errors.close();
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      const ColoredBox(key: ValueKey('video-frame'), color: Colors.blue);
}
