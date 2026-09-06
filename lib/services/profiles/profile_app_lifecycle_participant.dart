import 'package:flutter/foundation.dart';

import '../../screens/video_player/services/subtitle_settings_service.dart';
import '../../theme/app_theme_controller.dart';
import '../account_service.dart';
import '../alldebrid_account_service.dart';
import '../discover_prefs.dart';
import '../hide_watched_prefs.dart';
import '../debrify_tv_database.dart';
import '../download_service.dart';
import '../iptv_catalog_db.dart';
import '../iptv_service.dart';
import '../mdblist/mdblist_service.dart';
import '../mdblist/mdblist_id_resolver.dart';
import '../mdblist/mdblist_continue_watching_service.dart';
import '../mdblist/mdblist_calendar_service.dart';
import '../mdblist/mdblist_discover_source.dart';
import '../mdblist/mdblist_sync_coordinator.dart';
import '../main_page_bridge.dart';
import '../pikpak_api_service.dart';
import '../premiumize_account_service.dart';
import '../remote_control/remote_command_router.dart';
import '../simkl/simkl_service.dart';
import '../storage_service.dart';
import '../stream_badges_service.dart';
import '../stremio_service.dart';
import '../subtitle_font_service.dart';
import '../play_loader_style.dart';
import '../text_brightness.dart';
import '../trakt/trakt_service.dart';
import '../watched_status_service.dart';
import '../torbox_account_service.dart';
import '../tv_hero_artwork_quality_controller.dart';
import '../tvos_top_shelf_service.dart';
import '../xtream_codes_service.dart';
import '../engine/engine_profile_lifecycle.dart';
import '../engine/engine_registry.dart';
import 'profile_cache_ledger.dart';
import 'profile_lifecycle.dart';
import 'native_profile_projection.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';
import 'profile_session_memory.dart';

/// Resets process-wide mirrors that otherwise retain profile A, then warms the
/// target under its captured scope after authoritative publication.
class ProfileAppLifecycleParticipant implements ProfileLifecycleParticipant {
  @override
  Future<void> prepareDeactivate(ProfileScope current) async {
    ProfileSessionMemory.clearAll();
    EngineProfileLifecycle.prepareDeactivate();
    MainPageBridge.clearProfileSessionState();
    await TvosTopShelfService.instance.clear();
    RemoteCommandRouter().clearProfileSessionState();
    await DownloadService.instance.prepareProfileSwitch();
    await IptvCatalogDb.closeScope();
    await DebrifyTvDatabase.instance.closeScope(current);
    StremioService.instance.invalidateCache();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    PikPakApiService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    MdblistIdResolver.instance.resetProfileScope();
    MdblistContinueWatchingService.instance.resetProfileScope();
    MdblistCalendarService.instance.resetProfileScope();
    MdblistDiscoverSource.instance.resetProfileScope();
    MdblistSyncCoordinator.instance.resetProfileScope();
    WatchedStatusService.instance.resetProfileScope();
    IptvService.instance.clearCache();
    XtreamCodesService.instance.clearCache();
    DiscoverPrefs.resetProfileScope();
    HideWatchedPrefs.resetProfileScope();
    StreamBadgesService.instance.resetProfileScope();
    SubtitleFontService.instance.resetProfileScope();
    SubtitleSettingsService.instance.resetProfileScope();
    AccountService.clearUserInfo();
    TorboxAccountService.clearUserInfo();
    PremiumizeAccountService.clearUserInfo();
    AllDebridAccountService.clearUserInfo();
  }

  @override
  Future<void> initializeCandidate(ProfileScope candidate) => _warm(candidate);

  @override
  Future<void> didActivate(ProfileScope active) async {
    DebrifyTvDatabase.instance.activateScope(active);
    await NativeProfileProjection.publish(active);
    DownloadService.instance.finishProfileSwitch();
  }

  @override
  Future<void> rollback(ProfileScope restored) async {
    // Candidate staging may have opened a scoped database before publication.
    // Close it before warming the restored scope so a failed switch/restore
    // cannot leave the process attached to the invisible generation.
    await IptvCatalogDb.closeScope();
    await DebrifyTvDatabase.instance.closeScope();
    // closeScope deliberately tombstones its owner before awaiting the close.
    // Re-authorize the restored authoritative scope before warmers may touch
    // Debrify TV storage.
    DebrifyTvDatabase.instance.activateScope(restored);
    await _warm(restored);
    await NativeProfileProjection.publish(restored);
    DownloadService.instance.finishProfileSwitch();
  }

  /// Warms [reset] and records that this cache now belongs to [scope].
  ///
  /// Stamped one group at a time rather than once at the end: a throw partway
  /// through the warm must leave every later cache showing its PREVIOUS scope,
  /// because that stale stamp is the observable signature of the leak. See
  /// [ProfileCacheLedger].
  void _warmed(String name, ProfileScope scope, void Function() reset) {
    reset();
    ProfileCacheLedger.stamp(name, scope);
  }

  Future<void> _warm(ProfileScope scope) {
    return ProfileRuntime.withCapturedScope(scope, () async {
      _warmed('StorageService', scope, StorageService.resetProfileCaches);
      _warmed('Stremio', scope, StremioService.instance.invalidateCache);
      _warmed('Trakt', scope, TraktService.instance.resetProfileScope);
      _warmed('Simkl', scope, SimklService.instance.resetProfileScope);
      _warmed('PikPak', scope, PikPakApiService.instance.resetProfileScope);
      _warmed('MDBList', scope, MdblistService.instance.resetProfileScope);
      await StorageService.retireMdblistSavedCloneMarkers();
      _warmed('IPTV', scope, IptvService.instance.clearCache);
      _warmed('Xtream', scope, XtreamCodesService.instance.clearCache);
      _warmed('DiscoverPrefs', scope, DiscoverPrefs.resetProfileScope);
      _warmed('HideWatchedPrefs', scope, HideWatchedPrefs.resetProfileScope);
      _warmed(
        'StreamBadges',
        scope,
        StreamBadgesService.instance.resetProfileScope,
      );
      _warmed(
        'SubtitleFont',
        scope,
        SubtitleFontService.instance.resetProfileScope,
      );
      _warmed(
        'SubtitleSettings',
        scope,
        SubtitleSettingsService.instance.resetProfileScope,
      );
      await EngineProfileLifecycle.warmCurrentScope();
      // Measured, not declared: the registry tracks its own loaded scope, so
      // this row reports what it actually holds rather than that we asked.
      ProfileCacheLedger.stampRaw(
        'Engines',
        EngineRegistry.instance.loadedScopeKey,
      );

      await StorageService.migrateDefaultsGeneration();
      // Also run here, not just at cold start: the startup pass in main.dart
      // executes BEFORE the profile gate resolves, so it only ever reaches
      // whichever profile happened to be active then. The generation marker is
      // profile-scoped, so every other profile would keep its resume ghosts
      // forever. Best-effort — a profile switch must not fail over cleanup of
      // playback state written by builds as old as 0.7.0.
      try {
        await StorageService.purgeUnwatchedResumeGhosts();
      } catch (e) {
        debugPrint('ProfileAppLifecycle: resume-ghost purge failed — $e');
      }
      await Future.wait(<Future<Object?>>[
        StorageService.getPlayerStartPortrait(),
        StorageService.getTvKeyboardEnabled(),
        StorageService.getTvHomeStyle(),
        StorageService.getTvSidebarStyle(),
        StorageService.getDesktopSidebarStyle(),
        StorageService.getDebrifyTvStyle(),
        StorageService.getUiSounds(),
        StorageService.getUiHaptics(),
        StorageService.getLaunchAnimation(),
        StorageService.getLaunchIdentPalette(),
        StorageService.getDetailPageStyle(),
        StorageService.getDetailTheme(),
        StorageService.getParentsGuideStyle(),
      ]);
      await TextBrightnessController.warm();
      await PlayLoaderStyleController.warm();
      await AppThemeController.warm();
      await TvHeroArtworkQualityController.warm();
      await DiscoverPrefs.warmUp();
      await HideWatchedPrefs.warmUp();
      await StreamBadgesService.instance.warmUp();
      // Do not open credentials here. ProfileGate intentionally keeps the
      // candidate locked until switchTo returns; the newly mounted profile UI
      // refreshes provider authentication immediately after unlock.
      await DownloadService.instance.activateProfileView();
    });
  }
}
