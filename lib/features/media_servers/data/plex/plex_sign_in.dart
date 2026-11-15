import 'package:http/http.dart' as http;

import '../../../../models/media_server.dart';
import '../../../../services/media_server_service.dart';
import '../../../../services/profiles/profile_lock_controller.dart';
import '../../../../services/profiles/profile_session_unavailable.dart';
import '../../models/media_server_errors.dart';
import '../../models/plex_server_choice.dart';
import '../media_server_connection_store.dart';
import 'plex_account_link.dart';

/// Starts a Plex sign-in for the active profile. The attempt keeps every
/// token to itself; callers only see codes, server names and outcomes.
abstract interface class PlexSignInGateway {
  /// Captures the active profile (and the connection being reconnected) so
  /// the result can only be saved for them.
  Future<PlexSignInAttempt> start({String? replaceId});
}

abstract interface class PlexSignInAttempt {
  /// A new code for plex.tv/link.
  Future<({String code, DateTime expiresAt})> newCode();

  /// The account's servers once the code was entered, otherwise null.
  /// Throws [PlexPinExpired] when the code expired.
  Future<List<PlexServerChoice>?> poll();

  /// Verifies an address of [serverId] and saves the connection. Returns
  /// false when no allowed address answered.
  Future<bool> connect(
    String serverId, {
    required bool allowInsecureLocal,
    required String label,
  });

  void close();
}

class PlexAccountSignIn implements PlexSignInGateway {
  PlexAccountSignIn({http.Client Function()? httpClient})
    : _httpClient = httpClient ?? http.Client.new;

  final http.Client Function() _httpClient;

  @override
  Future<PlexSignInAttempt> start({String? replaceId}) async {
    final ticket = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
      replaceId: replaceId,
    );
    final deviceId =
        await MediaServerConnectionStore.previousDeviceId(ticket) ??
        MediaServerConnectionStore.newDeviceId();
    return _PlexSignInAttempt(
      ticket,
      deviceId,
      PlexAccountLink(clientId: deviceId, client: _httpClient()),
    );
  }
}

class _PlexSignInAttempt implements PlexSignInAttempt {
  _PlexSignInAttempt(this._ticket, this._deviceId, this._link);

  final MediaServerConnectTicket _ticket;
  final String _deviceId;
  final PlexAccountLink _link;
  PlexPin? _pin;
  String? _userId;
  bool _closed = false;
  List<PlexAccountServer> _servers = const [];

  @override
  Future<({String code, DateTime expiresAt})> newCode() async {
    final pin = await _link.createPin();
    _pin = pin;
    return (code: pin.code, expiresAt: pin.expiresAt);
  }

  @override
  Future<List<PlexServerChoice>?> poll() async {
    final pin = _pin;
    if (pin == null) throw const PlexPinExpired();
    final token = await _link.pollPin(pin);
    if (token == null) return null;
    // The account token is used for these two calls only, then dropped.
    _userId = await _link.userId(token);
    _servers = await _link.servers(token);
    _pin = null;
    return [
      for (final server in _servers)
        PlexServerChoice(
          id: server.id,
          name: server.name,
          owned: server.owned,
          hasSecureAddress: server.connections.any((c) => c.https),
          hasInsecureLocalAddress: plexHasInsecureLocal(server.connections),
        ),
    ];
  }

  @override
  Future<bool> connect(
    String serverId, {
    required bool allowInsecureLocal,
    required String label,
  }) async {
    final server = _servers.where((s) => s.id == serverId).firstOrNull;
    final userId = _userId;
    if (server == null || userId == null) {
      throw const MediaServerException('Sign in to Plex again.');
    }
    final connections = plexAllowedConnections(
      server.connections,
      allowInsecureLocal: allowInsecureLocal,
    );
    if (connections.isEmpty) return false;
    final account = MediaServerAccount(
      kind: MediaServerKind.plex,
      baseUrl: connections.first.uri,
      userId: userId,
      token: server.accessToken,
      serverId: server.id,
      deviceId: _deviceId,
      connections: connections,
    );
    final client = MediaServerService.createClient();
    try {
      final MediaServerAccount resolved;
      try {
        resolved = await client.resolve(account);
      } on MediaServerUnreachable {
        return false;
      }
      await client.testConnection(resolved);
      // The user left or cancelled while this was checked: save nothing.
      if (_closed) return false;
      await MediaServerConnectionStore.savePlex(
        _ticket,
        account.withBaseUrl(resolved.baseUrl),
        label.trim().isEmpty ? server.name : label,
      );
      return true;
    } on ProfileSessionUnavailable {
      throw MediaServerException(
        ProfileLockController.instance.lockedProfileId.value != null
            ? 'The profile locked while you were signing in. Unlock it, then sign in again.'
            : 'The active profile changed. Sign in again from this profile.',
      );
    } finally {
      client.close();
    }
  }

  @override
  void close() {
    _closed = true;
    _link.close();
  }
}
