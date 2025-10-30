import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// For debugPrint
import 'package:flutter/material.dart' show debugPrint;

typedef StreamNextProvider = Future<Map<String, String>?> Function();
typedef TorboxNextProvider = StreamNextProvider; // Backward compatibility

/// Bridge helper for launching native Android TV playback using ExoPlayer.
///
/// Supports both Torbox and Real-Debrid providers.
/// When active, native playback requests additional streams via the
/// [StreamNextProvider] callback.
class AndroidTvPlayerBridge {
  static const MethodChannel _channel =
      MethodChannel('com.debrify.app/android_tv_player');

  static StreamNextProvider? _streamNextProvider;
  static VoidCallback? _playbackFinishedCallback;
  static bool _handlerInitialized = false;
  
  // Deprecated: use _streamNextProvider
  static StreamNextProvider? get _torboxNextProvider => _streamNextProvider;
  static set _torboxNextProvider(StreamNextProvider? provider) => _streamNextProvider = provider;
  
  // Deprecated: use _playbackFinishedCallback
  static VoidCallback? get _torboxFinishedCallback => _playbackFinishedCallback;
  static set _torboxFinishedCallback(VoidCallback? callback) => _playbackFinishedCallback = callback;

  static void _ensureInitialized() {
    if (_handlerInitialized) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestTorboxNext':
        case 'requestRealDebridNext':
        case 'requestStreamNext':
          final provider = _streamNextProvider;
          if (provider == null) {
            return null;
          }
          try {
            return await provider();
          } catch (e) {
            throw PlatformException(
              code: 'stream_next_failed',
              message: e.toString(),
            );
          }
        case 'torboxPlaybackFinished':
        case 'realDebridPlaybackFinished':
        case 'streamPlaybackFinished':
          _streamNextProvider = null;
          final finished = _playbackFinishedCallback;
          _playbackFinishedCallback = null;
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
    _streamNextProvider = requestNext;
    _playbackFinishedCallback = onFinished;

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

    _streamNextProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  static Future<bool> launchRealDebridPlayback({
    required String initialUrl,
    required String title,
    required StreamNextProvider requestNext,
    VoidCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showWatermark = false,
    bool hideBackButton = false,
  }) async {
    debugPrint('AndroidTvPlayerBridge: launchRealDebridPlayback() called');
    debugPrint('AndroidTvPlayerBridge: Platform.isAndroid=${Platform.isAndroid}');
    
    if (!Platform.isAndroid) {
      debugPrint('AndroidTvPlayerBridge: Not Android platform, returning false');
      return false;
    }
    if (initialUrl.isEmpty) {
      debugPrint('AndroidTvPlayerBridge: initialUrl is empty, returning false');
      return false;
    }

    debugPrint('AndroidTvPlayerBridge: Initializing method channel handler');
    _ensureInitialized();
    _streamNextProvider = requestNext;
    _playbackFinishedCallback = onFinished;

    try {
      debugPrint('AndroidTvPlayerBridge: Invoking method channel "launchRealDebridPlayback"');
      debugPrint('AndroidTvPlayerBridge: URL=${initialUrl.substring(0, initialUrl.length > 50 ? 50 : initialUrl.length)}...');
      debugPrint('AndroidTvPlayerBridge: title="$title"');
      debugPrint('AndroidTvPlayerBridge: provider=real_debrid');
      
      final bool? launched = await _channel.invokeMethod<bool>(
        'launchRealDebridPlayback',
        {
          'initialUrl': initialUrl,
          'initialTitle': title,
          'provider': 'real_debrid',
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
      
      debugPrint('AndroidTvPlayerBridge: Method channel returned: $launched');
      
      if (launched == true) {
        debugPrint('AndroidTvPlayerBridge: ✅ Launch successful');
        return true;
      } else {
        debugPrint('AndroidTvPlayerBridge: ❌ Launch returned false or null');
      }
    } on PlatformException catch (e) {
      debugPrint('AndroidTvPlayerBridge: ❌ PlatformException: ${e.code} - ${e.message}');
      debugPrint('AndroidTvPlayerBridge: Details: ${e.details}');
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: ❌ Unexpected exception: $e');
    }

    debugPrint('AndroidTvPlayerBridge: Cleaning up providers');
    _streamNextProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  static void clearTorboxProvider() {
    _streamNextProvider = null;
    _playbackFinishedCallback = null;
  }

  static void clearStreamProvider() {
    _streamNextProvider = null;
    _playbackFinishedCallback = null;
  }
}
