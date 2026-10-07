import 'dart:async';

import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';

typedef PremiumizeStatusLayoutDeps = ({
  bool Function() isAtRoot,
  BuildContext Function() context,
  PremiumizeFocusState focusState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  PremiumizeCatalogState catalogState,
  Future<void> Function() refresh,
});

class PremiumizeStatusLayout {
  PremiumizeStatusLayout(this._deps);
  final PremiumizeStatusLayoutDeps _deps;

  Widget buildEmpty() {
    final isInFolder = !_deps.isAtRoot();
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
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
                      : 'Add torrents from search or with the + button to see them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildNotEnabled() {
    return CloudScaffold(
      appBar: AppBar(title: const Text('Premiumize')),
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
                  'Premiumize Not Configured',
                  style: Theme.of(_deps.context()).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add your Premiumize API key in Settings to view and manage your cloud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _deps.focusState.settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () => _deps.showSnackBar(
                    'Open Settings > Premiumize to configure',
                    isError: false,
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildError() {
    return CloudScaffold(
      appBar: AppBar(title: const Text('Premiumize')),
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
                  'Failed to Load',
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
                  onPressed: _deps.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
