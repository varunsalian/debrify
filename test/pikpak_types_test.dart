import 'package:debrify/features/pikpak/models/file.dart';
import 'package:debrify/features/pikpak/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('size', () {
    test('parses the string PikPak actually sends', () {
      final file = PikPakFile.fromJson({'id': '1', 'size': '1073741824'});

      expect(file.size, 1073741824);
    });

    test('accepts a number too, in case PikPak ever changes its mind', () {
      expect(PikPakFile.fromJson({'id': '1', 'size': 42}).size, 42);
    });

    test('an absent or junk size is 0, not null and not a throw', () {
      expect(PikPakFile.fromJson({'id': '1'}).size, 0);
      expect(PikPakFile.fromJson({'id': '1', 'size': 'huge'}).size, 0);
      expect(PikPakFile.fromJson({'id': '1', 'size': null}).size, 0);
    });
  });

  group('kind and phase', () {
    test('the two kinds map, anything else is unknown', () {
      expect(PikPakFile.fromJson({'kind': 'drive#file'}).kind, PikPakKind.file);
      expect(
        PikPakFile.fromJson({'kind': 'drive#folder'}).kind,
        PikPakKind.folder,
      );
      expect(PikPakFile.fromJson({}).kind, PikPakKind.unknown);
      expect(
        PikPakFile.fromJson({'kind': 'drive#shortcut'}).kind,
        PikPakKind.unknown,
      );
    });

    test('isFolder and isVideo read off kind and mime type', () {
      final folder = PikPakFile.fromJson({'kind': 'drive#folder'});
      final video = PikPakFile.fromJson({
        'kind': 'drive#file',
        'mime_type': 'video/x-matroska',
      });

      expect(folder.isFolder, isTrue);
      expect(folder.isVideo, isFalse);
      expect(video.isVideo, isTrue);
      expect(video.isFolder, isFalse);
    });

    test('a phase PikPak adds later degrades to unknown, not a crash', () {
      expect(
        PikPakFile.fromJson({'phase': 'PHASE_TYPE_COMPLETE'}).phase,
        PikPakPhase.complete,
      );
      expect(PikPakFile.fromJson({'phase': 'PHASE_TYPE_NEW'}).phase,
          PikPakPhase.unknown);
      expect(PikPakFile.fromJson({}).phase, PikPakPhase.unknown);
    });
  });

  group('streamingUrl', () {
    test('prefers the default rendition', () {
      final file = PikPakFile.fromJson({
        'web_content_link': 'https://download/fallback',
        'medias': [
          {'is_origin': true, 'link': {'url': 'https://origin'}},
          {'is_default': true, 'link': {'url': 'https://default'}},
        ],
      });

      expect(file.streamingUrl, 'https://default');
    });

    test('falls back to the original when nothing is marked default', () {
      final file = PikPakFile.fromJson({
        'medias': [
          {'link': {'url': 'https://other'}},
          {'is_origin': true, 'link': {'url': 'https://origin'}},
        ],
      });

      expect(file.streamingUrl, 'https://origin');
    });

    test('falls back to web_content_link when medias carry no url', () {
      final file = PikPakFile.fromJson({
        'web_content_link': 'https://download/fallback',
        'medias': [
          {'is_default': true, 'link': {'url': ''}},
        ],
      });

      expect(file.streamingUrl, 'https://download/fallback');
    });

    test('null when PikPak gave us neither', () {
      expect(PikPakFile.fromJson({'id': '1'}).streamingUrl, isNull);
      expect(
        PikPakFile.fromJson({'web_content_link': ''}).streamingUrl,
        isNull,
      );
    });
  });

  group('listFromJson', () {
    test('unwraps the files array PikPak wraps listings in', () {
      final files = PikPakFile.listFromJson({
        'files': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      });

      expect(files.map((f) => f.id), ['a', 'b']);
    });

    test('takes a bare array too', () {
      expect(PikPakFile.listFromJson([{'id': 'a'}]).single.id, 'a');
    });

    test('a listing with no files is empty, not null', () {
      expect(PikPakFile.listFromJson({}), isEmpty);
      expect(PikPakFile.listFromJson(null), isEmpty);
    });
  });

  group('PikPakTask', () {
    test('unwraps the task envelope addOfflineDownload returns', () {
      final task = PikPakTask.fromJson({
        'task': {
          'id': 't1',
          'file_id': 'f1',
          'phase': 'PHASE_TYPE_RUNNING',
          'progress': '40',
        },
      });

      expect(task.id, 't1');
      expect(task.fileId, 'f1');
      expect(task.isRunning, isTrue);
      expect(task.progress, 40);
    });

    test('reads a bare task, which is what getTaskStatus returns', () {
      final task = PikPakTask.fromJson({
        'id': 't2',
        'phase': 'PHASE_TYPE_COMPLETE',
      });

      expect(task.id, 't2');
      expect(task.isComplete, isTrue);
      expect(task.progress, 0);
    });

    test('a failed task carries PikPak\'s own message', () {
      final task = PikPakTask.fromJson({
        'phase': 'PHASE_TYPE_ERROR',
        'message': 'file is too large',
      });

      expect(task.hasFailed, isTrue);
      expect(task.message, 'file is too large');
    });
  });
}
