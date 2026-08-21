import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/trailer_engine.dart';

void main() {
  testWidgets('mounts the render surface before the first frame arrives', (
    tester,
  ) async {
    final engine = _PendingFirstFrameEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: HeroTrailerBackdrop(
          imageUrl: null,
          videoUrl: 'https://example.invalid/trailer.mp4',
          enabled: true,
          startDelay: Duration.zero,
          engineFactory: () async => engine,
        ),
      ),
    );
    // Advance the zero-duration start timer, then render the setState that
    // attaches the engine.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(engine.opened, isTrue);
    expect(engine.firstFrameCompleted, isFalse);
    expect(engine.buildVideoCalls, greaterThan(0));
  });
}

class _PendingFirstFrameEngine implements TrailerEngine {
  final Completer<void> _firstFrame = Completer<void>();
  bool opened = false;
  int buildVideoCalls = 0;

  bool get firstFrameCompleted => _firstFrame.isCompleted;

  @override
  bool get rendersUnderlay => true;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<void> get errorStream => const Stream<void>.empty();

  @override
  Future<void> get firstFrameRendered => _firstFrame.future;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    opened = true;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  void detach() {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) {
    buildVideoCalls++;
    return const SizedBox.expand();
  }
}
