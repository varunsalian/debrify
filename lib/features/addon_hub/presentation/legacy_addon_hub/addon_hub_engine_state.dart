import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';

class AddonHubEngineState {
  // Torrent engines (the "Torrent Engines" kind).
  final RemoteEngineManager remoteEngines = RemoteEngineManager();

  final LocalEngineStorage localEngines = LocalEngineStorage.instance;

  List<ImportedEngineMetadata> importedEngines = const [];

  List<RemoteEngineInfo> availableEngines = const [];

  List<RemoteEngineInfo> knownRemoteEngines = const [];

  bool enginesLoading = false;

  String? enginesError;

  bool enginesLoadedOnce = false;

  // ── Torrent engines ────────────────────────────────────────────────────────
  int engineLoadRevision = 0;

  bool blockingProgressUp = false;
}
