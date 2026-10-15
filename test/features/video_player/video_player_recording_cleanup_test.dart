import 'dart:async';
import 'dart:io';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/recording_delivery.dart';
import 'support/recording_driver.dart';

final class _NativeRecordingFiles extends IOOverrides {}

final class _RecordingDeleteFailure extends IOOverrides {
  final IOOverrides real = _NativeRecordingFiles();
  String? target;
  bool enabled = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  File createFile(String path) {
    final file = real.createFile(path);
    return enabled && path == target ? _DeleteFailureFile(file, this) : file;
  }
}

class _DeleteFailureFile implements File {
  _DeleteFailureFile(this.file, this.failure);
  final File file;
  final _RecordingDeleteFailure failure;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<File> delete({bool recursive = false}) async {
    failure.entered.complete();
    await failure.release.future;
    throw FileSystemException('fixture deletion denied', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected recording cleanup fixture call: ${invocation.memberName}',
  );
}

class _LateDirectoryFailure extends RecordingPaths {
  _LateDirectoryFailure(super.path, super.driver);
  final release = Completer<void>();
  @override
  Future<String?> getDownloadsPath() async {
    reads++;
    await release.future;
    throw StateError('fixture directory failed after dispose');
  }
}

void main() {
  testWidgets('p13 desktop one captured byte is saved after cancellation', (
    t,
  ) async {
    final d = RecordingDriver(t);
    await d.setup();
    try {
      final server = (await t.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      d.servers.add(server);
      await t.runAsync(() async {
        server.listen((request) {
          final response = request.response;
          d.responses.add(response);
          response.bufferOutput = false;
          response.add([0x47]);
          // Keep the live connection open until the capture cancels it.
        });
      });
      final url = 'http://127.0.0.1:${server.port}/one-byte.ts';
      await d.mountRecording(url: url, tee: false);
      d.native.properties['file-format'] = 'mpegts';
      d.desktopRecord();
      await d.f.until(
        t,
        () => DesktopRecordingService.instance.captureForUrl(url)?.bytes == 1,
      );
      final capture = DesktopRecordingService.instance.captureForUrl(url)!;
      await d.dismissNotice();
      d.desktopRecord();
      await d.f.actions.settle(t);
      expect(capture.isActive, isFalse);
      expect(capture.bytes, 1);
      expect(await t.runAsync(() => File(capture.path).length()), 1);
      expect(find.text('Recording saved: ${capture.path}'), findsOneWidget);
      expect(d.paths.reads, 1, reason: 'Stop must not start another capture');
      expect(DesktopRecordingService.instance.activeCount, 0);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'p13 TEE directory failure delivered after disposal stays quiet',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final paths = _LateDirectoryFailure(d.paths.path, d);
      try {
        await d.mountRecording();
        d.paths = paths;
        PathProviderPlatform.instance = paths;
        d.record();
        await d.f.until(t, () => paths.reads == 1);
        await d.removePlayer();
        paths.release.complete();
        await d.f.actions.settle(t);
        expect(d.propertyWrites, isEmpty);
        expect(
          d.logs.any((line) => line.contains('start recording failed')),
          isTrue,
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!paths.release.isCompleted) paths.release.complete();
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 TEE user stop cannot start another recording after its saved notice',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording();
        d.record();
        final path = await d.armed();
        await d.started();
        await t.runAsync(() => File(path).writeAsBytes([0x47]));
        await d.dismissNotice();
        d.record();
        await d.f.until(
          t,
          () => find.text('Recording saved: $path').evaluate().isNotEmpty,
        );
        expect(
          d.paths.reads,
          1,
          reason: 'the stop return precedes every start path',
        );
        await d.f.actions.settle(t);
        expect(d.active, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 desktop stop delivered after disposal performs no late State update',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final delivery = RecordingDelivery((value) => value is int && value > 0);
      try {
        final url = await d.loopback();
        await d.mountRecording(url: url, tee: false);
        d.native.properties['file-format'] = 'mpegts';
        d.desktopRecord();
        final capture = await d.captured(url);
        delivery.run(d.desktopRecord);
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.removePlayer();
        delivery.release();
        await d.f.actions.settle(t);
        expect(capture.isActive, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.close();
      }
    },
  );
  for (final failure in ['native-clear', 'file-delete']) {
    testWidgets(
      'p13 TEE stale start $failure failure retains its independent cleanup catches',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        final arm = Completer<void>();
        final files = _RecordingDeleteFailure();
        try {
          await d.mountRecording();
          d.native.heldOperation = (name, value) =>
              name == 'setProperty' &&
              value is (String, String) &&
              value.$1 == 'stream-record' &&
              value.$2.isNotEmpty;
          d.native.beforeOperation = (name, value) async {
            if (d.native.heldOperation!(name, value)) await arm.future;
            if (failure == 'native-clear' &&
                name == 'setProperty' &&
                value == ('stream-record', '')) {
              throw StateError('fixture native clear denied');
            }
          };
          IOOverrides.runWithIOOverrides(d.record, files);
          final path = await d.armed();
          files.target = path;
          await t.runAsync(() => File(path).writeAsBytes([0x47]));
          await d.zap();
          files.enabled = failure == 'file-delete';
          arm.complete();
          if (failure == 'file-delete') {
            await d.f.until(t, () => files.entered.isCompleted);
            expect(await t.runAsync(() => File(path).exists()), isTrue);
            expect(d.active, isFalse);
            files.release.complete();
          }
          await d.f.actions.settle(t);
          expect(d.active, isFalse);
          expect(
            await t.runAsync(() => File(path).exists()),
            failure == 'file-delete',
          );
          expect(
            d.logs.any(
              (line) => line.contains(
                failure == 'file-delete'
                    ? 'stray recording cleanup failed'
                    : 'disarm stray recording failed',
              ),
            ),
            isTrue,
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!arm.isCompleted) arm.complete();
          if (!files.release.isCompleted) files.release.complete();
          files.enabled = false;
          await d.close();
        }
      },
    );
  }
}
