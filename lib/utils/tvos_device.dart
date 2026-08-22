import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_util.dart';

/// Hardware-capacity probe for Apple TV.
///
/// The app treats every tvOS device identically, but the fleet is not
/// identical: the Apple TV HD (2 GB) and both 3 GB Apple TV 4K generations
/// (2017 and 2021) have well under half the jetsam budget of the 4 GB 2022
/// model, and the Full HD hero decode + trailer + Top Shelf export load a
/// modern unit shrugs off kills them. [warm] runs once before `runApp` so the
/// answer is synchronously readable everywhere a heavy path is gated — the
/// flag is constant for the process lifetime, which is what makes it safe
/// inside getters that must agree between initState and dispose.
class TvosDevice {
  TvosDevice._();

  static bool _lowMemory = false;

  /// True on Apple TV hardware that cannot afford the full cinematic Home
  /// load. Always false off tvOS and before [warm] completes.
  static bool get isLowMemoryCached => _lowMemory;

  static Future<void> warm() async {
    if (!PlatformUtil.isTvOS) return;
    try {
      final bytes = await const MethodChannel(
        'debrify/tvdevice',
      ).invokeMethod<int>('physicalMemory');
      _lowMemory = isLowMemoryBytes(bytes);
    } catch (_) {
      // An unanswered probe means an older runner build; keep the full-power
      // default rather than degrading modern hardware.
    }
  }

  /// Installed RAM measured natively, not inferred from the model table —
  /// AppleTV11,1 (2021) is 3 GB despite being a "current-looking" 4K box.
  /// The 3.5 GiB line separates the 2-3 GB units from the 4 GB 2022 model
  /// while leaving anything unprobed (0/null) on the full-power path.
  @visibleForTesting
  static bool isLowMemoryBytes(int? physicalMemoryBytes) {
    if (physicalMemoryBytes == null || physicalMemoryBytes <= 0) return false;
    const threshold = 7 << 29; // 3.5 GiB
    return physicalMemoryBytes < threshold;
  }

  @visibleForTesting
  static void debugOverride(bool value) {
    _lowMemory = value;
  }
}
