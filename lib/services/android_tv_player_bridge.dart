import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

// For debugPrint
import 'package:flutter/material.dart' show debugPrint;

typedef StreamNextProvider = Future<Map<String, String>?> Function();
typedef TorboxNextProvider = StreamNextProvider; // Backward compatibility
typedef ChannelSwitchProvider = Future<Map<String, dynamic>?> Function();
typedef ChannelByIdSwitchProvider = Future<Map<String, dynamic>?> Function(
    String channelId);
typedef PlaybackFinishedCallback = Future<void> Function();
typedef AndroidTvProgressCallback = Future<void> Function(
    Map<String, dynamic> progress);
typedef TorrentStreamProvider = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> request);

/// Bridge helper for launching native Android TV playback using ExoPlayer.
///
/// Supports both Torbox and Real-Debrid providers.
/// When active, native playback requests additional streams via the
/// [StreamNextProvider] callback.
class AndroidTvPlayerBridge {
  static const MethodChannel _channel =
      MethodChannel('com.debrify.app/android_tv_player');

  static StreamNextProvider? _streamNextProvider;
  static ChannelSwitchProvider? _channelSwitchProvider;
  static ChannelByIdSwitchProvider? _channelByIdSwitchProvider;
  static PlaybackFinishedCallback? _playbackFinishedCallback;
  static bool _handlerInitialized = false;
  static AndroidTvProgressCallback? _torrentProgressCallback;
  static PlaybackFinishedCallback? _torrentFinishedCallback;
  static TorrentStreamProvider? _torrentStreamProvider;
  
  // Deprecated: use _streamNextProvider
  static StreamNextProvider? get _torboxNextProvider => _streamNextProvider;
  static set _torboxNextProvider(StreamNextProvider? provider) => _streamNextProvider = provider;
  
  // Deprecated: use _playbackFinishedCallback
  static PlaybackFinishedCallback? get _torboxFinishedCallback => _playbackFinishedCallback;
  static set _torboxFinishedCallback(PlaybackFinishedCallback? callback) => _playbackFinishedCallback = callback;

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
        case 'requestNextChannel':
          final channelProvider = _channelSwitchProvider;
          if (channelProvider == null) {
            return null;
          }
          try {
            return await channelProvider();
          } catch (e) {
            throw PlatformException(
              code: 'channel_switch_failed',
              message: e.toString(),
            );
          }
        case 'requestChannelById':
          final args = call.arguments;
          String? channelId;
          if (args is Map) {
            final raw = args['channelId'];
            if (raw is String) {
              channelId = raw.trim();
            }
          } else if (args is String) {
            channelId = args.trim();
          }
          final selectProvider = _channelByIdSwitchProvider;
          if (channelId == null || channelId.isEmpty || selectProvider == null) {
            return null;
          }
          try {
            return await selectProvider(channelId);
          } catch (e) {
            throw PlatformException(
              code: 'channel_select_failed',
              message: e.toString(),
            );
          }
        case 'torboxPlaybackFinished':
        case 'realDebridPlaybackFinished':
        case 'streamPlaybackFinished':
          final finished = _playbackFinishedCallback;
          _streamNextProvider = null;
          _channelSwitchProvider = null;
          _channelByIdSwitchProvider = null;
          _playbackFinishedCallback = null;
          if (finished != null) {
            try {
              await finished();
            } catch (e, stack) {
              debugPrint('AndroidTvPlayerBridge: onFinished callback threw: $e\n$stack');
            }
          }
          return null;
        case 'torrentPlaybackProgress':
          final handler = _torrentProgressCallback;
          if (handler == null) {
            return null;
          }
          final args = call.arguments;
          if (args is Map) {
            try {
              await handler(Map<String, dynamic>.from(args));
            } catch (e, stack) {
              debugPrint('AndroidTvPlayerBridge: progress callback error $e\n$stack');
            }
          }
          return null;
        case 'torrentPlaybackFinished':
          final finishedTorrent = _torrentFinishedCallback;
          _torrentProgressCallback = null;
          _torrentFinishedCallback = null;
          _torrentStreamProvider = null;
          if (finishedTorrent != null) {
            try {
              await finishedTorrent();
            } catch (e, stack) {
              debugPrint('AndroidTvPlayerBridge: torrent finished callback threw: $e\n$stack');
            }
          }
          return null;
        case 'requestTorrentStream':
          debugPrint('AndroidTvPlayerBridge: requestTorrentStream received - args: ${call.arguments}');
          final resolver = _torrentStreamProvider;
          if (resolver == null) {
            debugPrint('AndroidTvPlayerBridge: ERROR - no torrent stream provider registered!');
            return null;
          }
          final args = call.arguments;
          if (args is Map) {
            try {
              final result = await resolver(Map<String, dynamic>.from(args));
              debugPrint('AndroidTvPlayerBridge: stream provider returned: ${result != null ? "success (url length: ${result['url']?.toString().length ?? 0})" : "null"}');
              return result;
            } catch (e, stack) {
              debugPrint('AndroidTvPlayerBridge: stream provider error $e\n$stack');
              throw PlatformException(
                code: 'torrent_stream_failed',
                message: e.toString(),
              );
            }
          }
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
    ChannelSwitchProvider? requestChannelSwitch,
    ChannelByIdSwitchProvider? requestChannelById,
    PlaybackFinishedCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showChannelName = false,
    String? channelName,
    List<Map<String, dynamic>>? channels,
    String? currentChannelId,
    int? currentChannelNumber,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (initialUrl.isEmpty) {
      return false;
    }

    _ensureInitialized();
    _streamNextProvider = requestNext;
    _channelSwitchProvider = requestChannelSwitch;
    _channelByIdSwitchProvider = requestChannelById;
    _playbackFinishedCallback = onFinished;

    try {
      final List<Map<String, dynamic>>? channelDirectory = channels
          ?.map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);

      final bool? launched = await _channel.invokeMethod<bool>(
        'launchTorboxPlayback',
        {
          'initialUrl': initialUrl,
          'initialTitle': title,
          'magnets': magnets,
          'channelName': channelName,
          'currentChannelId': currentChannelId,
          'currentChannelNumber': currentChannelNumber,
          'channels': channelDirectory,
          'config': {
            'startFromRandom': startFromRandom,
            'randomStartMaxPercent': randomStartMaxPercent,
            'hideSeekbar': hideSeekbar,
            'hideOptions': hideOptions,
            'showVideoTitle': showVideoTitle,
            'showChannelName': showChannelName,
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
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  static Future<bool> launchRealDebridPlayback({
    required String initialUrl,
    required String title,
    String? channelName,
    required StreamNextProvider requestNext,
    ChannelSwitchProvider? requestChannelSwitch,
    ChannelByIdSwitchProvider? requestChannelById,
    PlaybackFinishedCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showChannelName = false,
    List<Map<String, dynamic>>? channels,
    String? currentChannelId,
    int? currentChannelNumber,
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
    _channelSwitchProvider = requestChannelSwitch;
    _channelByIdSwitchProvider = requestChannelById;
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
          'channelName': channelName,
          'currentChannelId': currentChannelId,
          'currentChannelNumber': currentChannelNumber,
          'channels': channels
              ?.map((entry) => Map<String, dynamic>.from(entry))
              .toList(growable: false),
          'config': {
            'startFromRandom': startFromRandom,
            'randomStartMaxPercent': randomStartMaxPercent,
            'hideSeekbar': hideSeekbar,
            'hideOptions': hideOptions,
            'showVideoTitle': showVideoTitle,
            'showChannelName': showChannelName,
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
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  static void clearTorboxProvider() {
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
  }

  static void clearStreamProvider() {
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
  }

  static Future<bool> launchTorrentPlayback({
    required Map<String, dynamic> payload,
    AndroidTvProgressCallback? onProgress,
    PlaybackFinishedCallback? onFinished,
    TorrentStreamProvider? onRequestStream,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (payload.isEmpty) {
      return false;
    }

    _ensureInitialized();
    _torrentProgressCallback = onProgress;
    _torrentFinishedCallback = onFinished;
    _torrentStreamProvider = onRequestStream;

    try {
      final bool? launched = await _channel.invokeMethod<bool>(
        'launchTorrentPlayback',
        {
          'payload': payload,
        },
      );
      if (launched == true) {
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint('AndroidTvPlayerBridge: torrent launch failed: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: unexpected torrent launch error: $e');
    }

    _torrentProgressCallback = null;
    _torrentFinishedCallback = null;
    _torrentStreamProvider = null;
    return false;
  }
}
