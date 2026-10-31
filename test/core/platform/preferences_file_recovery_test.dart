// A Windows user's app stopped starting with "FormatException: Unexpected
// character (at character 1)" followed by NUL boxes: shared_preferences.json
// had been left zero-filled by an interrupted write, and the Windows/Linux
// plugin parses it with no guard on every launch.

import 'dart:convert';
import 'dart:io';

import 'package:debrify/core/platform/preferences_file_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File prefs;
  late File backup;
  late File corrupt;
  late File temp;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prefs-recovery');
    prefs = File('${dir.path}${Platform.pathSeparator}shared_preferences.json');
    backup = File('${prefs.path}.bak');
    corrupt = File('${prefs.path}.corrupt');
    temp = File('${prefs.path}.bak.tmp');
  });
  tearDown(() => dir.delete(recursive: true));

  const good = '{"flutter.theme":"dark"}';

  test('no file yet', () async {
    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.missing,
    );
    expect(await backup.exists(), isFalse);
  });

  test('a good file is kept and backed up', () async {
    await prefs.writeAsString(good);

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.valid,
    );
    expect(await prefs.readAsString(), good);
    expect(await backup.readAsString(), good);
  });

  test('a zero-filled file is replaced by the last good backup', () async {
    await prefs.writeAsString(good);
    await recoverPreferencesFile(dir, allowReset: true);
    await prefs.writeAsBytes(List.filled(512, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.restored,
    );
    expect(jsonDecode(await prefs.readAsString()), {'flutter.theme': 'dark'});
    expect(await corrupt.readAsBytes(), List.filled(512, 0));
  });

  test('without a good backup the app starts fresh', () async {
    await prefs.writeAsBytes(List.filled(64, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.reset,
    );
    expect(await prefs.exists(), isFalse);
    expect(await corrupt.exists(), isTrue);
  });

  test('where starting fresh is unsafe, the file is left alone', () async {
    // Linux keeps its device key in preferences: a fresh start would mint a
    // new key and strand every sealed credential.
    await prefs.writeAsBytes(List.filled(64, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: false),
      PreferencesFileRecovery.kept,
    );
    expect(await prefs.readAsBytes(), List.filled(64, 0));
    expect(await corrupt.exists(), isFalse);
  });

  test('a backup restores even where starting fresh is unsafe', () async {
    await backup.writeAsString(good);
    await prefs.writeAsBytes(List.filled(64, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: false),
      PreferencesFileRecovery.restored,
    );
    expect(await prefs.readAsString(), good);
    expect(await backup.readAsString(), good);
  });

  test('a later good launch refreshes an existing backup', () async {
    await backup.writeAsString('{"old":true}');
    await prefs.writeAsString(good);

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.valid,
    );
    expect(await backup.readAsString(), good);
  });

  test('no staging file is left after a backup or a restore', () async {
    await prefs.writeAsString(good);
    await recoverPreferencesFile(dir, allowReset: true);
    expect(await temp.exists(), isFalse);

    await prefs.writeAsBytes(List.filled(8, 0));
    await recoverPreferencesFile(dir, allowReset: true);
    expect(await temp.exists(), isFalse);
  });

  test('a restore interrupted between its renames is finished', () async {
    // The bad file was set aside but the staged backup never moved in.
    await corrupt.writeAsBytes(List.filled(8, 0));
    await temp.writeAsString(good);
    await backup.writeAsString(good);

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.restored,
    );
    expect(await prefs.readAsString(), good);
  });

  test('a backup without the required key does not count', () async {
    // Linux: a backup from before the device key existed would mint a new
    // key on restore.
    const key = 'flutter.profiles_linux_wrapped_key_v1';
    await backup.writeAsString(good);
    await prefs.writeAsBytes(List.filled(8, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: false, backupMustHold: key),
      PreferencesFileRecovery.kept,
    );

    await backup.writeAsString('{"$key":"sealed"}');
    expect(
      await recoverPreferencesFile(dir, allowReset: false, backupMustHold: key),
      PreferencesFileRecovery.restored,
    );
  });

  test('a corrupt backup is never restored', () async {
    await backup.writeAsString('{"flutter.th');
    await prefs.writeAsBytes(List.filled(64, 0));

    expect(
      await recoverPreferencesFile(dir, allowReset: true),
      PreferencesFileRecovery.reset,
    );
    expect(await prefs.exists(), isFalse);
  });

  for (final (label, bytes) in [
    ('an empty file', <int>[]),
    ('a truncated write', utf8.encode('{"flutter.theme":"da')),
    ('bytes that are not UTF-8', [0x7b, 0xff, 0xfe, 0x7d]),
    ('JSON that is not a map', utf8.encode('[]')),
  ]) {
    test('$label counts as unreadable', () async {
      await backup.writeAsString(good);
      await prefs.writeAsBytes(bytes);

      expect(
        await recoverPreferencesFile(dir, allowReset: true),
        PreferencesFileRecovery.restored,
      );
      expect(await prefs.readAsString(), good);
    });
  }
}
