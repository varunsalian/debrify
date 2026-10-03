import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_input_policy.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_add_input_state.dart';
import 'debrid_catalog_state.dart';

typedef DebridMagnetActionsDeps = ({
  BuildContext Function() context,
  DebridAddInputState addInputState,
  void Function(String message) showError,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  DebridCatalogState catalogState,
  Future<void> Function(String apiKey, {bool reset}) fetchTorrents,
});

class DebridMagnetActions {
  DebridMagnetActions(this._deps);
  final DebridMagnetActionsDeps _deps;
  bool get mounted => _deps.mounted();
  void Function(String message) get showError => _deps.showError;

  void showAddMagnetDialog() {
    // Auto-paste if clipboard has magnet link
    autoPasteMagnetLink();

    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Add Magnet Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _deps.addInputState.magnetController,
                decoration: const InputDecoration(
                  hintText: 'Paste magnet link here...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
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
                  child: OutlinedButton(
                    onPressed: showAdvancedMagnetDialog,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                    child: const Text('Advanced'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _deps.addInputState.isAddingMagnet
                        ? null
                        : addMagnetWithDefaultSelection,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    child: _deps.addInputState.isAddingMagnet
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
        ),
      ),
    );
  }

  Future<void> autoPasteMagnetLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      if (text.startsWith('magnet:?')) {
        _deps.addInputState.magnetController.text = text;
      }
    }
  }

  Future<void> addMagnetWithDefaultSelection() async {
    final magnetLink = _deps.addInputState.magnetController.text.trim();
    if (magnetLink.isEmpty) {
      showError('Please enter a magnet link');
      return;
    }

    if (!isValidMagnetLink(magnetLink)) {
      showError('Please enter a valid magnet link');
      return;
    }

    Navigator.of(_deps.context()).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Adding Torrent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing magnet link...'),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      _deps.setState(() {
        _deps.addInputState.isAddingMagnet = true;
      });
    }

    try {
      // Get the default file selection preference
      final fileSelection = await RealDebridStorage.getFileSelection();

      // Add the magnet using the same logic as the torrent search screen
      await DebridService.addTorrentToDebrid(
        _deps.catalogState.apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(_deps.context()).pop();
      }

      // Clear the input
      _deps.addInputState.magnetController.clear();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text('Magnet added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the torrent list
      await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
    } on TorrentNotCachedException catch (e) {
      await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      if (mounted) Navigator.of(_deps.context()).pop();
      if (mounted) showError('File is not readily available in Real Debrid');
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(_deps.context()).pop();
      }

      if (mounted) {
        showError(getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        _deps.setState(() {
          _deps.addInputState.isAddingMagnet = false;
        });
      }
    }
  }

  Future<void> showAdvancedMagnetDialog() async {
    final magnetLink = _deps.addInputState.magnetController.text.trim();
    if (magnetLink.isEmpty) {
      showError('Please enter a magnet link first');
      return;
    }

    if (!isValidMagnetLink(magnetLink)) {
      showError('Please enter a valid magnet link');
      return;
    }

    Navigator.of(_deps.context()).pop(); // Close the first dialog

    // Show file selection dialog similar to torrent search screen
    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Select File Type'),
        content: const Text('Choose how to handle files in this torrent:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _deps.addInputState.isAddingMagnet
                ? null
                : () => addMagnetWithSelection(magnetLink, 'smart'),
            child: _deps.addInputState.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Smart (recommended)'),
          ),
          TextButton(
            onPressed: _deps.addInputState.isAddingMagnet
                ? null
                : () => addMagnetWithSelection(magnetLink, 'largest'),
            child: _deps.addInputState.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Largest File'),
          ),
          TextButton(
            onPressed: _deps.addInputState.isAddingMagnet
                ? null
                : () => addMagnetWithSelection(magnetLink, 'video'),
            child: _deps.addInputState.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Video Files'),
          ),
          TextButton(
            onPressed: _deps.addInputState.isAddingMagnet
                ? null
                : () => addMagnetWithSelection(magnetLink, 'all'),
            child: _deps.addInputState.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('All Files'),
          ),
        ],
      ),
    );
  }

  Future<void> addMagnetWithSelection(
    String magnetLink,
    String fileSelection,
  ) async {
    Navigator.of(_deps.context()).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Adding Torrent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing magnet link...'),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );

    _deps.setState(() {
      _deps.addInputState.isAddingMagnet = true;
    });

    try {
      // Add the magnet with the selected file preference
      await DebridService.addTorrentToDebrid(
        _deps.catalogState.apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(_deps.context()).pop();
      }

      // Clear the input
      _deps.addInputState.magnetController.clear();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text('Magnet added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the torrent list
      await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
    } on TorrentNotCachedException catch (e) {
      await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      if (mounted) Navigator.of(_deps.context()).pop();
      if (mounted) showError('File is not readily available in Real Debrid');
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(_deps.context()).pop();
      }

      if (mounted) {
        showError(getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        _deps.setState(() {
          _deps.addInputState.isAddingMagnet = false;
        });
      }
    }
  }
}
