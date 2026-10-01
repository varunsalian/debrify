import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discover/application/metadata_feature_controller.dart';
import '../../features/discover/models/discover_source_state.dart';
import '../../features/discover/models/metadata_feature_policy.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/presentation/home_continuation_section.dart';
import '../../features/home/presentation/home_display_section.dart';
import '../../features/home/presentation/home_hero_preview.dart';
import '../../features/home/presentation/home_hero_section.dart';
import '../../features/search/presentation/search_title_section.dart';
import '../../models/metadata_preferences.dart';

typedef HomeMetadataDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() discoverMode,
});

/// Applies metadata preference invalidation to discovery, title suggestions and previews.
class HomeMetadataSection {
  HomeMetadataSection(
    this.ref,
    this._deps,
    this._discoverSection,
    this._titleSection,
    this._continuationSection,
    this._heroSection,
    this._heroPreview,
    this._displaySection,
  );
  final WidgetRef ref;
  final HomeMetadataDeps _deps;
  final DiscoverSection _discoverSection;
  final SearchTitleSection _titleSection;
  final HomeContinuationSection _continuationSection;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final HomeDisplaySection _displaySection;

  void start(MetadataFeatureSession metadataSession) {
    metadataFeatureSubscription = ref.listenManual(
      metadataFeaturePolicyProvider(metadataSession),
      (previous, next) {},
    );
    metadataFeatureController = ref.read(
      metadataFeaturePolicyProvider(metadataSession).notifier,
    );
    unawaited(refreshMetadataFeaturePolicy());
  }

  late final ProviderSubscription<MetadataFeaturePolicy>
  metadataFeatureSubscription;
  late final MetadataFeatureController metadataFeatureController;
  MetadataPreferences? get metadataFeaturePolicy =>
      metadataFeatureController.current.preferences;

  Future<void> refreshMetadataFeaturePolicy() => metadataFeatureController.load(
    isCurrent: () => _deps.mounted(),
    onAccepted: (prefs) {
      _deps.setState(() {});
      _titleSection.scheduleTitleSuggestions();
      if (_deps.discoverMode() &&
          _discoverSection.discSource == DiscoverSources.tmdb &&
          !prefs.features.contains(MetadataFeature.discovery)) {
        _discoverSection.selectDiscoverSource(DiscoverSources.cw);
      }
    },
  );

  void metadataSettingsChanged() {
    if (!_deps.mounted()) return;
    metadataFeatureController.invalidate();
    _titleSection.cancelTitleSuggestions();
    unawaited(refreshMetadataFeaturePolicy());
    _continuationSection.episodeArtworkController.refresh(
      isCurrent: () => _deps.mounted(),
      onChanged: () => _deps.setState(() {}),
    );
    _heroPreview.clearHeroTrailer();
    _heroSection.heroEnriched.value = null;
    final item = _heroSection.heroItem.value;
    if (item != null) {
      _heroSection.enrichHero(item);
      _heroPreview.scheduleHeroTrailer(
        item,
        fromSpotlight: _displaySection.homeStyleEffective == 'spotlight',
      );
    }
  }
}
