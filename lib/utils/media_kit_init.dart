import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'platform_util.dart';

/// One place that knows how to start `package:media_kit`, because Apple TV
/// needs an argument the other platforms don't.
///
/// `MediaKit.ensureInitialized()` with no argument resolves libmpv from a
/// platform-name map inside media_kit's `NativeLibrary`. That map has entries
/// for windows / linux / macos / ios / android and **none for `tvos`**, so on
/// Apple TV — where `Platform.operatingSystem` is `"tvos"` — the bare call
/// throws `Unsupported operating system: tvos` before anything can play.
///
/// Passing an explicit path skips the map entirely. It reaches the native
/// branch because media_kit dispatches on `UniversalPlatform.isIOS`, and
/// `Platform.isIOS` is true on tvOS.
///
/// The path is the app EXECUTABLE, not a framework. The only libmpv builds
/// with Apple TV slices today (karelrooted/libmpv) ship a **static**
/// `libmpv.a`, so there is no `Libmpv.framework/Libmpv` to dlopen — the
/// symbols are linked into the executable itself, and dlopen'ing that is the
/// equivalent of `DynamicLibrary.process()` (which media_kit never calls).
/// See `packages/media_kit_libs_tvos_video` for the linker side of this.
class MediaKitInit {
  MediaKitInit._();

  static bool _done = false;

  /// Idempotent — media_kit latches its own initialisation too, but a failed
  /// attempt there is sticky, so the guard is kept on this side as well.
  static void ensureInitialized() {
    if (_done) return;
    _done = true;
    if (!kIsWeb && PlatformUtil.isTvOS) {
      mk.MediaKit.ensureInitialized(libmpv: Platform.resolvedExecutable);
      return;
    }
    mk.MediaKit.ensureInitialized();
  }
}
