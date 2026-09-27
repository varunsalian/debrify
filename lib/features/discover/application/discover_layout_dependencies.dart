import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../data/discover_layout_preferences.dart';
import '../models/discover_layout_session.dart';

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
