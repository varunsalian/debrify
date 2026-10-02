import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/collections/tmdb_attribution.dart';
import 'package:flutter/material.dart';
import 'settings_layout.dart';
import 'settings_search_bar.dart';
import 'settings_spotlight_layout.dart';

Widget buildClassicSettingsLayout(SettingsLayout layout, BuildContext context) {
  final app = AppThemeScope.of(context);
  if (app.id == 'spotlight') return buildSpotlightLayout(layout, context);
  final t = app.settings;
  return SettingsBackground(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsHeader(),
              const SizedBox(height: 18),
              SettingsSearchBar(onTap: layout.onOpenSearch),
              const SizedBox(height: 24),
              // Connections section with cards
              layout.connections,
              const SizedBox(height: 24),
              // ONE information architecture, shared verbatim with the TV
              // rail (_kCategories in settings_tv_layout.dart) and the
              // search index — organized by what the user is changing,
              // never by platform. Platform-only rows hide where they don't
              // apply; the section names never differ between surfaces.
              SettingsSection(
                title: 'Home & Display',
                children: [
                  SettingsTile.spec(
                    SettingsRows.homePage,
                    onTap: layout.onOpenHomePageSettings,
                  ),
                  if (layout.isAndroidTv)
                    SettingsToggleTile.spec(
                      SettingsRows.tvKeyboard,
                      value: layout.tvKeyboardEnabled,
                      onChanged: layout.onToggleTvKeyboard,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Collections',
                children: [
                  SettingsTile.spec(
                    SettingsRows.collections,
                    onTap: layout.onOpenCollectionsSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Badges',
                children: [
                  SettingsTile.spec(
                    SettingsRows.badges,
                    onTap: layout.onOpenBadgesSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Metadata',
                children: [
                  SettingsTile.spec(
                    SettingsRows.metadata,
                    onTap: layout.onOpenMetadataSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Every look/layout pref, one tap from the root. The TV-only
              // pickers live in the TV layout's Appearance category — this
              // layout never renders on Android TV.
              SettingsSection(
                title: 'Presets',
                blurb:
                    'One pick that sets the theme, layouts and launch '
                    'animation together.',
                children: [
                  SettingsTile.spec(
                    SettingsRows.looks,
                    subtitle: AppLooks.active()?.label ?? 'Custom',
                    onTap: layout.onOpenLooks,
                  ),
                  SettingsTile.spec(
                    SettingsRows.themeTokens,
                    subtitle: layout.themeTokensLabel,
                    onTap: layout.onOpenThemeTokens,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Theme',
                blurb:
                    'Colour, focus and motion. Applies everywhere in the '
                    'app.',
                children: [
                  SettingsTile.spec(
                    SettingsRows.textBrightness,
                    subtitle: layout.textBrightnessLabel,
                    onTap: layout.onOpenTextBrightness,
                  ),
                  SettingsTile.spec(
                    SettingsRows.launchAnimation,
                    subtitle: layout.launchAnimationLabel,
                    onTap: layout.onOpenLaunchAnimation,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Screen layouts',
                blurb: 'Where things sit. Each screen is chosen separately.',
                children: [
                  if (layout.showsLargeCollectionStyles(context))
                    SettingsTile.spec(
                      SettingsRows.collectionListStyle,
                      subtitle: 'Grid · Gallery · Filmstrip · Journal',
                      onTap: layout.onOpenCollectionListStyle,
                    ),
                  SettingsTile.spec(
                    SettingsRows.detailPageStyle,
                    subtitle: layout.detailPageStyleLabel,
                    onTap: layout.onOpenDetailPageStyle,
                  ),
                  if (layout.showIptvAppearance)
                    SettingsTile.spec(
                      SettingsRows.iptvAppearance,
                      subtitle: layout.iptvStyleLabel,
                      onTap: layout.onOpenIptvStyle,
                    ),
                  SettingsTile.spec(
                    SettingsRows.debrifyTvAppearance,
                    subtitle: layout.debrifyTvStyleLabel,
                    onTap: layout.onOpenDebrifyTvStyle,
                  ),
                  SettingsTile.spec(
                    SettingsRows.playerGuideStyle,
                    subtitle: layout.playerGuideStyleLabel,
                    onTap: layout.onOpenPlayerGuideStyle,
                  ),
                  SettingsTile.spec(
                    SettingsRows.playLoaderStyle,
                    subtitle: layout.playLoaderStyleLabel,
                    onTap: layout.onOpenPlayLoaderStyle,
                  ),
                  // Televisions build TvControls, not Controls, so this
                  // pref has no consumer there. SettingsTvLayout omits the
                  // row entirely; this gate covers Apple TV, which shares
                  // the TV layout via AndroidNativeDownloader.isTelevision.
                  if (!PlatformUtil.isTelevision)
                    SettingsTile.spec(
                      SettingsRows.playerDock,
                      subtitle: layout.playerDockLabel,
                      onTap: layout.onOpenPlayerDock,
                    ),
                  SettingsTile.spec(
                    SettingsRows.parentsGuideStyle,
                    subtitle: layout.parentsGuideStyleLabel,
                    onTap: layout.onOpenParentsGuideStyle,
                  ),
                  SettingsTile.spec(
                    SettingsRows.profileAppearance,
                    subtitle: layout.profileAppearanceLabel,
                    onTap: layout.onOpenProfileAppearance,
                  ),
                  // Phone/small-window chrome — TVs navigate by sidebar
                  // and never read the style.
                  SettingsTile.spec(
                    SettingsRows.navigationStyle,
                    subtitle: layout.phoneNavStyleLabel,
                    onTap: layout.onOpenNavigationSettings,
                  ),
                  // Wide-window chrome: the desktop/tablet rail's picker
                  // (rail or pill). Phones never reach the wide layout but
                  // an iPad rotates in and out of it, so the row is not
                  // width-gated.
                  SettingsTile.spec(
                    SettingsRows.desktopSidebarStyle,
                    subtitle: layout.desktopSidebarStyleLabel,
                    onTap: layout.onOpenDesktopSidebarStyle,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Playback',
                children: [
                  for (final section in PlaybackSettingsSection.values)
                    SettingsTile(
                      key: ValueKey('playback-category-${section.name}'),
                      icon: section.icon,
                      title: section.label,
                      subtitle: section.description,
                      onTap: () => layout.onOpenPlaybackSection(section),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Search',
                children: [
                  SettingsTile.spec(
                    SettingsRows.searchSettings,
                    onTap: layout.onOpenTorrentSettings,
                  ),
                  SettingsTile.spec(
                    SettingsRows.filterSettings,
                    onTap: layout.onOpenFilterSettings,
                  ),
                  SettingsTile.spec(
                    SettingsRows.providerSettings,
                    onTap: layout.onOpenProviderSettings,
                  ),
                  SettingsTile.spec(
                    SettingsRows.quickPlay,
                    onTap: layout.onOpenQuickPlaySettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Discover',
                children: [
                  SettingsTile.spec(
                    SettingsRows.discoverDefault,
                    onTap: layout.onOpenDiscoverSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Live TV & DVR',
                children: [
                  SettingsTile.spec(
                    SettingsRows.debrifyTv,
                    onTap: layout.onOpenDebrifyTvSettings,
                  ),
                  SettingsTile.spec(
                    SettingsRows.recordings,
                    onTap: layout.onOpenRecordings,
                  ),
                  SettingsTile.spec(
                    SettingsRows.iptvPlaylists,
                    onTap: layout.onOpenIptvSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Devices',
                children: [
                  // Remote is listed on every platform. It used to be hidden
                  // off TV and desktop on the grounds that "mobile keeps its
                  // entry in the floating menu" — but that menu is gated on
                  // width (isDesktopWide, >= 600 px), not on platform, so a
                  // tablet or a phone in landscape lost both entry points at
                  // once and could only reach Remote through settings search.
                  SettingsTile.spec(
                    SettingsRows.remote,
                    onTap: () async => layout.onOpenRemoteControl(),
                  ),
                ],
              ),
              // Profiles' own card (it used to be a tenant row under
              // Devices). The list layout simply hides it in legacy mode —
              // no index coupling to preserve here, unlike the category
              // switches.
              if (layout.showSwitchProfile) ...[
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Profiles',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.switchProfile,
                      onTap: layout.onSwitchProfile,
                    ),
                    SettingsTile.spec(
                      SettingsRows.addProfile,
                      onTap: layout.onAddProfile,
                    ),
                    SettingsTile.spec(
                      SettingsRows.editProfile,
                      onTap: layout.onEditProfile,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Sync and Migrate',
                children: [
                  SettingsTile.spec(
                    SettingsRows.syncAndMigrate,
                    onTap: layout.onOpenSyncAndMigrate,
                    trailing: const WebDavSyncPendingBadge(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Data & Backup',
                children: [
                  if (layout.onOpenDownloadLocation != null)
                    SettingsTile.spec(
                      SettingsRows.downloadLocation,
                      subtitle: layout.downloadLocationSubtitle,
                      onTap: layout.onOpenDownloadLocation!,
                    ),
                  SettingsTile.spec(
                    SettingsRows.clearDownloads,
                    onTap: layout.onClearDownloads,
                  ),
                  SettingsTile.spec(
                    SettingsRows.clearPlayback,
                    onTap: layout.onClearPlayback,
                  ),
                  SettingsTile.spec(
                    SettingsRows.createBackup,
                    onTap: layout.onCreateBackup,
                  ),
                  SettingsTile.spec(
                    SettingsRows.restoreBackup,
                    onTap: layout.onRestoreBackup,
                  ),
                  if (layout.onExportDiagnosticLogs != null)
                    SettingsTile.spec(
                      SettingsRows.exportDiagnosticLogs,
                      onTap: layout.onExportDiagnosticLogs!,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              // About section
              SettingsSection(
                title: 'About',
                children: [
                  SettingsToggleTile.spec(
                    SettingsRows.autoUpdate,
                    value: layout.autoUpdateChecksEnabled,
                    onChanged: layout.onToggleAutoUpdateChecks,
                  ),
                  SettingsToggleTile.spec(
                    SettingsRows.includeAlphaUpdates,
                    value: layout.includeAlphaUpdates,
                    onChanged: layout.onToggleIncludeAlphaUpdates,
                  ),
                  SettingsTile.spec(
                    SettingsRows.checkUpdates,
                    subtitle: layout.updateSubtitle,
                    onTap: layout.onCheckForUpdates,
                    tag: 'New',
                    trailing: layout.checkingUpdates
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : null,
                  ),
                  if (layout.showSupportDonation)
                    SettingsTile(
                      icon: SettingsRows.supportDebrify.icon,
                      title: layout.supportDonationLabel,
                      subtitle: layout.supportDonationSubtitle,
                      onTap: layout.onOpenSupportDonation,
                    ),
                  SettingsTile.spec(
                    SettingsRows.reddit,
                    onTap: () => launchSettingsUrl(SettingsRows.reddit.url!),
                  ),
                  SettingsTile.spec(
                    SettingsRows.discord,
                    onTap: () => launchSettingsUrl(SettingsRows.discord.url!),
                  ),
                  SettingsTile.spec(
                    SettingsRows.github,
                    onTap: () => launchSettingsUrl(SettingsRows.github.url!),
                  ),
                  const TmdbAttribution(),
                  SettingsInfoTile.spec(
                    SettingsRows.version,
                    value: layout.appVersion,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Danger Zone LAST — destructive actions live at the end of
              // the page, isolated in their own red section on purpose.
              SettingsSection(
                title: 'Danger Zone',
                accentColor: t.danger.withValues(alpha: 0.85),
                children: [
                  SettingsTile.spec(
                    SettingsRows.resetDebrify,
                    onTap: layout.onDangerAction,
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
