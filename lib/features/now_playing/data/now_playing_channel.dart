/// The method-channel adapter between the Dart now-playing side and the
/// platform side: 'update' / 'clear' out, 'command' in.
library;

import 'dart:async';

import 'package:debrify/features/now_playing/application/now_playing_publisher.dart';
import 'package:debrify/features/now_playing/models/now_playing_models.dart';
import 'package:flutter/services.dart';

/// The name shared with the iOS/tvOS and Android handlers.
const nowPlayingChannelName = 'com.debrify.app/now_playing';

/// Talks to the platform now-playing surface over a [MethodChannel].
///
/// Out: 'update' with [NowPlayingInfo.toMap] and 'clear'. In: 'command' with
/// a map that [NowPlayingCommand.fromMap] parses; unparsable commands are
/// dropped. update/clear swallow [MissingPluginException] and
/// [PlatformException] so platforms without a handler keep working.
final class NowPlayingChannel implements NowPlayingSink {
  NowPlayingChannel({
    MethodChannel channel = const MethodChannel(nowPlayingChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  StreamController<NowPlayingCommand>? _controller;
  int _listeners = 0;

  @override
  Future<void> update(NowPlayingInfo info) => _send('update', info.toMap());

  @override
  Future<void> clear() => _send('clear', null);

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (_) {
      // No now-playing handler on this platform.
    } on PlatformException catch (_) {
      // A handler exists but refused the call; nothing the user can act on.
    }
  }

  /// Remote commands raised by the platform. The method call handler is
  /// installed when the first listener subscribes and removed when the last
  /// one cancels.
  Stream<NowPlayingCommand> get commands {
    final controller = _controller ??=
        StreamController<NowPlayingCommand>.broadcast(
          onListen: _startListening,
          onCancel: _stopListening,
        );
    return controller.stream;
  }

  void _startListening() {
    _listeners++;
    if (_listeners == 1) {
      _channel.setMethodCallHandler(_handleCall);
    }
  }

  void _stopListening([Object? subscription]) {
    _listeners = _listeners > 0 ? _listeners - 1 : 0;
    if (_listeners == 0) {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final command = NowPlayingCommand.fromMap(call.arguments);
    final controller = _controller;
    if (command != null) controller?.add(command);
    return null;
  }
}
