// Desktop captures written straight to the SMB share: a real loopback live
// stream, the real capture loop, and a fake share that can drop mid-way.
import 'dart:async';
import 'dart:io';

import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_direct_writer.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/recording_output/application/smb_fakes.dart';

final class _RealNetwork extends HttpOverrides {}

const _target = SmbTarget(enabled: true, host: 'nas', share: 'tv');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late HttpServer server;
  late FakeShare share;
  final pumps = <Timer>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    temp = Directory.systemTemp.createTempSync('debrify_smb_capture');
    share = FakeShare();
    DesktopRecordingService.openShare =
        ({required fileName, required ownerProfileId}) => SmbDirectWriter.open(
          connector: share,
          target: _target,
          password: null,
          fileName: fileName,
        );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final response = request.response..bufferOutput = false;
      response.headers.contentType = ContentType('video', 'mp2t');
      pumps.add(
        Timer.periodic(const Duration(milliseconds: 2), (_) {
          try {
            response.add(List.filled(64 * 1024, 0x47));
          } catch (_) {}
        }),
      );
    });
  });

  tearDown(() async {
    for (final timer in pumps) {
      timer.cancel();
    }
    pumps.clear();
    await DesktopRecordingService.instance.stopAll();
    await server.close(force: true);
    DesktopRecordingService.openShare =
        ({required fileName, required ownerProfileId}) async => null;
    ProfileRuntime.debugReset();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String localPath() => '${temp.path}${Platform.pathSeparator}News.ts';

  Future<DesktopRecordingCapture> record() async {
    final capture = await HttpOverrides.runWithHttpOverrides(
      () => DesktopRecordingService.instance.start(
        url: 'http://127.0.0.1:${server.port}/live.ts',
        path: localPath(),
        channelName: 'News',
        headers: const {},
      ),
      _RealNetwork(),
    );
    expect(capture, isNotNull);
    return capture!;
  }

  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  int shareBytes() =>
      share.files.values.fold(0, (sum, bytes) => sum + bytes.length);

  test('every byte goes to the share and nothing is kept locally', () async {
    final capture = await record();
    await until(() => capture.bytes >= 3 * 1024 * 1024);
    final bytes = await capture.stop();

    expect(shareBytes(), bytes);
    expect(share.files.keys, ['News.ts']);
    expect(File(localPath()).existsSync(), isFalse);
    expect(capture.savedTo, r'\\nas\tv\News.ts');
  });

  test(
    'a share that drops mid-recording continues in the local file',
    () async {
      final capture = await record();
      await until(() => share.writes >= 1);
      share.writeError = const SmbException(SmbFailureKind.network, 'dropped');
      await until(() => File(localPath()).existsSync());
      await until(() => capture.bytes >= 4 * 1024 * 1024);
      final bytes = await capture.stop();

      final local = File(localPath()).lengthSync();
      expect(shareBytes(), greaterThan(0));
      expect(local, greaterThan(0));
      expect(shareBytes() + local, bytes, reason: 'nothing lost in the switch');
      expect(
        capture.savedTo,
        r'\\nas\tv\News.ts (continued in '
        '${localPath()})',
      );
    },
  );

  test(
    'without a usable share the capture records locally as before',
    () async {
      DesktopRecordingService.openShare =
          ({required fileName, required ownerProfileId}) async => null;
      final capture = await record();
      await until(() => capture.bytes >= 1024 * 1024);
      final bytes = await capture.stop();

      expect(File(localPath()).lengthSync(), bytes);
      expect(share.files, isEmpty);
      expect(capture.savedTo, localPath());
    },
  );
}
