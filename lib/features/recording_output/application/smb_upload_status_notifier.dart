// Riverpod holder for the upload status the status UI subscribes to. The
// coordinator pushes through publish(); nothing else writes this state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/smb_upload_models.dart';

final class SmbUploadStatusNotifier extends Notifier<SmbUploadStatus> {
  @override
  SmbUploadStatus build() => const SmbUploadStatus();

  void publish(SmbUploadStatus status) => state = status;
}

final smbUploadStatusProvider =
    NotifierProvider<SmbUploadStatusNotifier, SmbUploadStatus>(
      SmbUploadStatusNotifier.new,
    );
