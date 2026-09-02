import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_util.dart';

/// Raised when the legacy migration cannot fit inside the tvOS preference
/// budget. Bootstrap catches this and stays in legacy mode; it must never
/// reach `main()`, where an uncaught error prevents the app from starting.
class ProfilePreferenceBudgetExceeded implements Exception {
  const ProfilePreferenceBudgetExceeded({
    required this.projectedBytes,
    required this.limitBytes,
  });

  final int projectedBytes;
  final int limitBytes;

  @override
  String toString() =>
      'ProfilePreferenceBudgetExceeded($projectedBytes > $limitBytes bytes)';
}

/// Keeps the tvOS `UserDefaults` database away from the platform limit.
///
/// tvOS terminates the process — it does not return an error — once the
/// defaults database reaches 1 MiB, and warns at 512 KiB. The limit is
/// database-wide, so scoping a value behind a profile prefix does not move it
/// out of the way. Debrify stores several unbounded collections there
/// (playback state, episode progress, per-title sources, playlists), so
/// ordinary use can reach the ceiling without any cache involved.
///
/// Measurement runs entirely in Dart. `shared_preferences` keeps every value in
/// an in-memory map, so no platform call is involved and the measurement can
/// run on every write — which removes cache drift as a failure mode entirely.
/// Everything that grows is written from Dart, so this view captures all of the
/// growth; native and plugin keys are invisible here but small and constant,
/// and the margin below covers them many times over.
///
/// The cost is O(total stored bytes), not O(keys): [_utf8Length] walks the code
/// units of every stored string. At the ceiling that is a few hundred thousand
/// iterations per admitted growing write — cheap next to the platform-channel
/// round trip and the recovery checkpoint that follow it, but not free. Writes
/// that shrink or keep the size skip the scan entirely. A cached running total
/// would avoid it, at the cost of drifting whenever a writer bypasses this
/// class — which several do.
class ProfilePreferenceBudget {
  ProfilePreferenceBudget._();

  /// Refusal threshold, measured against the conservative estimate below.
  ///
  /// The platform kills the process at 1 MiB. Because [entryFootprint]
  /// overestimates, staying under this bound keeps real usage near Apple's
  /// 512 KiB warning rather than near the kill line. The largest real
  /// installation observed measured roughly 72 KiB.
  static const int limitBytes = 384 * 1024;

  /// Writes smaller than this stay allowed above [limitBytes], up to
  /// [emergencyLimitBytes].
  ///
  /// The stores that reach the platform limit are large ones. Refusing every
  /// write once saturated would also drop settings and sealed credentials —
  /// and those failures are invisible, because `SecretVault.setString` returns
  /// `Future<void>` and discards the result, so the UI reports a saved API key
  /// that was never stored. Sealing also makes a credential larger than its
  /// plaintext, so they are exactly the growing writes that would be refused.
  static const int smallWriteBytes = 4 * 1024;

  /// Nothing grows past this, however small. Still well under the 1 MiB the
  /// platform kills the process at, and at Apple's own warning threshold.
  static const int emergencyLimitBytes = 512 * 1024;

  /// Headroom the legacy migration must leave for ordinary use afterwards.
  ///
  /// Migration is non-destructive, so it lands the database at roughly double
  /// the legacy size. Preflighting against [limitBytes] alone would let an
  /// install migrate to exactly the ceiling and then refuse every subsequent
  /// write — migrating successfully into a permanently saturated state.
  static const int migrationReserveBytes = 128 * 1024;

  /// Ceiling the migration preflight projects against.
  static const int migrationLimitBytes = limitBytes - migrationReserveBytes;

  /// Per-entry allowance for binary-plist structure plus the `flutter.` prefix
  /// the plugin adds natively. The app never calls `SharedPreferences.setPrefix`,
  /// so every Dart key carries that prefix on device.
  static const int perEntryOverheadBytes = 64;

  /// Test seam. [PlatformUtil.isTvOS] is a `static final` derived from
  /// `Platform.operatingSystem` and cannot be overridden, so tests drive
  /// enforcement through this instead.
  @visibleForTesting
  static bool? debugEnforcedOverride;

  static bool get enforced => debugEnforcedOverride ?? PlatformUtil.isTvOS;

  @visibleForTesting
  static void debugReset() {
    debugEnforcedOverride = null;
    _reportedSaturation = false;
  }

  /// Conservative on-disk cost of one stored entry.
  static int entryFootprint(String key, Object? value) =>
      perEntryOverheadBytes + _utf8Length(key) + _valueFootprint(value);

  /// Total measured size of the whole defaults database.
  static int measure(SharedPreferences preferences) {
    var total = 0;
    for (final key in preferences.getKeys()) {
      total += entryFootprint(key, preferences.get(key));
    }
    return total;
  }

  /// Whether writing [value] at [key] is allowed.
  ///
  /// A write that does not grow the database is always admitted, even when
  /// already over budget. Without that rule an over-budget installation could
  /// never shrink itself back and would be permanently stuck.
  ///
  /// This is synchronous, but the caller awaits the write it guards, so two
  /// writes racing at the boundary can both be admitted and overshoot by one
  /// value. That is deliberate: the limit sits ~640 KiB below the threshold
  /// that terminates the process, which absorbs any single overshoot.
  static bool admits(SharedPreferences preferences, String key, Object? value) {
    if (!enforced) return true;
    final replaced = preferences.containsKey(key)
        ? entryFootprint(key, preferences.get(key))
        : 0;
    final delta = entryFootprint(key, value) - replaced;
    return admitsProjectedDelta(
      currentBytes: delta <= 0 ? 0 : measure(preferences),
      deltaBytes: delta,
    );
  }

  /// Applies the same policy to a caller-computed projection. This lets a
  /// multi-key transaction prove its final sequence before its first native
  /// write instead of discovering the limit after a partial batch.
  static bool admitsProjectedDelta({
    required int currentBytes,
    required int deltaBytes,
  }) {
    // Shrinking and same-size writes skip the scan entirely, so the common
    // rewrite-in-place case costs nothing.
    if (deltaBytes <= 0) return true;
    final projected = currentBytes + deltaBytes;
    if (projected <= limitBytes) return true;
    // Above the limit only bulk growth is refused; settings and credentials
    // keep saving until the emergency ceiling.
    if (deltaBytes < smallWriteBytes && projected <= emergencyLimitBytes) {
      _reportSaturationOnce(projected);
      return true;
    }
    _reportSaturationOnce(projected);
    return false;
  }

  /// Reports the first refusal only. Past the limit an ordinary write path can
  /// retry every few seconds, and one line is the actionable signal. Key names
  /// and values are never logged: they carry titles and identifiers.
  static void _reportSaturationOnce(int projectedBytes) {
    if (_reportedSaturation) return;
    _reportedSaturation = true;
    debugPrint(
      'tvOS preference budget reached: preferences project $projectedBytes '
      'bytes against a $limitBytes byte limit. Bulk writes are now refused to '
      'keep the database below the size the platform terminates the process '
      'at; writes under $smallWriteBytes bytes continue until '
      '$emergencyLimitBytes bytes.',
    );
  }

  static bool _reportedSaturation = false;

  static int _valueFootprint(Object? value) => switch (value) {
    null => 0,
    bool _ => 1,
    int _ => 8,
    double _ => 8,
    String value => _utf8Length(value),
    // The in-memory cache stores string lists as `List<dynamic>`, so matching
    // on `List<String>` would silently score a large list as a few bytes.
    List<Object?> value => value.fold<int>(
      0,
      (sum, item) => sum + 8 + (item is String ? _utf8Length(item) : 8),
    ),
    _ => 16,
  };

  /// Exact UTF-8 byte length without allocating an encoded copy. Called for
  /// every stored string on every write, so `utf8.encode(...).length` would
  /// duplicate the entire database each time.
  static int _utf8Length(String value) {
    var bytes = 0;
    for (final unit in value.codeUnits) {
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit < 0xDC00) {
        // High surrogate: count the whole 4-byte pair here.
        bytes += 4;
      } else if (unit >= 0xDC00 && unit < 0xE000) {
        // Low surrogate: already counted with its high surrogate.
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}
