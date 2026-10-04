import 'dart:async' show unawaited;

import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsCategoryViewsDeps = ({
  BuildContext Function() context,
  List<IptvPlaylist> Function() hideableSources,
  IptvSettingsFocusOwner focusOwner,
  IptvSettingsSourcesOwner sourcesOwner,
  Future<void> Function(IptvPlaylist playlist) openHiddenCategories,
  List<IptvPlaylist> Function() categoryOrderSources,
  Future<void> Function(IptvPlaylist playlist) openCategoryOrder,
});

class IptvSettingsCategoryViews {
  IptvSettingsCategoryViews(this._deps);
  final IptvSettingsCategoryViewsDeps _deps;

  /// One row per catalog-backed source, each opening its own manager. Per
  /// source rather than one combined screen: the hidden set is stored per
  /// catalog, and two providers' identically-named categories are unrelated.
  List<Widget> buildHiddenCategoriesSection() {
    final t = AppThemeScope.of(_deps.context()).settings;
    final sources = _deps.hideableSources();
    return [
      for (var i = 0; i < sources.length; i++)
        ListTile(
          focusNode: i < _deps.focusOwner.hiddenFocusNodes.length
              ? _deps.focusOwner.hiddenFocusNodes[i]
              : null,
          leading: Icon(
            (_deps.sourcesOwner.hiddenCounts[sources[i].id] ?? 0) > 0
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: (_deps.sourcesOwner.hiddenCounts[sources[i].id] ?? 0) > 0
                ? t.accent
                : t.dim2,
          ),
          title: Text(
            sources[i].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            switch (_deps.sourcesOwner.hiddenCounts[sources[i].id] ?? 0) {
              0 => 'Nothing hidden',
              1 => '1 category hidden',
              final n => '$n categories hidden',
            },
            style: TextStyle(fontSize: 12, color: t.dim),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: t.dim2),
          onTap: () => unawaited(_deps.openHiddenCategories(sources[i])),
        ),
    ];
  }

  Widget buildCategoryOrderView() {
    final t = AppThemeScope.of(_deps.context()).settings;
    final sources = _deps.categoryOrderSources();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Category order'),
        Text(
          'Choose a source, then arrange its category chips and guide '
          'sections. Channels inside each category keep provider order.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (final source in sources)
                ListTile(
                  leading: Icon(Icons.swap_vert_rounded, color: t.accent),
                  title: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    source.isXtreamCodes
                        ? 'Live TV, Movies and Series'
                        : 'Playlist categories',
                    style: TextStyle(fontSize: 12, color: t.dim),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.dim2),
                  onTap: () => unawaited(_deps.openCategoryOrder(source)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // One row per source that stores a catalog. The hub hides its row when no
  // source qualifies, so this view never renders empty.
  Widget buildHiddenView() {
    final t = AppThemeScope.of(_deps.context()).settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Hidden categories'),
        Text(
          'Open a category\'s menu (or long-press it) in the IPTV page\'s '
          'category picker, then choose Hide category. Nothing is deleted — '
          'bring it back here any time.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),
        Card(child: Column(children: buildHiddenCategoriesSection())),
      ],
    );
  }
}
