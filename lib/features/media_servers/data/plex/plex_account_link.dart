import 'package:http/http.dart' as http;

import '../../../../models/media_server.dart';
import '../../models/media_server_errors.dart' show MediaServerHttpError;
import '../media_server_http.dart';
import 'plex_request.dart';

/// A plex.tv sign-in code the user enters at plex.tv/link.
class PlexPin {
  const PlexPin({
    required this.id,
    required this.code,
    required this.expiresAt,
  });
  final int id;
  final String code;
  final DateTime expiresAt;
}

/// One address of a server, as plex.tv lists it.
class PlexAccountConnection {
  const PlexAccountConnection({
    required this.uri,
    required this.https,
    required this.local,
    required this.relay,
  });
  final String uri;
  final bool https;
  final bool local;
  final bool relay;
}

/// A Plex Media Server the signed-in account can use. Holds the server's
/// own access token, so it never leaves the data and application layers.
class PlexAccountServer {
  const PlexAccountServer({
    required this.id,
    required this.name,
    required this.owned,
    required this.accessToken,
    required this.connections,
  });
  final String id;
  final String name;
  final bool owned;
  final String accessToken;
  final List<PlexAccountConnection> connections;
}

/// The PIN code still pending sign-in has expired or was never created for
/// this client.
class PlexPinExpired implements Exception {
  const PlexPinExpired();
}

/// plex.tv calls for the PIN sign-in. Never logs tokens, codes, or the
/// location plex.tv adds to its answers.
class PlexAccountLink {
  PlexAccountLink({
    required String clientId,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : this._(
         clientId,
         client ?? http.Client(),
         timeout,
         clock ?? DateTime.now,
       );

  PlexAccountLink._(this.clientId, this._client, Duration timeout, this._clock)
    : _http = MediaServerHttp(_client, timeout: timeout);

  static const _base = 'https://plex.tv/api/v2/';

  final String clientId;
  final http.Client _client;
  final DateTime Function() _clock;
  final MediaServerHttp _http;

  void close() => _client.close();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(_base).resolve(path).replace(queryParameters: query);

  /// A new 4-character code, valid for the time plex.tv grants (15 min).
  Future<PlexPin> createPin() async {
    final data = await _http.json(
      () => _uri('pins', {'strong': 'false'}),
      headers: () => PlexRequest.headers(clientId),
      kind: MediaServerKind.plex,
      operation: 'plex_tv_pin',
      method: 'POST',
    );
    final id = data['id'];
    final code = data['code'];
    final expires = data['expiresIn'];
    if (id is! int || code is! String || code.isEmpty || expires is! int) {
      throw const MediaServerException('plex.tv returned an invalid response.');
    }
    return PlexPin(
      id: id,
      code: code,
      expiresAt: _clock().add(Duration(seconds: expires)),
    );
  }

  /// The account token once the user has entered the code, otherwise null.
  /// Throws [PlexPinExpired] when plex.tv no longer knows the code.
  Future<String?> pollPin(PlexPin pin) async {
    if (!_clock().isBefore(pin.expiresAt)) throw const PlexPinExpired();
    final Map<String, dynamic> data;
    try {
      data = await _http.json(
        () => _uri('pins/${pin.id}'),
        headers: () => PlexRequest.headers(clientId),
        kind: MediaServerKind.plex,
        operation: 'plex_tv_pin',
      );
    } on MediaServerHttpError catch (error) {
      if (error.status == 404) throw const PlexPinExpired();
      rethrow;
    }
    final token = data['authToken'];
    return token is String && token.isNotEmpty ? token : null;
  }

  /// The signed-in account's stable id.
  Future<String> userId(String accountToken) async {
    final data = await _http.json(
      () => _uri('user'),
      headers: () => PlexRequest.headers(clientId, accountToken),
      kind: MediaServerKind.plex,
      operation: 'plex_tv_user',
    );
    final uuid = data['uuid'];
    if (uuid is String && RegExp(r'^[A-Za-z0-9_-]{4,128}$').hasMatch(uuid)) {
      return uuid;
    }
    throw const MediaServerException('plex.tv returned an invalid response.');
  }

  /// Media servers the account can use, with their addresses.
  Future<List<PlexAccountServer>> servers(String accountToken) async {
    final rows = await _http.jsonList(
      () => _uri('resources', {'includeHttps': '1', 'includeRelay': '1'}),
      headers: () => PlexRequest.headers(clientId, accountToken),
      kind: MediaServerKind.plex,
      operation: 'plex_tv_resources',
    );
    final servers = <PlexAccountServer>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final data = row;
      final provides = '${data['provides'] ?? ''}'.split(',');
      final id = data['clientIdentifier'];
      final token = data['accessToken'];
      if (!provides.contains('server') ||
          id is! String ||
          id.isEmpty ||
          token is! String ||
          token.isEmpty) {
        continue;
      }
      final connections = <PlexAccountConnection>[];
      final entries = data['connections'];
      for (final connection in entries is List ? entries : const []) {
        if (connection is! Map) continue;
        final uri = connection['uri'];
        if (uri is! String) continue;
        final Uri parsed;
        try {
          parsed = MediaServerHttp.normalizeBaseUrl(uri);
        } on MediaServerException {
          continue;
        }
        connections.add(
          PlexAccountConnection(
            uri: parsed.toString(),
            https: parsed.scheme == 'https',
            local: connection['local'] == true,
            relay: connection['relay'] == true,
          ),
        );
      }
      servers.add(
        PlexAccountServer(
          id: id,
          name: data['name'] is String && (data['name'] as String).isNotEmpty
              ? data['name'] as String
              : 'Plex Media Server',
          owned: data['owned'] == true,
          accessToken: token,
          connections: connections,
        ),
      );
    }
    return servers;
  }
}

/// The addresses a connection may use, in priority order: local https,
/// remote https, local http only when [allowInsecureLocal], then relay.
/// Remote http is never used.
List<MediaServerConnection> plexAllowedConnections(
  List<PlexAccountConnection> connections, {
  required bool allowInsecureLocal,
}) {
  final ordered = [
    for (final c in connections)
      if (c.https && c.local && !c.relay) c,
    for (final c in connections)
      if (c.https && !c.local && !c.relay) c,
    if (allowInsecureLocal)
      for (final c in connections)
        if (!c.https && c.local && !c.relay) c,
    for (final c in connections)
      if (c.https && c.relay) c,
  ];
  final seen = <String>{};
  return [
    for (final c in ordered)
      if (seen.add(c.uri)) MediaServerConnection(uri: c.uri, relay: c.relay),
  ];
}

/// Whether the server has a local address that is only reachable without
/// encryption (offered as an opt-in).
bool plexHasInsecureLocal(List<PlexAccountConnection> connections) =>
    connections.any((c) => !c.https && c.local && !c.relay);

/// Shown when no allowed address answers.
const plexUnreachableMessage =
    'Could not reach this server from here. Check that it is online and that '
    'Remote Access is on, or allow an unencrypted connection to its local '
    'address.';
