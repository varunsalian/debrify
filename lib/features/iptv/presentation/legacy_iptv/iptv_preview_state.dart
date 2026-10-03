import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

class IptvPreviewState {
  final ValueNotifier<IptvChannel?> previewShown = ValueNotifier<IptvChannel?>(
    null,
  );

  final ValueNotifier<EpgProgramme?> spotlightProgrammeShown =
      ValueNotifier<EpgProgramme?>(null);

  final ValueNotifier<bool> previewShowing = ValueNotifier<bool>(false);

  final ValueNotifier<int> previewEpoch = ValueNotifier<int>(0);

  final ValueNotifier<String?> previewStreamUrl = ValueNotifier<String?>(null);

  /// Candidate URLs for the focused Stremio channel; null while a non-Stremio
  /// channel is focused (their failures keep the old silent-floor behavior).
  List<String>? previewCandidates;

  /// Guards async resolves against focus moving on before they land.
  int previewResolveTicket = 0;

  bool previewRearmPending = false;

  /// True while the pointer sits inside the preview stage. See
  /// [_stageHoverGuard].
  bool pointerInStage = false;
}
