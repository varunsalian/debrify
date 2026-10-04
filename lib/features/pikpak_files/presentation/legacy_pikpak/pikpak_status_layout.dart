import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_navigation_state.dart';

typedef PikpakStatusLayoutDeps = ({
  BuildContext Function() context,
  PikpakFocusState focusState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  PikpakCatalogState catalogState,
  Future<void> Function() refreshFiles,
  PikpakNavigationState navigationState,
});

class PikpakStatusLayout {
  PikpakStatusLayout(this._deps);
  final PikpakStatusLayoutDeps _deps;

  Widget buildNotEnabled() {
    final app = AppThemeScope.of(_deps.context());
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  'PikPak Not Configured',
                  style: Theme.of(_deps.context()).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Configure your PikPak account in Settings to view and manage files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _deps.focusState.settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () {
                    // TODO: Navigate to settings
                    _deps.showSnackBar(
                      'Open Settings > PikPak to configure',
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildError() {
    final app = AppThemeScope.of(_deps.context());
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Failed to Load Files',
                  style: Theme.of(_deps.context()).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _deps.catalogState.errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _deps.focusState.retryButtonFocusNode,
                  autofocus: true,
                  onPressed: _deps.refreshFiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEmpty() {
    final isInFolder = _deps.navigationState.currentFolderId != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              isInFolder ? 'Folder is Empty' : 'No Files Yet',
              style: Theme.of(_deps.context()).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              isInFolder
                  ? 'This folder doesn\'t contain any files or subfolders.'
                  : 'Add torrents from the search screen to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
