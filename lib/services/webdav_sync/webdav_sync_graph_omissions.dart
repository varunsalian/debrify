import '../profiles/portable_profile_package.dart';
import '../profiles/profile_database_snapshot.dart';

/// The only omissions a WebDAV device graph may carry.
///
/// Most entries are permanent device-local exclusions. The two database
/// entries are a bounded fallback: when a complete SQLite snapshot cannot fit
/// the portable envelope, IPTV catalogue/EPG rows and Debrify TV
/// channels/hash pools are removed from a scratch copy. IPTV connection
/// resources and the durable database tables remain in the package.
abstract final class WebDavSyncGraphOmissionPolicy {
  static const String rebuildableDatabaseCachesKey =
      'rebuildableDatabaseCachesOmitted';

  static const Set<String> _deviceLocalKeys = <String>{
    'downloadAndRecordingBinaries',
    'activeJobsAndSchedules',
    'deviceWidePreferencesAndRuntimeState',
    'devicePathsAndOsGrants',
    'remoteIdentityAndPeers',
    'pinAttemptCountersAndLockout',
    'deviceKeysExecutablesCommandsAndCustomSchemes',
    'localFilesystemBindingsAndResolvedPlaybackSources',
    'transientPreferenceAndFileCaches',
  };

  /// Rejects every unknown or malformed omission. Adding a new exporter
  /// omission therefore remains fail-closed until this policy is reviewed.
  static void requireSupported(PortableProfilePackage package) {
    for (final entry in package.omissions.entries) {
      if (_deviceLocalKeys.contains(entry.key)) {
        if (entry.value != true) {
          throw const FormatException(
            'WebDAV sync graph has malformed device-local omissions',
          );
        }
        continue;
      }
      if (entry.key == rebuildableDatabaseCachesKey) {
        if (entry.value is! String || (entry.value as String).trim().isEmpty) {
          throw const FormatException(
            'WebDAV sync graph has malformed IPTV cache omissions',
          );
        }
        continue;
      }
      if (entry.key == DebrifyTvBackupOmission.key) {
        final omission = DebrifyTvBackupOmission.fromOmissions(
          package.omissions,
        );
        if (omission == null ||
            omission.profilesAffected > package.profiles.length) {
          throw const FormatException(
            'WebDAV sync graph has malformed Debrify TV omissions',
          );
        }
        continue;
      }
      throw FormatException(
        'WebDAV sync graph has an unsupported omission: ${entry.key}',
      );
    }
  }
}
