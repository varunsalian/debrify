import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:flutter/material.dart';

/// Live access to the State and its current widget; no widget/context snapshot.
typedef IptvViewBindings = ({
  StateSetter setState,
  bool Function() mounted,
  BuildContext Function() context,
  String Function() searchQuery,
  bool Function() isTelevision,
  Widget? Function() searchHeader,
  VoidCallback? Function() onUpArrowFromFilters,
  ValueChanged<int>? Function() debugOnSpotlightStartupFocus,
  DateTime Function() Function() debugSpotlightNow,
});

/// References to the nine owners constructed before the State mounts.
/// This record borrows their resources and does not duplicate/dispose state.
typedef IptvCompositionStates = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  IptvRecordingState recordingState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,
});
