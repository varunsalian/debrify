import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_menus.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_loading.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart';

class MergedDetailParts {
  final MergedDetailMetadataState metadataState;
  final MergedDetailTrailerState trailerState;
  final MergedDetailResumeState resumeState;
  final MergedDetailFocusState focusState;
  final MergedDetailResumeActions resumeActions;
  final MergedDetailTrackingState trackingState;
  final MergedDetailMenus menus;
  final MergedDetailWatchlistActions watchlistActions;
  final MergedDetailPlaybackActions playbackActions;
  final MergedDetailMetadataLoading metadataLoading;
  final MergedDetailTrackingActions trackingActions;
  final MergedDetailTrailerActions trailerActions;
  final MergedDetailMetadataActions metadataActions;
  final MergedDetailModelFactory modelFactory;
  MergedDetailParts(MergedDetailDependencies deps)
    : metadataState = MergedDetailMetadataState(deps),
      trailerState = MergedDetailTrailerState(),
      resumeState = MergedDetailResumeState(),
      focusState = MergedDetailFocusState(),
      resumeActions = MergedDetailResumeActions(deps),
      trackingState = MergedDetailTrackingState(),
      menus = MergedDetailMenus(deps),
      watchlistActions = MergedDetailWatchlistActions(deps),
      playbackActions = MergedDetailPlaybackActions(deps),
      metadataLoading = MergedDetailMetadataLoading(deps),
      trackingActions = MergedDetailTrackingActions(deps),
      trailerActions = MergedDetailTrailerActions(deps),
      metadataActions = MergedDetailMetadataActions(deps),
      modelFactory = MergedDetailModelFactory(deps);
}
