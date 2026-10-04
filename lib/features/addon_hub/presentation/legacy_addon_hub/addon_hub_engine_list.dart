import 'package:debrify/features/addon_hub/presentation/addon_hub_action_button.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_row.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

typedef AddonHubEngineListDeps = ({
  AddonHubEngineState engineState,
  // TEMP(addon_hub): emptyState remains on the facade until step 6.
  Widget Function({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  })
  emptyState,
  Future<void> Function() loadEngines,
  AddonHubNavigationState navigationState,
  Future<void> Function(ImportedEngineMetadata) deleteEngine,
  Future<void> Function(RemoteEngineInfo) installEngine,
});

class AddonHubEngineList {
  AddonHubEngineList(this._deps);
  final AddonHubEngineListDeps _deps;

  Widget buildEngineList() {
    if (_deps.engineState.enginesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_deps.engineState.enginesError != null) {
      return _deps.emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load engines',
        subtitle: _deps.engineState.enginesError!,
        action: AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: _deps.loadEngines,
        ),
      );
    }
    if (_deps.engineState.importedEngines.isEmpty &&
        _deps.engineState.availableEngines.isEmpty) {
      return _deps.emptyState(
        icon: Icons.travel_explore_rounded,
        title: 'No engines available',
        subtitle: 'Import an engine YAML, or check back after a refresh.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      children: [
        if (_deps.engineState.importedEngines.isNotEmpty) ...[
          engineSectionHeader(
            'Imported',
            _deps.engineState.importedEngines.length,
          ),
          for (
            var i = 0;
            i < _deps.engineState.importedEngines.length;
            i++
          ) ...[
            AddonHubEngineRow(
              icon: iconForEngine(_deps.engineState.importedEngines[i].icon),
              title: _deps.engineState.importedEngines[i].displayName,
              subtitle:
                  'Imported ${relativeDate(_deps.engineState.importedEngines[i].importedAt)}',
              actionLabel: 'Remove',
              danger: true,
              focusNode: i == 0 ? _deps.navigationState.firstRowFocus : null,
              onTap: () =>
                  _deps.deleteEngine(_deps.engineState.importedEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
        if (_deps.engineState.availableEngines.isNotEmpty) ...[
          engineSectionHeader(
            'Available to install',
            _deps.engineState.availableEngines.length,
          ),
          for (
            var i = 0;
            i < _deps.engineState.availableEngines.length;
            i++
          ) ...[
            AddonHubEngineRow(
              icon: iconForEngine(_deps.engineState.availableEngines[i].icon),
              title: _deps.engineState.availableEngines[i].displayName,
              subtitle: _deps.engineState.availableEngines[i].description,
              actionLabel: 'Install',
              primary: true,
              focusNode: (_deps.engineState.importedEngines.isEmpty && i == 0)
                  ? _deps.navigationState.firstRowFocus
                  : null,
              onTap: () =>
                  _deps.installEngine(_deps.engineState.availableEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ],
    );
  }

  Widget engineSectionHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: kSeeAllAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: kSeeAllAccent2,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData iconForEngine(String? name) {
    switch (name) {
      case 'sailing':
        return Icons.sailing_rounded;
      case 'storage':
      case 'database':
        return Icons.storage_rounded;
      case 'movie':
      case 'movie_creation':
        return Icons.movie_rounded;
      case 'tv':
        return Icons.tv_rounded;
      case 'cloud':
        return Icons.cloud_rounded;
      case 'search':
        return Icons.search_rounded;
      case 'public':
        return Icons.public_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  String relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
