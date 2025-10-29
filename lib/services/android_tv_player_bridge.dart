import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef TorboxNextProvider = Future<Map<String, String>?> Function();

/// Bridge helper for launching native Android TV playback using ExoPlayer.
///
/// When active, native playback requests additional Torbox streams via the
/// [TorboxNextProvider] callback.
class AndroidTvPlayerBridge {
  static const MethodChannel _channel =
      MethodChannel('com.debrify.app/android_tv_player');

  static TorboxNextProvider? _torboxNextProvider;
  static VoidCallback? _torboxFinishedCallback;
  static bool _handlerInitialized = false;

  static void _ensureInitialized() {
    if (_handlerInitialized) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestTorboxNext':
          final provider = _torboxNextProvider;
          if (provider == null) {
            return null;
          }
          try {
            return await provider();
          } catch (e) {
            throw PlatformException(
              code: 'torbox_next_failed',
              message: e.toString(),
            );
          }
        case 'torboxPlaybackFinished':
          _torboxNextProvider = null;
          final finished = _torboxFinishedCallback;
          _torboxFinishedCallback = null;
          finished?.call();
          return null;
        default:
          throw PlatformException(
            code: 'unimplemented',
            message: 'Method ${call.method} not handled on Flutter side.',
          );
      }
    });
    _handlerInitialized = true;
  }

  static Future<bool> launchTorboxPlayback({
    required String initialUrl,
    required String title,
    required List<Map<String, dynamic>> magnets,
    required TorboxNextProvider requestNext,
    VoidCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showWatermark = false,
    bool hideBackButton = false,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (initialUrl.isEmpty || magnets.isEmpty) {
      return false;
    }

    _ensureInitialized();
    _torboxNextProvider = requestNext;
    _torboxFinishedCallback = onFinished;

    try {
      final bool? launched = await _channel.invokeMethod<bool>(
        'launchTorboxPlayback',
        {
          'initialUrl': initialUrl,
          'initialTitle': title,
          'magnets': magnets,
          'config': {
            'startFromRandom': startFromRandom,
            'randomStartMaxPercent': randomStartMaxPercent,
            'hideSeekbar': hideSeekbar,
            'hideOptions': hideOptions,
            'showVideoTitle': showVideoTitle,
            'showWatermark': showWatermark,
            'hideBackButton': hideBackButton,
          },
        },
      );
      if (launched == true) {
        return true;
      }
    } on PlatformException {
      // Fall through to cleanup and return false.
    }

    _torboxNextProvider = null;
    _torboxFinishedCallback = null;
    return false;
  }

  static void clearTorboxProvider() {
    _torboxNextProvider = null;
    _torboxFinishedCallback = null;
  }
}
