import '../../theme/app_theme_controller.dart';
import '../discover_prefs.dart';
import '../hide_watched_prefs.dart';
import '../engine/engine_profile_lifecycle.dart';
import '../engine/local_engine_storage.dart';
import '../main_page_bridge.dart';
import '../play_loader_style.dart';
import '../storage_service.dart';
import '../stream_badges_service.dart';
import '../stremio_service.dart';
import '../text_brightness.dart';
import '../tv_hero_artwork_quality_controller.dart';
import 'webdav_sync_hot_merge.dart';

abstract interface class WebDavSyncActiveProfileRefresher {
  Future<void> refresh(
    Set<String> changedKeys, {
    required void Function() authorizationBarrier,
  });
}

/// Refreshes only process mirrors affected by a completed hot-sync batch.
///
/// This deliberately does not run the full profile lifecycle: provider
/// sessions, databases, and unrelated caches remain mounted. Each mutation is
/// bracketed by the cycle's captured-session barrier so a profile switch cannot
/// publish the prior profile's refresh into the new session.
final class DefaultWebDavSyncActiveProfileRefresher
    implements WebDavSyncActiveProfileRefresher {
  const DefaultWebDavSyncActiveProfileRefresher();

  @override
  Future<void> refresh(
    Set<String> changedKeys, {
    required void Function() authorizationBarrier,
  }) async {
    if (changedKeys.isEmpty) return;

    Future<void> guarded(Future<void> Function() action) async {
      authorizationBarrier();
      await action();
      authorizationBarrier();
    }

    Future<void> warmIf(String key, Future<Object?> Function() warmer) async {
      if (!changedKeys.contains(key)) return;
      await guarded(() async {
        await warmer();
      });
    }

    await warmIf('tv_keyboard_enabled', StorageService.getTvKeyboardEnabled);
    await warmIf('tv_home_style', StorageService.getTvHomeStyle);
    await warmIf('debrify_tv_style', StorageService.getDebrifyTvStyle);
    await warmIf('detail_page_style', StorageService.getDetailPageStyle);
    await warmIf('detail_theme', StorageService.getDetailTheme);
    await warmIf('parents_guide_style', StorageService.getParentsGuideStyle);
    await warmIf('iptv_style', StorageService.getIptvStyle);
    await warmIf('discover_layout', StorageService.getDiscoverLayout);
    await warmIf('launch_animation', StorageService.getLaunchAnimation);
    await warmIf('launch_ident_palette', StorageService.getLaunchIdentPalette);
    await warmIf('tv_sidebar_style', StorageService.getTvSidebarStyle);
    await warmIf(
      'desktop_sidebar_style',
      StorageService.getDesktopSidebarStyle,
    );
    await warmIf(
      'sidebar_configuration_v1',
      StorageService.getSidebarConfiguration,
    );
    await warmIf(
      'player_start_portrait',
      StorageService.getPlayerStartPortrait,
    );
    await warmIf('ui_sounds', StorageService.getUiSounds);
    await warmIf('ui_haptics', StorageService.getUiHaptics);

    if (changedKeys.contains('text_brightness')) {
      await guarded(TextBrightnessController.warm);
    }
    if (changedKeys.contains('app_theme') ||
        changedKeys.contains('theme_overrides')) {
      await guarded(AppThemeController.warm);
    }
    if (changedKeys.contains('play_loader_style')) {
      await guarded(PlayLoaderStyleController.warm);
    }
    if (changedKeys.contains('tv_hero_artwork_quality') ||
        changedKeys.contains('tv_low_res_render')) {
      await guarded(TvHeroArtworkQualityController.warm);
    }

    if (changedKeys.contains(StreamBadgesService.sourcesKey) ||
        changedKeys.contains(StreamBadgesService.enabledKey)) {
      await guarded(StreamBadgesService.instance.refreshFromPreferences);
    }

    if (changedKeys.contains(HideWatchedPrefs.key)) {
      await HideWatchedPrefs.refreshFromPreferences(
        authorizationBarrier: authorizationBarrier,
      );
    }
    final discoverChanged = changedKeys.any(
      (key) => key.startsWith('discover_'),
    );
    if (discoverChanged) {
      await guarded(() async {
        DiscoverPrefs.resetProfileScope();
        await DiscoverPrefs.warmUp();
      });
    }
    if (changedKeys.any((key) => key.startsWith('engine_'))) {
      await guarded(EngineProfileLifecycle.warmCurrentScope);
      if (changedKeys.any(
        (key) => key.startsWith(LocalEngineStorage.definitionPrefix),
      )) {
        authorizationBarrier();
        LocalEngineStorage.changes.value++;
        authorizationBarrier();
      }
    }
    if (changedKeys.contains('stremio_addons_v1') ||
        changedKeys.contains('stremio_metadata_provider_v1')) {
      authorizationBarrier();
      StremioService.instance.refreshAfterExternalChange();
      authorizationBarrier();
    }

    if (changedKeys.any(_affectsLocalCompletion)) {
      authorizationBarrier();
      StorageService.localCompletionRevision.value++;
      authorizationBarrier();
    }
    if (changedKeys.contains(WebDavSyncHotMerge.playlistPreference) ||
        changedKeys.contains(WebDavSyncHotMerge.playlistFavoritesPreference)) {
      await guarded(() async {
        await MainPageBridge.notifyPlaylistChanged();
      });
    }
  }

  static bool _affectsLocalCompletion(String key) =>
      key == WebDavSyncHotMerge.playbackPreference ||
      key == WebDavSyncHotMerge.continueWatchingPreference ||
      key == WebDavSyncHotMerge.finishedMoviesPreference ||
      key == WebDavSyncHotMerge.explicitlyWatchedSeriesPreference;
}
