import 'package:flutter/material.dart';

import '../../../models/torrent_filter_state.dart';
import '../../../theme/app_theme_scope.dart';
import '../models/source_provider_option.dart';
import 'source_active_filters.dart';
import 'source_provider_strip.dart';

/// Provider status and filter presentation; controls/actions remain view-owned.
Widget buildSourceToolbar(
  BuildContext context, {
  required ColorScheme scheme,
  required bool showProviders,
  required bool providersVisible,
  required List<SourceProviderOption> options,
  required bool showAll,
  required String? selectedKey,
  required ValueChanged<String?> onSelectProvider,
  required ValueChanged<String> onRetryProvider,
  required ValueGetter<List<String>> messages,
  required Widget controls,
  required TorrentFilterState filters,
  required VoidCallback onClearFilters,
}) {
  final app = AppThemeScope.of(context);
  final accent = app.home.chromeAccent;
  final dim = app.fade(app.core.tx, 0.55);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showProviders && providersVisible)
        SourceProviderStrip(
          options: options,
          showAll: showAll,
          selectedKey: selectedKey,
          onSelect: onSelectProvider,
          onRetry: onRetryProvider,
        ),
      if (showProviders)
        for (final message in messages())
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Text(
              message,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
      controls,
      if (!filters.isEmpty)
        SourceActiveFilters(
          filters: filters,
          accent: accent,
          dim: dim,
          onClear: onClearFilters,
        ),
    ],
  );
}
