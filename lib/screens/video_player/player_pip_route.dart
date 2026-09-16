import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_surfaces.dart';
import '../../theme/legacy_theme_boundary.dart';
import '../../utils/platform_util.dart';

/// Only iOS needs to release its Flutter route while native PiP is visible.
FrozenLegacyPageRoute<T> videoPlayerRoute<T>({
  required WidgetBuilder builder,
}) => Platform.isIOS && !PlatformUtil.isTvOS
    ? IosPipPlayerRoute<T>(builder: builder)
    : FrozenLegacyPageRoute<T>(builder: builder);

/// Moves the existing player element into an offstage overlay while browsing.
/// Removing the route and reparenting happen in the same frame: the player,
/// subscriptions and media texture keep their identity and are not disposed.
class IosPipPlayerRoute<T> extends FrozenLegacyPageRoute<T> {
  factory IosPipPlayerRoute({required WidgetBuilder builder}) =>
      IosPipPlayerRoute._(PlayerPipSession(builder));

  IosPipPlayerRoute._(this.session) : super(builder: session.buildPlayer) {
    session._route = this;
  }

  final PlayerPipSession session;
  bool _retainedForPip = false;

  @override
  TickerFuture didPush() {
    session._replaceOtherParkedPlayer();
    return super.didPush();
  }

  // Callers await playback completion (including result-based next-episode
  // handoffs), not the temporary removal of the fullscreen presentation.
  @override
  Future<T?> get popped => session._result.future.then((value) => value as T?);

  @override
  void didComplete(T? result) {
    if (!_retainedForPip) session._complete(result);
    super.didComplete(result);
  }

  @override
  void dispose() {
    if (!_retainedForPip) session.close();
    super.dispose();
  }
}

class PlayerPipSession {
  PlayerPipSession(this._builder);

  final WidgetBuilder _builder;
  static PlayerPipSession? _parkedSession;
  final GlobalKey _playerKey = GlobalKey();
  final Completer<Object?> _result = Completer<Object?>();
  IosPipPlayerRoute<dynamic>? _route;
  NavigatorState? _navigator;
  OverlayEntry? _parkedEntry;
  bool _closed = false;
  bool wasReplaced = false;

  bool get isParked => _parkedEntry != null;

  static PlayerPipSession? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlayerPipScope>()?.session;

  Widget buildPlayer(BuildContext context) => KeyedSubtree(
    key: _playerKey,
    child: _PlayerPipScope(
      session: this,
      child: Builder(builder: _builder),
    ),
  );

  bool park() {
    final route = _route;
    final navigator = route?.navigator;
    if (_closed ||
        isParked ||
        route == null ||
        navigator == null ||
        !route.isCurrent ||
        route.isFirst) {
      return false;
    }
    _navigator = navigator;
    final entry = OverlayEntry(
      maintainState: true,
      builder: (context) => Offstage(
        child: ExcludeFocus(
          child: TickerMode(
            enabled: false,
            child: LegacyThemeBoundary(
              withMessenger: true,
              child: buildPlayer(context),
            ),
          ),
        ),
      ),
    );
    _parkedEntry = entry;
    _parkedSession = this;
    route._retainedForPip = true;
    navigator.removeRoute(route);
    _route = null;
    navigator.overlay!.insert(entry);
    return true;
  }

  /// Restore above whatever the viewer has browsed to, without popping it.
  bool restore() {
    final navigator = _navigator;
    if (_closed || !isParked || navigator == null || !navigator.mounted) {
      return false;
    }
    _removeParkedEntry();
    navigator.push(IosPipPlayerRoute<dynamic>._(this));
    return true;
  }

  /// Called on PiP dismissal, replacement by another player, or normal exit.
  void close([Object? result]) {
    if (_closed) return;
    _closed = true;
    _complete(result);
    _removeParkedEntry();
    _navigator = null;
    _route = null;
  }

  void _complete(Object? value) {
    if (!_result.isCompleted) _result.complete(value);
  }

  void _replaceOtherParkedPlayer() {
    final previous = _parkedSession;
    if (previous != null && !identical(previous, this)) {
      previous.wasReplaced = true;
      previous.close();
    }
  }

  void _removeParkedEntry() {
    if (identical(_parkedSession, this)) _parkedSession = null;
    final entry = _parkedEntry;
    _parkedEntry = null;
    entry?.remove();
    entry?.dispose();
  }
}

class _PlayerPipScope extends InheritedWidget {
  const _PlayerPipScope({required this.session, required super.child});

  final PlayerPipSession session;

  @override
  bool updateShouldNotify(_PlayerPipScope oldWidget) =>
      session != oldWidget.session;
}
