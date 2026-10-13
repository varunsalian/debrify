import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';

abstract interface class VpSubtitleAutoSyncHost {
  bool get mounted;
  void setState(VoidCallback fn);
  mk.Player get player;
  Duration get position;
  bool get isPlaying;
  bool get audioPassthroughEnabled;
  SubtitleSettingsData? get subtitleSettings;
  set subtitleSettings(SubtitleSettingsData? v);
  String? get activeExternalSubtitlePath;
  set activeExternalSubtitlePath(String? v);
  ValueNotifier<AutoSyncPillModel?> get autoSyncPill;
  ValueNotifier<bool> get controlsVisible;
  set showSyncOverlay(bool v);
  void tvReleaseFocusForOverlay();
}

class VpSubtitleAutoSync {
  VpSubtitleAutoSync(this._host);
  final VpSubtitleAutoSyncHost _host;

  bool subtitleAutoSyncEnabled = false;
  MediaKitSubtitleAutoSync? subtitleAutoSync;
  // True from listening until a verdict/terminal hide: the engine is trying.
  bool autoSyncWindowActive = false;
  Timer? autoSyncPillHold; // result auto-hide
  Timer? autoSyncPillPhaseTimer;

  void installSubtitleAutoSyncForPlayer(mk.Player player) {
    if (!subtitleAutoSyncEnabled || !PlatformUtil.supportsSubtitleAutoSync) {
      debugPrint(
        'SubtitleAutoSync: not installing — enabled=$subtitleAutoSyncEnabled '
        'web=$kIsWeb platform=${Platform.operatingSystem}',
      );
      return;
    }
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      debugPrint(
        'SubtitleAutoSync: not installing — player backend is not NativePlayer '
        '(${platform.runtimeType})',
      );
      return;
    }
    debugPrint(
      'SubtitleAutoSync: controller installed '
      '(passthrough=${!kIsWeb && Platform.isAndroid && _host.audioPassthroughEnabled})',
    );
    subtitleAutoSync = MediaKitSubtitleAutoSync(
      player: platform,
      enabled: subtitleAutoSyncEnabled,
      passthroughEnabled:
          !kIsWeb && Platform.isAndroid && _host.audioPassthroughEnabled,
      currentPositionMs: () => _host.position.inMilliseconds,
      isPlaying: () => _host.isPlaying,
      currentOffsetMs: () => _host.subtitleSettings?.syncOffsetMs ?? 0,
      applyOffsetMs: applyAutoSubtitleSyncOffset,
      onNotice: showSubtitleAutoSyncNotice,
    );
  }

  Future<void> disposeSubtitleAutoSync() async {
    final controller = subtitleAutoSync;
    subtitleAutoSync = null;
    hideAutoSyncPill();
    await controller?.dispose();
  }

  Future<void> applyAutoSubtitleSyncOffset(int milliseconds) async {
    final clamped = milliseconds.clamp(
      SubtitleSettingsService.syncOffsetMinMs,
      SubtitleSettingsService.syncOffsetMaxMs,
    );
    if (!_host.mounted) return;
    _host.subtitleSettings = _host.subtitleSettings?.copyWith(
      syncOffsetMs: clamped,
    );
    applySubtitleSyncOffset(clamped);
    _host.setState(() {});
    try {
      await SubtitleSettingsService.instance.setSyncOffsetMs(clamped);
    } catch (error) {
      // The live player already has the safe, bounded offset. A preference
      // write failure must not escape a timer callback or affect playback.
      debugPrint('SubtitleAutoSync: offset persistence failed: $error');
    }
  }

  void showSubtitleAutoSyncNotice(SubtitleAutoSyncNotice notice) {
    if (!_host.mounted) return;
    // Full detail (offsets, advice) lives here; the pill stays number-free.
    debugPrint('SubtitleAutoSync: ${notice.message}');
    switch (notice.kind) {
      case SubtitleAutoSyncNoticeKind.listening:
        // A fresh window: announce for ~5s, then go quiet until an event.
        openAutoSyncPillWindow();
      case SubtitleAutoSyncNoticeKind.checking:
        // An alignment pass is genuinely running — surface it, even if the
        // pill was idle-hidden in the meantime.
        if (autoSyncWindowActive) {
          autoSyncPillPhaseTimer?.cancel();
          _host.autoSyncPill.value = const AutoSyncPillModel(
            AutoSyncPillPhase.checking,
          );
        }
      case SubtitleAutoSyncNoticeKind.stillListening:
        // The pass ended with no verdict: leave the screen quiet again.
        if (autoSyncWindowActive &&
            _host.autoSyncPill.value?.phase == AutoSyncPillPhase.checking) {
          _host.autoSyncPill.value = null;
        }
      case SubtitleAutoSyncNoticeKind.synced ||
          SubtitleAutoSyncNoticeKind.resynced:
        // A verify-pass re-sync corrects silently; only the first sync speaks.
        if (notice.kind == SubtitleAutoSyncNoticeKind.resynced &&
            !autoSyncWindowActive &&
            _host.autoSyncPill.value == null) {
          return;
        }
        showAutoSyncPillResult(AutoSyncPillPhase.synced);
      case SubtitleAutoSyncNoticeKind.failed:
        showAutoSyncPillResult(AutoSyncPillPhase.failed);
    }
  }

  void openAutoSyncPillWindow() {
    autoSyncPillHold?.cancel();
    autoSyncPillHold = null;
    autoSyncWindowActive = true;
    _host.autoSyncPill.value = const AutoSyncPillModel(
      AutoSyncPillPhase.announce,
    );
    autoSyncPillPhaseTimer?.cancel();
    autoSyncPillPhaseTimer = Timer(const Duration(seconds: 5), () {
      // The sentence had its moment; the screen goes quiet until a real
      // event (a checking pass or a verdict) has something to say.
      if (autoSyncWindowActive &&
          _host.autoSyncPill.value?.phase == AutoSyncPillPhase.announce) {
        _host.autoSyncPill.value = null;
      }
    });
  }

  void showAutoSyncPillResult(AutoSyncPillPhase phase) {
    autoSyncWindowActive = false;
    autoSyncPillPhaseTimer?.cancel();
    autoSyncPillPhaseTimer = null;
    autoSyncPillHold?.cancel();
    _host.autoSyncPill.value = AutoSyncPillModel(phase);
    autoSyncPillHold = Timer(
      const Duration(milliseconds: 2400),
      hideAutoSyncPill,
    );
  }

  void hideAutoSyncPill() {
    autoSyncWindowActive = false;
    autoSyncPillPhaseTimer?.cancel();
    autoSyncPillPhaseTimer = null;
    autoSyncPillHold?.cancel();
    autoSyncPillHold = null;
    if (_host.autoSyncPill.value != null) _host.autoSyncPill.value = null;
  }

  void setActiveExternalSubtitlePath(String? path) {
    if (_host.activeExternalSubtitlePath == path) return;
    _host.activeExternalSubtitlePath = path;
    final controller = subtitleAutoSync;
    debugPrint(
      'SubtitleAutoSync: external subtitle ${path == null ? 'cleared' : 'set'} '
      '(controller=${controller == null ? 'MISSING' : 'present'})',
    );
    if (controller == null) return;
    if (path == null) {
      unawaited(controller.deactivateSubtitle());
      hideAutoSyncPill();
    } else {
      unawaited(controller.activateSubtitle(path));
    }
  }

  /// Load subtitle style settings
  Future<void> loadSubtitleSettings() async {
    final settings = await SubtitleSettingsService.instance.loadAll();
    if (_host.mounted) {
      _host.setState(() {
        _host.subtitleSettings = settings;
      });
      if (settings.syncOffsetMs != 0) {
        applySubtitleSyncOffset(settings.syncOffsetMs);
      }
    }
  }

  /// Update subtitle style settings
  void onSubtitleStyleChanged(SubtitleSettingsData settings) {
    // Style saves are awaited before this fires, so it can land after the
    // whole player route is gone (close right after adjusting a style).
    if (!_host.mounted) return;
    final offsetChanged =
        _host.subtitleSettings?.syncOffsetMs != settings.syncOffsetMs;
    _host.setState(() {
      _host.subtitleSettings = settings;
    });
    if (offsetChanged) {
      subtitleAutoSync?.manualOffsetChanged(settings.syncOffsetMs);
      hideAutoSyncPill();
      applySubtitleSyncOffset(settings.syncOffsetMs);
    }
  }

  void applySubtitleSyncOffset(int ms) {
    final platform = _host.player.platform;
    if (platform is mk.NativePlayer) {
      platform.setProperty('sub-delay', (ms / 1000.0).toStringAsFixed(3));
    }
  }

  /// Reset the sync offset to 0. The offset belongs to the specific subtitle it
  /// was dialed in against, so it must reset whenever the subtitle or the
  /// content changes. mpv's `sub-delay` is push-based, so zero it explicitly
  /// rather than relying on a stale in-memory value carrying over.
  void resetSubtitleSyncOffset() {
    SubtitleSettingsService.instance.resetSyncOffset();
    // Keep the UI model in sync (no setState needed: the sync overlay is closed
    // on these transitions and no style rendering depends on the offset).
    _host.subtitleSettings = _host.subtitleSettings?.copyWith(syncOffsetMs: 0);
    applySubtitleSyncOffset(0);
  }

  void showSyncOverlayPanel() {
    _host.tvReleaseFocusForOverlay();
    _host.setState(() {
      _host.showSyncOverlay = true;
      _host.controlsVisible.value = false;
    });
  }

  void hideSyncOverlay() {
    _host.setState(() => _host.showSyncOverlay = false);
  }

  Widget buildSyncOverlay() {
    final externalPath = _host.activeExternalSubtitlePath;
    if (externalPath != null) {
      return SubtitleLinePickerOverlay(
        subtitleFilePath: externalPath,
        getCurrentPositionMs: () => _host.player.state.position.inMilliseconds,
        currentOffsetMs: _host.subtitleSettings?.syncOffsetMs ?? 0,
        onOffsetChanged: (ms) async {
          await SubtitleSettingsService.instance.setSyncOffsetMs(ms);
          subtitleAutoSync?.manualOffsetChanged(ms);
          hideAutoSyncPill();
          applySubtitleSyncOffset(ms);
          if (_host.mounted) {
            _host.setState(() {
              _host.subtitleSettings = _host.subtitleSettings?.copyWith(
                syncOffsetMs: ms,
              );
            });
          }
        },
        onDismiss: hideSyncOverlay,
      );
    }

    return buildSliderSyncOverlay();
  }

  Widget buildSliderSyncOverlay() {
    return SyncStepperOverlay(
      offsetMs: _host.subtitleSettings?.syncOffsetMs ?? 0,
      onOffsetChanged: (ms) async {
        final clamped = ms.clamp(
          SubtitleSettingsService.syncOffsetMinMs,
          SubtitleSettingsService.syncOffsetMaxMs,
        );
        await SubtitleSettingsService.instance.setSyncOffsetMs(clamped);
        subtitleAutoSync?.manualOffsetChanged(clamped);
        hideAutoSyncPill();
        applySubtitleSyncOffset(clamped);
        if (_host.mounted) {
          _host.setState(() {
            _host.subtitleSettings = _host.subtitleSettings?.copyWith(
              syncOffsetMs: clamped,
            );
          });
        }
      },
      onDismiss: hideSyncOverlay,
    );
  }
}
