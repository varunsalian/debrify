import 'dart:async';

import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_link_state.dart';
import 'premiumize_navigation_state.dart';

typedef PremiumizeLinkActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  PremiumizeLinkState linkState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  PremiumizeCatalogState catalogState,
  void Function(VoidCallback) setState,
  void Function(String message) showLoadingDialog,
  PremiumizeNavigationState navigationState,
  void Function() dismissDialog,
  Future<void> Function() refresh,
});

class PremiumizeLinkActions {
  PremiumizeLinkActions(this._deps);
  final PremiumizeLinkActionsDeps _deps;

  // ── Add link ───────────────────────────────────────────────────────────────

  Future<void> showAddLinkDialog() async {
    await autoPasteLink();
    if (!_deps.mounted()) return;
    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add to Premiumize',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a magnet or link to add to your cloud:',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Focus(
              // D-pad: let arrow-down move focus out of the field to the buttons.
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
                    borderSide: const BorderSide(color: Color(0xFFFB923C)),
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
              'Adding to cloud spends fair-use points (~1pt/GB).',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _deps.linkState.linkController.clear();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB923C),
            ),
            onPressed: _deps.linkState.isAddingLink ? null : addLink,
            child: const Text('Add', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> autoPasteLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null &&
          (text.startsWith('http://') ||
              text.startsWith('https://') ||
              text.startsWith('magnet:'))) {
        _deps.linkState.linkController.text = text;
      }
    } catch (_) {}
  }

  Future<void> addLink() async {
    final link = _deps.linkState.linkController.text.trim();
    if (link.isEmpty) {
      _deps.showSnackBar('Please enter a link', isError: true);
      return;
    }
    if (!(link.startsWith('http://') ||
        link.startsWith('https://') ||
        link.startsWith('magnet:'))) {
      _deps.showSnackBar(
        'Please enter a valid URL or magnet link',
        isError: true,
      );
      return;
    }
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    Navigator.of(_deps.context()).pop();
    _deps.setState(() => _deps.linkState.isAddingLink = true);
    _deps.showLoadingDialog('Adding to Premiumize...');

    try {
      await PremiumizeService.createTransfer(
        apiKey,
        link,
        folderId: _deps.navigationState.currentFolderId,
      );
      _deps.dismissDialog();
      if (!_deps.mounted()) return;
      _deps.linkState.linkController.clear();
      _deps.showSnackBar('Added to Premiumize', isError: false);
      await _deps.refresh();
    } catch (e) {
      _deps.dismissDialog();
      _deps.showSnackBar('Failed to add: $e', isError: true);
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() => _deps.linkState.isAddingLink = false);
      }
    }
  }
}
