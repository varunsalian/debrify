import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_editor.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_export.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_save.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_share.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dormant.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_persistence.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart';

class DebrifyTvSections {
  // TEMP(debrify_tv): borrows remaining facade callbacks; removed in step 7.
  final DebrifyTvDependencies legacy;
  final DebrifyTvFeedback feedback;
  final DebrifyTvSettingsLoader settings;
  final DebrifyTvEngineLimits engines;
  final DebrifyTvPlaybackFilters filters;
  final DebrifyTvChannelLibrary library;
  final DebrifyTvChannelWarmup warmup;
  final DebrifyTvChannelEditor editor;
  final DebrifyTvChannelActions actions;
  final DebrifyTvChannelSave save;
  final DebrifyTvChannelShare share;
  final DebrifyTvChannelExport channelExport;
  final DebrifyTvChannelImport channelImport;
  final DebrifyTvUrlImport urlImport;
  final DebrifyTvImportFormats formats;
  final DebrifyTvImportPersistence persistence;
  final DebrifyTvPlayerHandoff handoff;
  final DebrifyTvTorboxResolver torbox;
  final DebrifyTvCloudResolvers cloud;
  final DebrifyTvPrefetcher prefetch;
  final DebrifyTvDormant dormant;
  final DebrifyTvSpotlightStage stage;
  DebrifyTvSections(DebrifyTvDependencies deps)
    : legacy = deps,
      feedback = DebrifyTvFeedback(deps),
      settings = DebrifyTvSettingsLoader(deps),
      engines = DebrifyTvEngineLimits(deps),
      filters = DebrifyTvPlaybackFilters(deps),
      library = DebrifyTvChannelLibrary(deps),
      warmup = DebrifyTvChannelWarmup(deps),
      editor = DebrifyTvChannelEditor(deps),
      actions = DebrifyTvChannelActions(deps),
      save = DebrifyTvChannelSave(deps),
      share = DebrifyTvChannelShare(deps),
      channelExport = DebrifyTvChannelExport(deps),
      channelImport = DebrifyTvChannelImport(deps),
      urlImport = DebrifyTvUrlImport(deps),
      formats = DebrifyTvImportFormats(deps),
      persistence = DebrifyTvImportPersistence(deps),
      handoff = DebrifyTvPlayerHandoff(deps),
      torbox = DebrifyTvTorboxResolver(deps),
      cloud = DebrifyTvCloudResolvers(deps),
      prefetch = DebrifyTvPrefetcher(deps),
      dormant = DebrifyTvDormant(deps),
      stage = DebrifyTvSpotlightStage(deps) {
    deps.sections = this;
  }
}
