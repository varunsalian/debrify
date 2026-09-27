import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../data/home_layout_preferences.dart';
import '../models/home_catalog_session.dart';
import 'home_layout_preference.dart';

final homeLayoutPreferencesProvider = Provider<HomeLayoutPreferences>(
  (ref) => HomeLayoutPreferences(
    readCached: () => StorageService.tvHomeStyleCached,
    readSaved: StorageService.getTvHomeStyle,
  ),
  dependencies: const [],
);

final homeLayoutPreferenceProvider = Provider.autoDispose
    .family<HomeLayoutPreference, HomeCatalogSession>(
      (ref, session) {
        final preferences = ref.watch(homeLayoutPreferencesProvider);
        final scope = session.owner.scope;
        final operation = HomeLayoutPreference(
          initialStyle: preferences.readCached(),
          readSaved: () => scope == null
              ? preferences.readSaved()
              : ProfileRuntime.withCapturedScope(scope, preferences.readSaved),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: [homeLayoutPreferencesProvider],
    );
