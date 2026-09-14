import '../../models/webdav_item.dart';

/// The existing receiver deduplication contract. Keep outbound precedence in
/// sync with this key so the receiver cannot discard the preferred login.
String remoteWebDavEndpointKey(String url) =>
    url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');

bool sameRemoteWebDavLogin(WebDavConfig a, WebDavConfig b) =>
    remoteWebDavEndpointKey(a.baseUrl) == remoteWebDavEndpointKey(b.baseUrl) &&
    a.username == b.username &&
    a.password == b.password;

List<WebDavConfig> preferRemoteWebDavSyncAccount(
  Iterable<WebDavConfig> mediaServers,
  WebDavConfig syncAccount,
) {
  final syncKey = remoteWebDavEndpointKey(syncAccount.baseUrl);
  return [
    for (final server in mediaServers)
      if (remoteWebDavEndpointKey(server.baseUrl) != syncKey) server,
    syncAccount,
  ];
}
