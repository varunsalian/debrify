import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotlightBoardHeroState {
  final cancelHeroWarmups = <VoidCallback>{};

  /// Which hero item is showing. Held by ID so a rail re-order does not move
  /// the page under the user.
  String? heroId;

  /// Left-third luminance per backdrop URL. Probed once; the result decides
  /// which side the identity sits on.
  final Map<String, double> leftThird = {};

  /// The hero's cadence: resolve its trailer as soon as it is eligible.
  /// **Never an advance.**
  ///
  ///     art ──▶ resolve immediately ──▶ trailer (loops until a move)
  ///      ▲                                      │
  ///      └──────── swipe / LEFT/RIGHT ──────────┘
  ///
  /// The reel used to page itself (art → trailer → advance → next art, and a
  /// plain timed advance with trailers off). Killed by user call, on every
  /// device: a carousel that moves under you takes the choice away — the
  /// reel now moves ONLY on a swipe, a dot tap, or a DPAD page. The one
  /// timer is now only a cancellable next-event-loop handoff: trailer lookup
  /// already takes noticeable time, so an artificial art dwell only makes the
  /// hero feel unresponsive.
  ///
  /// ONE timer with ONE owner. The shared `_scheduleHeroTrailer` is excluded
  /// for this style precisely so the two cannot interleave and start a trailer
  /// under the wrong title.
  static const Duration hiddenRetry = Duration(seconds: 1);

  Timer? cadence;

  /// Whether the cadence has asked the host for a trailer.
  ///
  /// Bookkeeping for the CLOCK only — it must never gate the trailer widget.
  /// The host owns the engine's lifetime and tears it down on playback launch,
  /// route push and style change; a second opinion here is how a released
  /// engine stayed mounted.
  bool rolling = false;

  /// Desktop previews and the hero share the process-wide video-output lease.
  /// Keep a small owner set rather than a bool: when the pointer moves from
  /// one live card to another, MouseRegion enter/exit ordering must never
  /// briefly restart the hero between the two previews.
  final Set<Object> desktopPreviewOwners = <Object>{};

  String? dwelledHeroId;

  /// Bumped on every hero change. A probe that resolves after the user has
  /// paged on must not publish its colour over the current one.
  int probeGen = 0;

  final Map<String, Color?> tints = {};

  ({String? art, Color? tint})? lastAmbient;

  void Function(String?, Color?)? lastAmbientSink;

  /// Which item `_flipValue` was decided for.
  String? flipFor;

  bool flipValue = false;
}
