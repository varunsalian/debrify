import 'dart:async';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_return_observers.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

final class ExternalActivityLifecycle {
  /// Runs [action] once another activity takes the foreground (first
  /// lifecycle state away from resumed), or after a short timeout if that
  /// never happens. Lets a play-flow loading overlay stay up through an
  /// external-activity launch transition, dismissed only while it's hidden —
  /// the timeout guarantees a launch that silently dies can't strand it.
  static void runWhenCoveredByExternalActivity(VoidCallback action) {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      action();
      return;
    }
    var done = false;
    Timer? fallback;
    late final AppCoverObserver observer;
    void finish() {
      if (done) return;
      done = true;
      fallback?.cancel();
      binding.removeObserver(observer);
      action();
    }

    observer = AppCoverObserver(onCovered: finish);
    binding.addObserver(observer);
    fallback = Timer(const Duration(seconds: 4), finish);
  }

  /// How long to wait for the launched activity to actually cover the app
  /// before giving up on ever seeing it return (see
  /// [_notifyOnReturnFromExternalActivity]).
  static const Duration externalReturnArmTimeout = Duration(seconds: 30);

  /// Arms the one-shot "the player activity gave the screen back" signal.
  ///
  /// [_runWhenCoveredByExternalActivity] answers *"the player took over"*;
  /// this answers *"the player finished"* — the moment watch progress is final
  /// and every resume label / episode tick / Continue Watching row on screen is
  /// stale. External-activity launches push no Flutter route, so this is the
  /// only signal those screens can hang a refresh off (see
  /// [MainPageBridge.notifyPlaybackReturned]).
  ///
  /// Only fires on a cover→resume PAIR, so a launch that silently died (app
  /// never left the foreground) can't be mistaken for a finished playback. If
  /// the cover never comes within [_externalReturnArmTimeout] the observer is
  /// dropped, so it can't leak or fire on some unrelated later resume.
  static AppReturnObserver? armedReturnObserver;

  static void notifyOnReturnFromExternalActivity() {
    // Already armed — a launch issued while the player activity still owns the
    // screen (Debrify TV moving to the next channel, a playlist advancing)
    // must not stack a second observer: they'd both fire on the one resume and
    // every listener would refresh twice.
    if (ExternalActivityLifecycle.armedReturnObserver != null) return;

    final binding = WidgetsBinding.instance;
    var done = false;
    late final AppReturnObserver observer;
    void finish({required bool notify}) {
      if (done) return;
      done = true;
      binding.removeObserver(observer);
      if (identical(ExternalActivityLifecycle.armedReturnObserver, observer)) {
        ExternalActivityLifecycle.armedReturnObserver = null;
      }
      if (notify) MainPageBridge.notifyPlaybackReturned();
    }

    observer = AppReturnObserver(onReturned: () => finish(notify: true));
    // Launch prep can await across the activity transition, so the player may
    // ALREADY be covering us by the time we arm. Seed from the live state —
    // otherwise the only lifecycle event left is the resume, which an unseeded
    // observer would discard as "never covered" and the refresh would be lost.
    observer.wasCovered = binding.lifecycleState != AppLifecycleState.resumed;
    ExternalActivityLifecycle.armedReturnObserver = observer;
    binding.addObserver(observer);
    Timer(ExternalActivityLifecycle.externalReturnArmTimeout, () {
      if (!observer.wasCovered) {
        finish(notify: false);
        MainPageBridge.notifyContentPlaybackStopped();
      }
    });
  }
}
