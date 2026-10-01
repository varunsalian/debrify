import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/discover_prefs.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../data/discover_layout_preferences.dart';
import '../data/discover_source_repository.dart';
import '../models/discover_card_settings.dart';
import '../models/discover_layout_session.dart';
import '../models/discover_source_state.dart';
import '../models/metadata_feature_policy.dart';

/// Reads only the cache warmed by the existing profile startup/settings owner.
/// It performs no warm-up, persistence or asynchronous work while building UI.
final discoverCardSettingsReaderProvider = Provider.autoDispose
    .family<DiscoverCardSettingsReader, DiscoverCardSettingsSession>(
      (ref, session) => () {
        if (!ref.mounted ||
            session.owner != ProfileSessionMemory.captureOwner()) {
          return null;
        }
        return (
          showTypeTags: DiscoverPrefs.showTypeTags,
          showRatings: DiscoverPrefs.showRatings,
          showTitles: DiscoverPrefs.showTitles,
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

/// Bounded process memory replacing the screen's static layout mirror. Re-entry
/// in the same session stays warm; profile handoff invalidates the retained value.
abstract final class _DiscoverLayoutMemory {
  static final _last = ProfileSessionMemory<String>();

  static String read(ProfileSessionOwner owner) {
    if (owner != ProfileSessionMemory.captureOwner()) return 'stage';
    final value = _last.take(owner);
    // This is a reusable preference mirror, not a consumable route snapshot.
    if (value != null) _last.store(owner, value);
    return value ?? 'stage';
  }

  static void remember(ProfileSessionOwner owner, String layout) {
    if (owner == ProfileSessionMemory.captureOwner()) {
      _last.store(owner, layout);
    }
  }
}

final discoverLayoutPreferencesProvider = Provider.autoDispose
    .family<DiscoverLayoutPreferences, DiscoverLayoutSession>(
      (ref, session) {
        bool ownerCurrent() =>
            session.owner == ProfileSessionMemory.captureOwner();
        return DiscoverLayoutPreferences(
          readCached: () => _DiscoverLayoutMemory.read(session.owner),
          remember: (layout) =>
              _DiscoverLayoutMemory.remember(session.owner, layout),
          readSaved: (isCurrent) {
            bool current() => ownerCurrent() && isCurrent();
            if (!current()) throw StateError('Discover layout owner retired');
            Future<String> read() =>
                StorageService.getDiscoverLayout(canContinue: current);
            final scope = session.owner.scope;
            return scope == null
                ? read()
                : ProfileRuntime.withCapturedScope(scope, read);
          },
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final discoverSourceRepositoryProvider = Provider.autoDispose
    .family<DiscoverSourceRepository, DiscoverSourceSession>(
      (ref, session) {
        bool current() => session.owner == ProfileSessionMemory.captureOwner();
        Future<T> scoped<T>(Future<T> Function() read) {
          if (!current()) throw StateError('Discover source owner retired');
          final scope = session.owner.scope;
          return scope == null
              ? read()
              : ProfileRuntime.withCapturedScope(scope, read);
        }

        return DiscoverSourceRepository(
          readDefault: () => scoped(() async {
            final value = await StorageService.getDiscoverDefaultSource();
            return value == StorageService.discoverDefaultRememberLast
                ? null
                : value;
          }),
          readLast: () => scoped(StorageService.getDiscoverLastSource),
          readAddons: () => scoped(StremioService.instance.getCatalogAddons),
          writeLast: (source, isCurrent) =>
              StorageService.setDiscoverLastSource(
                source,
                canContinue: () => current() && isCurrent(),
              ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final metadataFeatureReaderProvider = Provider.autoDispose
    .family<MetadataFeatureReader, MetadataFeatureSession>(
      (ref, session) => () async {
        if (session.owner != ProfileSessionMemory.captureOwner()) {
          throw StateError('Metadata policy owner retired');
        }
        final scope = session.owner.scope;
        return scope == null
            ? MetadataPreferencesService.load()
            : ProfileRuntime.withCapturedScope(
                scope,
                MetadataPreferencesService.load,
              );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
