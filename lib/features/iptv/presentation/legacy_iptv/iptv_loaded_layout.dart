import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_layout_policy.dart';
import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

typedef IptvLoadedLayoutDeps = ({
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,
  Widget Function() buildClassic,
  Widget Function(BoxConstraints constraints, IptvSpotlightLayoutMode mode)
  buildSpotlight,
  Widget Function(BoxConstraints c, {required bool touchSelector})
  buildTvTwoPane,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() mounted,
  Widget? Function() searchHeader,
  StateSetter setState,
});

class IptvLoadedLayout {
  final IptvLoadedLayoutDeps _deps;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;
  final IptvStatusState _statusState;

  IptvLoadedLayout(this._deps)
    : _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState,
      _statusState = _deps.statusState;

  /// Mount the parent-owned Browse search field in the shipped position. The
  /// Spotlight shell takes the same widget as a rail slot instead, so each
  /// build mounts exactly one instance while BrowseScreen retains its query,
  /// controller, IME and TV focus-handoff state.
  Widget withBrowseSearch(Widget child) {
    final search = _deps.searchHeader();
    if (search == null) return child;
    return Column(
      children: [
        search,
        Expanded(child: child),
      ],
    );
  }

  Widget buildLoadedLayout(
    BoxConstraints constraints, {
    required bool spotlightRequested,
    required IptvSpotlightLayoutMode spotlightMode,
  }) {
    final availableSize = Size(constraints.maxWidth, constraints.maxHeight);
    final touchTablet = IptvLayoutPolicy.shouldUseTouchTabletTwoPane(
      isTelevision: _deps.isTelevision(),
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      availableSize: availableSize,
    );
    final twoPaneEligible =
        _deps.isTelevision() || IptvSettingsState.isDesktop || touchTablet;
    final spotlightActive = spotlightMode != IptvSpotlightLayoutMode.classic;
    // Spotlight deliberately falls back to the useful single-pane page below
    // its minimum height. Do not route that saved preference into the old
    // two-pane cockpit with Spotlight colours.
    final spotlightFallback = spotlightRequested && !spotlightActive;
    final regularTwoPane =
        !spotlightFallback &&
        twoPaneEligible &&
        constraints.maxWidth >= 760 &&
        constraints.maxHeight >= 380;
    final twoPane = spotlightActive || regularTwoPane;
    final touchTwoPane = regularTwoPane && touchTablet && !spotlightActive;

    if (twoPane != _selectionState.tvTwoPaneActive ||
        touchTwoPane != _selectionState.touchTabletTwoPaneActive ||
        spotlightMode != _selectionState.spotlightLayoutMode) {
      // Never write state synchronously from the layout phase: playback and
      // schedule callbacks consult these flags. One post-frame of lag can only
      // occur while the window is actively changing size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        final wasTouchTablet = _selectionState.touchTabletTwoPaneActive;
        _selectionState.tvTwoPaneActive = twoPane;
        _selectionState.touchTabletTwoPaneActive = touchTwoPane;
        _selectionState.spotlightLayoutMode = spotlightMode;
        if (!twoPane &&
            wasTouchTablet &&
            _selectionState.scheduleChannel != null &&
            _deps.mounted()) {
          _deps.setState(() => _selectionState.scheduleChannel = null);
        }
      });
    }

    final Widget body = spotlightActive
        ? _deps.buildSpotlight(constraints, spotlightMode)
        : !regularTwoPane
        ? _deps.buildClassic()
        : _deps.buildTvTwoPane(constraints, touchSelector: touchTablet);

    // The background-refresh chip floats over whichever layout is active.
    // Stack stays paint-neutral for the native preview underlay.
    final Widget page = _settingsState.showIosRecordingNotice
        ? Column(
            children: [
              buildIosRecordingNotice(),
              Expanded(child: body),
            ],
          )
        : body;
    return Stack(
      fit: StackFit.passthrough,
      children: [page, buildCatalogChip()],
    );
  }

  /// The iOS-only "no recording here" banner: dismiss is remembered forever.
  Widget buildIosRecordingNotice() {
    final app = AppThemeScope.of(_deps.context());
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
      decoration: BoxDecoration(
        color: app.iptv.surfaceTint,
        borderRadius: app.shape.br(10),
        border: Border.all(color: app.iptv.hairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fiber_manual_record_rounded,
            size: 14,
            color: app.core.tx.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Recording isn't available on iOS — Apple doesn't let "
              'apps capture streams in the background.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: app.iptv.inkDim,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.core.tx.withValues(alpha: 0.45),
            ),
            onPressed: dismissIosRecordingNotice,
          ),
        ],
      ),
    );
  }

  void dismissIosRecordingNotice() {
    _deps.setState(() => _settingsState.showIosRecordingNotice = false);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) =>
            prefs.setBool(IptvSettingsState.iosNoticeDismissedPref, true),
      ),
    );
  }

  /// Bottom-right status chip for background catalog refreshes. Pure
  /// display: no focusables, no hit-testing — DPAD and touch pass straight
  /// through. Snap show/hide, no tween (TV GPU rule).
  Widget buildCatalogChip() {
    final app = AppThemeScope.of(_deps.context());
    if (_statusState.chipState == CatalogChipState.hidden) {
      return const SizedBox.shrink();
    }
    final Widget leading = switch (_statusState.chipState) {
      CatalogChipState.updating => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: app.seeAll.accent2,
        ),
      ),
      CatalogChipState.success => const Icon(
        Icons.check_circle_rounded,
        size: 15,
        color: Color(0xFF4ADE80),
      ),
      CatalogChipState.failure => const Icon(
        Icons.cloud_off_rounded,
        size: 15,
        color: Color(0xFFFBBF24),
      ),
      CatalogChipState.hidden => const SizedBox.shrink(),
    };
    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: app.iptv.chipSurface,
            borderRadius: app.shape.br(22),
            border: Border.all(color: app.core.tx.withValues(alpha: 0.10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 8),
              Text(
                _statusState.chipMessage,
                style: TextStyle(
                  fontSize: 12.5,
                  color: app.core.tx.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
