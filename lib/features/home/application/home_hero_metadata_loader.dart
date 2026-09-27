import 'dart:async';
import '../../../models/hero_metadata_presentation.dart';
import '../../../models/stremio_addon.dart';
import '../data/home_hero_metadata_repository.dart';
import 'home_hero_metadata_policy.dart';

/// Per-view enrichment requests. Owns the debounce and request generation;
/// the view retains its presented value and ordered shell-art publication.
class HomeHeroMetadataLoader {
  HomeHeroMetadataLoader({
    required HomeHeroMetadataRepository repository,
    required bool Function() Function() captureScopeGuard,
  }) : _repository = repository,
       _captureScopeGuard = captureScopeGuard;

  final HomeHeroMetadataRepository _repository;
  final bool Function() Function() _captureScopeGuard;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load(
    StremioMeta item, {
    required bool Function() isCurrent,
    required void Function(HeroMetadataPresentation) onResolved,
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    final scopeCurrent = _captureScopeGuard();
    bool current() =>
        !_disposed &&
        isCurrent() &&
        generation == _generation &&
        scopeCurrent();
    final prefs = await _repository.readPreferences(current);
    if (prefs == null) return;
    _timer?.cancel();
    if (!needsHomeHeroMetadata(item, currentProvider: prefs.isCurrent)) return;
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null && prefs.isCurrent) return;
    // Starts only after preferences resolve, preserving the existing 140ms
    // debounce after the separate 260ms view-level hero-swap settle.
    _timer = Timer(const Duration(milliseconds: 140), () async {
      if (!current()) return;
      try {
        final originalDetails = imdb == null
            ? item
            : await _repository.fetchDetails(imdb, item.type);
        final presentation = await _repository.present(
          mergeHeroMetadata(item, originalDetails),
          prefs,
          current,
        );
        final details = prefs.isCurrent ? originalDetails : presentation.item;
        if (!current() || details == null) return;
        onResolved(HeroMetadataPresentation(details, prefs));
      } catch (_) {
        // Optional enrichment leaves the currently rendered hero intact.
      }
    });
  }

  /// A folder takes the stage without requesting title metadata. Preserve
  /// cancellation before generation invalidation at that transition point.
  void cancel() {
    _timer?.cancel();
    _generation++;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
