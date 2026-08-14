import 'package:flutter/foundation.dart';

import '../../utils/platform_util.dart';

/// The one place that decides whether this device accepts *user* avatar files.
///
/// Apple TV does not. `AppStorage` redirects Documents to `Library/Caches` on
/// real hardware because Documents and Application Support are read-only there,
/// and that cache is purgeable — its own contract says nothing in it should be
/// treated as durable user data. Rather than build a missing-file state, an
/// automatic re-request from the phone and a repair affordance to survive that,
/// tvOS is restricted to art and icons, which are code and assets and cannot be
/// purged at all.
///
/// That decision has three enforcement points — the avatar picker, package
/// restore, and the phone transfer receiver — and they all funnel through here.
/// Checking `isTvOS` at each call site instead would let the rule drift, and a
/// rule enforced in two places out of three is not enforced.
///
/// Art and icons are unaffected on every platform; this gates user files only.
class ProfileAvatarPolicy {
  ProfileAvatarPolicy._();

  static bool? _override;

  static bool get userImagesSupported => _override ?? !PlatformUtil.isTvOS;

  /// Lets a test exercise the tvOS branch on a desktop test runner. Pass null
  /// to restore real platform behaviour.
  @visibleForTesting
  static void debugSetUserImagesSupported(bool? value) => _override = value;
}
