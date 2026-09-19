// Run this entry point in profile mode; sample_data.dart embeds QA-only files.
// Uses temporary storage and never opens Debrify's user preferences or database.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'sample_data.dart';
import 'recreation_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/widgets/launch/imported_launch_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VerificationApp(),
    ),
  );
}

class VerificationApp extends StatefulWidget {
  const VerificationApp({super.key});
  @override
  State<VerificationApp> createState() => _VerificationAppState();
}

class _VerificationAppState extends State<VerificationApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  final _boundary = GlobalKey();
  final _timings = <FrameTiming>[];
  final _errors = <String>[];
  LoadedLaunchAnimation? _loaded;
  String _label = 'Preparing';
  double _ratio = 16 / 9;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_record);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  void _record(List<FrameTiming> frames) => _timings.addAll(frames);
  Future<void> _verify() async {
    final output = await Directory.systemTemp.createTemp(
      'debrify-launch-verification-',
    );
    final root = await Directory.systemTemp.createTemp('debrify-launch-qa-');
    final library = LaunchAnimationLibrary(
      directory: () async => Directory('${root.path}/library'),
    );
    final reports = <Map<String, Object?>>[];
    try {
      const selected = String.fromEnvironment('LAUNCH_SAMPLE');
      const recreations = bool.fromEnvironment('LAUNCH_RECREATIONS');
      final cases = recreations
          ? [
              for (final source in recreatedAnimations.keys.where(
                (name) => selected.isEmpty || name == selected,
              ))
                for (final orientation in ['landscape', 'portrait'])
                  (
                    name: '$source-$orientation',
                    data: recreatedAnimations[source]!,
                    id: '$source-$orientation',
                  ),
            ]
          : [
              for (final name
                  in selected.isEmpty ? launchSamples.keys : [selected])
                (name: name, data: launchSamples[name]!, id: null),
            ];
      for (final sample in cases) {
        final name = sample.name;
        final importWatch = Stopwatch()..start();
        final source = await File(
          '${root.path}/$name.lottie',
        ).writeAsBytes(base64Decode(sample.data));
        final entry = await library.install(source, animationId: sample.id);
        importWatch.stop();
        final loadWatch = Stopwatch()..start();
        final loaded = await library.load(entry.id);
        loadWatch.stop();
        for (final ratio in [9 / 16, 16 / 9, 21 / 9]) {
          _timings.clear();
          setState(() {
            _loaded = loaded;
            _label = name;
            _ratio = ratio;
          });
          _controller.duration = loaded.composition.duration;
          await _controller.forward(from: 0).orCancel;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await WidgetsBinding.instance.endOfFrame;
          final boundary =
              _boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File(
            '${output.path}/$name-${ratio.toStringAsFixed(2)}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          final raster =
              _timings
                  .map((f) => f.rasterDuration.inMicroseconds / 1000)
                  .toList()
                ..sort();
          reports.add({
            'sample': name,
            'aspectRatio': ratio,
            'importMs': importWatch.elapsedMilliseconds,
            'loadMs': loadWatch.elapsedMilliseconds,
            'frames': raster.length,
            'rssBytes': ProcessInfo.currentRss,
            'peakRssBytes': ProcessInfo.maxRss,
            'rasterP95Ms': raster.isEmpty
                ? null
                : raster[((raster.length - 1) * .95).round()],
            'rasterMaxMs': raster.isEmpty ? null : raster.last,
          });
        }
        setState(() => _loaded = null);
        await WidgetsBinding.instance.endOfFrame;
        loaded.dispose();
      }
      await File('${output.path}/results.json').writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'reports': reports, 'errors': _errors}),
      );
      // ignore: avoid_print
      print(
        'LAUNCH_VERIFICATION ${output.path}/results.json errors=${_errors.length}',
      );
    } catch (error, stack) {
      await File('${output.path}/error.txt').writeAsString('$error\n$stack');
      _errors.add('$error');
    } finally {
      await root.delete(recursive: true);
      exit(_errors.isEmpty ? 0 : 1);
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_record);
    _controller.dispose();
    _loaded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff171c26),
    body: Column(
      children: [
        Text(_label, style: const TextStyle(color: Colors.white)),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _ratio,
              child: RepaintBoundary(
                key: _boundary,
                child: _loaded == null
                    ? const ColoredBox(color: Colors.black)
                    : ImportedLaunchPlayer(
                        animation: _loaded!,
                        progress: _controller,
                        onError: (error) => _errors.add('$error'),
                      ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
