import 'package:flutter/services.dart';

import '../utils/platform_util.dart';

/// "The user finished with the Apple TV keyboard."
///
/// tvOS presents a full-screen keyboard whose action button commits and
/// dismisses **without inserting a newline** — and a literal `"\n"` is the only
/// thing the iOS text-input plugin turns into a submit action (see the comment
/// in `tvos/Runner/AppDelegate.swift`). So on Apple TV `onSubmitted` never
/// fires and every text field is a dead end: text goes in, nothing can act on
/// it.
///
/// UIKit does post the fact even though Flutter never sees it, so the native
/// side forwards `UITextFieldTextDidEndEditingNotification` here.
///
/// **This signal cannot tell commit from cancel.** Measured on an Apple TV 4K
/// (tvOS 26.6): the action button and the remote's BACK button emit the same
/// notification. Treating it as submit therefore also submits when the user
/// backs out — benign for a search box, so the listener side is opt-in per
/// field rather than global.
class TvosKeyboardSignal {
  TvosKeyboardSignal._();

  static const MethodChannel _channel = MethodChannel('debrify/tvkeyboard');

  /// Fields currently willing to be told. A set (not a single slot) because
  /// nothing guarantees only one field is mounted; each decides for itself
  /// whether it was the one being edited.
  static final Set<VoidCallback> _listeners = <VoidCallback>{};
  static bool _wired = false;

  /// Registers [onEndEditing] until the returned callback is invoked.
  static VoidCallback listen(VoidCallback onEndEditing) {
    if (!PlatformUtil.isTvOS) return () {};
    if (!_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'endEditing') return null;
        // Copy: a listener may unregister itself while being notified.
        for (final l in List<VoidCallback>.of(_listeners)) {
          l();
        }
        return null;
      });
    }
    _listeners.add(onEndEditing);
    return () => _listeners.remove(onEndEditing);
  }
}
