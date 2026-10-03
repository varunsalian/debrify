import 'package:debrify/features/torbox_downloads/application/torbox_magnet_policy.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_add_input_state.dart';
import 'torbox_catalog_state.dart';

typedef TorboxMagnetActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  TorboxCatalogState catalogState,
  TorboxAddInputState addInputState,
  Future<void> Function() refresh,
});

class TorboxMagnetActions {
  TorboxMagnetActions(this._deps);
  final TorboxMagnetActionsDeps _deps;

  void showComingSoon(String action) {
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text('$action support coming soon'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> showAddMagnetDialog() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.catalogState.apiKey!.isEmpty) {
      showComingSoon('Add Torbox API key');
      return;
    }

    await autoPasteMagnetLink();
    if (!_deps.mounted()) return;

    showDialog(
      context: _deps.context(),
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Magnet Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    node.nextFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _deps.addInputState.magnetController,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Paste magnet link here…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => handleAddMagnet(dialogContext),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> autoPasteMagnetLink() async {
    if (_deps.addInputState.magnetController.text.trim().isNotEmpty) return;
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim();
    if (text != null && text.startsWith('magnet:?')) {
      _deps.addInputState.magnetController.text = text;
    }
  }

  void handleAddMagnet(BuildContext dialogContext) {
    final magnetLink = _deps.addInputState.magnetController.text.trim();
    if (magnetLink.isEmpty) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link.')),
      );
      return;
    }

    if (!isValidMagnetLink(magnetLink)) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Please enter a valid magnet link.')),
      );
      return;
    }

    Navigator.of(dialogContext).pop();
    addMagnetToTorbox(magnetLink);
  }

  Future<void> addMagnetToTorbox(String magnetLink) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      showComingSoon('Add Torbox API key');
      return;
    }

    final navigator = Navigator.of(_deps.context(), rootNavigator: true);
    var dialogClosed = false;

    void closeDialogIfOpen() {
      if (!dialogClosed && navigator.canPop()) {
        navigator.pop();
        dialogClosed = true;
      }
    }

    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          title: Text('Adding torrent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Submitting magnet to Torbox…'),
            ],
          ),
        );
      },
    );

    try {
      final response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: true,
        addOnlyIfCached: true,
      );

      if (!_deps.mounted()) return;

      closeDialogIfOpen();

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = (response['error'] ?? 'Failed to add magnet')
            .toString();
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
        return;
      }

      _deps.addInputState.magnetController.clear();
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(const SnackBar(content: Text('Magnet added to Torbox.')));

      await _deps.refresh();
    } catch (e) {
      if (!_deps.mounted()) return;
      closeDialogIfOpen();
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add magnet: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
  }

  void openSettings() {
    // NOTE: pre-existing behavior — this "Open Torbox Settings" button navigated
    // to the PikPak tab (index 6), which looks like a bug (Settings is index 8).
    // Preserved as-is through the Cloud consolidation (index 6 is no longer a nav
    // tab, so route through the Cloud hub). Flagged for review — do not "fix"
    // silently.
    MainPageBridge.openCloudProvider?.call('pikpak');
  }
}
