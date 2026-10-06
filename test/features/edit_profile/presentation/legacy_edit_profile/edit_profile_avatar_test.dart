import 'dart:async';
import 'dart:io';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/edit_profile_fixture.dart';

void main() {
  for (final error in [
    'declared',
    'inline',
    'streamed',
    'unreadable',
    'platform',
    'missing',
  ]) {
    testWidgets('R picker $error rejects without preview', (t) async {
      await editProfileCase(t, (f) async {
        final max = ProfileAvatarIngest.maxInputBytes;
        String? path;
        if (error == 'streamed') {
          path = '${f.root.path}/large.png';
          await t.runAsync(() => File(path!).writeAsBytes(Uint8List(max + 1)));
        } else if (error == 'unreadable') {
          path = '${f.root.path}/absent.png';
        }
        f.picker.response = () async {
          if (error == 'platform') throw PlatformException(code: 'unsupported');
          return FilePickerResult([
            PlatformFile(
              name: 'avatar.png',
              size: error == 'declared' ? max + 1 : 0,
              path: path,
              bytes: error == 'inline' ? Uint8List(max + 1) : null,
            ),
          ]);
        };
        await f.mount(t);
        await f.tap(t, find.text('Choose image or GIF (this device only)'));
        final message = ['declared', 'inline', 'streamed'].contains(error)
            ? 'That image is too large to open. Choose one under 12 MB.'
            : error == 'platform'
            ? 'The image picker is not available.'
            : error == 'missing'
            ? 'That file could not be read.'
            : 'That image could not be opened.';
        await f.until(t, () => find.text(message).evaluate().isNotEmpty);
        expect(find.text('Discard picked image'), findsNothing);
        expect(f.picker.type, FileType.any);
        expect(f.picker.withData, isFalse);
      });
    });
  }
  testWidgets('R valid PNG preview discards without disk publication', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      f.picker.response = () async => FilePickerResult([
        PlatformFile(name: 'avatar.png', size: 0, bytes: editProfilePng()),
      ]);
      await f.mount(t);
      await f.tap(t, find.text('Choose image or GIF (this device only)'));
      await f.until(
        t,
        () => find.text('Discard picked image').evaluate().isNotEmpty,
      );
      expect(find.byType(Image), findsWidgets);
      expect(await t.runAsync(() => f.registry.listProfiles()), hasLength(1));
      final files = (await t.runAsync(
        () => f.root.list(recursive: true).toList(),
      ))!;
      expect(
        files.whereType<File>().where((file) => file.path.endsWith('.png')),
        isEmpty,
        reason: 'preview does not publish avatar files',
      );
      await f.tap(t, find.text('Discard picked image'));
      expect(find.text('Discard picked image'), findsNothing);
    });
  });
  for (final editing in [false, true]) {
    testWidgets(
      'O picked PNG ${editing ? "edit" : "create"} publishes file key and bytes',
      (t) async {
        await editProfileCase(t, (f) async {
          final target = editing
              ? await t.runAsync(() => f.profile('Target'))
              : null;
          f.picker.response = () async => FilePickerResult([
            PlatformFile(name: 'avatar.png', size: 0, bytes: editProfilePng()),
          ]);
          await f.mount(t, target: target);
          await f.name(t, 'With image');
          await f.tap(t, find.text('Choose image or GIF (this device only)'));
          await f.until(
            t,
            () => find.text('Discard picked image').evaluate().isNotEmpty,
          );
          await f.save(t);
          await f.until(t, () => f.popped);
          final rows = (await t.runAsync(() => f.registry.listProfiles()))!;
          final row = rows.singleWhere((p) => p.id != f.admin.id);
          expect(
            row.avatarKey,
            startsWith('file:'),
            reason: 'picked image persisted',
          );
          final files = (await t.runAsync(
            () => f.root.list(recursive: true).toList(),
          ))!;
          expect(
            files.whereType<File>().where((x) => x.path.endsWith('.png')),
            isNotEmpty,
          );
          expect(
            await t.runAsync(f.avatarIntents),
            isNot(contains(row.id)),
            reason: 'latest committed intent finalized',
          );
        });
      },
    );
  }
  testWidgets('R picker started before held save drops late bytes', (t) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      final picked = Completer<FilePickerResult?>();
      f.picker.response = () => picked.future;
      await f.mount(t, target: target);
      await f.name(t, 'Saving');
      final dynamic startPicker = t
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Choose image or GIF (this device only)'),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed;
      late Future<void> pickerDone;
      await t.runAsync(() async {
        pickerDone = startPicker() as Future<void>;
      });
      await f.settle(t);
      await f.pin(t, '1234');
      f.pins.release = Completer<void>();
      await f.save(t);
      await f.until(t, () => f.pins.written);
      picked.complete(
        FilePickerResult([
          PlatformFile(name: 'avatar.png', size: 0, bytes: editProfilePng()),
        ]),
      );
      await t.runAsync(() => pickerDone);
      await t.pump();
      expect(
        find.text('Discard picked image'),
        findsNothing,
        reason: 'saving drops late picker',
      );
      f.pins.release!.complete();
      await f.until(t, () => find.text('I saved it').evaluate().isNotEmpty);
      expect(
        (await t.runAsync(() => f.registry.getProfile(target.id)))!.avatarKey,
        'person',
      );
      await f.tap(t, find.text('I saved it'));
      await f.until(t, () => f.popped);
    });
  });
}
