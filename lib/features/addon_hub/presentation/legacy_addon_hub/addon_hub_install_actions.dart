import 'dart:convert';

import 'package:debrify/features/addon_hub/presentation/addon_hub_dialog.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef AddonHubInstallActionsDeps = ({
  BuildContext Function() context,
  AddonHubInstalledState installedState,
  bool Function() mounted,
  Future<void> Function() loadInstalled,
  AddonHubNavigationState navigationState,
});

class AddonHubInstallActions {
  AddonHubInstallActions(this._deps);
  final AddonHubInstallActionsDeps _deps;

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> installFromMarket(MarketplaceAddon m, int? fromNav) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      final addon = await _deps.installedState.stremio.addAddon(m.transportUrl);
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} installed')),
      );
      // The row we just installed becomes a non-focusable "Installed" label, so
      // its button — which held DPAD focus — vanishes. Reload now (the change
      // listener also fires) and, once the list rebuilds, land focus on whatever
      // row now occupies this slot (or the previous one / the filter bar) so the
      // TV remote is never stranded.
      await _deps.loadInstalled();
      if (!_deps.mounted()) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted() || fromNav == null) return;
        if (!_deps.navigationState.marketNav.focus(fromNav) &&
            !_deps.navigationState.marketNav.focus(fromNav - 1)) {
          _deps.navigationState.searchBtnFocus.requestFocus();
        }
      });
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> configureInBrowser(MarketplaceAddon m) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    final uri = Uri.tryParse(m.configureUrl);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!_deps.mounted()) return;
    if (!opened) {
      // TV / no browser: copy the URL so the user can configure elsewhere.
      await Clipboard.setData(ClipboardData(text: m.configureUrl));
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Configure link copied — open it in a browser, then '
            'paste the configured URL into "Add addon".',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> addByUrl() async {
    final app = AppThemeScope.of(_deps.context());
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Add addon',
        content: TvTextField(
          controller: controller,
          autofocus: true,
          cursorColor: app.seeAll.accent,
          decoration: InputDecoration(
            hintText: 'https://…/manifest.json',
            hintStyle: TextStyle(color: app.fade(app.core.tx, 0.35)),
            enabledBorder: OutlineInputBorder(
              borderRadius: app.shape.br(11),
              borderSide: BorderSide(color: app.seeAll.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: app.shape.br(11),
              borderSide: BorderSide(color: app.seeAll.accent, width: 2),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(),
          ),
          AddonHubHubDialogButton(
            label: 'Add',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !_deps.mounted()) return;
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      final addon = await _deps.installedState.stremio.addAddon(url);
      if (!_deps.mounted()) return;
      messenger.showSnackBar(SnackBar(content: Text('${addon.name} added')));
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> importJson() async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.json')) {
        throw Exception('Please select the Stremio addon JSON export.');
      }
      final List<int> bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await file.xFile.readAsBytes();
      } else {
        throw Exception('Could not read the selected file.');
      }
      final importResult = await _deps.installedState.stremio
          .importAddonsFromJson(utf8.decode(bytes));
      if (!_deps.mounted()) return;
      await showImportResult(importResult);
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> showImportResult(StremioAddonImportResult r) {
    return showDialog<void>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Import complete',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            importRow('Found', '${r.discovered}'),
            importRow('Imported', '${r.imported}'),
            importRow('Already installed', '${r.skippedDuplicates}'),
            if (r.skippedUnsupported > 0)
              importRow('Unsupported', '${r.skippedUnsupported}'),
            if (r.failed > 0) importRow('Failed', '${r.failed}'),
          ],
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Done',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget importRow(String label, String value) {
    final app = AppThemeScope.of(_deps.context());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: app.fade(app.core.tx, 0.7))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
