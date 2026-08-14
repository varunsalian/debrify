import '../../screens/video_player/services/subtitle_settings_service.dart';
import '../../theme/app_theme_controller.dart';
import '../account_service.dart';
import '../alldebrid_account_service.dart';
import '../discover_prefs.dart';
import '../debrify_tv_database.dart';
import '../download_service.dart';
import '../iptv_catalog_db.dart';
import '../iptv_service.dart';
import '../mdblist/mdblist_service.dart';
import '../main_page_bridge.dart';
import '../pikpak_api_service.dart';
import '../premiumize_account_service.dart';
import '../remote_control/remote_command_router.dart';
import '../simkl/simkl_service.dart';
import '../storage_service.dart';
import '../stremio_service.dart';
import '../subtitle_font_service.dart';
import '../text_brightness.dart';
import '../trakt/trakt_service.dart';
import '../torbox_account_service.dart';
import '../tv_hero_artwork_quality_controller.dart';
import '../tvos_top_shelf_service.dart';
import '../xtream_codes_service.dart';
import '../engine/engine_profile_lifecycle.dart';
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
    await DebrifyTvDatabase.instance.closeScope();
    StremioService.instance.invalidateCache();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    PikPakApiService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    IptvService.instance.clearCache();
    XtreamCodesService.instance.clearCache();
    DiscoverPrefs.resetProfileScope();
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
    await _warm(restored);
    await NativeProfileProjection.publish(restored);
    DownloadService.instance.finishProfileSwitch();
  }

  Future<void> _warm(ProfileScope scope) {
    return ProfileRuntime.withCapturedScope(scope, () async {
      StorageService.resetProfileCaches();
      StremioService.instance.invalidateCache();
      TraktService.instance.resetProfileScope();
      SimklService.instance.resetProfileScope();
      PikPakApiService.instance.resetProfileScope();
      MdblistService.instance.resetProfileScope();
      IptvService.instance.clearCache();
      XtreamCodesService.instance.clearCache();
      DiscoverPrefs.resetProfileScope();
      SubtitleFontService.instance.resetProfileScope();
      SubtitleSettingsService.instance.resetProfileScope();
      await EngineProfileLifecycle.warmCurrentScope();

      await StorageService.migrateDefaultsGeneration();
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
      await AppThemeController.warm();
      await TvHeroArtworkQualityController.warm();
      await DiscoverPrefs.warmUp();
      // Do not open credentials here. ProfileGate intentionally keeps the
      // candidate locked until switchTo returns; the newly mounted profile UI
      // refreshes provider authentication immediately after unlock.
      await DownloadService.instance.activateProfileView();
    });
  }
}
