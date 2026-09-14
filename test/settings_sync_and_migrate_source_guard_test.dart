import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final adaptive = File('lib/screens/settings_screen.dart').readAsStringSync();
  final tv = File(
    'lib/screens/settings/settings_tv_layout.dart',
  ).readAsStringSync();
  final page = File(
    'lib/screens/settings/sync_and_migrate_page.dart',
  ).readAsStringSync();

  test('adaptive, TV, and search surfaces all register Sync and Migrate', () {
    expect(adaptive, contains("label: 'Sync and Migrate'"));
    expect(
      adaptive,
      contains("SettingsRows.syncAndMigrate,\n        'Sync and Migrate'"),
    );
    expect(adaptive, contains("title: 'Sync and Migrate'"));
    expect(
      tv,
      contains("'Sync and Migrate',\n    'Sync across devices with WebDAV'"),
    );
    expect(page, isNot(contains('SettingsRows.createWebDavBackup')));
    expect(page, isNot(contains('SettingsRows.restoreWebDavBackup')));
  });

  test('index-based category switches preserve the destructive tail', () {
    expect(
      adaptive,
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
