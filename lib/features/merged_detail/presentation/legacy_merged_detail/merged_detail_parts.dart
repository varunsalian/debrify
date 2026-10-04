import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart';

class MergedDetailParts {
  final MergedDetailMetadataState metadataState;
  final MergedDetailTrailerState trailerState;
  final MergedDetailResumeState resumeState;
  final MergedDetailFocusState focusState;
  final MergedDetailResumeActions resumeActions;
  final MergedDetailTrackingState trackingState;
  final MergedDetailWatchlistActions watchlistActions;
  final MergedDetailPlaybackActions playbackActions;
  final MergedDetailTrackingActions trackingActions;
  final MergedDetailModelFactory modelFactory;
  MergedDetailParts(MergedDetailDependencies deps)
    : metadataState = MergedDetailMetadataState(),
      trailerState = MergedDetailTrailerState(),
      resumeState = MergedDetailResumeState(),
      focusState = MergedDetailFocusState(),
      resumeActions = MergedDetailResumeActions(deps),
      trackingState = MergedDetailTrackingState(),
      watchlistActions = MergedDetailWatchlistActions(deps),
      playbackActions = MergedDetailPlaybackActions(deps),
      trackingActions = MergedDetailTrackingActions(deps),
      modelFactory = MergedDetailModelFactory();
}
