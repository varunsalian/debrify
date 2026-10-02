import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'settings_connection_grid.dart';
import 'settings_layout.dart';

Widget buildSpotlightCategory(
  SettingsLayout layout,
  BuildContext context,
  int category,
) {
  final t = AppThemeScope.of(context).settings;
  switch (category) {
    case 0:
      return buildConnectionGrid(layout, context, layout.providerConnections);
    case 1:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionLabel('Tracking'),
          buildConnectionGrid(layout, context, [
            layout.connections.tracking,
          ], singleFullWidth: true),
          const SizedBox(height: 22),
          const SettingsSectionLabel('Tracker services'),
          buildConnectionGrid(layout, context, layout.trackerServices),
        ],
      );
    case 2:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.homePage,
            onTap: layout.onOpenHomePageSettings,
          ),
          SettingsTile.spec(
            SettingsRows.navigationStyle,
            subtitle: layout.phoneNavStyleLabel,
            onTap: layout.onOpenNavigationSettings,
          ),
          SettingsTile.spec(
            SettingsRows.desktopSidebarStyle,
            subtitle: layout.desktopSidebarStyleLabel,
            onTap: layout.onOpenDesktopSidebarStyle,
          ),
        ],
      );
    case 3:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.collections,
            onTap: layout.onOpenCollectionsSettings,
          ),
        ],
      );
    case 4:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.badges,
            onTap: layout.onOpenBadgesSettings,
          ),
        ],
      );
    case 5:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.metadata,
            onTap: layout.onOpenMetadataSettings,
          ),
        ],
      );
    case 6:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLookHero(
            label: AppLooks.active()?.label ?? 'Custom',
            subtitle: 'Full-bleed art, borderless focus, and ambient detail.',
            onTap: layout.onOpenLooks,
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Presets',
            blurb:
                'One pick sets the theme, layouts, and launch animation '
                'together.',
            children: [
              SettingsTile.spec(
                SettingsRows.themeTokens,
                subtitle: layout.themeTokensLabel,
                onTap: layout.onOpenThemeTokens,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Theme',
            blurb: 'Colour, focus, and motion. Applies everywhere.',
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
          const SizedBox(height: 18),
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
            ],
          ),
        ],
      );
    case 7:
      return SettingsSection(
        title: '',
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
      );
    case 8:
      return SettingsSection(
        title: '',
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
      );
    case 9:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.discoverDefault,
            onTap: layout.onOpenDiscoverSettings,
          ),
        ],
      );
    case 10:
      return SettingsSection(
        title: '',
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
      );
    case 11:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.remote,
            onTap: () async => layout.onOpenRemoteControl(),
          ),
        ],
      );
    case 12:
      // Profiles' own card (it used to be a tenant row under Devices). A
      // legacy-mode install keeps the card but says why it's empty rather
      // than presenting actions that would fail.
      return SettingsSection(
        title: '',
        children: [
          if (layout.showSwitchProfile) ...[
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
          ] else
            SettingsTile.spec(
              SettingsRowContent(
                icon: Icons.info_outline_rounded,
                title: 'Profiles unavailable',
                // First line only: the captured reason can carry a stack
                // frame on its second line, and the row is one-line copy.
                subtitle: layout.legacyReasonSummary().split('\n').first,
              ),
              onTap: () => showLegacyModeInfoDialog(context),
            ),
        ],
      );
    case 13:
      return SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.syncAndMigrate,
            onTap: layout.onOpenSyncAndMigrate,
            trailing: const WebDavSyncPendingBadge(),
          ),
        ],
      );
    case 14:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (layout.onOpenDownloadLocation != null) ...[
            SettingsSection(
              title: 'Downloads',
              children: [
                SettingsTile.spec(
                  SettingsRows.downloadLocation,
                  subtitle: layout.downloadLocationSubtitle,
                  onTap: layout.onOpenDownloadLocation!,
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          SettingsSection(
            title: 'Maintenance',
            children: [
              SettingsTile.spec(
                SettingsRows.clearDownloads,
                onTap: layout.onClearDownloads,
              ),
              SettingsTile.spec(
                SettingsRows.clearPlayback,
                onTap: layout.onClearPlayback,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Backup & Restore',
            children: [
              SettingsTile.spec(
                SettingsRows.createBackup,
                onTap: layout.onCreateBackup,
              ),
              SettingsTile.spec(
                SettingsRows.restoreBackup,
                onTap: layout.onRestoreBackup,
              ),
            ],
          ),
          if (layout.onExportDiagnosticLogs != null) ...[
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Diagnostics',
              children: [
                SettingsTile.spec(
                  SettingsRows.exportDiagnosticLogs,
                  onTap: layout.onExportDiagnosticLogs!,
                ),
              ],
            ),
          ],
        ],
      );
    case 15:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            title: 'Updates',
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
              SettingsInfoTile.spec(
                SettingsRows.version,
                value: layout.appVersion,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Community & Support',
            children: [
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
            ],
          ),
        ],
      );
    case 16:
      return SettingsSection(
        title: '',
        accentColor: t.danger,
        children: [
          SettingsTile.spec(
            SettingsRows.resetDebrify,
            onTap: layout.onDangerAction,
            destructive: true,
          ),
        ],
      );
    default:
      return const SizedBox.shrink();
  }
}
