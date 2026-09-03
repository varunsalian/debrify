import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_ui_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late void Function()? originalNavPreferences;
  late void Function()? originalTvHomeStyle;
  late void Function()? originalTvHeroArtworkQuality;
  late void Function()? originalDiscoverLayout;
  late void Function()? originalDiscoverCardSettings;
  late void Function()? originalTvSidebarStyle;
  late void Function()? originalDesktopSidebarStyle;
  late void Function()? originalSidebarConfiguration;
  late WebDavSyncLocalChangeSink? originalLocalChangeSink;

  setUp(() {
    originalNavPreferences = MainPageBridge.navPrefsChanged;
    originalTvHomeStyle = MainPageBridge.tvHomeStyleChanged;
    originalTvHeroArtworkQuality = MainPageBridge.tvHeroArtworkQualityChanged;
    originalDiscoverLayout = MainPageBridge.discoverLayoutChanged;
    originalDiscoverCardSettings = MainPageBridge.discoverCardSettingsChanged;
    originalTvSidebarStyle = MainPageBridge.tvSidebarStyleChanged;
    originalDesktopSidebarStyle = MainPageBridge.desktopSidebarStyleChanged;
    originalSidebarConfiguration = MainPageBridge.sidebarConfigurationChanged;
    originalLocalChangeSink = ProfilePreferences.webDavSyncLocalChangeSink;

    MainPageBridge.navPrefsChanged = null;
    MainPageBridge.tvHomeStyleChanged = null;
    MainPageBridge.tvHeroArtworkQualityChanged = null;
    MainPageBridge.discoverLayoutChanged = null;
    MainPageBridge.discoverCardSettingsChanged = null;
    MainPageBridge.tvSidebarStyleChanged = null;
    MainPageBridge.desktopSidebarStyleChanged = null;
    MainPageBridge.sidebarConfigurationChanged = null;
    ProfilePreferences.webDavSyncLocalChangeSink = null;
  });

  tearDown(() {
    MainPageBridge.navPrefsChanged = originalNavPreferences;
    MainPageBridge.tvHomeStyleChanged = originalTvHomeStyle;
    MainPageBridge.tvHeroArtworkQualityChanged = originalTvHeroArtworkQuality;
    MainPageBridge.discoverLayoutChanged = originalDiscoverLayout;
    MainPageBridge.discoverCardSettingsChanged = originalDiscoverCardSettings;
    MainPageBridge.tvSidebarStyleChanged = originalTvSidebarStyle;
    MainPageBridge.desktopSidebarStyleChanged = originalDesktopSidebarStyle;
    MainPageBridge.sidebarConfigurationChanged = originalSidebarConfiguration;
    ProfilePreferences.webDavSyncLocalChangeSink = originalLocalChangeSink;
  });

  test('multiple home keys notify Home once', () {
    var homeCalls = 0;
    void homeListener() => homeCalls++;
    MainPageBridge.addHomeSettingsListener(homeListener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(homeListener));

    WebDavSyncUiRefresh.dispatch(const <String>{
      'home_card_orientation',
      'home_hide_card_titles_and_ratings',
      'home_row_order_v1',
    });

    expect(homeCalls, 1);
  });

  test('mixed groups fire each notifier once', () {
    var homeCalls = 0;
    var tvHomeCalls = 0;
    var discoverCardCalls = 0;
    void homeListener() => homeCalls++;
    MainPageBridge.addHomeSettingsListener(homeListener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(homeListener));
    MainPageBridge.tvHomeStyleChanged = () => tvHomeCalls++;
    MainPageBridge.discoverCardSettingsChanged = () => discoverCardCalls++;

    WebDavSyncUiRefresh.dispatch(const <String>{
      'home_card_orientation',
      'home_hero_source_v1',
      'tv_home_style',
      'discover_show_type_tags',
      'discover_show_ratings',
    });

    expect(homeCalls, 1);
    expect(tvHomeCalls, 1);
    expect(discoverCardCalls, 1);
  });

  test('unknown and playlist keys fire no curated notifier', () {
    var calls = 0;
    void homeListener() => calls++;
    MainPageBridge.addHomeSettingsListener(homeListener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(homeListener));
    MainPageBridge.tvHomeStyleChanged = () => calls++;

    WebDavSyncUiRefresh.dispatch(const <String>{
      'future_unknown_preference',
      WebDavSyncHotMerge.playlistPreference,
      WebDavSyncHotMerge.playlistFavoritesPreference,
    });

    expect(calls, 0);
  });

  test('a throwing notifier does not stop the others', () {
    var discoverCalls = 0;
    MainPageBridge.tvHomeStyleChanged = () => throw StateError('stale UI');
    MainPageBridge.discoverLayoutChanged = () => discoverCalls++;

    expect(
      () => WebDavSyncUiRefresh.dispatch(const <String>{
        'tv_home_style',
        'discover_layout',
      }),
      returnsNormally,
    );
    expect(discoverCalls, 1);
  });

  test('tracking policy bumps its revision and Home once per dispatch', () {
    final revisionBefore = StorageService.trackingSourceRevision.value;
    var homeCalls = 0;
    void homeListener() => homeCalls++;
    MainPageBridge.addHomeSettingsListener(homeListener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(homeListener));

    WebDavSyncUiRefresh.dispatch(const <String>{
      StorageService.trackingScrobbleTargetsKey,
      StorageService.homeTickSourcesKey,
      StorageService.watchProgressSourceKey,
    });

    expect(StorageService.trackingSourceRevision.value, revisionBefore + 1);
    expect(homeCalls, 1);
  });

  test('dispatch never echoes a WebDAV local-change signal', () {
    var localChangeSignals = 0;
    ProfilePreferences.webDavSyncLocalChangeSink = (_, _) {
      localChangeSignals++;
    };
    void homeListener() {}
    MainPageBridge.addHomeSettingsListener(homeListener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(homeListener));
    MainPageBridge.tvHomeStyleChanged = () {};
    MainPageBridge.discoverLayoutChanged = () {};

    WebDavSyncUiRefresh.dispatch(const <String>{
      'home_card_orientation',
      'tv_home_style',
      'discover_layout',
      StorageService.watchProgressSourceKey,
    });

    expect(localChangeSignals, 0);
  });
}
