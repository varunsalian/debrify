import 'package:flutter/widgets.dart';

/// One-shot focus transfer from a submitted TV search field to its results.
///
/// Android's stock IME unfocuses an [EditableText] before it invokes
/// `onSubmitted`, while [TvTextField]'s in-app keyboard deliberately returns
/// focus to its non-editing shell. Search surfaces need to accept both states:
/// the field may still own focus, or focus may have fallen back to a
/// [FocusScopeNode].
///
/// A concrete focus node anywhere else means the user moved on while the
/// search was in flight. In that case the pending transfer is consumed without
/// moving focus, so a late result can never yank the remote away from them.
class TvSearchFocusHandoff {
  int _serial = 0;
  int? _pendingSerial;

  bool get pending => _pendingSerial != null;

  /// Arms a new one-shot transfer. A non-TV submission clears any older one.
  void arm({required bool enabled}) {
    final serial = ++_serial;
    _pendingSerial = enabled ? serial : null;
  }

  void cancel() {
    _serial++;
    _pendingSerial = null;
  }

  /// Runs [requestFocus] after the result frame is mounted, if focus still
  /// belongs to this submission.
  void complete({
    required FocusNode field,
    required bool Function() isMounted,
    required VoidCallback requestFocus,
    bool Function()? targetHasFocus,
  }) {
    final serial = _pendingSerial;
    if (serial == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingSerial != serial || !isMounted()) return;

      if (targetHasFocus?.call() ?? false) {
        _pendingSerial = null;
        return;
      }

      final primary = FocusManager.instance.primaryFocus;
      final fieldStillOwnsFocus = field.hasPrimaryFocus;
      final stockImeDroppedFocus = primary == null || primary is FocusScopeNode;

      // Consume before requesting focus: a synchronous focus listener may
      // rebuild or even start another search.
      _pendingSerial = null;
      if (!fieldStillOwnsFocus && !stockImeDroppedFocus) return;
      requestFocus();
    });
  }
}
