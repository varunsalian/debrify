import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:flutter/widgets.dart';

abstract interface class VpDockLayoutHost {
  ValueNotifier<double> get dockExtent;
  int get dockGeometryGeneration;
  set dockGeometryGeneration(int v);
  set dockPalette(PlayerDockPalette v);
  PlayerDockSize get dockSize;
  set dockSize(PlayerDockSize v);
  PlayerDockStyle get dockStyle;
  set dockStyle(PlayerDockStyle v);
  int get infoPanelGeneration;
  set infoPanelGeneration(int v);
  set infoPanelHeight(double v);
  set lastInfoPanelSignature(String v);
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  bool get hideOptions;
  bool get hideSeekbar;
}

class VpDockLayout {
  VpDockLayout(this._host);
  final VpDockLayoutHost _host;

  /// Everything that can change the dock's height without the dock itself
  /// changing: the viewport, the safe-area insets, the text scaler, the
  /// chosen style and size, and the two flags that add or remove whole rows.
  String dockGeometrySignature(MediaQueryData media) => [
    media.size.width.round(),
    media.size.height.round(),
    media.padding.top.round(),
    media.padding.bottom.round(),
    media.textScaler.scale(100).round(),
    _host.dockStyle.name,
    _host.dockSize.name,
    _host.hideOptions,
    _host.hideSeekbar,
  ].join('|');

  String lastDockGeometrySignature = '';

  /// Drops the cached dock geometry whenever anything that can change the
  /// dock's height changes.
  void refreshDockGeometry() {
    // Rotation, window resize, split-screen, a safe-area change or a font-size
    // change all land here. Any of them can make the cached extent wrong, and
    // a stale extent means a tap near the bottom is judged against the wrong
    // band — so drop back to the legacy constants until a fresh measurement
    // arrives, rather than trusting the old number for a frame.
    final signature = dockGeometrySignature(MediaQuery.of(_host.context));
    if (signature == lastDockGeometrySignature) return;
    lastDockGeometrySignature = signature;
    _host.dockGeometryGeneration++;
    _host.dockExtent.value = 0;
    _host.infoPanelGeneration++;
    _host.infoPanelHeight = DockLayoutInput.kInfoPanelBound;
    _host.lastInfoPanelSignature = '';
  }

  Future<void> loadDockPrefs() async {
    final style = await PlayerAppearanceStorage.getPlayerDockStyle();
    final palette = await PlayerAppearanceStorage.getPlayerDockPalette();
    final size = await PlayerAppearanceStorage.getPlayerDockSize();
    if (!_host.mounted) return;
    _host.setState(() {
      _host.dockStyle = PlayerDockStyle.fromPref(style);
      _host.dockPalette = PlayerDockPalette.fromPref(palette);
      _host.dockSize = PlayerDockSize.fromPref(size);
      // Style/size are part of the geometry signature but arrive here, not
      // through an inherited dependency.
      lastDockGeometrySignature = '';
      // Deliberately NOT seeded to the viewport height. Over-protecting the
      // whole screen kills every gesture until the first measurement, and it
      // also strands the fallback case: when DockMetrics.compute returns null
      // the classic subtree renders and no reporter is ever mounted, so the
      // seed would never be corrected. 0 means `_dockBand` yields the legacy
      // constant, which is exactly right for both.
    });
  }
}
