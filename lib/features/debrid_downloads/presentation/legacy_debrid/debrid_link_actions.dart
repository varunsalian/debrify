import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_input_policy.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_add_input_state.dart';
import 'debrid_catalog_state.dart';

typedef DebridLinkActionsDeps = ({
  BuildContext Function() context,
  DebridAddInputState addInputState,
  void Function(String message) showError,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  DebridCatalogState catalogState,
  Future<void> Function(String apiKey, {bool reset}) fetchDownloads,
});

class DebridLinkActions {
  DebridLinkActions(this._deps);
  final DebridLinkActionsDeps _deps;

  Future<void> showAddLinkDialog() async {
    // Auto-paste link from clipboard if available
    await autoPasteLink();

    showDialog(
      context: _deps.context(),
      builder: (context) {
        final app = AppThemeScope.of(context);
        return AlertDialog(
          backgroundColor: app.cloud.dialogSurface,
          shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
          title: const Text(
            'Add Link',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a link to unrestrict:',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 12),
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
                  controller: _deps.addInputState.linkController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/file.zip',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: const BorderSide(color: Color(0xFF475569)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: const BorderSide(color: Color(0xFF475569)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: BorderSide(color: app.cloud.accent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  maxLines: 3,
                  minLines: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Supported: Direct download links, file hosting services, etc.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _deps.addInputState.isAddingLink
                        ? null
                        : addLink,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    child: _deps.addInputState.isAddingLink
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> autoPasteLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      // Check if it looks like a URL
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _deps.addInputState.linkController.text = text;
      }
    }
  }

  Future<void> addLink() async {
    final link = _deps.addInputState.linkController.text.trim();
    if (link.isEmpty) {
      _deps.showError('Please enter a link');
      return;
    }

    if (!isValidLink(link)) {
      _deps.showError(
        'Please enter a valid URL (must start with http:// or https://)',
      );
      return;
    }

    Navigator.of(_deps.context()).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unrestricting Link',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing link...'),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.addInputState.isAddingLink = true;
      });
    }

    try {
      // Unrestrict the link
      await DebridService.unrestrictLink(_deps.catalogState.apiKey!, link);

      // Close loading dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context()).pop();
      }

      // Clear the input
      _deps.addInputState.linkController.clear();

      // Show success message
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text('Link unrestricted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the downloads list
      await _deps.fetchDownloads(_deps.catalogState.apiKey!, reset: true);
    } catch (e) {
      // Close loading dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context()).pop();
      }

      if (_deps.mounted()) {
        // Show the actual Real Debrid error message with user-friendly formatting
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        final friendlyMessage = getLinkUnrestrictErrorMessage(errorMessage);
        _deps.showError(friendlyMessage);
      }
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.addInputState.isAddingLink = false;
        });
      }
    }
  }
}
