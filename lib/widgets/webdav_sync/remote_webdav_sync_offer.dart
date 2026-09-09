import 'package:flutter/material.dart';

import '../../models/webdav_item.dart';
import '../../services/webdav_protocol_client.dart';
import '../../services/webdav_sync/webdav_sync_connect_controller.dart';
import '../../services/webdav_sync/webdav_sync_runtime.dart';
import '../../services/webdav_sync/webdav_sync_setup_authorization.dart';
import 'webdav_foreground_sync.dart';

typedef RemoteWebDavConnect =
    Future<WebDavSyncConnectOutcome> Function(
      WebDavSyncLoginCredentials credentials,
      Future<bool> Function() confirmReplacement,
      ValueChanged<String> updateStage,
    );

/// Optional account setup after credentials have already been imported. Its
/// outcome is deliberately separate from the remote configuration receipt.
Future<void> offerRemoteWebDavSync(
  BuildContext context,
  List<WebDavConfig> servers, {
  required bool Function() isCurrent,
  RemoteWebDavConnect? connect,
  Future<void> Function()? requireAdmin,
  VoidCallback? pause,
  Future<void> Function()? resume,
}) async {
  if (servers.isEmpty || !context.mounted || !isCurrent()) return;
  var paused = false;
  try {
    await (requireAdmin ??
        const ProfileWebDavSyncSetupAuthorization().requireAdmin)();
    if (!context.mounted || !isCurrent()) return;
    final selected = await showDialog<WebDavConfig>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable WebDAV Sync?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your server credentials are saved. Choose an account '
                'to register this device and start sync. This can replace your '
                'current sync connection. Existing remote profiles require '
                'another confirmation before replacing local data.',
              ),
              const SizedBox(height: 16),
              for (final server in servers)
                ListTile(
                  title: Text(server.name),
                  trailing: const Icon(Icons.sync),
                  onTap: () => Navigator.of(dialogContext).pop(server),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted || !isCurrent()) return;
    await (requireAdmin ??
        const ProfileWebDavSyncSetupAuthorization().requireAdmin)();
    if (!context.mounted || !isCurrent()) return;
    (pause ?? WebDavSyncRuntime.instance.pauseForReconfiguration)();
    paused = true;
    final controller = connect == null
        ? createWebDavSyncConnectController()
        : null;
    final outcome = await runWebDavForegroundSync(
      context,
      stage: 'Preparing WebDAV sync…',
      progressLimit: null,
      operation: (update) async {
        Future<bool> confirmReplacement() async {
          if (!context.mounted || !isCurrent()) return false;
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Use sync data from this account?'),
              content: const Text(
                'Existing profiles and connections on this '
                'device, including the configuration just imported, will be '
                'replaced by this account’s sync data. Create a manual backup '
                'first if you want to keep them.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Use sync data'),
                ),
              ],
            ),
          );
          return confirmed == true && isCurrent();
        }

        final credentials = WebDavSyncLoginCredentials(
          endpoint: WebDavProtocolClient.parseEndpoint(selected.baseUrl),
          username: selected.username,
          password: selected.password,
          serverName: selected.name,
        );
        return connect != null
            ? connect(credentials, confirmReplacement, update)
            : controller!.connect(
                credentials: credentials,
                confirmExistingReplacement: confirmReplacement,
                onProgress: update,
              );
      },
    );
    if (!context.mounted) return;
    final message = switch (outcome) {
      WebDavSyncConnectActive() => 'WebDAV Sync connected; first sync complete',
      WebDavSyncConnectAdoptedFinishing() => 'WebDAV Sync setup is finishing',
      WebDavSyncConnectCancelled() =>
        'Sync setup cancelled; server credentials remain saved',
      WebDavSyncConnectPreHandoffFailure() =>
        'Server credentials saved, but sync setup failed. Retry in Sync & Migrate.',
      WebDavSyncConnectPostHandoffFailure() =>
        'Sync data was adopted, but reconnection is pending. Check Sync & Migrate.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  } catch (error) {
    debugPrint('Remote WebDAV sync setup failed (${error.runtimeType})');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server credentials saved. Configure WebDAV Sync from an unlocked Admin profile in Sync & Migrate.',
          ),
        ),
      );
    }
  } finally {
    if (paused) {
      try {
        await (resume ??
            WebDavSyncRuntime.instance.resumeAfterReconfiguration)();
      } catch (_) {
        // Import is already committed. Runtime retains retry/recovery state.
      }
    }
  }
}
