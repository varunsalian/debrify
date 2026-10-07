import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AllDebridAddActionsDeps = ({
  AllDebridLibraryState libraryState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function() dismissLoading,
  Future<void> Function() load,
  Future<void> Function() loadLinks,
  void Function(String message) showLoading,
  void Function(String message, {bool isError}) snack,
});

class AllDebridAddActions {
  final AllDebridAddActionsDeps _deps;
  AllDebridAddActions(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;

  // ── Add magnet ─────────────────────────────────────────────────────────────

  Future<void> showAddMagnetDialog() async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final controller = TextEditingController();
    final magnet = await showDialog<String>(
      context: _deps.context(),
      builder: (ctx) => AlertDialog(
        title: const Text('Add magnet'),
        content: Focus(
          // D-pad: let arrow-down leave the field for the Cancel/Add buttons.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              node.nextFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Paste a magnet link or infohash',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (magnet == null || magnet.isEmpty) return;
    _deps.showLoading('Adding…');
    try {
      await AllDebridService.uploadMagnet(apiKey, magnet);
      _deps.dismissLoading();
      _deps.snack('Magnet added', isError: false);
      await _deps.load();
    } catch (e) {
      _deps.dismissLoading();
      _deps.snack('Failed to add magnet: $e', isError: true);
    }
  }

  Future<void> showAddLinkDialog() async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final controller = TextEditingController();
    // Auto-paste a URL from the clipboard, matching the Real-Debrid page.
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text?.trim() ?? '';
    if (clipText.startsWith('http://') || clipText.startsWith('https://')) {
      controller.text = clipText;
    }
    if (!_deps.mounted()) return;
    final link = await showDialog<String>(
      context: _deps.context(),
      builder: (ctx) => AlertDialog(
        title: const Text('Add link'),
        content: Focus(
          // D-pad: let arrow-down leave the field for the Cancel/Add buttons.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              node.nextFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Paste a download link',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (link == null || link.isEmpty) return;
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      _deps.snack(
        'Enter a valid URL (must start with http:// or https://)',
        isError: true,
      );
      return;
    }
    _deps.showLoading('Adding…');
    try {
      // Unlock first to validate the host is supported, then persist it to the
      // saved-links library so it shows up in this view.
      await AllDebridService.unlockLink(apiKey, link);
      await AllDebridService.saveLink(apiKey, link);
      _deps.dismissLoading();
      _deps.snack('Link added', isError: false);
      await _deps.loadLinks();
    } catch (e) {
      _deps.dismissLoading();
      _deps.snack('Failed to add link: $e', isError: true);
    }
  }
}
