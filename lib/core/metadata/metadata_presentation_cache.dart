import 'dart:convert';

import '../../models/metadata_preferences.dart';
import '../../models/metadata_presentation.dart';
import '../../models/stremio_addon.dart';
import '../../services/profiles/profile_scope.dart';

typedef MetadataPresentationCacheEntry = ({
  MetadataPresentation value,
  DateTime expires,
});

/// The existing process-wide resolved cache, shared by cards and hero preloads.
/// Consumers retain ownership of relevance checks and expiry checks at use time.
class MetadataPresentationCache {
  MetadataPresentationCache({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static final shared = MetadataPresentationCache();

  final DateTime Function() _now;
  final _resolved = <StremioMeta, MetadataPresentationCacheEntry>{};
  ProfileScope? _scope;
  int? _revision;
  String? _policy;

  void prepare({
    required ProfileScope? scope,
    required int revision,
    required MetadataPreferences preferences,
  }) {
    final policy = jsonEncode(preferences.toJson());
    if (_scope != scope || _revision != revision || _policy != policy) {
      _resolved.clear();
      _scope = scope;
      _revision = revision;
      _policy = policy;
    }
  }

  /// Preloading reads without consuming or promoting an existing entry.
  MetadataPresentationCacheEntry? peek(StremioMeta item) => _resolved[item];

  /// Visible resolution consumes the entry before checking freshness; a
  /// successful result is stored again, moving it to the end of the cache.
  MetadataPresentationCacheEntry? take(StremioMeta item) =>
      _resolved.remove(item);

  void store(StremioMeta original, MetadataPresentation presentation) {
    if (presentation.retryable || presentation.unavailable.isNotEmpty) return;
    _resolved[original] = (
      value: presentation,
      expires: _now().add(const Duration(minutes: 15)),
    );
    while (_resolved.length > 256) {
      _resolved.remove(_resolved.keys.first);
    }
  }
}
