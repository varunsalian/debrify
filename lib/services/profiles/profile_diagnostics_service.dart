import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../utils/app_storage.dart';
import 'portable_profile_package.dart';
import 'profile_database_snapshot.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';

class ProfileDiagnosticsService {
  ProfileDiagnosticsService._();

  static Future<Map<String, Object?>> collect(ProfileRegistry registry) async {
    final summary = await registry.privacySafeDiagnostics();
    final databases = <String, String>{};
    if (ProfileRuntime.isProfileCommitted) {
      final scope = ProfileRuntime.capture();
      final documents = await AppStorage.documents();
      for (final name in ProfileDatabaseSnapshot.databaseNames) {
        final file = scope.fileIn(documents, 'documents', name);
        if (!await file.exists()) {
          databases[name] = 'absent';
          continue;
        }
        try {
          final database = await openDatabase(
            file.path,
            readOnly: true,
            singleInstance: false,
          );
          try {
            final result = await database.rawQuery('PRAGMA quick_check');
            databases[name] =
                result.isNotEmpty && result.first.values.first == 'ok'
                ? 'healthy'
                : 'unhealthy';
          } finally {
            await database.close();
          }
        } catch (_) {
          databases[name] = 'unavailable';
        }
      }
    }
    return <String, Object?>{
      'format': 'debrify-profile-diagnostics',
      'version': 1,
      'profilePackageVersion': PortableProfilePackage.version,
      ...summary,
      'activeScopedDatabases': databases,
    };
  }

  static Future<String> collectJson(ProfileRegistry registry) async =>
      const JsonEncoder.withIndent('  ').convert(await collect(registry));
}
