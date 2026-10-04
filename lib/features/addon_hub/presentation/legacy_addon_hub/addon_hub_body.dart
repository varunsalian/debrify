import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:flutter/material.dart';

typedef AddonHubBodyDeps = ({
  AddonHubNavigationState navigationState,
  Widget Function() buildEngineList,
  Widget Function() buildInstalledList,
  Widget Function() buildMarketList,
});

class AddonHubBody {
  AddonHubBody(this._deps);
  final AddonHubBodyDeps _deps;

  Widget buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Text(
        'Addons',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget buildBody() {
    if (_deps.navigationState.kind == AddonHubKind.engines) {
      return _deps.buildEngineList();
    }
    switch (_deps.navigationState.source) {
      case AddonHubSource.installed:
        return _deps.buildInstalledList();
      case AddonHubSource.official:
      case AddonHubSource.community:
        return _deps.buildMarketList();
    }
  }

  Widget emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }
}
