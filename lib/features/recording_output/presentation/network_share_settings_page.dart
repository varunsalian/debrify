// "Network share": the SMB share recordings are written to (or copied to),
// on a page of its own so the Recordings page and the recording settings can
// both lead straight to it.

import 'package:flutter/material.dart';

import 'smb_upload_section.dart';

class NetworkShareSettingsPage extends StatelessWidget {
  const NetworkShareSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network share')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Record to a folder on a NAS or another computer on your '
              'network (SMB). Recordings written straight to the share need '
              'no space on this device, and play from the Recordings page.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SmbUploadSection(),
        ],
      ),
    );
  }
}
