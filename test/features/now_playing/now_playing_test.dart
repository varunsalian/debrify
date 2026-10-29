// Now Playing: what reaches the system (and when), how remote commands map
// onto the player, and the method channel adapter.
import 'package:debrify/features/now_playing/application/now_playing_commands.dart';
import 'package:debrify/features/now_playing/application/now_playing_publisher.dart';
import 'package:debrify/features/now_playing/data/now_playing_channel.dart';
import 'package:debrify/features/now_playing/models/now_playing_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sink implements NowPlayingSink {
  final pushes = <NowPlayingInfo>[];
  var clears = 0;
  @override
  Future<void> update(NowPlayingInfo info) async => pushes.add(info);
  @override
  Future<void> clear() async => clears++;
}

NowPlayingInfo _info({
  String title = 'Dune',
  Duration position = Duration.zero,
  bool playing = true,
  bool canGoNext = false,
}) => NowPlayingInfo(
  title: title,
  subtitle: 'Movie',
  duration: const Duration(minutes: 150),
  position: position,
  playing: playing,
  canGoNext: canGoNext,
);

void main() {
  group('models', () {
    test('toMap carries every field in milliseconds', () {
      expect(_info(position: const Duration(seconds: 3)).toMap(), {
        'title': 'Dune',
        'subtitle': 'Movie',
        'durationMs': 9000000,
        'positionMs': 3000,
        'playing': true,
        'rate': 1.0,
        'isLive': false,
        'canGoNext': false,
        'canGoPrevious': false,
      });
      expect(_info(), _info());
      final paused = NowPlayingInfo(
        title: 'x',
        duration: Duration.zero,
        position: Duration.zero,
        playing: false,
        rate: 1.5,
      );
      expect(paused.effectiveRate, 0);
      expect(paused.toMap()['rate'], 0.0);
    });

    test('commands parse, and malformed ones are null', () {
      expect(
        NowPlayingCommand.fromMap({'type': 'toggle'})?.type,
        NowPlayingCommandType.toggle,
      );
      final seek = NowPlayingCommand.fromMap({
        'type': 'seekTo',
        'positionMs': 61000,
      });
      expect(seek?.type, NowPlayingCommandType.seekTo);
      expect(seek?.position, const Duration(seconds: 61));
      expect(NowPlayingCommand.fromMap({'type': 'seekTo'}), isNull);
      expect(
        NowPlayingCommand.fromMap({'type': 'seekTo', 'positionMs': -1}),
        isNull,
      );
      expect(NowPlayingCommand.fromMap({'type': 'dance'}), isNull);
      expect(NowPlayingCommand.fromMap('play'), isNull);
      expect(NowPlayingCommand.fromMap(null), isNull);
    });
  });

  group('publisher', () {
    late _Sink sink;
    late DateTime now;
    late NowPlayingPublisher publisher;
    setUp(() {
      sink = _Sink();
      now = DateTime(2026);
      publisher = NowPlayingPublisher(sink, clock: () => now);
    });

    test('the first report is pushed; an identical one is not', () {
      publisher.report(_info());
      publisher.report(_info());
      expect(sink.pushes, hasLength(1));
    });

    test('a position that follows playback is not pushed', () {
      publisher.report(_info());
      now = now.add(const Duration(seconds: 10));
      publisher.report(_info(position: const Duration(seconds: 11)));
      expect(sink.pushes, hasLength(1));
    });

    test('a jump of more than two seconds is pushed', () {
      publisher.report(_info());
      now = now.add(const Duration(seconds: 10));
      publisher.report(_info(position: const Duration(seconds: 40)));
      expect(sink.pushes, hasLength(2));
    });

    test('while paused the position must stay put', () {
      publisher.report(_info(playing: false));
      now = now.add(const Duration(seconds: 30));
      publisher.report(
        _info(playing: false, position: const Duration(seconds: 1)),
      );
      expect(sink.pushes, hasLength(1));
      publisher.report(
        _info(playing: false, position: const Duration(seconds: 5)),
      );
      expect(sink.pushes, hasLength(2));
    });

    test('extrapolation follows the playback rate', () {
      NowPlayingInfo fast(Duration at) => NowPlayingInfo(
        title: 'Dune',
        duration: const Duration(minutes: 150),
        position: at,
        playing: true,
        rate: 1.5,
      );
      publisher.report(fast(Duration.zero));
      now = now.add(const Duration(seconds: 10));
      publisher.report(fast(const Duration(seconds: 15)));
      expect(sink.pushes, hasLength(1));
      publisher.report(
        const NowPlayingInfo(
          title: 'Dune',
          duration: Duration(minutes: 150),
          position: Duration(seconds: 15),
          playing: true,
        ),
      );
      expect(sink.pushes, hasLength(2), reason: 'a rate change is pushed');
    });

    test('play state, title or skip ability changes are pushed', () {
      publisher.report(_info());
      publisher.report(_info(playing: false));
      publisher.report(_info(playing: false, title: 'Dune Part Two'));
      publisher.report(
        _info(playing: false, title: 'Dune Part Two', canGoNext: true),
      );
      expect(sink.pushes, hasLength(4));
    });

    test('clear runs once, and the next report pushes again', () {
      publisher.clear();
      expect(sink.clears, 0, reason: 'nothing was pushed yet');
      publisher.report(_info());
      publisher.clear();
      publisher.clear();
      expect(sink.clears, 1);
      publisher.report(_info());
      expect(sink.pushes, hasLength(2));
    });
  });

  group('commands', () {
    late List<String> calls;
    late NowPlayingTarget target;
    setUp(() {
      calls = [];
      target = NowPlayingTarget(
        play: () async => calls.add('play'),
        pause: () async => calls.add('pause'),
        seek: (to) async => calls.add('seek ${to.inSeconds}'),
        position: () => const Duration(seconds: 10),
        duration: () => const Duration(seconds: 20),
        next: () async => calls.add('next'),
      );
    });

    Future<void> run(NowPlayingCommand command, {bool playing = true}) =>
        handleNowPlayingCommand(command, target, isPlaying: playing);

    test('play, pause and toggle', () async {
      await run(const NowPlayingCommand(NowPlayingCommandType.play));
      await run(const NowPlayingCommand(NowPlayingCommandType.pause));
      await run(const NowPlayingCommand(NowPlayingCommandType.toggle));
      await run(
        const NowPlayingCommand(NowPlayingCommandType.toggle),
        playing: false,
      );
      expect(calls, ['play', 'pause', 'pause', 'play']);
    });

    test('skips and seeks clamp to the media', () async {
      await run(const NowPlayingCommand(NowPlayingCommandType.skipForward));
      await run(const NowPlayingCommand(NowPlayingCommandType.skipBackward));
      await run(
        const NowPlayingCommand(
          NowPlayingCommandType.seekTo,
          position: Duration(seconds: 5),
        ),
      );
      await run(
        const NowPlayingCommand(
          NowPlayingCommandType.seekTo,
          position: Duration(minutes: 5),
        ),
      );
      expect(calls, ['seek 20', 'seek 0', 'seek 5', 'seek 20']);
    });

    test('a live stream (no duration) ignores skips and seeks', () async {
      final live = NowPlayingTarget(
        play: () async => calls.add('play'),
        pause: () async => calls.add('pause'),
        seek: (to) async => calls.add('seek ${to.inSeconds}'),
        position: () => const Duration(seconds: 10),
        duration: () => Duration.zero,
      );
      for (final c in [
        const NowPlayingCommand(NowPlayingCommandType.skipForward),
        const NowPlayingCommand(NowPlayingCommandType.skipBackward),
        const NowPlayingCommand(
          NowPlayingCommandType.seekTo,
          position: Duration(seconds: 5),
        ),
        const NowPlayingCommand(NowPlayingCommandType.pause),
      ]) {
        await handleNowPlayingCommand(c, live, isPlaying: true);
      }
      expect(calls, ['pause']);
    });

    test('next calls through; a missing previous is ignored', () async {
      await run(const NowPlayingCommand(NowPlayingCommandType.next));
      await run(const NowPlayingCommand(NowPlayingCommandType.previous));
      expect(calls, ['next']);
    });
  });

  group('channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const name = 'com.debrify.app/now_playing';
    const channel = MethodChannel(name);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('update and clear send their method calls', () async {
      final sent = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
      final adapter = NowPlayingChannel();
      await adapter.update(_info());
      await adapter.clear();
      expect(sent.map((c) => c.method), ['update', 'clear']);
      expect(sent.first.arguments, _info().toMap());
    });

    test('a missing plugin is not an error', () async {
      final adapter = NowPlayingChannel();
      await adapter.update(_info());
      await adapter.clear();
    });

    test('native commands arrive parsed; junk is dropped', () async {
      final adapter = NowPlayingChannel();
      final got = <NowPlayingCommandType>[];
      final sub = adapter.commands.listen((c) => got.add(c.type));
      Future<void> send(Object? args) => messenger.handlePlatformMessage(
        name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('command', args),
        ),
        (_) {},
      );
      await send({'type': 'pause'});
      await send({'type': 'nope'});
      await send({'type': 'next'});
      await Future<void>.delayed(Duration.zero);
      expect(got, [NowPlayingCommandType.pause, NowPlayingCommandType.next]);
      await sub.cancel();
    });
  });
}
