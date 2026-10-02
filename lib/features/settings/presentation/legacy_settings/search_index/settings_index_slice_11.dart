import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice11 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice11() {
    return [
      // Updates
      SettingsSearchEntry(
        icon: SettingsRows.autoUpdate.icon,
        title: SettingsRows.autoUpdate.title,
        subtitle: SettingsRows.autoUpdate.subtitle,
        category: 'About',
        keywords: const ['notify', 'releases', 'startup'],
        toggleValue: () => summaries.autoUpdateChecksEnabled,
        onToggle: deps.toggleAutoUpdateChecks,
      ),
      SettingsSearchEntry(
        icon: SettingsRows.includeAlphaUpdates.icon,
        title: SettingsRows.includeAlphaUpdates.title,
        subtitle: SettingsRows.includeAlphaUpdates.subtitle,
        category: 'About',
        keywords: const ['alpha', 'beta', 'prerelease', 'experimental'],
        toggleValue: () => summaries.includeAlphaUpdates,
        onToggle: deps.toggleIncludeAlphaUpdates,
      ),
      nav(
        SettingsRows.checkUpdates,
        'About',
        deps.checkForAppUpdates,
        subtitle: summaries.updateSubtitle,
        keywords: const ['version', 'upgrade', 'github', 'new build'],
      ),

      // Support
      if (summaries.supportDonation.hasProviders)
        SettingsSearchEntry(
          icon: SettingsRows.supportDebrify.icon,
          title: summaries.supportSettingsLabel,
          subtitle: summaries.supportSettingsSubtitle,
          category: 'About',
          keywords: const ['donate', 'tip', 'contribute', 'fund'],
          onTap: deps.openSupportDonation,
        ),
      nav(
        SettingsRows.reddit,
        'About',
        () => launchSettingsUrl(SettingsRows.reddit.url!),
        keywords: const ['community', 'subreddit'],
      ),
      nav(
        SettingsRows.discord,
        'About',
        () => launchSettingsUrl(SettingsRows.discord.url!),
        keywords: const ['community', 'chat', 'help'],
      ),
      nav(
        SettingsRows.github,
        'About',
        () => launchSettingsUrl(SettingsRows.github.url!),
        keywords: const ['source code', 'contribute', 'issues'],
      ),

      // Danger Zone
      nav(
        SettingsRows.resetDebrify,
        'Danger Zone',
        deps.resetAppData,
        destructive: true,
        keywords: const ['wipe', 'factory reset', 'clear all', 'erase'],
      ),

      // In-page options (deep-link to the page that hosts them).
      ...deps.leafSearchEntries(),
    ];
  }
}
