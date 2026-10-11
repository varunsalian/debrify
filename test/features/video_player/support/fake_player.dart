import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

/// Broadcast streams stay open until fixture cleanup, allowing a replaced
/// instance to emit late events after production has cancelled its listeners.
class FakePlayer implements mk.Player {
  FakePlayer(this.configuration, {bool native = false}) {
    platform = native ? FakeNativePlayer(this) : FakePlatformPlayer(this);
  }

  final mk.PlayerConfiguration configuration;
  final calls = <(String, Object?)>[];
  final delays = <String, Completer<void>>{};
  final failures = <String, Object>{};
  final events = <String, StreamController<dynamic>>{};
  final disposed = Completer<void>();
  bool readyDelivered = false;
  void Function()? onOpen;

  Stream<T> channel<T>(String name) => events
      .putIfAbsent(name, () => StreamController<T>.broadcast())
      .stream
      .cast<T>();

  void emit<T>(String name, T value) {
    channel<T>(name);
    events[name]!.add(value);
  }

  @override
  mk.PlayerState state = const mk.PlayerState(
    tracks: mk.Tracks(
      audio: [mk.AudioTrack('1', 'English audio', 'eng')],
      subtitle: [mk.SubtitleTrack('1', 'English', 'eng')],
    ),
  );
  @override
  mk.PlatformPlayer? platform;
  @override
  late final stream = mk.PlayerStream(
    channel<mk.Playlist>('playlist'),
    channel<bool>('playing'),
    channel<bool>('completed'),
    channel<Duration>('position'),
    channel<Duration>('duration'),
    channel<double>('volume'),
    channel<double>('rate'),
    channel<double>('pitch'),
    channel<bool>('buffering'),
    channel<double>('bufferingPercentage'),
    channel<Duration>('buffer'),
    channel<mk.PlaylistMode>('playlistMode'),
    channel<mk.AudioParams>('audioParams'),
    channel<mk.VideoParams>('videoParams'),
    channel<double?>('audioBitrate'),
    channel<mk.AudioDevice>('audioDevice'),
    channel<List<mk.AudioDevice>>('audioDevices'),
    channel<mk.Track>('track'),
    channel<mk.Tracks>('tracks'),
    channel<int?>('width'),
    channel<int?>('height'),
    channel<List<String>>('subtitle'),
    channel<mk.PlayerLog>('log'),
    channel<String>('error'),
  );
  @override
  mk.PlayerStream get streams => stream;

  Future<void> operation(String name, [Object? value]) async {
    calls.add((name, value));
    await delays[name]?.future;
    if (failures.containsKey(name)) throw failures.remove(name)!;
  }

  /// Called by the fixture only after player/controller assignments and binds.
  void deliverReady() {
    if (readyDelivered) throw StateError('ready callback delivered twice');
    readyDelivered = true;
    configuration.ready?.call();
  }

  void publishFrame({Duration duration = const Duration(minutes: 20)}) {
    state = state.copyWith(
      duration: duration,
      position: const Duration(milliseconds: 80),
      width: 1280,
      height: 720,
      videoParams: const mk.VideoParams(w: 1280, h: 720),
    );
    emit('duration', duration);
    emit<int?>('width', 1280);
    emit<int?>('height', 720);
    emit('videoParams', state.videoParams);
    emit('position', state.position);
  }

  void publishTracks(mk.Tracks available, {mk.Track? selected}) {
    state = state.copyWith(tracks: available, track: selected);
    emit('tracks', available);
    emit('track', state.track);
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    await operation('open', (playable, play));
    final playlist = playable is mk.Playlist
        ? playable
        : mk.Playlist([playable as mk.Media]);
    state = state.copyWith(
      playlist: playlist,
      playing: play,
      completed: false,
      position: Duration.zero,
    );
    emit('playlist', playlist);
    emit('playing', play);
    emit('completed', false);
    onOpen?.call();
  }

  @override
  Future<void> play() async {
    await operation('play');
    state = state.copyWith(playing: true);
    emit('playing', true);
  }

  @override
  Future<void> pause() async {
    await operation('pause');
    state = state.copyWith(playing: false);
    emit('playing', false);
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();
  @override
  Future<void> stop() async {
    await operation('stop');
    state = state.copyWith(playing: false, position: Duration.zero);
    emit('playing', false);
    emit('position', Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    await operation('seek', position);
    state = state.copyWith(position: position, completed: false);
    emit('position', position);
    emit('completed', false);
  }

  @override
  Future<void> setRate(double rate) async {
    await operation('rate', rate);
    state = state.copyWith(rate: rate);
    emit('rate', rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await operation('volume', volume);
    state = state.copyWith(volume: volume);
    emit('volume', volume);
  }

  @override
  Future<void> setAudioTrack(mk.AudioTrack audio) async {
    await operation('audio', audio);
    state = state.copyWith(track: state.track.copyWith(audio: audio));
    emit('track', state.track);
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack subtitle) async {
    await operation('subtitle', subtitle);
    state = state.copyWith(track: state.track.copyWith(subtitle: subtitle));
    emit('track', state.track);
  }

  @override
  Future<int> get handle async => 71;
  @override
  Future<void> dispose() async {
    await operation('dispose');
    for (final release in platform!.release) {
      await release();
    }
    disposed.complete();
  }

  Future<void> closeStreams() async {
    await Future.wait(events.values.map((controller) => controller.close()));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unmodelled player call: ${invocation.memberName}',
  );
}

class FakePlatformPlayer implements mk.PlatformPlayer {
  FakePlatformPlayer(this.player);
  final FakePlayer player;
  @override
  mk.PlayerConfiguration get configuration => player.configuration;
  @override
  mk.PlayerState get state => player.state;
  @override
  mk.PlayerStream get stream => player.stream;
  @override
  final release = <Future<void> Function()>[];
  @override
  bool isVideoControllerAttached = false;
  @override
  final videoControllerCompleter = Completer<void>();
  @override
  final completer = Completer<void>()..complete();
  @override
  Future<int> get handle => player.handle;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unmodelled platform call: ${invocation.memberName}',
  );
}

class FakeNativePlayer extends FakePlatformPlayer implements mk.NativePlayer {
  FakeNativePlayer(super.player);
  final properties = <String, String>{};
  final observers = <String, Future<void> Function(String)>{};
  final mapObservers = <String, void Function(Map<String, String>)>{};
  final calls = <(String, Object?)>[];
  final delays = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<void> operation(String name, Object? value) async {
    calls.add((name, value));
    await delays[name]?.future;
    if (failures.containsKey(name)) throw failures.remove(name)!;
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    await operation('setProperty', (property, value));
    properties[property] = value;
  }

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    await operation('getProperty', property);
    return properties[property] ?? '';
  }

  @override
  Future<void> observeProperty(
    String property,
    Future<void> Function(String) listener, {
    bool waitForInitialization = true,
  }) async {
    await operation('observeProperty', property);
    if (observers.containsKey(property)) throw StateError('duplicate observer');
    observers[property] = listener;
  }

  @override
  Future<void> observePropertyMap(
    String property,
    void Function(Map<String, String>) listener, {
    bool waitForInitialization = true,
  }) async {
    await operation('observePropertyMap', property);
    mapObservers[property] = listener;
  }

  @override
  Future<void> unobserveProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    await operation('unobserveProperty', property);
    observers.remove(property);
    mapObservers.remove(property);
  }

  @override
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
    bool throwOnError = false,
  }) => operation('command', List<String>.of(command));
}
