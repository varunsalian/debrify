import 'package:flutter/material.dart';

/// Icon + copy for one settings row. Defined once in [SettingsRows] and
/// consumed by BOTH the phone single-column layout and the TV two-pane layout
/// (via `SettingsTile.spec` / `SettingsToggleTile.spec`) so the two can't
/// drift — change a title/icon here and both surfaces update.
class SettingsRowContent {
  final IconData icon;
  final String title;
  final String subtitle;

  /// External link for community rows (Reddit/Discord/GitHub).
  final String? url;

  const SettingsRowContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.url,
  });
}

/// Single source of truth for every settings row's icon + copy.
abstract final class SettingsRows {
  static const metadata = SettingsRowContent(
    icon: Icons.info_outline_rounded,
    title: 'Metadata',
    subtitle: 'Providers, artwork, languages & discovery',
  );
  static const homePage = SettingsRowContent(
    icon: Icons.home_rounded,
    title: 'Home Screen',
    subtitle: 'Layout, rows, trailer & continue watching',
  );
  static const collections = SettingsRowContent(
    icon: Icons.collections_bookmark_rounded,
    title: 'Collections',
    subtitle: 'Import Nuvio-style folder collections as Home rows',
  );
  static const badges = SettingsRowContent(
    icon: Icons.sell_rounded,
    title: 'Badges',
    subtitle: 'Import and manage stream badge rules',
  );
  static const player = SettingsRowContent(
    icon: Icons.play_circle_outline_rounded,
    title: 'Playback',
    subtitle: 'Player, video, audio & subtitles',
  );
  static const remote = SettingsRowContent(
    icon: Icons.phonelink_rounded,
    title: 'Remote',
    subtitle: 'Control another device, send or receive setup',
  );
  // The Profiles hub replaced the bare switch action: switching lives on the
  // hub beside the roster, so this row is now the one front door. It heads
  // the Profiles SECTION now (its own card, not a Devices tenant), with the
  // two most-wanted actions surfaced beside it as rows of their own.
  static const switchProfile = SettingsRowContent(
    icon: Icons.switch_account_rounded,
    title: 'Profiles',
    subtitle: 'Who can use this device',
  );
  static const addProfile = SettingsRowContent(
    icon: Icons.person_add_alt_rounded,
    title: 'Add a profile',
    subtitle: 'Admin, Member or Kid',
  );
  static const editProfile = SettingsRowContent(
    icon: Icons.edit_rounded,
    title: 'Edit this profile',
    subtitle: 'Name, avatar, PIN & access',
  );
  static const navigationStyle = SettingsRowContent(
    icon: Icons.call_to_action_rounded,
    title: 'Navigation',
    subtitle: 'Classic bottom bar or floating button',
  );
  static const searchSettings = SettingsRowContent(
    icon: Icons.search_rounded,
    title: 'Engines',
    subtitle: 'Search engine defaults and indexers',
  );
  static const filterSettings = SettingsRowContent(
    icon: Icons.filter_list_rounded,
    title: 'Filters',
    subtitle: 'Default quality, source, and language filters',
  );
  static const providerSettings = SettingsRowContent(
    icon: Icons.cloud_sync_rounded,
    title: 'Default Provider',
    subtitle: 'Where added torrents go',
  );
  static const quickPlay = SettingsRowContent(
    icon: Icons.bolt_rounded,
    title: 'Quick Play',
    subtitle: 'Timeouts, series packs, and cache fallback',
  );
  static const discoverDefault = SettingsRowContent(
    icon: Icons.explore_rounded,
    title: 'Default View',
    subtitle: 'Default source and poster details',
  );
  static const debrifyTv = SettingsRowContent(
    icon: Icons.live_tv_rounded,
    title: 'Debrify TV',
    subtitle: 'Limits, channels, and playback configuration',
  );
  static const recordings = SettingsRowContent(
    icon: Icons.fiber_dvr_rounded,
    title: 'Recordings',
    subtitle: 'Live recordings, schedules, and library',
  );
  static const iptvPlaylists = SettingsRowContent(
    icon: Icons.playlist_play_rounded,
    title: 'IPTV Playlists',
    subtitle: 'Playlists, lists, and startup channel',
  );
  static const tvKeyboard = SettingsRowContent(
    icon: Icons.keyboard_rounded,
    title: 'Debrify Keyboard',
    subtitle: 'Remote-friendly on-screen keyboard for text fields',
  );
  // Subtitle is dynamic (the chosen size) — passed per call site.
  static const tvScreenSize = SettingsRowContent(
    icon: Icons.fit_screen_rounded,
    title: 'Screen Size',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen mode) — passed per call site.
  static const tvRenderQuality = SettingsRowContent(
    icon: Icons.hd_rounded,
    title: 'Rendering',
    subtitle: '',
  );
  static const tvHeroArtworkQuality = SettingsRowContent(
    icon: Icons.photo_size_select_large_rounded,
    title: 'Hero Artwork Quality',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const tvHomeStyle = SettingsRowContent(
    icon: Icons.view_quilt_rounded,
    title: 'Home Layout',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const collectionListStyle = SettingsRowContent(
    icon: Icons.view_carousel_outlined,
    title: 'Collection list style',
    subtitle: '',
  );

  static const discoverLayout = SettingsRowContent(
    icon: Icons.explore_rounded,
    title: 'Discover Layout',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const tvSidebarStyle = SettingsRowContent(
    icon: Icons.view_sidebar_rounded,
    title: 'Sidebar Style',
    subtitle: '',
  );
  // The desktop/tablet counterpart — never shown beside the TV row (each is
  // platform-gated), so the shared title is unambiguous wherever it appears.
  static const desktopSidebarStyle = SettingsRowContent(
    icon: Icons.view_sidebar_rounded,
    title: 'Sidebar Style',
    subtitle: '',
  );
  static const profileAppearance = SettingsRowContent(
    icon: Icons.switch_account_rounded,
    title: 'Profile Picker',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen brightness) — passed per call site.
  static const textBrightness = SettingsRowContent(
    icon: Icons.brightness_6_rounded,
    title: 'Text Brightness',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen ident) — passed per call site.
  static const launchAnimation = SettingsRowContent(
    icon: Icons.rocket_launch_rounded,
    title: 'Launch Animation',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const iptvAppearance = SettingsRowContent(
    icon: Icons.style_rounded,
    title: 'IPTV Appearance',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const debrifyTvAppearance = SettingsRowContent(
    icon: Icons.connected_tv_rounded,
    title: 'Debrify TV',
    subtitle: '',
  );
  // Subtitle is dynamic (style + palette) — passed per call site.
  static const playerDock = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Player Controls',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen skin) — passed per call site. Android
  // TV only: the native player's control skin (OTT dock vs Legacy).
  static const tvPlayerControls = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Player Controls',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site. Android
  // TV only: the Debrify TV playback screen (native TorboxTvPlayerActivity).
  static const debrifyTvPlayer = SettingsRowContent(
    icon: Icons.live_tv_rounded,
    title: 'Debrify TV Player',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen look) — passed per call site.
  static const playLoaderStyle = SettingsRowContent(
    icon: Icons.play_circle_outline_rounded,
    title: 'Play Loader',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const playerGuideStyle = SettingsRowContent(
    icon: Icons.smart_display_rounded,
    title: 'Player Guide',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const detailPageStyle = SettingsRowContent(
    icon: Icons.article_rounded,
    title: 'Details Page',
    subtitle: '',
  );
  static const themeLab = SettingsRowContent(
    icon: Icons.science_rounded,
    title: 'Theme Lab',
    subtitle: 'Preview the looks on real widgets',
  );
  // Subtitle is dynamic (the active Look, or "Custom") — passed per call site.
  static const looks = SettingsRowContent(
    icon: Icons.auto_awesome_rounded,
    title: 'Looks',
    subtitle: '',
  );

  /// Sits directly under Looks, in the same section. It was reachable only by
  /// opening Looks first, which put the entire token layer two levels down
  /// behind a row that gave no hint it was there.
  static const themeTokens = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Advanced',
    subtitle: '',
  );
  static const appTheme = SettingsRowContent(
    icon: Icons.format_paint_rounded,
    // Just 'Theme': the section header above it already says THEME, and
    // 'App Theme' only ever needed the qualifier to tell itself apart from
    // the Details Theme row that no longer exists.
    title: 'Theme',
    subtitle: '',
  );
  static const detailTheme = SettingsRowContent(
    icon: Icons.palette_rounded,
    title: 'Details Theme',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen presentation) — passed per call site.
  static const parentsGuideStyle = SettingsRowContent(
    icon: Icons.family_restroom_rounded,
    title: 'Parents Guide',
    subtitle: '',
  );
  // Subtitle is dynamic (current folder) — passed per call site.
  static const downloadLocation = SettingsRowContent(
    icon: Icons.folder_rounded,
    title: 'Download Location',
    subtitle: '',
  );
  static const clearDownloads = SettingsRowContent(
    icon: Icons.download_rounded,
    title: 'Clear Download Data',
    subtitle: 'Remove queue history and in-progress entries',
  );
  static const clearPlayback = SettingsRowContent(
    icon: Icons.play_circle_rounded,
    title: 'Clear Playback Data',
    subtitle: 'Reset resume points and playback sessions',
  );
  static const createBackup = SettingsRowContent(
    icon: Icons.save_alt_rounded,
    title: 'Create Backup',
    subtitle: 'Back up all profiles and shared connections (Admin)',
  );
  static const restoreBackup = SettingsRowContent(
    icon: Icons.restore_rounded,
    title: 'Restore from Backup',
    subtitle: 'Import services and addons from a backup file',
  );
  static const syncAndMigrate = SettingsRowContent(
    icon: Icons.sync_alt_rounded,
    title: 'Sync and Migrate',
    subtitle: 'Sync across devices with WebDAV',
  );
  static const enableWebDavSync = SettingsRowContent(
    icon: Icons.sync_rounded,
    title: 'Enable WebDAV Sync',
    subtitle: 'Keep supported profile state in one WebDAV account',
  );
  static const createWebDavBackup = SettingsRowContent(
    icon: Icons.cloud_upload_outlined,
    title: 'Save backup to WebDAV',
    subtitle: 'Save an encrypted backup of all profiles (Admin)',
  );
  static const restoreWebDavBackup = SettingsRowContent(
    icon: Icons.cloud_download_outlined,
    title: 'Restore backup from WebDAV',
    subtitle: 'Choose an encrypted profile package on your server',
  );
  static const storageUsage = SettingsRowContent(
    icon: Icons.storage_rounded,
    title: 'Storage Usage',
    subtitle: 'See what Debrify keeps on this device',
  );
  static const exportDiagnosticLogs = SettingsRowContent(
    icon: Icons.bug_report_outlined,
    title: 'Export Diagnostic Logs',
    subtitle: 'Save recent logs (2h) and critical events (24h)',
  );
  static const resetDebrify = SettingsRowContent(
    icon: Icons.warning_rounded,
    title: 'Reset Debrify',
    subtitle: 'Remove connections, preferences, and caches',
  );
  static const autoUpdate = SettingsRowContent(
    icon: Icons.notifications_active_rounded,
    title: 'Auto Check for Updates',
    subtitle: 'Notify about new releases on startup',
  );
  static const includeAlphaUpdates = SettingsRowContent(
    icon: Icons.science_outlined,
    title: 'Include Alpha Builds',
    subtitle: 'Receive alpha and beta updates; alpha may be unstable',
  );
  // Subtitle is dynamic (update status) — passed per call site.
  static const checkUpdates = SettingsRowContent(
    icon: Icons.system_update_rounded,
    title: 'Check for Updates',
    subtitle: '',
  );
  static const supportDebrify = SettingsRowContent(
    icon: Icons.favorite_rounded,
    title: 'Support Debrify',
    subtitle: '',
  );
  static const reddit = SettingsRowContent(
    icon: Icons.forum_rounded,
    title: 'Reddit Community',
    subtitle: 'r/debrify - Questions, tips, and discussion',
    url: 'https://www.reddit.com/r/debrify/',
  );
  static const discord = SettingsRowContent(
    icon: Icons.chat_rounded,
    title: 'Discord',
    subtitle: 'Join for help, updates, and discussion',
    url: 'https://discord.gg/xuAc4Q2c9G',
  );
  static const github = SettingsRowContent(
    icon: Icons.code_rounded,
    title: 'GitHub',
    subtitle: 'Source code and contributions',
    url: 'https://github.com/varunsalian/debrify',
  );
  static const version = SettingsRowContent(
    icon: Icons.info_outline_rounded,
    title: 'Version',
    subtitle: '',
  );
}
