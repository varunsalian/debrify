import 'dart:async';

import 'package:flutter/foundation.dart';

/// Presentation lifetime, independent of playing/paused state and sync gates.
/// Owners keep overlapping player handoffs hidden until both have closed.
abstract final class PlayerVisibility {
  static final Set<Object> _owners = {};
  static final ValueNotifier<bool> _visible = ValueNotifier(false);
  static ValueListenable<bool> get visible => _visible;
  static final _refreshAllowed = ValueNotifier<bool>(true);
  static ValueListenable<bool> get refreshAllowed => _refreshAllowed;
  static final _settling = <Object, Timer>{};
  static final _stable = <Object>{};
  static final _nativeOwners = <Object>{};
  static bool get nativeVisible => _nativeOwners.isNotEmpty;
  @visibleForTesting
  static Duration settleDuration = const Duration(seconds: 30);

  static void opened(Object owner, {bool native = false}) {
    _owners.add(owner);
    if (native) _nativeOwners.add(owner);
    _publishRefreshAllowed();
    _visible.value = _owners.isNotEmpty;
  }

  /// Only uninterrupted playing/non-buffering time permits new catalog work.
  /// Existing jobs are deliberately unaffected by this scheduling signal.
  static void playbackState(Object owner, {required bool ready}) {
    if (!_owners.contains(owner)) return;
    if (!ready) {
      _settling.remove(owner)?.cancel();
      _stable.remove(owner);
      _publishRefreshAllowed();
    } else if (!_stable.contains(owner) && !_settling.containsKey(owner)) {
      _settling[owner] = Timer(settleDuration, () {
        _settling.remove(owner);
        if (_owners.contains(owner)) _stable.add(owner);
        _publishRefreshAllowed();
      });
    }
  }

  static void _publishRefreshAllowed() {
    _refreshAllowed.value = _owners.every(_stable.contains);
  }

  static void closed(Object owner) {
    _owners.remove(owner);
    _nativeOwners.remove(owner);
    _settling.remove(owner)?.cancel();
    _stable.remove(owner);
    _publishRefreshAllowed();
    _visible.value = _owners.isNotEmpty;
  }
}
