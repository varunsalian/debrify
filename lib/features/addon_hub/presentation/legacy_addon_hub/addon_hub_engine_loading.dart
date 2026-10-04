import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AddonHubEngineLoadingDeps = ({
  AddonHubEngineState engineState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class AddonHubEngineLoading {
  AddonHubEngineLoading(this._deps);
  final AddonHubEngineLoadingDeps _deps;

  Future<void> onEnginesChanged() async {
    final revision = ++_deps.engineState.engineLoadRevision;
    try {
      final imported = await _deps.engineState.localEngines
          .getImportedEngines();
      if (!_deps.mounted() ||
          revision != _deps.engineState.engineLoadRevision) {
        return;
      }
      _deps.setState(() {
        _deps.engineState.importedEngines = imported;
        final installed = imported.map((e) => e.id).toSet();
        _deps.engineState.availableEngines = _deps
            .engineState
            .knownRemoteEngines
            .where((e) => !installed.contains(e.id))
            .toList();
        _deps.engineState.enginesLoading = false;
        _deps.engineState.enginesError = null;
      });
    } catch (_) {
      if (_deps.mounted() && revision == _deps.engineState.engineLoadRevision) {
        _deps.setState(() {
          _deps.engineState.enginesLoading = false;
          _deps.engineState.enginesError =
              'Could not refresh installed engines';
        });
      }
    }
  }

  Future<void> loadEngines() async {
    final revision = ++_deps.engineState.engineLoadRevision;
    _deps.setState(() {
      _deps.engineState.enginesLoading = true;
      _deps.engineState.enginesError = null;
      _deps.engineState.enginesLoadedOnce = true;
    });
    try {
      final imported = await _deps.engineState.localEngines
          .getImportedEngines();
      final remote = await _deps.engineState.remoteEngines
          .fetchAvailableEngines();
      if (!_deps.mounted()) return;
      _deps.engineState.knownRemoteEngines = remote;
      if (revision != _deps.engineState.engineLoadRevision) {
        await onEnginesChanged();
        return;
      }
      final importedIds = imported.map((e) => e.id).toSet();
      if (_deps.mounted() && revision == _deps.engineState.engineLoadRevision) {
        _deps.setState(() {
          _deps.engineState.importedEngines = imported;
          _deps.engineState.availableEngines = remote
              .where((e) => !importedIds.contains(e.id))
              .toList();
          _deps.engineState.enginesLoading = false;
        });
      }
    } catch (e) {
      if (_deps.mounted() && revision == _deps.engineState.engineLoadRevision) {
        _deps.setState(() {
          _deps.engineState.enginesError = e.toString().replaceFirst(
            'Exception: ',
            '',
          );
          _deps.engineState.enginesLoading = false;
        });
      }
    }
  }
}
