import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'pikpak_navigation_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakFeedbackDeps = ({
  void Function() exitSelectionMode,
  PikpakNavigationState navigationState,
  PikpakViewState viewState,
  void Function(VoidCallback) setState,
  Future<void> Function() loadFiles,
  bool Function() mounted,
  BuildContext Function() context,
});

class PikpakFeedback {
  PikpakFeedback(this._deps);
  final PikpakFeedbackDeps _deps;

  Future<void> refreshFiles() async {
    _deps.exitSelectionMode();

    // Clear cache for current folder when refreshing
    if (_deps.navigationState.currentFolderId != null) {
      _deps.viewState.recursiveFileCache.remove(
        _deps.navigationState.currentFolderId!,
      );
    }

    // Exit virtual folder if in one
    if (_deps.viewState.isInVirtualFolder) {
      _deps.setState(() {
        _deps.viewState.isInVirtualFolder = false;
        _deps.viewState.virtualFolderName = null;
        _deps.viewState.virtualFolderFiles.clear();
      });
    }

    await _deps.loadFiles();
    showSnackBar('Files refreshed', isError: false);
  }

  void showSnackBar(String message, {bool isError = true, Duration? duration}) {
    if (!_deps.mounted()) return;

    final app = AppThemeScope.of(_deps.context());
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF22C55E),
                borderRadius: app.shape.br(8),
              ),
              child: Icon(
                isError ? Icons.error : Icons.check_circle,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        margin: const EdgeInsets.all(16),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }
}
