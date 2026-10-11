import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

class FakeVideoController implements mkv.VideoController {
  FakeVideoController(this.player, this.configuration) {
    backend = FakePlatformVideoController(this);
    player.platform!.isVideoControllerAttached = true;
    player.platform!.videoControllerCompleter.complete();
  }
  @override
  final mk.Player player;
  final mkv.VideoControllerConfiguration configuration;
  late final FakePlatformVideoController backend;
  @override
  final platform = Completer<mkv.PlatformVideoController>();
  @override
  final notifier = ValueNotifier<mkv.PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);
  final firstFrame = Completer<void>();
  final sizes = <(int?, int?)>[];
  @override
  Future<void> get waitUntilFirstFrameRendered => firstFrame.future;
  @override
  Future<void> setSize({int? width, int? height}) async {
    sizes.add((width, height));
  }

  void publishFrame() {
    if (!platform.isCompleted) platform.complete(backend);
    notifier.value = backend;
    rect.value = const Rect.fromLTWH(0, 0, 1280, 720);
    if (!firstFrame.isCompleted) firstFrame.complete();
  }

  void close() => backend.dispose();
}

/// No vendored constructors and no native texture registration. Readiness
/// and geometry are explicit while a null texture id is retained deliberately.
class FakePlatformVideoController implements mkv.PlatformVideoController {
  FakePlatformVideoController(this.controller);
  final FakeVideoController controller;
  @override
  mk.Player get player => controller.player;
  @override
  mkv.VideoControllerConfiguration get configuration =>
      controller.configuration;
  @override
  ValueNotifier<int?> get id => controller.id;
  @override
  ValueNotifier<Rect?> get rect => controller.rect;
  @override
  Completer<void> get waitUntilFirstFrameRenderedCompleter =>
      controller.firstFrame;
  @override
  Future<void> get waitUntilFirstFrameRendered => controller.firstFrame.future;
  @override
  Future<void> setSize({int? width, int? height}) =>
      controller.setSize(width: width, height: height);
  @override
  void dispose() {
    controller.notifier.dispose();
    id.dispose();
    rect.dispose();
  }
}
