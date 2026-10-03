import 'package:debrify/features/pikpak_files/application/pikpak_link_policy.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_link_state.dart';
import 'pikpak_navigation_state.dart';

typedef PikpakLinkActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  PikpakLinkState linkState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  void Function(VoidCallback) setState,
  PikpakNavigationState navigationState,
  Future<void> Function() refreshFiles,
});

class PikpakLinkActions {
  PikpakLinkActions(this._deps);
  final PikpakLinkActionsDeps _deps;

  Future<void> showAddLinkDialog() async {
    // Auto-paste link from clipboard if available
    await autoPasteLink();

    if (!_deps.mounted()) return;

    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Link',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a link to download:',
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
                controller: _deps.linkState.linkController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'magnet:?xt=... or https://...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF475569)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF475569)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFFFAA00)),
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
              'Supported: Magnet links, HTTP/HTTPS URLs',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _deps.linkState.linkController.clear();
                    Navigator.of(context).pop();
                  },
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
                  onPressed: _deps.linkState.isAddingLink ? null : addLink,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFFFAA00),
                  ),
                  child: _deps.linkState.isAddingLink
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add',
                          style: TextStyle(color: Colors.black),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> autoPasteLink() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final text = clipboardData!.text!.trim();
        // Check if it looks like a supported link
        if (text.startsWith('http://') ||
            text.startsWith('https://') ||
            text.startsWith('magnet:')) {
          _deps.linkState.linkController.text = text;
        }
      }
    } catch (e) {
      debugPrint('Failed to read clipboard: $e');
    }
  }

  Future<void> addLink() async {
    final link = _deps.linkState.linkController.text.trim();
    if (link.isEmpty) {
      _deps.showSnackBar('Please enter a link', isError: true);
      return;
    }

    if (!isValidPikPakLink(link)) {
      _deps.showSnackBar(
        'Please enter a valid URL or magnet link',
        isError: true,
      );
      return;
    }

    Navigator.of(_deps.context()).pop(); // Close the dialog

    _deps.setState(() {
      _deps.linkState.isAddingLink = true;
    });

    // Show loading dialog
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFAA00)),
            const SizedBox(height: 16),
            const Text('Adding to PikPak...'),
            const SizedBox(height: 8),
            Text(
              link.length > 50 ? '${link.substring(0, 50)}...' : link,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    try {
      final pikpak = PikPakApiService.instance;

      // Use current folder if browsing, otherwise use restricted folder or root
      final parentFolderId =
          _deps.navigationState.currentFolderId ??
          _deps.navigationState.restrictedFolderId;

      final result = await pikpak.addOfflineDownload(
        link,
        parentFolderId: parentFolderId,
      );

      if (!_deps.mounted()) return;
      Navigator.of(_deps.context()).pop(); // Close loading dialog

      // Extract file name from response
      String? fileName;
      if (result['file'] != null) {
        fileName = result['file']['name'];
      } else if (result['task'] != null) {
        fileName = result['task']['name'];
      }

      _deps.showSnackBar(
        'Added to PikPak${fileName != null ? ': $fileName' : ''}',
        isError: false,
      );

      // Clear the controller and refresh
      _deps.linkState.linkController.clear();
      _deps.refreshFiles();
    } catch (e) {
      if (!_deps.mounted()) return;
      Navigator.of(_deps.context()).pop(); // Close loading dialog

      _deps.showSnackBar('Failed to add: ${e.toString()}', isError: true);
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.linkState.isAddingLink = false;
        });
      }
    }
  }
}
