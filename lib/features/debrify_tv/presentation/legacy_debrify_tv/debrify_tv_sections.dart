import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_all_debrid.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_pikpak.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_premiumize.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_real_debrid.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_torbox.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_editor.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_export.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_save.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_share.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_switch.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_watch.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dialogs.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dormant.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_cards.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_layout.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_persistence.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_alldebrid.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_pikpak.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_premiumize.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_torbox.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_card.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_chips.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart';

class DebrifyTvSections {
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
  final DebrifyTvQuickPlay quickPlay;
  final DebrifyTvQuickPlayTorbox quickTorbox;
  final DebrifyTvQuickPlayPikPak quickPikPak;
  final DebrifyTvQuickPlayPremiumize quickPremiumize;
  final DebrifyTvQuickPlayAllDebrid quickAllDebrid;
  final DebrifyTvChannelWatch channelWatch;
  final DebrifyTvChannelSwitch channelSwitch;
  final DebrifyTvCachedRealDebrid cachedRealDebrid;
  final DebrifyTvCachedAllDebrid cachedAllDebrid;
  final DebrifyTvCachedTorbox cachedTorbox;
  final DebrifyTvCachedPikPak cachedPikPak;
  final DebrifyTvCachedPremiumize cachedPremiumize;
  final DebrifyTvPlayerHandoff handoff;
  final DebrifyTvTorboxResolver torbox;
  final DebrifyTvCloudResolvers cloud;
  final DebrifyTvPrefetcher prefetch;
  final DebrifyTvDormant dormant;
  final DebrifyTvSettingsChips chips;
  final DebrifyTvSettingsCard settingsCard;
  final DebrifyTvDialogs dialogs;
  final DebrifyTvSpotlightStage stage;
  final DebrifyTvTopBar topBar;
  final DebrifyTvGridLayout grid;
  final DebrifyTvGridCards cards;
  DebrifyTvSections(DebrifyTvDependencies deps)
    : feedback = DebrifyTvFeedback(deps),
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
      quickPlay = DebrifyTvQuickPlay(deps),
      quickTorbox = DebrifyTvQuickPlayTorbox(deps),
      quickPikPak = DebrifyTvQuickPlayPikPak(deps),
      quickPremiumize = DebrifyTvQuickPlayPremiumize(deps),
      quickAllDebrid = DebrifyTvQuickPlayAllDebrid(deps),
      channelWatch = DebrifyTvChannelWatch(deps),
      channelSwitch = DebrifyTvChannelSwitch(deps),
      cachedRealDebrid = DebrifyTvCachedRealDebrid(deps),
      cachedAllDebrid = DebrifyTvCachedAllDebrid(deps),
      cachedTorbox = DebrifyTvCachedTorbox(deps),
      cachedPikPak = DebrifyTvCachedPikPak(deps),
      cachedPremiumize = DebrifyTvCachedPremiumize(deps),
      handoff = DebrifyTvPlayerHandoff(deps),
      torbox = DebrifyTvTorboxResolver(deps),
      cloud = DebrifyTvCloudResolvers(deps),
      prefetch = DebrifyTvPrefetcher(deps),
      dormant = DebrifyTvDormant(deps),
      chips = DebrifyTvSettingsChips(deps),
      settingsCard = DebrifyTvSettingsCard(deps),
      dialogs = DebrifyTvDialogs(deps),
      stage = DebrifyTvSpotlightStage(deps),
      topBar = DebrifyTvTopBar(deps),
      grid = DebrifyTvGridLayout(deps),
      cards = DebrifyTvGridCards(deps) {
    deps.sections = this;
  }
}
