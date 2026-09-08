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

  Future<void> _resolveMetadata() async {
    final generation = ++_metadataGeneration;
    final original = originalMetadata;
    _sourceSnapshot = original;
    if (original == null) return;
    try {
      final prefs = await MetadataPreferencesService.load();
      if (!mounted || generation != _metadataGeneration) return;
      setState(() => _presentationPreferences = prefs);
      final scope = ProfileRuntime.scope.value;
      final revision = MetadataPreferencesService.revision.value;
      final policy = jsonEncode(prefs.toJson());
      if (_cacheScope != scope ||
          _cacheRevision != revision ||
          _cachePolicy != policy) {
        _resolved.clear();
        _cacheScope = scope;
        _cacheRevision = revision;
        _cachePolicy = policy;
      }
      final cached = _resolved.remove(original);
      final presentation =
          (cached != null && cached.expires.isAfter(DateTime.now())
              ? cached.value
              : null) ??
          await metadataProvider.present(
            original,
            preferences: prefs,
            isRelevant: () => mounted && generation == _metadataGeneration,
          );
      if (!mounted ||
          generation != _metadataGeneration ||
          !identical(originalMetadata, original)) {
        return;
      }
      if (!presentation.retryable && presentation.unavailable.isEmpty) {
        _resolved[original] = (
          value: presentation,
          expires: DateTime.now().add(const Duration(minutes: 15)),
        );
        while (_resolved.length > 256) {
          _resolved.remove(_resolved.keys.first);
        }
      }
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
        _metadataPresentation = presentation.item;
        _presentationPreferences = prefs;
      });
      onMetadataPresentationChanged();
    } catch (_) {
      // Preference/profile transitions must never remove a usable card.
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _metadataGeneration++;
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    ProfileRuntime.scope.removeListener(_policyChanged);
    super.dispose();
  }
}
