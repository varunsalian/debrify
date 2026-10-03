import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_add_input_state.dart';
import 'torbox_catalog_state.dart';

typedef TorboxWebCreateActionsDeps = ({
  TorboxCatalogState catalogState,
  void Function(String message, {bool isError}) showSnackBar,
  TorboxAddInputState addInputState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function({bool reset}) fetchWebDownloads,
});

class TorboxWebCreateActions {
  TorboxWebCreateActions(this._deps);
  final TorboxWebCreateActionsDeps _deps;

  Future<void> showAddWebDownloadDialog() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.catalogState.apiKey!.isEmpty) {
      _deps.showSnackBar('Add Torbox API key first');
      return;
    }

    _deps.addInputState.webLinkController.clear();
    _deps.addInputState.webNameController.clear();
    _deps.addInputState.webPasswordController.clear();

    await showDialog(
      context: _deps.context(),
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Web Download'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        node.nextFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _deps.addInputState.webLinkController,
                    maxLines: 2,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Paste URL here (YouTube, file hosts, etc.)',
                      labelText: 'URL *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _deps.addInputState.webNameController,
                  // D-pad exits (formerly a Focus/onKeyEvent wrapper).
                  onDownArrow: () =>
                      FocusManager.instance.primaryFocus?.nextFocus(),
                  onUpArrow: () =>
                      FocusManager.instance.primaryFocus?.previousFocus(),
                  decoration: const InputDecoration(
                    hintText: 'Custom name for the download',
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _deps.addInputState.webPasswordController,
                  obscureText: true,
                  // D-pad exits (formerly a Focus/onKeyEvent wrapper).
                  onDownArrow: () =>
                      FocusManager.instance.primaryFocus?.nextFocus(),
                  onUpArrow: () =>
                      FocusManager.instance.primaryFocus?.previousFocus(),
                  decoration: const InputDecoration(
                    hintText: 'Password if required',
                    labelText: 'Password (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Supports YouTube, file hosts, and direct links.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => handleAddWebDownload(dialogContext),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> handleAddWebDownload(BuildContext dialogContext) async {
    final link = _deps.addInputState.webLinkController.text.trim();
    if (link.isEmpty) {
      _deps.showSnackBar('Please enter a URL.');
      return;
    }

    // Basic URL validation
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      _deps.showSnackBar(
        'Please enter a valid URL starting with http:// or https://',
      );
      return;
    }

    Navigator.of(dialogContext).pop();

    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

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
          title: Text('Adding web download'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('This may take up to a minute...'),
            ],
          ),
        );
      },
    );

    try {
      final response = await TorboxService.createWebDownload(
        apiKey: apiKey,
        link: link,
        name: _deps.addInputState.webNameController.text.trim().isNotEmpty
            ? _deps.addInputState.webNameController.text.trim()
            : null,
        password:
            _deps.addInputState.webPasswordController.text.trim().isNotEmpty
            ? _deps.addInputState.webPasswordController.text.trim()
            : null,
      );

      if (!_deps.mounted()) return;

      closeDialogIfOpen();

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = (response['error'] ?? 'Failed to add web download')
            .toString();
        _deps.showSnackBar(errorMessage);
        return;
      }

      _deps.addInputState.webLinkController.clear();
      _deps.addInputState.webNameController.clear();
      _deps.addInputState.webPasswordController.clear();

      final detail = response['detail'] as String? ?? 'Web download added.';
      _deps.showSnackBar(detail, isError: false);

      // Refresh the web downloads list
      await _deps.fetchWebDownloads(reset: true);
    } catch (e) {
      if (!_deps.mounted()) return;
      closeDialogIfOpen();
      _deps.showSnackBar(
        'Failed to add web download: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }
}
