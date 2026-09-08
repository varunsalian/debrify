import '../models/metadata_preferences.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/stremio_addon.dart';
import '../services/metadata_preferences_service.dart';
import '../services/metadata_provider_service.dart';
import '../services/profiles/profile_runtime.dart';

/// Lazily enrichs mounted cards, never the complete remote catalogue. Requests
/// are shared by the repository. Item/provider/profile changes invalidate any
/// in-flight result before it can update a recycled tile.
mixin MetadataPresentationMixin<T extends StatefulWidget> on State<T> {
  StremioMeta? get originalMetadata;
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
      final presentation = await MetadataProviderService.instance.present(
        original,
        preferences: prefs,
        isRelevant: () => mounted && generation == _metadataGeneration,
      );
      if (!mounted ||
          generation != _metadataGeneration ||
          !identical(originalMetadata, original)) {
        return;
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
    _metadataGeneration++;
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    ProfileRuntime.scope.removeListener(_policyChanged);
    super.dispose();
  }
}
