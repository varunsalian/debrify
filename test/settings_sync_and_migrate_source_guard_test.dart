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

  test('adaptive, TV, and search surfaces all register Sync and backup', () {
    expect(adaptive, contains("label: 'Sync and backup'"));
    expect(
      adaptive,
      contains("SettingsRows.syncAndMigrate,\n        'Sync and backup'"),
    );
    expect(adaptive, contains("title: 'Sync and backup'"));
    expect(
      tv,
      contains("'Sync and backup',\n    'Sync across devices with WebDAV'"),
    );
    expect(page, isNot(contains('SettingsRows.createWebDavBackup')));
    expect(page, isNot(contains('SettingsRows.restoreWebDavBackup')));
  });

  test('index-based category switches preserve the destructive tail', () {
    expect(
      adaptive,
      matches(
        RegExp(
          r'case 11:[\s\S]*?SettingsRows\.syncAndMigrate[\s\S]*?case 12:[\s\S]*?SettingsRows\.downloadLocation[\s\S]*?case 13:[\s\S]*?SettingsRows\.autoUpdate[\s\S]*?case 14:[\s\S]*?SettingsRows\.resetDebrify',
        ),
      ),
    );
    expect(
      tv,
      matches(
        RegExp(
          r'case 11: // Sync and Migrate[\s\S]*?case 12: // Data & Backup[\s\S]*?case 13: // About[\s\S]*?case 14: // Danger Zone',
        ),
      ),
    );
  });
}
