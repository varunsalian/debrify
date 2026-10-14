import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vp_fixture_actions.dart';

/// Holds only the real result-focus post-frame callback; all other frames,
/// mounts and callbacks use the ordinary automated widget-test binding.
class IdentifyFocusBinding extends AutomatedTestWidgetsFlutterBinding {
  bool hold = false;
  final pending = <void Function()>[];
  @override
  void addPostFrameCallback(
    FrameCallback callback, {
    String debugLabel = 'callback',
  }) {
    if (hold &&
        StackTrace.current.toString().contains(
          'tv_search_focus_handoff.dart',
        )) {
      super.addPostFrameCallback((time) {
        pending.add(
          VpFixtureActions.heldCallback(
            'identify-focus-post-frame',
            () => callback(time),
          ),
        );
      }, debugLabel: debugLabel);
    } else {
      super.addPostFrameCallback(callback, debugLabel: debugLabel);
    }
  }

  void release() {
    hold = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
