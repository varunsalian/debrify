import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';

/// Constructs the original nine owners eagerly and in their original order.
/// The State retains ordered lifecycle teardown; this holder never disposes them.
class IptvCompositionOwners {
  final catalogState = IptvCatalogState();
  final focusState = IptvFocusState();
  final membershipState = IptvMembershipState();
  final playerState = IptvPlayerState();
  final previewState = IptvPreviewState();
  final recordingState = IptvRecordingState();
  final selectionState = IptvSelectionState();
  final settingsState = IptvSettingsState();
  final statusState = IptvStatusState();

  IptvCompositionStates get states => (
    catalogState: catalogState,
    focusState: focusState,
    membershipState: membershipState,
    playerState: playerState,
    previewState: previewState,
    recordingState: recordingState,
    selectionState: selectionState,
    settingsState: settingsState,
    statusState: statusState,
  );
}
