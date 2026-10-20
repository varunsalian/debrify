import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_driver.dart';
import 'subtitle_apply_driver.dart' show applyScreen;

/// Mounts the screen without waiting for its controller: a held video-output
/// slot parks player construction, which the shared mount would wait out.
Future<void> pumpScreen(
  EngineDriver d, [
  VideoPlayerScreen screen = applyScreen,
]) => d.observe(() async {
  d.t.view.physicalSize = const Size(1280, 800);
  d.t.view.devicePixelRatio = 1;
  await d.t.pumpWidget(
    MaterialApp(
      navigatorKey: d.f.navigator,
      theme: ThemeData.dark(),
      home: screen,
    ),
  );
});

/// The rest of the shared mount once the controller exists.
Future<void> finishMount(EngineDriver d) async {
  await d.f.until(d.t, () => d.f.controllers.isNotEmpty);
  d.player.deliverReady();
  await d.f.until(d.t, () => d.player.calls.any((c) => c.$1 == 'open'));
  await d.f.advance(d.t, const Duration(seconds: 2));
  // As the shared mount: initialization settles once its periodic save runs.
  await d.f.until(d.t, () => d.periodic.contains(const Duration(seconds: 6)));
}

/// Time until [condition], in whole fixture steps of [step].
Future<Duration> elapsedUntil(
  EngineDriver d,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 100),
  Duration limit = const Duration(seconds: 30),
}) async {
  var elapsed = Duration.zero;
  while (!condition()) {
    expect(elapsed, lessThan(limit), reason: 'condition not reached');
    await d.f.advance(d.t, step);
    elapsed += step;
  }
  return elapsed;
}
