import 'package:debrify/features/video_player/presentation/legacy_video_player/vp_start_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

class _Host implements VpStartPositionHost {
  _Host({this.startFromRandom = false, this.startAtPercent, this.offset});

  final Duration? offset;
  final calls = <String>[];

  @override
  final bool startFromRandom;
  @override
  final double? startAtPercent;
  @override
  Duration get duration => const Duration(minutes: 10);
  @override
  mk.Player get player => throw UnimplementedError();
  @override
  Duration? randomStartOffset(Duration duration) => offset;
  @override
  Duration? percentStartOffset(Duration duration) => offset;
  @override
  Future<void> maybeRestoreResume({bool verifyLanding = false}) async =>
      calls.add('resume:$verifyLanding');
  @override
  Future<void> seekForResume(
    int targetMs, {
    bool verifyLanding = false,
  }) async => calls.add('seek:$targetMs:$verifyLanding');
}

void main() {
  test('a plain launch restores resume and verifies the landing', () async {
    final host = _Host();
    await applyInitialStartPosition(host);
    expect(host.calls, ['resume:true']);
  });

  test('a random start with no usable offset falls back to resume', () async {
    final host = _Host(startFromRandom: true, startAtPercent: 0.5);
    await applyInitialStartPosition(host);
    expect(host.calls, ['resume:true']);
  });

  test('an explicit percent seeks instead of restoring resume', () async {
    final host = _Host(
      startAtPercent: 0.5,
      offset: const Duration(seconds: 90),
    );
    await applyInitialStartPosition(host);
    expect(host.calls, ['seek:90000:true']);
  });

  test('a deferred percent leaves the position alone', () async {
    final host = _Host(
      startAtPercent: 0.5,
      offset: const Duration(seconds: 90),
    );
    await applyInitialStartPosition(host, deferPercent: true);
    expect(host.calls, isEmpty);
  });
}
