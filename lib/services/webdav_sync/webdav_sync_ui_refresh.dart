import '../home_row_refresh.dart';
import '../hide_watched_prefs.dart';
import '../iptv_channel_order.dart';
import '../iptv_media_store.dart';
import '../main_page_bridge.dart';
import '../storage_service.dart';

enum _WebDavSyncUiRefreshTarget {
  trackingSourceRevision,
  homeSettings,
  navPreferences,
  tvHomeStyle,
  tvHeroArtworkQuality,
  discoverLayout,
  discoverCardSettings,
  tvSidebarStyle,
  desktopSidebarStyle,
  sidebarConfiguration,
  iptvCatalog,
  iptvSource,
  iptvLists,
  playbackData,
  debrifyTvLibrary,
}

/// Replays the same live-UI notifications used by local settings writes after
/// a recurring-sync preference batch has committed for the active profile.
///
/// This list is intentionally explicit. A preference belongs here only when a
/// local settings flow writes that exact logical key and fires the matching
/// [MainPageBridge] notification. Playlist preferences stay on the existing
/// awaited `notifyPlaylistChanged` path in the active-profile refresher.
abstract final class WebDavSyncUiRefresh {
  static const Map<String, Set<_WebDavSyncUiRefreshTarget>> _targetsByKey = {
    HideWatchedPrefs.key: {_WebDavSyncUiRefreshTarget.homeSettings},
    'tv/ch': {_WebDavSyncUiRefreshTarget.debrifyTvLibrary},
    'tv/pool': {_WebDavSyncUiRefreshTarget.debrifyTvLibrary},
    'catalog/hidden': {_WebDavSyncUiRefreshTarget.iptvCatalog},
    'catalog/category-order': {_WebDavSyncUiRefreshTarget.iptvCatalog},
    'iptv/order': {_WebDavSyncUiRefreshTarget.iptvSource},
    'iptv/list': {_WebDavSyncUiRefreshTarget.iptvLists},
    'iptv/list-ch': {_WebDavSyncUiRefreshTarget.iptvLists},
    'iptv/watch': {_WebDavSyncUiRefreshTarget.playbackData},
    'resume': {_WebDavSyncUiRefreshTarget.playbackData},
    // HomePageSettingsPage and SpotlightHeroSourcePage.
    'home_cw_merge_local': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_cw_merge_trakt': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_cw_merge_simkl': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_cw_merge_mdblist': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_default_source_type': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hide_provider_cards': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_card_orientation': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hide_card_titles_and_ratings': {
      _WebDavSyncUiRefreshTarget.homeSettings,
    },
    'home_hide_catalog_addon_names': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_disabled_sections_v1': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_extra_rows_v1': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_collections_v1': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_collections_folder_layout': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_row_order_v1': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_continue_watching_enabled': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hero_trailer_enabled': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hero_trailer_audio_enabled': {
      _WebDavSyncUiRefreshTarget.homeSettings,
    },
    'detail_trailer_audio_enabled': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hero_trailer_volume': {_WebDavSyncUiRefreshTarget.homeSettings},
    'detail_trailer_volume': {_WebDavSyncUiRefreshTarget.homeSettings},
    'home_hero_source_v1': {_WebDavSyncUiRefreshTarget.homeSettings},

    // TrackingSettingsPage setters bump this revision; progress and tick
    // changes also refresh Home. Synced tracking policy treats the three keys
    // as one policy group so every consumer observes one coherent revision.
    StorageService.trackingScrobbleTargetsKey: {
      _WebDavSyncUiRefreshTarget.trackingSourceRevision,
      _WebDavSyncUiRefreshTarget.homeSettings,
    },
    StorageService.homeTickSourcesKey: {
      _WebDavSyncUiRefreshTarget.trackingSourceRevision,
      _WebDavSyncUiRefreshTarget.homeSettings,
    },
    StorageService.watchProgressSourceKey: {
      _WebDavSyncUiRefreshTarget.trackingSourceRevision,
      _WebDavSyncUiRefreshTarget.homeSettings,
    },

    // Dedicated settings pickers/customizers.
    'phone_nav_style': {_WebDavSyncUiRefreshTarget.navPreferences},
    'phone_nav_bar_indices': {_WebDavSyncUiRefreshTarget.navPreferences},
    'tv_home_style': {_WebDavSyncUiRefreshTarget.tvHomeStyle},
    'tv_hero_artwork_quality': {
      _WebDavSyncUiRefreshTarget.tvHeroArtworkQuality,
    },
    'tv_low_res_render': {_WebDavSyncUiRefreshTarget.tvHeroArtworkQuality},
    'discover_layout': {_WebDavSyncUiRefreshTarget.discoverLayout},
    'discover_show_type_tags': {
      _WebDavSyncUiRefreshTarget.discoverCardSettings,
    },
    'discover_show_ratings': {_WebDavSyncUiRefreshTarget.discoverCardSettings},
    'discover_show_titles': {_WebDavSyncUiRefreshTarget.discoverCardSettings},
    'tv_sidebar_style': {_WebDavSyncUiRefreshTarget.tvSidebarStyle},
    'desktop_sidebar_style': {_WebDavSyncUiRefreshTarget.desktopSidebarStyle},
    'sidebar_configuration_v1': {
      _WebDavSyncUiRefreshTarget.sidebarConfiguration,
    },
  };

  /// Fires every notification selected by [appliedKeys] at most once.
  ///
  /// UI callbacks are best-effort boundaries: a stale mounted consumer must
  /// neither fail sync nor prevent another independent surface from updating.
  static void dispatch(Set<String> appliedKeys) {
    if (appliedKeys.isEmpty) return;
    HomeRowRefreshSignal.dispatch(appliedKeys);
    final targets = <_WebDavSyncUiRefreshTarget>{};
    for (final key in appliedKeys) {
      final mapped = _targetsByKey[key];
      if (mapped != null) targets.addAll(mapped);
    }
    for (final target in _WebDavSyncUiRefreshTarget.values) {
      if (!targets.contains(target)) continue;
      try {
        switch (target) {
          case _WebDavSyncUiRefreshTarget.trackingSourceRevision:
            StorageService.trackingSourceRevision.value++;
          case _WebDavSyncUiRefreshTarget.homeSettings:
            MainPageBridge.notifyHomeSettingsChanged();
          case _WebDavSyncUiRefreshTarget.navPreferences:
            MainPageBridge.navPrefsChanged?.call();
          case _WebDavSyncUiRefreshTarget.tvHomeStyle:
            MainPageBridge.tvHomeStyleChanged?.call();
          case _WebDavSyncUiRefreshTarget.tvHeroArtworkQuality:
            MainPageBridge.tvHeroArtworkQualityChanged?.call();
          case _WebDavSyncUiRefreshTarget.discoverLayout:
            MainPageBridge.discoverLayoutChanged?.call();
          case _WebDavSyncUiRefreshTarget.discoverCardSettings:
            MainPageBridge.discoverCardSettingsChanged?.call();
          case _WebDavSyncUiRefreshTarget.tvSidebarStyle:
            MainPageBridge.tvSidebarStyleChanged?.call();
          case _WebDavSyncUiRefreshTarget.desktopSidebarStyle:
            MainPageBridge.desktopSidebarStyleChanged?.call();
          case _WebDavSyncUiRefreshTarget.sidebarConfiguration:
            MainPageBridge.sidebarConfigurationChanged?.call();
          case _WebDavSyncUiRefreshTarget.iptvCatalog:
            IptvChannelOrderSignal.notifyCatalogChanged('');
          case _WebDavSyncUiRefreshTarget.iptvSource:
            IptvChannelOrderSignal.notifySourceChanged('');
          case _WebDavSyncUiRefreshTarget.iptvLists:
            IptvMediaStore.notifyListsChanged();
          case _WebDavSyncUiRefreshTarget.playbackData:
            MainPageBridge.notifyPlaybackDataChanged();
          case _WebDavSyncUiRefreshTarget.debrifyTvLibrary:
            MainPageBridge.notifyDebrifyTvLibraryChanged();
        }
      } catch (_) {
        // A UI notification can never turn an already committed sync batch
        // into a failed cycle. Continue with every other matched surface.
      }
    }
  }
}
