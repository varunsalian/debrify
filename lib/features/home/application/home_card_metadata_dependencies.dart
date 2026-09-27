import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/metadata/metadata_presentation_cache.dart';
import '../../../services/diagnostic_log.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/metadata_provider_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_card_metadata_repository.dart';
import '../models/home_card_metadata.dart';

final homeCardMetadataEpochProvider =
    Provider.autoDispose<HomeCardMetadataEpoch>(
      (ref) {
        void changed() => ref.invalidateSelf();
        MetadataPreferencesService.revision.addListener(changed);
        ProfileRuntime.scope.addListener(changed);
        ref.onDispose(() {
          MetadataPreferencesService.revision.removeListener(changed);
          ProfileRuntime.scope.removeListener(changed);
        });
        return (
          owner: ProfileSessionMemory.captureOwner(),
          revision: MetadataPreferencesService.revision.value,
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeCardMetadataRepositoryProvider = Provider.autoDispose
    .family<HomeCardMetadataRepository, HomeCardMetadataEpoch>(
      (ref, epoch) {
        bool current() =>
            epoch.owner == ProfileSessionMemory.captureOwner() &&
            epoch.revision == MetadataPreferencesService.revision.value;
        Future<T> read<T>(Future<T> Function() action) {
          if (!current()) {
            return Future.error(StateError('Retired metadata session'));
          }
          final scope = epoch.owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeCardMetadataRepository(
          epoch: epoch,
          cache: MetadataPresentationCache.shared,
          isCurrent: current,
          readPreferences: () => read(MetadataPreferencesService.load),
          present: (item, preferences, relevant) => read(
            () => MetadataProviderService.instance.present(
              item,
              preferences: preferences,
              isRelevant: () => current() && relevant(),
            ),
          ),
          recordReady: (diagnostic) => DiagnosticLog.instance.recordEvent(
            source: 'metadata',
            event: 'presentation_ready',
            fields: {
              'elapsed_ms': diagnostic.elapsedMs,
              'retryable': diagnostic.retryable,
              'cache_hit': diagnostic.cacheHit,
              'attempt': diagnostic.attempt,
              'missing': diagnostic.missing,
            },
          ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
