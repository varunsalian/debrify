import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../models/sources_session.dart';
import 'saved_sources_controller.dart';
import 'source_settings_controller.dart';

final sourceStartupProvider = Provider<SourceStartup>(
  SourceStartup.new,
  dependencies: [sourceSettingsProvider, savedSourcesProvider],
);

/// Loads the existing state owners before the view starts its first search.
class SourceStartup {
  SourceStartup(this._ref);
  final Ref _ref;

  bool _active(SourcesSession session) =>
      _ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  Future<bool> load(SourcesSession session) async {
    if (!_active(session)) return false;
    // Priority must be known before the first engine batch. Loading it beside
    // search previously used the toolbar interaction path and froze streaming.
    await Future.wait<Object?>([
      _ref.read(sourceSettingsProvider(session).notifier).load(),
      _ref.read(savedSourcesProvider(session).notifier).reload(),
    ]);
    return _active(session);
  }
}
