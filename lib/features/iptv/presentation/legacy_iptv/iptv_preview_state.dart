import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

class IptvPreviewState {
  // TV preview stage (the two-pane layout's left rail). Notifiers, not
  // setState: a DPAD move over the channel list must repaint the rail alone,
  // never rebuild the whole grid. [_previewShown] is the focused channel;
  // [_previewShowing] flips when the embedded player actually has frames;
  // [_previewEpoch] bumps after returning from real playback so the stage
  // remounts fresh (HeroTrailerBackdrop latches itself off for the rest of a
  // page visit once real content playback launches — a new instance is the
  // supported way to re-arm it).
  final ValueNotifier<IptvChannel?> previewShown = ValueNotifier<IptvChannel?>(
    null,
  );

  final ValueNotifier<EpgProgramme?> spotlightProgrammeShown =
      ValueNotifier<EpgProgramme?>(null);

  final ValueNotifier<bool> previewShowing = ValueNotifier<bool>(false);

  final ValueNotifier<int> previewEpoch = ValueNotifier<int>(0);

  // The URL the preview stage actually plays. For M3U/Xtream channels this is
  // just the channel URL; for Stremio-addon channels it is the current rung of
  // the candidate ladder (resolved async on focus, advanced by
  // [_onPreviewPlaybackFailed] until one plays or the list runs out). Null =
  // nothing to play, the stage shows only its static floor.
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
