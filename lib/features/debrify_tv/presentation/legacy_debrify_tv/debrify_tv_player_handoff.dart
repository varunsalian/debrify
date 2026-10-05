import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/dialogs/external_player_notice_dialog.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvPlayerHandoff {
  final DebrifyTvDependencies _deps;
  DebrifyTvPlayerHandoff(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<bool> launchTorboxOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_owners.settings.isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }
    // Torbox native player already receives a prepared stream URL, so skip sending magnet
    // bundles—the binder payload stays small and launch succeeds.
    const List<Map<String, dynamic>> magnets = [];

    final title = (firstStream['title'] ?? '').trim();

    try {
      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: magnets,
        requestNext: requestNext,
        requestChannelSwitch: _owners.library.channels.length > 1
            ? _sections.channelWatch.requestNextChannel
            : null,
        requestChannelById: _owners.library.channels.length > 1
            ? _sections.channelWatch.requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!_deps.mounted()) {
            return;
          }
          _deps.setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed: $e');
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  Future<bool> launchRealDebridOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    debugPrint('DebrifyTV: _launchRealDebridOnAndroidTv() called');
    debugPrint('DebrifyTV: _isAndroidTv=${_owners.settings.isAndroidTv}');

    if (!_owners.settings.isAndroidTv) {
      debugPrint('DebrifyTV: Not Android TV, skipping native launch');
      return false;
    }

    final initialUrl = firstStream['url'] ?? '';
    debugPrint(
      'DebrifyTV: initialUrl=${initialUrl.substring(0, initialUrl.length > 50 ? 50 : initialUrl.length)}...',
    );

    if (initialUrl.isEmpty) {
      debugPrint('DebrifyTV: Initial URL is empty, cannot launch');
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();
    debugPrint('DebrifyTV: title="$title"');
    debugPrint(
      'DebrifyTV: Calling AndroidTvPlayerBridge.launchRealDebridPlayback()...',
    );

    try {
      final bool canSwitchChannels =
          _owners.library.currentWatchingChannelId != null &&
          _owners.library.channels.length > 1 &&
          (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
              _owners.settings.provider ==
                  DebrifyTvConstants.providerAllDebrid);

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchRealDebridPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        channelName: channelName,
        requestNext: requestNext,
        requestChannelSwitch: canSwitchChannels
            ? _sections.channelWatch.requestNextChannel
            : null,
        requestChannelById: canSwitchChannels
            ? _sections.channelWatch.requestChannelById
            : null,
        onFinished: () async {
          debugPrint('DebrifyTV: Android TV playback finished callback');

          // Stop prefetcher when exiting player
          await _sections.prefetch.stopPrefetch();
          debugPrint('DebrifyTV: Stopped prefetcher on player exit');

          AndroidTvPlayerBridge.clearStreamProvider();
          _owners.library.currentWatchingChannelId =
              null; // Clear channel tracking
          if (!_deps.mounted()) return;
          _deps.setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );

      debugPrint(
        'DebrifyTV: AndroidTvPlayerBridge.launchRealDebridPlayback() returned: $launched',
      );

      if (launched) {
        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.status = 'Playing via Android TV';
          });
        }
        debugPrint(
          'DebrifyTV: ✅ Successfully launched Real-Debrid on Android TV',
        );
        return true;
      } else {
        debugPrint(
          'DebrifyTV: ❌ AndroidTvPlayerBridge returned false - launch failed',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DebrifyTV: ❌ Exception during Android TV launch: $e');
      debugPrint('DebrifyTV: Stack trace: $stackTrace');
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearStreamProvider();
    debugPrint('DebrifyTV: Falling back to Flutter player');
    return false;
  }

  Future<bool> launchPikPakOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_owners.settings.isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();

    try {
      MainPageBridge.notifyPlayerLaunching();

      // Reuse Torbox bridge method - it works for any stream URL
      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: const [],
        requestNext: requestNext,
        requestChannelSwitch: _owners.library.channels.length > 1
            ? _sections.channelWatch.requestNextChannel
            : null,
        requestChannelById: _owners.library.channels.length > 1
            ? _sections.channelWatch.requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!_deps.mounted()) {
            return;
          }
          _deps.setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed for PikPak: $e');
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }
  // ===================== External player hand-off =====================

  /// Hands one resolved stream to the user's external player when that is
  /// their default, after warning them what external playback costs here.
  ///
  /// Returns true when the caller must abandon its own launch — either the
  /// stream is now playing in another app, or the user backed out of the
  /// warning. False means "carry on unchanged": the in-app player is the
  /// default, or the external launch failed and the built-in player is the
  /// fallback (same policy as [VideoPlayerLauncher.push]).
  ///
  /// Channel rotation dies with the hand-off — nothing outside Debrify can
  /// call back into `requestMagicNext` — so on any outcome that ends the flow
  /// this also stops the prefetcher that exists purely to feed it. A failed
  /// launch leaves the prefetcher running, because the in-app player that
  /// picks the flow back up still wants it.
  Future<bool> handOffToExternalPlayer(String url, String title) async {
    if (url.isEmpty || !_deps.mounted()) return false;
    if (!await VideoPlayerLauncher.isExternalPlayerDefault()) return false;
    if (!_deps.mounted()) return false;

    _sections.feedback.closeProgressDialog();
    // The home-screen auto-launch overlay draws above routes, so drop it
    // before the notice or the notice appears underneath it. Only the overlay
    // — firing notifyPlayerLaunching here would stop other screens' trailers
    // for a launch the user may still decline.
    MainPageBridge.hideAutoLaunchOverlay?.call();
    if (!_deps.mounted()) return false;

    // Backing out must not silently fall through to the in-app player — that
    // is the very thing the user chose against — so a decline reports
    // "handled" too and every caller stops. Deliberately without touching
    // _watchCancelled: that flag is only reset by the quick-play and cached-
    // dialog entry points, so setting it here would leave channel plays
    // stuck-cancelled on the next attempt.
    if (!await ExternalPlayerNoticeDialog.confirm(_deps.context())) {
      await _sections.prefetch.stopPrefetch();
      return true;
    }
    if (!_deps.mounted()) return true;

    final launched = await VideoPlayerLauncher.launchExternalIfConfigured(
      _deps.context(),
      videoUrl: url,
      title: title.trim().isEmpty ? 'Debrify TV' : title.trim(),
    );
    if (launched) {
      _owners.session.launchedPlayer = true;
      await _sections.prefetch.stopPrefetch();
      return true;
    }
    return false;
  }
}
