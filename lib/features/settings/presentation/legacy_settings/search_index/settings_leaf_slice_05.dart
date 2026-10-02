import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/subtitle_priority_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice05 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice5() {
    return [
      // Nested appearance controls that are not represented by their picker
      // choice alone.
      leaf(
        'Launch Animation',
        'Match the app theme',
        'Use the active Look\'s accent colour for the launch ident',
        const [
          'launch',
          'animation',
          'ident',
          'colour',
          'color',
          'accent',
          'look',
          'theme',
        ],
      ),
      leaf(
        'Sidebar',
        'Order & Names',
        'Reorder and rename navigation destinations',
        const [
          'sidebar items',
          'navigation',
          'reorder',
          'arrange',
          'rename',
          'labels',
          'restore default order and names',
          'reset sidebar',
        ],
      ),
      for (final option in SettingsLeafBuilder.advancedAppearanceOptions)
        leaf('Advanced', option.title, option.subtitle, option.keywords),
      leaf(
        'Advanced',
        'Reset appearance overrides',
        'Return all or one section of advanced tokens to the active Look',
        const [
          'reset',
          'restore',
          'clear changes',
          'follow the look',
          'reset colour',
          'reset ground',
          'reset shape',
          'reset type',
          'reset focus',
          'reset motion',
          'reset surfaces',
          'reset artwork',
          'reset texture',
          'reset feedback',
        ],
      ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Profile Picker',
          'Personalized Top Shelf',
          'Show the unlocked active profile on the Apple TV Home Screen',
          const [
            'apple tv',
            'tvos',
            'top shelf',
            'profile',
            'home screen',
            'personalization',
          ],
        ),

      for (final section in PlaybackSettingsSection.values)
        leaf(
          'Playback',
          section.label,
          section.description,
          const [],
          onTap: () => deps.openPlaybackSection(section),
        ),
      leaf(
        'Playback',
        'Subtitle priority',
        'Reorder embedded subtitles and subtitle addons',
        const [
          'subtitle',
          'priority',
          'order',
          'embedded',
          'addons',
          'language',
        ],
        onTap: () async {
          if (!await deps.ensureProfileFeature(
            ProfileFeature.externalPlayers,
          )) {
            return;
          }
          if (!deps.mounted()) return;
          final context = deps.context();
          if (!context.mounted) return;
          await pushSettingsPage(context, const SubtitlePriorityPage());
        },
      ),
    ];
  }
}
