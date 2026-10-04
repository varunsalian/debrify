import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:flutter/material.dart';

class MergedDetailMetadataActions {
  final MergedDetailDependencies _deps;
  MergedDetailMetadataActions(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  MetadataPreferences get metadataPreferences => _deps.metadataPreferences();

  VoidCallback? get metadataExploreAction =>
      metadataPreferences.features.isNotEmpty &&
          _deps.onRecommendationTap() != null
      ? openMetadataExplore
      : null;

  void openMetadataExplore() {
    final prefs = metadataPreferences;
    final onOpen = _deps.onRecommendationTap();
    if (prefs.features.isEmpty || onOpen == null) return;
    Navigator.of(_deps.context()).push(
      MaterialPageRoute<void>(
        builder: (_) => MetadataExplorePage(
          item: _item,
          preferences: prefs,
          onOpen: onOpen,
          isTelevision: _deps.isTelevision(),
        ),
      ),
    );
  }
}
