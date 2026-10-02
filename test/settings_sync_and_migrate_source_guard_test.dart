import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final adaptive = File('lib/screens/settings_screen.dart').readAsStringSync();
  final categories = File(
    'lib/features/settings/presentation/settings_categories.dart',
  ).readAsStringSync();
  final categoryBody = File(
    'lib/features/settings/presentation/settings_spotlight_category.dart',
  ).readAsStringSync();
  final classic = File(
    'lib/features/settings/presentation/settings_classic_layout.dart',
  ).readAsStringSync();
  final tv = File(
    'lib/screens/settings/settings_tv_layout.dart',
  ).readAsStringSync();
  final page = File(
    'lib/screens/settings/sync_and_migrate_page.dart',
  ).readAsStringSync();

  test('adaptive, TV, and search surfaces all register Sync and Migrate', () {
    expect(categories, contains("label: 'Sync and Migrate'"));
    expect(
      adaptive,
      contains("SettingsRows.syncAndMigrate,\n        'Sync and Migrate'"),
    );
    expect(classic, contains("title: 'Sync and Migrate'"));
    expect(
      tv,
      contains("'Sync and Migrate',\n    'Sync across devices with WebDAV'"),
    );
    expect(classic, contains('SettingsRows.syncAndMigrate'));
    final allOwners = [
      adaptive,
      page,
      ...Directory('lib/features/settings')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync()),
    ].join('\n');
    expect(allOwners, isNot(contains('SettingsRows.createWebDavBackup')));
    expect(allOwners, isNot(contains('SettingsRows.restoreWebDavBackup')));
  });

  test('index-based category switches preserve the destructive tail', () {
    expect(
      categoryBody,
      matches(
        RegExp(
          r'case 13:[\s\S]*?SettingsRows\.syncAndMigrate[\s\S]*?case 14:[\s\S]*?SettingsRows\.downloadLocation[\s\S]*?case 15:[\s\S]*?SettingsRows\.autoUpdate[\s\S]*?case 16:[\s\S]*?SettingsRows\.resetDebrify',
        ),
      ),
    );
    expect(
      tv,
      matches(
        RegExp(
          r'case 13: // Sync and Migrate[\s\S]*?case 14: // Data & Backup[\s\S]*?case 15: // About[\s\S]*?case 16: // Danger Zone',
        ),
      ),
    );
  });
}
