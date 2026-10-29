import 'package:dart_smb2/dart_smb2.dart';
import 'package:debrify/features/recording_output/application/smb_upload_policy.dart';
import 'package:debrify/features/recording_output/data/dart_smb2_connector.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dart_smb2 errors map to upload failure kinds', () {
    expect(smbFailureKindOf(Smb2ErrorType.auth), SmbFailureKind.auth);
    expect(
      smbFailureKindOf(Smb2ErrorType.fileNotFound),
      SmbFailureKind.notFound,
    );
    expect(
      smbFailureKindOf(Smb2ErrorType.notADirectory),
      SmbFailureKind.notFound,
    );
    expect(
      smbFailureKindOf(Smb2ErrorType.accessDenied),
      SmbFailureKind.accessDenied,
    );
    expect(smbFailureKindOf(Smb2ErrorType.diskFull), SmbFailureKind.noSpace);
    expect(smbFailureKindOf(Smb2ErrorType.connection), SmbFailureKind.network);
    expect(smbFailureKindOf(Smb2ErrorType.timeout), SmbFailureKind.network);
    expect(smbFailureKindOf(Smb2ErrorType.io), SmbFailureKind.other);
  });

  test('transport failures stop a run but are retried later', () {
    // A dropped connection must not give up on a recording for good.
    final kind = smbFailureKindOf(Smb2ErrorType.timeout);
    expect(stopsSmbRun(kind), isTrue);
    expect(isPermanentSmbFailure(kind), isFalse);
  });
}
