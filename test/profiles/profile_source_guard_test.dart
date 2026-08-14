import 'dart:io';

import 'package:debrify/services/profiles/privacy_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'direct SharedPreferences opens stay inside reviewed adapters/stores',
    () {
      const reviewedCallCounts = <String, int>{
        'lib/services/profiles/profile_bootstrap.dart': 1,
        'lib/services/profiles/profile_preferences.dart': 3,
        'lib/services/profiles/profile_migration_service.dart': 1,
        'lib/services/profiles/profile_package_service.dart': 1,
        'lib/services/profiles/profile_data_generation.dart': 5,
        'lib/services/profiles/native_profile_projection.dart': 3,
        'lib/services/profiles/device_key_provider.dart': 5,
        // These two perform reviewed whole-store durability/reset operations;
        // neither exposes a generic preference API to feature code.
        'lib/services/profiles/profile_registry.dart': 2,
        'lib/services/profiles/profile_device_reset_service.dart': 1,
        'lib/services/secret_vault.dart': 1,
        'lib/services/remote_control/remote_pairing_store.dart': 7,
        'lib/services/android_download_history.dart': 1,
        'lib/services/desktop_schedule_service.dart': 2,
      };
      final violations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final source = entity.readAsStringSync();
        final count = 'SharedPreferences.getInstance()'
            .allMatches(source)
            .length;
        final reviewedCount = reviewedCallCounts[path];
        if (reviewedCount != null) {
          if (count != reviewedCount) violations.add('$path:$count');
        } else if (count != 0) {
          violations.add(path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Use ProfilePreferences or register a reviewed device/job store.',
      );
    },
  );

  test('profile-owned fixed database names stay in scoped path adapters', () {
    const allowed = <String>{
      // These two legacy services are migrated by ProfileDatabasePaths. The
      // allowlist is intentionally exact so another bypass cannot appear.
      'lib/services/debrify_tv_database.dart',
      'lib/services/iptv_catalog_db.dart',
      'lib/services/profiles/profile_registry.dart',
      'lib/services/profiles/profile_bootstrap.dart',
      'lib/services/profiles/profile_migration_service.dart',
      'lib/services/profiles/profile_database_snapshot.dart',
    };
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (allowed.contains(path)) continue;
      final source = entity.readAsStringSync();
      if (source.contains("'debrify_tv.db'") ||
          source.contains("'iptv_catalog.db'")) {
        violations.add(path);
      }
    }
    expect(violations, isEmpty);
  });

  test('profile editor keeps feature controls hidden behind one switch', () {
    final source = File(
      'lib/screens/profiles/edit_profile_screen.dart',
    ).readAsStringSync();
    // The switch moved onto the widget (public, @visibleForTesting) when the
    // save rule was extracted into EditProfileScreen.policyFor.
    expect(
      source,
      contains('static const bool showFeaturePolicyControls = false;'),
    );
    expect(
      'if (EditProfileScreen.showFeaturePolicyControls) ...['
          .allMatches(source)
          .length,
      1,
      reason: 'The existing feature controls must stay present but hidden.',
    );
    expect(
      source,
      contains('ProfilePolicy.allAllowedFor(role)'),
      reason:
          'policyFor must select the full role policy while the switch is off.',
    );
    expect(
      source,
      contains('ProfilePolicy.allAllowedFor(_role)'),
      reason: 'Initialization must select the full role policy too.',
    );
  });

  test(
    'search result preservation is owned by the mounted profile session',
    () {
      final source = File('lib/screens/search_screen.dart').readAsStringSync();
      expect(
        source,
        contains('ProfileSessionMemory<_KwPreservedState> _kwPreserved'),
      );
      expect(
        source,
        contains('_profileSessionOwner = ProfileSessionMemory.captureOwner()'),
      );
      expect(source, contains('_kwPreserved.take('));
      expect(source, contains('_kwPreserved.store('));
      expect(
        source,
        isNot(contains('static _KwPreservedState? _kwPreserved')),
        reason: 'Raw screen statics can carry content across profile switches.',
      );
    },
  );

  test(
    'Android protects recents before pause and notifications stay generic',
    () {
      final activity = File(
        'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
      ).readAsStringSync();
      final onPause = activity.substring(
        activity.indexOf('override fun onPause()'),
        activity.indexOf('override fun onUserLeaveHint()'),
      );
      expect(onPause, contains('shouldProtectWhenBackgrounded(this)'));
      expect(
        onPause.indexOf('window.addFlags'),
        lessThan(onPause.indexOf('super.onPause()')),
        reason: 'FLAG_SECURE must precede Android task-snapshot capture.',
      );

      final download = File(
        'android/app/src/main/kotlin/com/debrify/app/download/'
        'MediaStoreDownloadService.kt',
      ).readAsStringSync();
      final recording = File(
        'android/app/src/main/kotlin/com/debrify/app/recording/'
        'LiveRecordingService.kt',
      ).readAsStringSync();
      final alarm = File(
        'android/app/src/main/kotlin/com/debrify/app/recording/'
        'RecordingAlarmReceiver.kt',
      ).readAsStringSync();
      expect(download, isNot(contains('.setContentTitle(state.fileName)')));
      expect(
        download,
        isNot(contains('.setSubText(if (completed) null else title)')),
      );
      expect(download, isNot(contains('.setSummaryText(title)')));
      expect(recording, isNot(contains('.setContentTitle(state.channelName)')));
      expect(
        recording,
        isNot(contains('.setSubText(if (completed) null else title)')),
      );
      expect(alarm, isNot(contains(r'${schedule.channelName} —')));
    },
  );

  test('native subtitle fonts follow the active profile scope', () {
    final fontManager = File(
      'android/app/src/main/kotlin/com/debrify/app/util/'
      'SubtitleFontManager.kt',
    ).readAsStringSync();
    final settings = File(
      'android/app/src/main/kotlin/com/debrify/app/util/SubtitleSettings.kt',
    ).readAsStringSync();

    expect(
      fontManager,
      contains(
        'ProfilePreferenceProjection.scopedPreferences(context, PREFS_NAME)',
      ),
    );
    expect(
      fontManager,
      contains('active.profileId != MIGRATED_ADMIN_PROFILE_ID'),
    );
    expect(
      settings,
      contains('ProfilePreferenceProjection.scopedPreferences('),
    );
  });

  test('Debrify TV access stays behind the profile-switch scope gate', () {
    final files = <String>[
      'lib/services/debrify_tv_cache_service.dart',
      'lib/services/debrify_tv_repository.dart',
      'lib/services/iptv_media_store.dart',
    ];
    final directWrite = RegExp(
      r'await\s+db\.(?:insert|update|delete|execute|rawInsert|rawUpdate|rawDelete)\s*\(',
    );
    final rawHandle = RegExp(
      r'DebrifyTvDatabase\s*\.\s*instance\s*\.\s*database',
    );
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        directWrite.hasMatch(source),
        isFalse,
        reason: '$path can race DebrifyTvDatabase.closeScope()',
      );
      expect(
        rawHandle.hasMatch(source),
        isFalse,
        reason: '$path reads can race DebrifyTvDatabase.closeScope()',
      );
    }
  });

  test('profile, download, deep-link, and remote logs stay redacted', () {
    final files = <File>[
      ...Directory('lib/services')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/widgets/remote')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/screens/settings')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final violations = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      if (RegExp(r'\bprint\s*\(').hasMatch(source)) {
        violations.add(file.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Service diagnostics must pass through the redacted debug sink.',
    );
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('PrivacyLog.install();'));
    expect(
      'debugPrint ='.allMatches(main).length,
      1,
      reason: 'Do not replace the installed process-wide privacy sink.',
    );
  });

  test('privacy sink removes sentinel URLs, tokens, IPs, and payloads', () {
    const sentinel = 'PRIVATE_SENTINEL';
    final redacted = PrivacyLog.redact(
      'request failed: https://10.20.30.40:8080/path?token=$sentinel '
      'authorization=Bearer-$sentinel payload: {"key":"$sentinel"}',
    );
    expect(redacted, isNot(contains(sentinel)));
    expect(redacted, isNot(contains('10.20.30.40')));
    expect(redacted, isNot(contains('https://')));
  });
}
