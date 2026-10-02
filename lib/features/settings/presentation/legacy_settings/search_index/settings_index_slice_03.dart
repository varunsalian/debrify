import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice03 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice3() {
    return [
      // General
      nav(
        SettingsRows.homePage,
        'Home & Display',
        deps.openHomePageSettings,
        keywords: const [
          'home page',
          'default view',
          'startup',
          'landing',
          'tab',
        ],
      ),
      nav(
        SettingsRows.badges,
        'Badges',
        deps.openBadgesSettings,
        keywords: const ['stream badges', 'rules', 'nuvio'],
      ),
      nav(
        SettingsRows.collections,
        'Collections',
        deps.openCollectionsSettings,
        keywords: const [
          'collections',
          'collection',
          'nuvio',
          'xperience',
          'folders',
          'import json',
        ],
      ),

      nav(
        SettingsRows.metadata,
        'Metadata',
        deps.openMetadataSettings,
        keywords: const [
          'tmdb',
          'language',
          'poster',
          'artwork',
          'provider',
          'trailer',
        ],
      ),
    ];
  }
}
