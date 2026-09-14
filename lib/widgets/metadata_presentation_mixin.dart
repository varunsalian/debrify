import '../services/tmdb_metadata_repository.dart';
import '../services/diagnostic_log.dart';
import '../models/hero_metadata_presentation.dart';
import '../models/metadata_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../models/stremio_addon.dart';
import '../services/metadata_preferences_service.dart';
import '../services/metadata_provider_service.dart';
import '../services/profiles/profile_runtime.dart';

/// Lazily enrichs mounted cards, never the complete remote catalogue. Requests
/// are shared by the repository. Item/provider/profile changes invalidate any
/// in-flight result before it can update a recycled tile.
mixin MetadataPresentationMixin<T extends StatefulWidget> on State<T> {
  static final _resolved =
      <StremioMeta, ({MetadataPresentation value, DateTime expires})>{};
  static Object? _cacheScope;
  static int? _cacheRevision;
  static String? _cachePolicy;
  Timer? _retry;
  int _attempt = 0;
  bool _resolvedOnce = false;

  StremioMeta? get originalMetadata;
  bool get prioritizeMetadata => false;
  Future<MetadataPresentation> _present(StremioMeta item, MetadataPreferences prefs,
      bool Function() relevant, {bool hero = false}) {
    Future<MetadataPresentation> action() => metadataProvider.present(item,
        preferences: prefs, isRelevant: relevant);
    return hero || prioritizeMetadata
        ? TmdbMetadataRepository.withHeroPriority(action) : action();
  }
  final _preloadDelays = <VoidCallback>{};
  void _cancelPreloadDelays() {
    for (final cancel in _preloadDelays.toList()) { cancel(); }
  }
  Future<void> _preloadDelay(Duration duration) {
    final done = Completer<void>();
    late Timer timer;
    late VoidCallback cancel;
    cancel = () {
      timer.cancel();
      _preloadDelays.remove(cancel);
      if (!done.isCompleted) done.complete();
    };
    timer = Timer(duration, cancel);
    _preloadDelays.add(cancel);
    return done.future;
  }
  @protected
  MetadataProviderService get metadataProvider =>
      MetadataProviderService.instance;

  /// Cards must not paint an unrelated provider while their policy resolves.
  bool metadataArtworkPending(MetadataCategory category) =>
      originalMetadata != null &&
      (originalMetadata!.type == 'movie' ||
          originalMetadata!.type == 'series') &&
      (_presentationPreferences == null ||
          (!_resolvedOnce && usesMetadataProvider(category)));

  /// Hero surfaces share the card loading policy for artwork and information.
  StremioMeta? get heroPresentation {
    final item = presentedMetadata;
    if (item == null) return null;
    final info = metadataArtworkPending(MetadataCategory.information);
    final art = metadataArtworkPending(MetadataCategory.backgrounds);
    final poster = metadataArtworkPending(MetadataCategory.posters);
    if (!info && !art && !poster) return item;
    return StremioMeta(
      id: item.id,
      imdbId: item.imdbId,
      type: item.type,
      name: item.name,
      description: info ? null : item.description,
      genres: info ? null : item.genres,
      runtime: info ? null : item.runtime,
      background: art ? null : item.background,
      logo: art ? null : item.logo,
      poster: poster ? null : item.poster,
      year: item.year,
      imdbRating: item.imdbRating,
      sourceAddon: item.sourceAddon,
      addedAtMs: item.addedAtMs,
      trailerYtId: item.trailerYtId,
    );
  }

  StremioMeta? _metadataPresentation;
  StremioMeta? _sourceSnapshot;
  int _metadataGeneration = 0;
  MetadataPreferences? _presentationPreferences;
  MetadataPreferences get metadataPreferences =>
      _presentationPreferences ?? MetadataPreferences();
  bool usesMetadataProvider(MetadataCategory category) =>
      _presentationPreferences != null &&
      _presentationPreferences!.provider(category) !=
          MetadataPreferences.current;
  StremioMeta? get presentedMetadata =>
      _metadataPresentation ?? originalMetadata;

  @override
  void initState() {
    super.initState();
    MetadataPreferencesService.revision.addListener(_policyChanged);
    ProfileRuntime.scope.addListener(_policyChanged);
    unawaited(_resolveMetadata());
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ordinary parent rebuilds must not restart metadata for the same card.
    if (identical(_sourceSnapshot, originalMetadata)) return;
    _retry?.cancel();
    _attempt = 0;
    _resolvedOnce = false;
    // Recycled cards can change without changing their element key.
    _metadataPresentation = null;
    _presentationPreferences = null;
    unawaited(_resolveMetadata());
  }

  void refreshMetadataPresentation() => _metadataChanged();
  void onMetadataPolicyChanged() {}
  void onMetadataPresentationChanged() {}
  void _policyChanged() {
    _cancelPreloadDelays();
    _metadataChanged();
    onMetadataPolicyChanged();
  }

  void _metadataChanged() {
    if (!mounted) return;
    _retry?.cancel();
    _attempt = 0;
    _resolvedOnce = false;
    setState(() {
      _metadataPresentation = null;
      _presentationPreferences = null;
    });
    unawaited(_resolveMetadata());
  }

  int _preloadGeneration = 0;

  /// Only a small, known hero reel; never prefetch whole shelves.
  Future<void> preloadMetadata(
    List<StremioMeta> items,
    Future<void> Function(StremioMeta, MetadataPreferences) warmArtwork,
  ) async {
    _cancelPreloadDelays();
    final generation = ++_preloadGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool relevant() => mounted && generation == _preloadGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    try {
      final prefs = await MetadataPreferencesService.load();
      if (!relevant()) return;
      _prepareCache(prefs);
      final queue = items.toList();
      var cursor = 0;
      Future<void> worker() async {
        while (relevant() && cursor < queue.length) {
          final index = cursor++;
          final item = queue[index];
          final timer = Stopwatch()..start();
          try {
            final cached = _resolved[item];
            var result = cached != null && cached.expires.isAfter(DateTime.now())
                ? cached.value
                : await _present(item, prefs, relevant, hero: true);
            for (var attempt = 1; result.retryable && attempt <= 2 && relevant(); attempt++) {
              DiagnosticLog.instance.recordEvent(source: 'metadata', event: 'hero_preload_retry',
                  fields: {'slot': index, 'attempt': attempt});
              await _preloadDelay(Duration(seconds: attempt * 2));
              if (!relevant()) return;
              result = await _present(item, prefs, relevant, hero: true);
            }
            if (!relevant()) return;
            _storePresentation(item, result);
            DiagnosticLog.instance.recordEvent(source: 'metadata', event: 'hero_preload',
              fields: {'slot': index, 'elapsed_ms': timer.elapsedMilliseconds,
                'retryable': result.retryable});
            await warmArtwork(result.item, prefs);
          } catch (_) {
            // A speculative request must not surface errors or block the reel.
          }
        }
      }
      await Future.wait([worker(), worker()]);
    } catch (_) {
      // Profile transitions invalidate preference reads.
    }
  }

  void _prepareCache(MetadataPreferences prefs) {
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    final policy = jsonEncode(prefs.toJson());
    if (_cacheScope != scope || _cacheRevision != revision || _cachePolicy != policy) {
      _resolved.clear();
      _cacheScope = scope;
      _cacheRevision = revision;
      _cachePolicy = policy;
    }
  }

  void _storePresentation(StremioMeta original, MetadataPresentation presentation) {
    if (presentation.retryable || presentation.unavailable.isNotEmpty) return;
    _resolved[original] = (value: presentation,
        expires: DateTime.now().add(const Duration(minutes: 15)));
    while (_resolved.length > 256) {
      _resolved.remove(_resolved.keys.first);
    }
  }

  Future<void> _resolveMetadata() async {
    final timing = Stopwatch()..start();
    final generation = ++_metadataGeneration;
    final original = originalMetadata;
    _sourceSnapshot = original;
    if (original == null) return;
    try {
      final prefs = await MetadataPreferencesService.load();
      if (!mounted || generation != _metadataGeneration) return;
      setState(() => _presentationPreferences = prefs);
      _prepareCache(prefs);
      final cached = _resolved.remove(original);
      final presentation =
          (cached != null && cached.expires.isAfter(DateTime.now())
              ? cached.value
              : null) ??
          await _present(original, prefs,
            () => mounted && generation == _metadataGeneration);
      if (!mounted ||
          generation != _metadataGeneration ||
          !identical(originalMetadata, original)) {
        return;
      }
      DiagnosticLog.instance.recordEvent(source: 'metadata', event: 'presentation_ready',
        fields: {'elapsed_ms': timing.elapsedMilliseconds, 'retryable': presentation.retryable,
          'cache_hit': cached != null && cached.expires.isAfter(DateTime.now()),
          'attempt': _attempt, 'missing': presentation.unavailable.length});
      _storePresentation(original, presentation);
      _resolvedOnce = true;
      if (presentation.retryable && _attempt < 2) {
        _retry?.cancel();
        _retry = Timer(Duration(seconds: ++_attempt * 2), () {
          if (mounted && generation == _metadataGeneration) {
            unawaited(_resolveMetadata());
          }
        });
      }
      if (identical(presentation.item, original) && prefs.isCurrent) {
        _presentationPreferences = prefs;
        onMetadataPresentationChanged();
        return;
      }
      setState(() {
        // A retry belongs to this exact item and policy generation. Preserve
        // fields already resolved under that policy if a later request fails;
        // never use the original catalog as a fallback when it is disabled.
        _metadataPresentation =
            presentation.retryable && _metadataPresentation != null
            ? mergeHeroMetadata(_metadataPresentation!, presentation.item)
            : presentation.item;
        _presentationPreferences = prefs;
      });
      onMetadataPresentationChanged();
    } catch (_) {
      // Preference/profile transitions must never remove a usable card.
    }
  }

  @override
  void dispose() {
    _cancelPreloadDelays();
    _retry?.cancel();
    _metadataGeneration++;
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    ProfileRuntime.scope.removeListener(_policyChanged);
    super.dispose();
  }
}
