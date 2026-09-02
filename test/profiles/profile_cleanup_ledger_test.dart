import 'dart:io';

import 'package:debrify/services/profiles/profile_cleanup_ledger.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-cleanup-ledger-');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppStorage.debugOverride(
      documents: Directory(p.join(root.path, 'documents')),
      support: Directory(p.join(root.path, 'support')),
      cache: Directory(p.join(root.path, 'cache')),
    );
  });

  tearDown(() async {
    AppStorage.debugReset();
    if (await root.exists()) {
      // Undo the lock the deferral test installs so the temp dir can go.
      await Process.run('chmod', <String>['-R', 'u+rwx', root.path]);
      await root.delete(recursive: true);
    }
  });

  Future<Directory> profileDirectory(String id) async {
    final directory = Directory(
      p.join((await AppStorage.documents()).path, 'profiles', id),
    );
    await directory.create(recursive: true);
    await File(p.join(directory.path, 'data.bin')).writeAsBytes(<int>[1]);
    return directory;
  }

  test(
    'resume removes a scheduled profile and clears the ledger',
    () async {
      const id = 'profile-gone-v1';
      final directory = await profileDirectory(id);
      await ProfileCleanupLedger.scheduleProfile(id);

      await ProfileCleanupLedger.resume(null);

      expect(await directory.exists(), isFalse);
      // A second resume is a no-op: nothing pending, nothing thrown.
      await ProfileCleanupLedger.resume(null);
    },
    skip: !Platform.isMacOS && !Platform.isLinux,
  );

  test(
    'a deletion the OS refuses is deferred instead of failing boot',
    () async {
      // Issue #49: a locked or read-only file under a OneDrive-synced
      // Documents folder made resume() throw on every launch, and the app
      // never got past the startup failure screen.
      const stuck = 'profile-stuck-v1';
      const clean = 'profile-clean-v1';
      final stuckDirectory = await profileDirectory(stuck);
      final cleanDirectory = await profileDirectory(clean);
      await ProfileCleanupLedger.scheduleProfile(stuck);
      await ProfileCleanupLedger.scheduleProfile(clean);
      // Removing write permission on the parent makes the delete fail with a
      // FileSystemException the same way a Windows sharing violation does.
      await Process.run('chmod', <String>['a-w', stuckDirectory.path]);

      await expectLater(ProfileCleanupLedger.resume(null), completes);

      expect(await stuckDirectory.exists(), isTrue);
      expect(await cleanDirectory.exists(), isFalse);

      // The stuck profile stays pending, so the next launch retries it.
      await Process.run('chmod', <String>['u+w', stuckDirectory.path]);
      await ProfileCleanupLedger.resume(null);
      expect(await stuckDirectory.exists(), isFalse);
    },
    skip: !Platform.isMacOS && !Platform.isLinux,
  );
}
