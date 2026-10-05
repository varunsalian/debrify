import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart';

class DebrifyTvSections {
  // TEMP(debrify_tv): borrows remaining facade callbacks; removed in step 7.
  final DebrifyTvDependencies legacy;
  final DebrifyTvFeedback feedback;
  final DebrifyTvSettingsLoader settings;
  final DebrifyTvEngineLimits engines;
  final DebrifyTvPlaybackFilters filters;
  final DebrifyTvChannelLibrary library;
  final DebrifyTvSpotlightStage stage;
  DebrifyTvSections(DebrifyTvDependencies deps)
    : legacy = deps,
      feedback = DebrifyTvFeedback(deps),
      settings = DebrifyTvSettingsLoader(deps),
      engines = DebrifyTvEngineLimits(deps),
      filters = DebrifyTvPlaybackFilters(deps),
      library = DebrifyTvChannelLibrary(deps),
      stage = DebrifyTvSpotlightStage(deps) {
    deps.sections = this;
  }
}
