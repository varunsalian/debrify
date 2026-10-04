/// Normalize a user-entered Xtream server URL: add a scheme when missing,
/// strip a trailing get.php/player_api.php endpoint and any query, and drop a
/// trailing slash — keeping a base path so panels behind a path prefix still
/// work. Returns null when the input has no valid host. Shared by add and
/// edit so both accept the same pasted forms.
String? normalizeXtreamServerUrl(String raw) {
  var serverUrl = raw.trim();
  if (serverUrl.isEmpty) return null;
  if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
    serverUrl = 'http://$serverUrl';
  }
  final serverUri = Uri.tryParse(serverUrl);
  if (serverUri == null || serverUri.host.isEmpty) return null;
  final pathSegments = serverUri.pathSegments
      .where((s) => s.isNotEmpty)
      .toList();
  if (pathSegments.isNotEmpty && pathSegments.last.endsWith('.php')) {
    pathSegments.removeLast();
  }
  serverUrl = Uri(
    scheme: serverUri.scheme,
    // Keep basic-auth credentials if the pasted URL carried them.
    userInfo: serverUri.userInfo.isEmpty ? null : serverUri.userInfo,
    host: serverUri.host,
    port: serverUri.hasPort ? serverUri.port : null,
    pathSegments: pathSegments,
  ).toString();
  if (serverUrl.endsWith('/')) {
    serverUrl = serverUrl.substring(0, serverUrl.length - 1);
  }
  return serverUrl;
}
