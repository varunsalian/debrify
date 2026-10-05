import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/channel_creation_dialog.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/overlay_theme.dart';
import 'package:flutter/material.dart';

class DebrifyTvFeedback {
  final DebrifyTvDependencies _deps;
  DebrifyTvFeedback(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  void closeProgressDialog() {
    if (!_owners.progress.progressOpen) {
      return;
    }
    if (_owners.progress.progressSheetContext != null) {
      try {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
      } catch (_) {}
      _owners.progress.progressSheetContext = null;
      _owners.progress.progressOpen = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_owners.progress.progressOpen) {
        return;
      }
      if (_owners.progress.progressSheetContext != null) {
        _sections.feedback.closeProgressDialog();
        return;
      }
      if (_deps.mounted()) {
        try {
          Navigator.of(_deps.context(), rootNavigator: true).pop();
        } catch (_) {}
      }
      _owners.progress.progressSheetContext = null;
      _owners.progress.progressOpen = false;
    });
  }

  void updateProgress(Iterable<String> messages, {bool replace = false}) {
    final sanitized = messages
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) {
      return;
    }

    if (replace || _owners.progress.progress.value.isEmpty) {
      _owners.progress.progress.value = sanitized;
      return;
    }

    final copy = List<String>.from(_owners.progress.progress.value)
      ..addAll(sanitized);
    _owners.progress.progress.value = copy;
  }

  void cancelActiveWatch({
    BuildContext? dialogContext,
    bool clearQueue = true,
  }) {
    debugPrint(
      '[MagicTV] _cancelActiveWatch called, dialogContext=$dialogContext, clearQueue=$clearQueue, _watchCancelled=${_owners.session.watchCancelled}',
    );
    if (_owners.session.watchCancelled) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Already cancelled, just popping dialog',
      );
      if (dialogContext != null) {
        try {
          Navigator.of(dialogContext).pop();
        } catch (e) {
          debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
        }
      }
      return;
    }
    _owners.session.watchCancelled = true;
    _owners.prefetch.prefetchStopRequested = true;
    debugPrint(
      '[MagicTV] _cancelActiveWatch: Set _watchCancelled=true, stopping prefetch',
    );
    unawaited(_sections.legacy.stopPrefetch());
    if (clearQueue) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Clearing queue (had ${_owners.session.queue.length} items)',
      );
      _owners.session.queue.clear();
    }
    _owners.progress.progress.value = [];
    if (dialogContext != null) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Popping dialog via dialogContext',
      );
      try {
        Navigator.of(dialogContext).pop();
      } catch (e) {
        debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
      }
      _owners.progress.progressOpen = false;
      _owners.progress.progressSheetContext = null;
    } else if (_owners.progress.progressOpen) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: No dialogContext, calling _closeProgressDialog',
      );
      _sections.feedback.closeProgressDialog();
    }
    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
    }
    debugPrint('[MagicTV] _cancelActiveWatch: Done');
  }

  void showNativeSettingsFailure(NativePlayerSettingsUnavailable error) {
    unawaited(_sections.legacy.stopPrefetch());
    MainPageBridge.notifyAutoLaunchFailed(error.message.toString());
    if (_deps.mounted())
      _sections.feedback.showSnack(
        error.message.toString(),
        color: Colors.orange,
      );
  }

  void showChannelCreationDialog(String channelName, {int? countdownSeconds}) {
    if (_owners.progress.progressOpen || !_deps.mounted()) {
      return;
    }
    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    Future.microtask(() {
      if (!_deps.mounted() || !_owners.progress.progressOpen) {
        return;
      }
      // showGeneralDialog skips InheritedTheme capture; snapshot this frozen
      // screen's themes so the dialog stays legacy under any app theme.
      final capturedThemes = captureAppThemes(_deps.context());
      showGeneralDialog(
        context: _deps.context(),
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          return capturedThemes.wrap(
            ChannelCreationDialog(
              channelName: channelName,
              countdownSeconds: countdownSeconds,
              onReady: (dialogCtx) {
                _owners.progress.progressSheetContext = dialogCtx;
              },
            ),
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
    });
  }

  void showCachedPlaybackDialog() {
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog called, _progressOpen=${_owners.progress.progressOpen}, mounted=${_deps.mounted()}, _watchCancelled=${_owners.session.watchCancelled}',
    );
    if (_owners.progress.progressOpen || !_deps.mounted()) {
      return;
    }

    // Reset cancellation flag for new playback session.
    // This must happen before the auto-launch check so that playback can proceed
    // even when the dialog is skipped (auto-launch has its own overlay UI).
    _owners.session.watchCancelled = false;
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog: Reset _watchCancelled to false',
    );

    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    Future.microtask(() {
      if (!_deps.mounted() || !_owners.progress.progressOpen) {
        return;
      }
      // Same snapshot rule as the channel-creation dialog above.
      final capturedThemes = captureAppThemes(_deps.context());
      showGeneralDialog(
        context: _deps.context(),
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          // Use pageBuilder context directly - simpler and avoids race conditions
          _owners.progress.progressSheetContext = ctx;
          return capturedThemes.wrap(
            CachedLoadingDialog(
              onCancel: () {
                debugPrint('[MagicTV] onCancel callback triggered');
                _sections.feedback.cancelActiveWatch(dialogContext: ctx);
              },
            ),
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
    });
  }

  void showSnack(String message, {Color color = Colors.blueGrey}) {
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
