// Manual native regression (no profile data is read or changed):
// mkdir -p /tmp/debrify-native-video-fixture
// ffmpeg -f lavfi -i testsrc2=size=320x180:rate=24 -t 2 -c:v libx264
//   -pix_fmt yuv420p /tmp/debrify-native-video-fixture/video.mp4
// python3 -m http.server 38837 --bind 127.0.0.1
//   --directory /tmp/debrify-native-video-fixture
// flutter run -d macos --release -t tool/native_video_disposal_probe.dart
// Each command above is a single shell command; run the server separately.
// Local HTTP is used because the release app's sandbox cannot read arbitrary
// /tmp files. The probe prints PASS after 30 hardware and 10 software cycles.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  VideoController? controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    try {
      for (var i = 0; i < 40; i++) {
        final player = Player();
        final errors = player.stream.error.listen(
          (e) => debugPrint('DISPOSAL_PROBE media error: $e'),
        );
        final video = VideoController(
          player,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: i < 30,
          ),
        );
        setState(() => controller = video);
        await player.setVolume(0);
        await player.open(Media('http://127.0.0.1:38837/video.mp4'));
        await video.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 15),
        );
        await Future<void>.delayed(Duration(milliseconds: 10 + i % 4 * 30));
        setState(() => controller = null);
        await WidgetsBinding.instance.endOfFrame;
        await player.dispose().timeout(const Duration(seconds: 15));
        await errors.cancel();
        debugPrint('DISPOSAL_PROBE cycle ${i + 1}/40 complete');
      }
      debugPrint('DISPOSAL_PROBE PASS');
      exit(0);
    } catch (error, stack) {
      debugPrint('DISPOSAL_PROBE FAIL: $error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: controller == null
        ? const Center(child: Text('Native video disposal probe'))
        : Video(controller: controller!, controls: NoVideoControls),
  );
}
