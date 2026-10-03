import 'dart:async';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';

typedef IptvRootLayoutDeps = ({
  StateSetter setState,
  IptvSettingsState settingsState,
  Widget Function(Widget child) withBrowseSearch,
  Widget Function(
    BoxConstraints constraints, {
    required bool spotlightRequested,
    required IptvSpotlightLayoutMode spotlightMode,
  })
  buildLoadedLayout,
  Future<void> Function({bool forceReload}) loadSettings,
  bool Function() spotlightRequestedForDevice,
});

/// Builds the existing loading/error surface and dispatches responsive layouts.
class IptvRootLayout {
  final IptvRootLayoutDeps _deps;

  final IptvSettingsState _settingsState;

  IptvRootLayout(this._deps) : _settingsState = _deps.settingsState;

  bool get _spotlightRequestedForDevice => _deps.spotlightRequestedForDevice();

  Widget build(BuildContext context) {
    if (!_settingsState.settingsLoaded) {
      final settingsError = _settingsState.settingsError;
      if (settingsError == null) {
        return _deps.withBrowseSearch(
          const Center(child: CircularProgressIndicator()),
        );
      }
      return _deps.withBrowseSearch(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not open IPTV',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  settingsError,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () {
                    _deps.setState(() => _settingsState.settingsError = null);
                    unawaited(_deps.loadSettings(forceReload: true));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Spotlight owns the full canvas because its search lives inside the
    // source rail. Legacy layouts mount search above their body, so their
    // breakpoints must be evaluated by the inner LayoutBuilder after that
    // header has taken its height.
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final outerSize = Size(
          outerConstraints.maxWidth,
          outerConstraints.maxHeight,
        );
        final spotlightRequested = _spotlightRequestedForDevice;
        final spotlightMode = spotlightRequested
            ? resolveIptvSpotlightLayout(outerSize)
            : IptvSpotlightLayoutMode.classic;
        if (spotlightMode != IptvSpotlightLayoutMode.classic) {
          return _deps.buildLoadedLayout(
            outerConstraints,
            spotlightRequested: spotlightRequested,
            spotlightMode: spotlightMode,
          );
        }
        return _deps.withBrowseSearch(
          LayoutBuilder(
            builder: (context, bodyConstraints) => _deps.buildLoadedLayout(
              bodyConstraints,
              spotlightRequested: spotlightRequested,
              spotlightMode: IptvSpotlightLayoutMode.classic,
            ),
          ),
        );
      },
    );
  }
}
