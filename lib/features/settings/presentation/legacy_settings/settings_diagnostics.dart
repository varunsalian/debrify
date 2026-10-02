import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsDiagnostics {
  SettingsDiagnostics(this._summaries, this._deps);
  final ({
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;

  Future<bool> activeProfileMayExportDiagnostics() async {
    // saveBackupFile has no user-retrievable destination on physical tvOS.
    // Keep this hidden until diagnostics use the authenticated Remote
    // transfer flow, as profile backups already do on Apple TV.
    if (PlatformUtil.isTvOS) return false;
    try {
      if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
        // A legacy install has one implicit device owner/admin.
        return true;
      }
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      return actor.role == UserProfileRole.admin;
    } catch (_) {
      return false;
    }
  }

  Future<void> exportDiagnosticLogs() async {
    if (_summaries.exportingDiagnostics) return;
    if (!await activeProfileMayExportDiagnostics()) {
      if (!_deps.mounted()) return;
      _deps.setState(() => _summaries.diagnosticExportVisible = false);
      final context = _deps.context();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only an admin can export diagnostic logs.'),
        ),
      );
      return;
    }
    if (!_deps.mounted()) return;
    _deps.setState(() => _summaries.exportingDiagnostics = true);

    try {
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_requested',
      );
      final exported = await DiagnosticLog.instance.exportLastWindow();
      if (!_deps.mounted()) return;

      if (kIsWeb) {
        final savedReference = await FilePicker.platform.saveFile(
          dialogTitle: 'Save diagnostic logs',
          fileName: exported.fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['jsonl'],
          bytes: exported.bytes,
        );
        if (!_deps.mounted() || savedReference == null) return;
        final context = _deps.context();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${exported.entryCount} privacy-filtered diagnostic entries.',
            ),
          ),
        );
      } else {
        final context = _deps.context();
        if (!context.mounted) return;
        await ProfileBackupFlows(context).saveBackupFile(
          fileName: exported.fileName,
          bytes: exported.bytes,
          mimeType: 'application/x-ndjson',
          artifactLabel: 'diagnostic log',
        );
      }
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_saved',
        fields: <String, Object?>{'entries': exported.entryCount},
      );
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: 'settings',
        event: 'diagnostic_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_deps.mounted()) return;
      final context = _deps.context();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export diagnostic logs.')),
      );
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() => _summaries.exportingDiagnostics = false);
      }
    }
  }
}
