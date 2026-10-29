// Connects the in-app media_kit player to the system's Now Playing surface
// (lock screen, Control Centre, AirPods) on iPhone and iPad.
//
// One player owns the surface at a time: attaching a new player (next episode,
// source switch, renderer restart) hands it over, and a detaching player only
// clears what it still owns, so the old player's teardown never wipes the new
// one's entry. Remote commands go to the current owner.
import 'dart:async';

import 'package:debrify/features/now_playing/application/now_playing_commands.dart';
import 'package:debrify/features/now_playing/application/now_playing_publisher.dart';
import 'package:debrify/features/now_playing/data/now_playing_channel.dart';
import 'package:debrify/features/now_playing/models/now_playing_models.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

final class PlayerNowPlaying {
  PlayerNowPlaying._();

  static final _channel = NowPlayingChannel();
  static final _publisher = NowPlayingPublisher(_channel);
  static StreamSubscription<NowPlayingCommand>? _commands;
  static _Attachment? _current;
  static ({String title, String? subtitle})? _launch;

  /// What the next player shows until it knows better; set at launch.
  static void prepare({required String title, String? subtitle}) {
    _launch = (title: title, subtitle: subtitle);
  }

  /// Publishes [player] until it is disposed. [liveTitle] names a live IPTV
  /// channel (it follows zapping); null means the launch title is used.
  static void attach(mk.Player player, {String? Function()? liveTitle}) {
    if (!PlatformUtil.isIosMobile) return;
    _current?.cancel();
    // A launch title names one launch: a later player (a Debrify TV channel,
    // a renderer restart) must not inherit it.
    final launch = _launch;
    _launch = null;
    late final _Attachment attachment;
    attachment = _Attachment(
      player,
      title: () =>
          liveTitle?.call() ??
          attachment.mediaTitle ??
          launch?.title ??
          'Debrify',
      subtitle: () {
        if (liveTitle?.call() != null) return 'Live TV';
        // The launch subtitle described the first item only.
        return attachment.mediaTitle == null ? launch?.subtitle : null;
      },
      isLive: () => liveTitle?.call() != null,
    );
    _current = attachment;
    _commands ??= _channel.commands.listen(_onCommand);
    attachment.start(
      onDone: () {
        if (!identical(_current, attachment)) return;
        _current = null;
        _publisher.clear();
      },
    );
  }

  static void _onCommand(NowPlayingCommand command) {
    final attachment = _current;
    if (attachment == null) return;
    unawaited(
      handleNowPlayingCommand(
        command,
        attachment.target,
        isPlaying: attachment.player.state.playing,
      ).catchError((Object error) {
        debugPrint('Now Playing command failed: $error');
      }),
    );
  }

  static void _report(_Attachment attachment) {
    if (!identical(_current, attachment)) return;
    _publisher.report(attachment.info());
  }
}

final class _Attachment {
  _Attachment(
    this.player, {
    required this.title,
    required this.subtitle,
    required this.isLive,
  });

  final mk.Player player;
  final String Function() title;
  final String? Function() subtitle;
  final bool Function() isLive;
  final _subs = <StreamSubscription<Object?>>[];

  /// mpv's title for the current item once the player moved past the item
  /// it was launched with (next episode, playlist advance).
  String? mediaTitle;
  String? _firstUri;

  late final target = NowPlayingTarget(
    play: player.play,
    pause: player.pause,
    seek: player.seek,
    position: () => player.state.position,
    duration: () => isLive() ? Duration.zero : player.state.duration,
  );

  NowPlayingInfo info() {
    final state = player.state;
    final live = isLive();
    return NowPlayingInfo(
      title: title(),
      subtitle: subtitle(),
      duration: live ? Duration.zero : state.duration,
      position: state.position,
      // Buffering holds the clock still so the system does not run ahead.
      playing: state.playing && !state.buffering,
      rate: state.rate,
      isLive: live,
    );
  }

  void start({required void Function() onDone}) {
    void report(Object? _) => PlayerNowPlaying._report(this);
    final stream = player.stream;
    _subs
      ..add(stream.playing.listen(report))
      ..add(stream.buffering.listen(report))
      ..add(stream.duration.listen(report))
      ..add(stream.rate.listen(report))
      ..add(stream.playlist.listen(_onPlaylist))
      // Position ticks are cheap: the publisher drops ones the system
      // already extrapolates. Its stream ends when the player is disposed.
      ..add(
        stream.position.listen(
          report,
          onDone: () {
            cancel();
            onDone();
          },
        ),
      );
  }

  void _onPlaylist(mk.Playlist playlist) {
    // Compare the item, not the index: a next episode can reopen a
    // one-item playlist.
    if (playlist.medias.isEmpty) return;
    final index = playlist.index.clamp(0, playlist.medias.length - 1);
    final uri = playlist.medias[index].uri;
    final first = _firstUri ??= uri;
    if (uri == first) return;
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    unawaited(
      platform
          .getProperty('media-title')
          .then((title) {
            final trimmed = title.trim();
            if (trimmed.isEmpty) return;
            mediaTitle = trimmed;
            PlayerNowPlaying._report(this);
          })
          .catchError((Object _) {}),
    );
  }

  void cancel() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }
}
