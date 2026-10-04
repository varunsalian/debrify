import 'package:debrify/features/addon_hub/presentation/addon_hub_dialog.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/services/engine/config_loader.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

typedef AddonHubEngineActionsDeps = ({
  BuildContext Function() context,
  AddonHubEngineState engineState,
  Future<void> Function() loadEngines,
  bool Function() mounted,
});

class AddonHubEngineActions {
  AddonHubEngineActions(this._deps);
  final AddonHubEngineActionsDeps _deps;

  Future<void> installEngine(RemoteEngineInfo engine) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    showBlockingProgress('Installing ${engine.displayName}…');
    try {
      final yaml = await _deps.engineState.remoteEngines.downloadEngineYaml(
        engine.fileName,
      );
      if (yaml == null) throw Exception('Failed to download engine config');
      await _deps.engineState.localEngines.saveEngine(
        engineId: engine.id,
        fileName: engine.fileName,
        yamlContent: yaml,
        displayName: engine.displayName,
        icon: engine.icon,
      );
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      dismissBlockingProgress();
      await _deps.loadEngines();
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${engine.displayName} installed')),
      );
    } catch (e) {
      dismissBlockingProgress();
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to install: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> deleteEngine(ImportedEngineMetadata engine) async {
    final app = AppThemeScope.of(_deps.context());
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Delete engine',
        content: Text(
          'Delete "${engine.displayName}"?',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          AddonHubHubDialogButton(
            label: 'Delete',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return;
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      await _deps.engineState.localEngines.deleteEngine(engine.id);
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      await _deps.loadEngines();
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${engine.displayName} deleted')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> importEngineFromFile() async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    // Captured with the messenger, before any await: the replace-confirmation
    // dialog below opens after the file picker returns.
    final app = AppThemeScope.of(_deps.context());
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final lower = file.name.toLowerCase();
      if (!lower.endsWith('.yaml') && !lower.endsWith('.yml')) {
        throw Exception('Please select a YAML file (.yaml or .yml)');
      }
      final String yamlContent;
      if (file.bytes != null) {
        yamlContent = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        yamlContent = String.fromCharCodes(await file.xFile.readAsBytes());
      } else {
        throw Exception('Could not read file content');
      }
      final yaml = loadYaml(yamlContent);
      final engineId = yaml is Map ? yaml['id'] as String? : null;
      final displayName = yaml is Map ? yaml['display_name'] as String? : null;
      final icon = yaml is Map ? yaml['icon'] as String? : null;
      if (engineId == null || engineId.isEmpty) {
        throw Exception('YAML must contain an "id" field');
      }
      if (displayName == null || displayName.isEmpty) {
        throw Exception('YAML must contain a "display_name" field');
      }
      final existing = await _deps.engineState.localEngines
          .getImportedEngines();
      if (existing.any((e) => e.id == engineId)) {
        if (!_deps.mounted()) return;
        final replace = await showDialog<bool>(
          context: _deps.context(),
          builder: (ctx) => AddonHubHubDialog(
            title: 'Engine already exists',
            content: Text(
              'Replace the existing "$engineId"?',
              style: TextStyle(color: app.fade(app.core.tx, 0.75)),
            ),
            actions: [
              AddonHubHubDialogButton(
                label: 'Cancel',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              AddonHubHubDialogButton(
                label: 'Replace',
                primary: true,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      if (!_deps.mounted()) return;
      showBlockingProgress('Importing $displayName…');
      await _deps.engineState.localEngines.saveEngine(
        engineId: engineId,
        fileName: file.name,
        yamlContent: yamlContent,
        displayName: displayName,
        icon: icon,
      );
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      dismissBlockingProgress();
      await _deps.loadEngines();
      if (!_deps.mounted()) return;
      messenger.showSnackBar(SnackBar(content: Text('$displayName imported')));
    } catch (e) {
      dismissBlockingProgress();
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void showBlockingProgress(String message) {
    final app = AppThemeScope.of(_deps.context());
    _deps.engineState.blockingProgressUp = true;
    showDialog<void>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: app.seeAll.panel,
        shape: RoundedRectangleBorder(
          borderRadius: app.shape.br(16),
          side: BorderSide(color: app.seeAll.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: app.seeAll.accent,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void dismissBlockingProgress() {
    if (_deps.engineState.blockingProgressUp && _deps.mounted()) {
      Navigator.of(_deps.context(), rootNavigator: true).pop();
      _deps.engineState.blockingProgressUp = false;
    }
  }
}
