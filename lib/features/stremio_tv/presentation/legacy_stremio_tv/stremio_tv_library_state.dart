import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/screens/stremio_tv/stremio_tv_service.dart';
import 'package:flutter/material.dart';

class StremioTvLibraryState {
  final StremioTvService service = StremioTvService.instance;

  List<StremioTvChannel> channels = [];

  bool loading = true;

  bool refreshing = false;

  /// Bumped whenever a channel's items finish lazy-loading. The tuner is
  /// wrapped in a ValueListenableBuilder on this, so a load completing
  /// mid-surf rebuilds only the tuner subtree — not the whole screen with its
  /// header — which is what made DPAD navigation stutter while channels were
  /// still tuning in.
  final ValueNotifier<int> contentRevision = ValueNotifier<int>(0);
  // Mix salt (0-9, cycles on shuffle button)
  int mixSalt = 0;
  // Lazy loading: track channels currently being fetched to avoid duplicates
  final Set<String> loadingChannelIds = {};
}
