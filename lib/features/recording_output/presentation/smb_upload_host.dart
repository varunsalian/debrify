// Starts the SMB recording upload for the app's lifetime. Sits inside the
// root ProviderScope; renders its child unchanged.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/smb_upload_providers.dart';

class SmbUploadHost extends ConsumerStatefulWidget {
  const SmbUploadHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SmbUploadHost> createState() => _SmbUploadHostState();
}

class _SmbUploadHostState extends ConsumerState<SmbUploadHost> {
  @override
  void initState() {
    super.initState();
    // The coordinator's own timers wait 30 s before the first pass, so
    // start-up work is never delayed. Disabled targets make each pass a no-op.
    if (ref.read(smbUploadSupportedProvider)) {
      ref.read(smbUploadCoordinatorProvider).start();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
