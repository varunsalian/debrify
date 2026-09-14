import '../../models/webdav_item.dart';
import '../webdav_sync/webdav_sync_binding_store.dart';
import '../webdav_sync/webdav_sync_feature.dart';
import '../webdav_sync/webdav_sync_setup_authorization.dart';

/// Local selection ID, not a new wire command. Only the server login is sent;
/// the receiver discovers the sync folder through its existing setup flow.
const remoteWebDavSyncAccountId = 'webdav_sync_account';

Future<WebDavConfig?> readRemoteWebDavSyncAccount({
  WebDavSyncBindingStore? store,
  WebDavSyncSetupAuthorization? authorization,
}) async {
  if (!WebDavSyncFeature.enabled) return null;
  final access = authorization ?? const ProfileWebDavSyncSetupAuthorization();
  return access.runForAdminSession((beforeSend) async {
    final bindings = store ?? WebDavSyncBindingStore();
    final snapshot = await bindings.load();
    if (WebDavSyncBindingStore.logoutPending(snapshot)) return null;
    // An uncommitted setup candidate is not the user's configured account.
    final binding = snapshot.activeBinding;
    if (binding == null) return null;
    final secrets = await bindings.readSecrets(binding);
    await beforeSend?.call();
    final refreshed = await bindings.load();
    if (WebDavSyncBindingStore.logoutPending(refreshed)) return null;
    final current = refreshed.activeBinding;
    if (current?.id != binding.id ||
        current?.updatedAt != binding.updatedAt ||
        current?.sealedSecrets != binding.sealedSecrets) {
      throw StateError('WebDAV sync account changed');
    }
    await beforeSend?.call();
    // Authorization itself can yield while logout starts. Check the complete
    // store again, not only binding fields (logout changes namespace values).
    final finalSnapshot = await bindings.load();
    if (WebDavSyncBindingStore.logoutPending(finalSnapshot)) return null;
    final finalBinding = finalSnapshot.activeBinding;
    if (finalBinding?.id != binding.id ||
        finalBinding?.updatedAt != binding.updatedAt ||
        finalBinding?.sealedSecrets != binding.sealedSecrets) {
      throw StateError('WebDAV sync account changed');
    }
    return WebDavConfig(
      id: remoteWebDavSyncAccountId,
      name: binding.location.serverName,
      baseUrl: binding.location.endpoint.toString(),
      username: secrets.username,
      password: secrets.password,
    );
  });
}
