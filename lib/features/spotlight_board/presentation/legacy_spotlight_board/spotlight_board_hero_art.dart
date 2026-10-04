import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:flutter/material.dart';

class SpotlightBoardHeroArt {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardHeroArt(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  bool get prioritizeMetadata => true;

  StremioMeta? get originalMetadata =>
      view.hero.isEmpty ? null : view.hero[_sections.heroArt.heroIndex];

  void onMetadataPresentationChanged() => unawaited(_sections.ambient.probe());

  void onMetadataPolicyChanged() {
    // A previous image's tint must not publish after the policy changes.
    _owners.hero.probeGen++;
    _sections.heroWarmup.preloadHeroes();
  }

  int get heroDecodeWidth => view.dpad
      ? 1400
      : (MediaQuery.devicePixelRatioOf(_deps.context()) *
                MediaQuery.sizeOf(_deps.context()).width)
            .round()
            .clamp(720, 1920);

  Duration get heroImageFadeIn =>
      (MediaQuery.maybeOf(_deps.context())?.disableAnimations ?? false)
      ? Duration.zero
      : Duration(milliseconds: view.dpad ? 180 : 420);

  Duration get heroImageFadeOut =>
      view.dpad ||
          (MediaQuery.maybeOf(_deps.context())?.disableAnimations ?? false)
      ? Duration.zero
      : const Duration(milliseconds: 1000);

  ImageProvider heroWarmupProvider(String url) => ResizeImage.resizeIfNeeded(
    _sections.heroArt.heroDecodeWidth,
    null,
    CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
  );

  /// Best full-bleed art for [item]: its own backdrop, else a MetaHub 16:9
  /// still derived from its IMDb id — the same synchronous trick the other
  /// stage layouts use, because catalog and Continue Watching items carry a
  /// poster but rarely a backdrop — and the poster only as a last resort.
  ///
  /// This is intentionally the *large* MetaHub path. It feeds the single
  /// full-screen hero only; shelf cards keep their medium artwork and small
  /// decode budgets. The poster fallback is what blurry heroes are made of
  /// (~350px of 2:3 art cover-cropped over a full screen), so it is LAST, not
  /// second.
  String? heroPoster(StremioMeta item) =>
      view.metadataArtworkPending(MetadataCategory.backgrounds)
      ? null
      : view.usesMetadataProvider(MetadataCategory.backgrounds) &&
            !view.metadataPreferences.fallback
      ? null
      : highQualityArtworkUrl(item.poster);

  String? heroArt(StremioMeta item) {
    if (view.metadataArtworkPending(MetadataCategory.backgrounds)) return null;
    final b = item.background;
    if (b != null && b.isNotEmpty) return highQualityArtworkUrl(b);
    if (view.usesMetadataProvider(MetadataCategory.backgrounds))
      return _sections.heroArt.heroPoster(item);
    final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (tt != null) {
      return 'https://images.metahub.space/background/large/$tt/img';
    }
    final p = item.poster;
    return (p != null && p.isNotEmpty) ? highQualityArtworkUrl(p) : null;
  }

  int get heroIndex {
    if (view.hero.isEmpty) return 0;
    final i = view.hero.indexWhere((m) => m.id == _owners.hero.heroId);
    return i < 0 ? 0 : i;
  }

  StremioMeta? get heroItem => view.heroPresentation;

  void openHero() {
    final item = view.originalMetadata;
    final addon = view.heroAddon;
    if (item != null && addon != null) view.onHeroOpen(item, addon);
  }

  /// The id of the slide currently SHOWING — the host's suppression snapshot
  /// reads this at content-playback launch, because its own bookkeeping only
  /// knows the last *dwelled* item and playback can start before any dwell.
  String? get currentHeroId => _sections.heroArt.heroItem?.id;
}
