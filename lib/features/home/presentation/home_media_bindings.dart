import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/home_hero_tint_loader.dart';
import '../application/home_hero_providers.dart';
import '../application/home_hero_live_preview.dart';
import '../application/home_hero_trailer_loader.dart';
import '../data/home_tracker_resume_repository.dart';
import '../application/home_playback_providers.dart';
import '../data/home_series_resume_resolver.dart';
import '../application/home_hero_metadata_loader.dart';
import '../models/home_catalog_session.dart';

/// Retains route-scoped hero loaders and resume resolvers. Reads stay live so
/// dependency invalidation still replaces the underlying provider value.
class HomeMediaBindings {
  HomeMediaBindings(WidgetRef ref, HomeCatalogSession session) {
    _tint = ref.listenManual(
      homeHeroTintLoaderProvider(session),
      (previous, next) {},
    );
    _live = ref.listenManual(
      homeHeroLivePreviewProvider(session),
      (previous, next) {},
    );
    _trailer = ref.listenManual(
      homeHeroTrailerLoaderProvider(session),
      (previous, next) {},
    );
    _trackerResume = ref.listenManual(
      homeTrackerResumeRepositoryProvider(session),
      (previous, next) {},
    );
    _seriesResume = ref.listenManual(
      homeSeriesResumeResolverProvider(session),
      (previous, next) {},
    );
    _metadata = ref.listenManual(
      homeHeroMetadataLoaderProvider(session),
      (previous, next) {},
    );
  }

  late final ProviderSubscription<HomeHeroTintLoader> _tint;
  HomeHeroTintLoader get tint => _tint.read();
  late final ProviderSubscription<HomeHeroLivePreview> _live;
  HomeHeroLivePreview get live => _live.read();
  late final ProviderSubscription<HomeHeroTrailerLoader> _trailer;
  HomeHeroTrailerLoader get trailer => _trailer.read();
  late final ProviderSubscription<HomeTrackerResumeRepository> _trackerResume;
  HomeTrackerResumeRepository get trackerResume => _trackerResume.read();
  late final ProviderSubscription<HomeSeriesResumeResolver> _seriesResume;
  HomeSeriesResumeResolver get seriesResume => _seriesResume.read();
  late final ProviderSubscription<HomeHeroMetadataLoader> _metadata;
  HomeHeroMetadataLoader get metadata => _metadata.read();

  // These explicit phases bracket the host's existing hero swap/notifier cleanup.
  void disposeResumeAndMetadata() {
    seriesResume.dispose();
    trackerResume.dispose();
    metadata.dispose();
  }

  void disposeTrailerAndTint() {
    trailer.dispose();
    tint.dispose();
  }

  void disposeLivePreview() => live.dispose();

  void close() {
    _tint.close();
    _live.close();
    _trailer.close();
    _seriesResume.close();
    _trackerResume.close();
    _metadata.close();
  }
}
