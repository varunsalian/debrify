import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/discover_prefs.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/discover_card_settings.dart';

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
