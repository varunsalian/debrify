import Flutter
import Foundation

/// Carries the libmpv frameworks — and does one small but load-bearing thing
/// at registration.
///
/// `package:media_kit`'s `NativeLibrary.ensureInitialized()` resolves libmpv
/// from a platform-name map with no `tvos` entry, and it has NO
/// already-resolved guard: every call re-runs the lookup. Passing an explicit
/// path at startup therefore fixes only the FIRST call. `media_kit_video`'s
/// `query_decoders.dart` calls the no-argument form again while building a
/// VideoController, and that throws `Unsupported operating system: tvos`
/// — so video never initialises even though audio plays fine.
///
/// `NativeLibrary` checks the `LIBMPV_LIBRARY_PATH` environment variable
/// BEFORE consulting that map. Setting it here, natively and before Dart
/// starts, makes every call site resolve correctly with no fork of media_kit
/// or media_kit_video.
///
/// The value is the app EXECUTABLE, not a framework: the Apple TV libmpv
/// builds are static archives linked into the binary, so dlopen'ing the
/// executable is what `DynamicLibrary.process()` would do (which media_kit
/// never calls).
public class MediaKitLibsTvosVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    if let path = Bundle.main.executablePath {
      // overwrite: 0 — never clobber a value someone deliberately exported.
      setenv("LIBMPV_LIBRARY_PATH", path, 0)
    }
  }
}
