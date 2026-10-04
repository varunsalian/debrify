import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';

class MergedDetailParts {
  final MergedDetailMetadataState metadataState;
  final MergedDetailTrailerState trailerState;
  final MergedDetailResumeState resumeState;
  final MergedDetailFocusState focusState;
  final MergedDetailTrackingState trackingState;
  final MergedDetailModelFactory modelFactory;
  MergedDetailParts(MergedDetailDependencies deps)
    : metadataState = MergedDetailMetadataState(),
      trailerState = MergedDetailTrailerState(),
      resumeState = MergedDetailResumeState(),
      focusState = MergedDetailFocusState(),
      trackingState = MergedDetailTrackingState(),
      modelFactory = MergedDetailModelFactory();
}
