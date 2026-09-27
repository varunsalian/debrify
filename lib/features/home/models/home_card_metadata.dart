import '../../../models/metadata_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';

typedef HomeCardMetadataEpoch = ({ProfileSessionOwner owner, int revision});

/// Read-only presentation state; legacy catalog objects retain their identity.
class HomeCardMetadataState {
  const HomeCardMetadataState({
    required this.original,
    this.presentation,
    this.preferences,
    this.resolvedOnce = false,
  });

  final StremioMeta original;
  final StremioMeta? presentation;
  final MetadataPreferences? preferences;
  final bool resolvedOnce;

  StremioMeta get presented => presentation ?? original;
  MetadataPreferences get effectivePreferences =>
      preferences ?? MetadataPreferences();

  bool artworkPending(MetadataCategory category) =>
      (original.type == 'movie' || original.type == 'series') &&
      (preferences == null ||
          (!resolvedOnce &&
              preferences!.provider(category) != MetadataPreferences.current));

  HomeCardMetadataState forSource(StremioMeta next) {
    if (resolvedOnce && original.id == next.id && original.type == next.type) {
      return HomeCardMetadataState(
        original: next,
        presentation: presentation ?? original,
        preferences: preferences,
        resolvedOnce: true,
      );
    }
    return HomeCardMetadataState(original: next);
  }
}

/// One source/policy binding within one mounted card and originating profile.
class HomeCardMetadataSession {
  const HomeCardMetadataSession({
    required this.epoch,
    required this.viewIdentity,
    required this.generation,
    required this.initial,
  });

  final HomeCardMetadataEpoch epoch;
  final Object viewIdentity;
  final int generation;
  final HomeCardMetadataState initial;

  @override
  bool operator ==(Object other) =>
      other is HomeCardMetadataSession &&
      other.epoch == epoch &&
      identical(other.viewIdentity, viewIdentity) &&
      other.generation == generation;

  @override
  int get hashCode =>
      Object.hash(epoch, identityHashCode(viewIdentity), generation);
}

typedef HomeCardMetadataDiagnostic = ({
  int elapsedMs,
  bool retryable,
  bool cacheHit,
  int attempt,
  int missing,
});
