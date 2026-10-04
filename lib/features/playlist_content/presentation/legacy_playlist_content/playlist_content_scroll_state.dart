import 'dart:async';
import 'package:flutter/material.dart';

class PlaylistContentScrollState {
  // Auto-scroll state
  final ScrollController episodeListScrollController = ScrollController();

  int? targetEpisodeIndex; // Episode to scroll to after list is built

  Timer? scrollRetryTimer; // Timer for scroll retry to prevent memory leaks

  bool isScrollScheduled = false; // Flag to prevent duplicate scroll scheduling
}
