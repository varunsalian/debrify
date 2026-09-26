import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingDirectoryPicker extends FilePicker {
  final response = Completer<String?>();
  var calls = 0;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) {
    calls++;
    return response.future;
  }
}

Future<void> advance(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
}

void main() {
  setUpAll(() => FilePicker.platform = PendingDirectoryPicker());
  for (final scenario in [
    'mode',
    'movie_directory',
    'series_directory',
    'profile_directory',
    'active_movie',
    'active_series',
  ]) {
    testWidgets('local binding respects action ownership at $scenario', (
      tester,
    ) async {
      final originalPicker = FilePicker.platform;
      final picker = PendingDirectoryPicker();
      FilePicker.platform = picker;
      final series =
          scenario == 'series_directory' || scenario == 'active_series';
      final staysActive = scenario.startsWith('active_');
      late Directory root;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'local-retirement-fixture-',
        );
        await File('${root.path}/Unmatched.mkv').writeAsBytes([1, 2]);
        if (scenario == 'active_series') {
          final folder = await Directory('${root.path}/Fixture Show').create();
          await File(
            '${folder.path}/Fixture.Show.S01E01.mkv',
          ).writeAsBytes([1, 2]);
        }
      });
      addTearDown(() async {
        FilePicker.platform = originalPicker;
        ProfileSessionMemory.debugReset();
        await root.delete(recursive: true);
      });
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold();
            },
          ),
        ),
      );
      final owner = ProfileSessionMemory.captureOwner();
      var active = true;
      var saves = 0;
      var finished = false;
      bool? result;
      Object? error;
      await tester.runAsync(() async {
        unawaited(
          const SourceBindingBridge()
              .pinLocal(
                page,
                imdbId: 'tt-fixture',
                isMovie: !series,
                title: 'Fixture Show',
                canContinue: () =>
                    active && owner == ProfileSessionMemory.captureOwner(),
                saveBinding: (_) async {
                  saves++;
                  return true;
                },
              )
              .then(
                (value) {
                  result = value;
                  finished = true;
                },
                onError: (Object caught) {
                  error = caught;
                  finished = true;
                },
              ),
        );
      });
      if (!series) {
        await tester.pumpAndSettle();
        if (scenario == 'mode') active = false;
        await tester.tap(find.text('Pick Folder'));
        await tester.pump();
      }
      if (scenario != 'mode') {
        // Retire while the native picker is pending, after the mode sheet closes.
        for (var attempt = 0; attempt < 100 && picker.calls == 0; attempt++) {
          await advance(tester);
        }
        expect(picker.calls, 1);
      }
      if (scenario == 'profile_directory') {
        ProfileSessionMemory.clearAll();
      } else if (!staysActive) {
        active = false;
      }
      await tester.runAsync(() async {
        picker.response.complete(root.path);
      });
      var followupOpened = false;
      // Settle an unexpected legacy dialog too, so a failing baseline does not
      // leave the pending operation behind when its assertion reports the bug.
      for (var attempt = 0; attempt < 100 && !finished; attempt++) {
        await advance(tester);
        final fileChoice = find.text('Unmatched.mkv');
        final guidance = find.text('Choose the Show Folder');
        if (!followupOpened &&
            (fileChoice.evaluate().isNotEmpty ||
                guidance.evaluate().isNotEmpty)) {
          followupOpened = true;
          await tester.pumpAndSettle();
          if (staysActive && fileChoice.evaluate().isNotEmpty) {
            await tester.tap(fileChoice);
          } else {
            Navigator.of(page).pop();
          }
        }
      }
      expect(finished, isTrue);
      expect(error, isNull);
      expect(result, staysActive);
      expect(saves, staysActive ? 1 : 0);
      expect(picker.calls, scenario == 'mode' ? 0 : 1);
      expect(followupOpened, scenario == 'active_movie');
      await tester.pumpAndSettle();
      expect(Navigator.of(page).canPop(), isFalse);
      if (!staysActive) expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
