import 'dart:async';

import 'package:flutter/material.dart';

class StremioTvTunerOwners {
  /// Drives the live "broadcast" — re-evaluates now-playing every second so
  /// progress bars sweep and slot rollovers flip themselves on screen.
  Timer? tick;

  /// Channel id currently driving the Stage (wide) / page (narrow).
  /// A ValueNotifier so a surf step only rebuilds the Stage (via the
  /// ValueListenableBuilder in [_buildWide]) — the Home hero's model — instead
  /// of setState-ing the whole tuner and re-running every dial card.
  final ValueNotifier<String?> activeId = ValueNotifier<String?>(null);

  /// Channel id currently CENTRED in the dial (touch layout only). Kept apart
  /// from [_activeId] because the centre ring has to track the finger frame by
  /// frame while the expensive Stage swap stays behind [_setActive]'s settle
  /// debounce.
  final ValueNotifier<String?> centredId = ValueNotifier<String?>(null);

  /// Latest focused channel id, awaiting the focus-settle debounce before it
  /// becomes [_activeId] and triggers the heavy Stage swap.
  String? pendingId;

  Timer? settle;

  /// O(1) channel-id → index into [StremioTvTuner.allChannels] (and thus into
  /// [StremioTvTuner.rowFocusNodes]). Rebuilt whenever the widget updates.
  /// Replaces the per-lookup indexWhere scans that made every DPAD press and
  /// every rebuild O(n²) once genre expansion pushed the channel count into
  /// the hundreds.
  Map<String, int> indexById = const {};

  final PageController pageController = PageController();

  /// Drives the wide layout's horizontal channel dial. Needed on desktop so a
  /// mouse (no DPAD focus to auto-scroll) can pan the row: a vertical wheel is
  /// mapped to horizontal offset, and mouse/trackpad drag is enabled below.
  final ScrollController dialScroll = ScrollController();
}
