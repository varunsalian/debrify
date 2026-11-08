// THROWAWAY diagnostic for the iOS "no source plays" report on v0.10.2-alpha.1.
// Lives only on branch ios-audio-probe. Plays a clip with sound through
// media_kit/mpv exactly as the app does on iPhone (default audio output),
// once without and once with the app's own now-playing audio session, and
// prints every audio-output log line, error and outcome with a PROBE prefix.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const _url = String.fromEnvironment(
  'PROBE_URL',
  defaultValue:
      'https://raw.githubusercontent.com/varunsalian/debrify/0b44a53ca5effe2bea9e9ccbb293b09f401e235f/integration_test/assets/duo_test.mp4',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();
  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final List<String> _lines = [];
  Player? _player;
  VideoController? _controller;

  void _log(String s) {
    // ignore: avoid_print
    print('PROBE $s');
    File('${Directory.systemTemp.path}/probe.log')
        .writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
    if (mounted) setState(() => _lines.add(s));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _phase(String name, {required bool session}) async {
    _log('--- phase $name (session=$session) url=$_url');
    if (session) {
      try {
        await const MethodChannel('com.debrify.app/now_playing').invokeMethod(
          'update',
          {'title': 'probe', 'durationMs': 10000, 'positionMs': 0, 'rate': 1.0},
        );
        _log('$name: now_playing update ok (session .playback active)');
      } catch (e) {
        _log('$name: now_playing update failed: $e');
      }
    }
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v),
    );
    final controller = VideoController(player);
    setState(() {
      _player = player;
      _controller = controller;
    });
    final errors = <String>[];
    final subs = <StreamSubscription<dynamic>>[
      player.stream.error.listen((e) {
        errors.add(e);
        _log('$name: ERROR $e');
      }),
      player.stream.log.listen((l) {
        final p = l.prefix.toLowerCase();
        final t = l.text.trim();
        if (p.startsWith('ao') ||
            p.contains('audio') ||
            p == 'cplayer' && t.toLowerCase().contains('audio') ||
            l.level == 'error' ||
            l.level == 'fatal') {
          _log('$name: [${l.prefix}] ${l.level}: $t');
        }
      }),
    ];
    await player.open(Media(_url));
    await Future<void>.delayed(const Duration(seconds: 12));
    final s = player.state;
    _log(
      '$name: RESULT playing=${s.playing} pos=${s.position.inMilliseconds}ms '
      'width=${s.width} audioParams=${s.audioParams} '
      'audioDevice=${s.audioDevice} errors=${errors.length}',
    );
    for (final sub in subs) {
      await sub.cancel();
    }
    setState(() {
      _player = null;
      _controller = null;
    });
    await player.dispose();
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final f = File('${Directory.systemTemp.path}/probe.log');
    if (f.existsSync()) f.deleteSync();
    await _phase('plain', session: false);
    await _phase('session', session: true);
    _log('DONE');
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 200,
                child: c == null || _player == null
                    ? const SizedBox()
                    : Video(controller: c, controls: NoVideoControls),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final l in _lines)
                      Text(
                        l,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
