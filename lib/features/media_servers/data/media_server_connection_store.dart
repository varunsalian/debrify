import 'dart:math';

import '../../../models/media_server.dart';
import '../../../models/profiles/connection_resource.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/media_server_service.dart';
import '../../../services/profiles/connection_resource_service.dart';
import '../../../services/profiles/device_key_provider.dart';
import '../../../services/profiles/profile_async_authorization.dart';
import '../../../services/profiles/profile_authorization.dart';
import '../../../services/profiles/profile_bootstrap.dart';
import '../../../services/profiles/profile_collection_resource_facade.dart';

/// Permission to save one media-server connection for the profile that was
/// active when it was issued. Saving re-validates the captured context, so a
/// profile switch, lock or permission change in between writes nothing.
class MediaServerConnectTicket {
  const MediaServerConnectTicket._(this._context, this.kind, this._replace);

  final ProfileAuthorizationContext _context;
  final MediaServerKind kind;
  final ({String id, int authorizationRevision})? _replace;

  bool get reconnecting => _replace != null;
}

/// Connects, tests and disconnects media servers (moved from
/// `MediaServerService`; guards unchanged).
class MediaServerConnectionStore {
  const MediaServerConnectionStore._();

  static ConnectionResourceService get _resources => ConnectionResourceService(
    registry: ProfileBootstrap.registry,
    cipher: DeviceKeyProvider.cipher,
  );

  static String newDeviceId() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Starts connecting a [kind] server, or reconnecting [replaceId], for the
  /// active profile.
  static Future<MediaServerConnectTicket> begin({
    required MediaServerKind kind,
    String? replaceId,
  }) async {
    if (!ProfileCollectionResourceFacade.active) {
      throw const MediaServerException(
        'Media servers require an active Debrify profile.',
      );
    }
    final context = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await context.validate(ProfileBootstrap.registry);
    if (!profile.allows(ProfileFeature.manageConnections) ||
        !profile.allows(ProfileFeature.cloud)) {
      throw const MediaServerException(
        'This profile cannot manage media server connections.',
      );
    }
    if (replaceId == null) {
      return MediaServerConnectTicket._(context, kind, null);
    }
    final existing = await _replaceTarget(context, replaceId, kind);
    return MediaServerConnectTicket._(context, kind, (
      id: existing.id,
      authorizationRevision: existing.authorizationRevision,
    ));
  }

  static Future<ConnectionResource> _replaceTarget(
    ProfileAuthorizationContext context,
    String resourceId,
    MediaServerKind kind,
  ) async {
    final existing = await _resources.authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    if (existing.type != ConnectionResourceType.mediaServer) {
      throw const MediaServerException('Invalid media server connection.');
    }
    final label = existing.publicConfig['accountLabel'];
    final declared = MediaServerKind.values
        .where((known) => known.label == label)
        .firstOrNull;
    // A connection without a known type reconnects as Jellyfin or Emby, as
    // before Plex existed; a known type is kept.
    if (declared != null ? declared != kind : kind == MediaServerKind.plex) {
      throw const MediaServerException(
        'This connection is a different server type. Disconnect it and connect again.',
      );
    }
    return existing;
  }

  /// The client id a reconnect should keep, so the server does not list
  /// Debrify as a new device. Null when there is nothing to keep.
  static Future<String?> previousDeviceId(
    MediaServerConnectTicket ticket,
  ) async {
    final replace = ticket._replace;
    if (replace == null) return null;
    try {
      final secret = await _resources.resolveSecretForUse(
        context: ticket._context,
        resourceId: replace.id,
        feature: ProfileFeature.cloud,
      );
      final deviceId = secret['deviceId'];
      return deviceId is String && deviceId.isNotEmpty ? deviceId : null;
    } on Exception {
      return null;
    }
  }

  /// Jellyfin/Emby: username sign-in, then save.
  static Future<void> connect({
    required MediaServerKind kind,
    required String label,
    required String baseUrl,
    required String username,
    required String password,
    String? replaceId,
  }) async {
    final ticket = await begin(kind: kind, replaceId: replaceId);
    Future<void> check() async {
      await ticket._context.validate(ProfileBootstrap.registry);
    }

    final client = MediaServerService.createClient();
    try {
      final account = await client.login(
        kind: kind,
        baseUrl: baseUrl,
        username: username,
        password: password,
        deviceId: newDeviceId(),
        authorize: check,
      );
      await client.testConnection(account, authorize: check);
      await check();
      await _store(ticket, account, label);
    } finally {
      client.close();
    }
  }

  /// Plex: [account] comes from the plex.tv sign-in started with [ticket].
  static Future<void> savePlex(
    MediaServerConnectTicket ticket,
    MediaServerAccount account,
    String label,
  ) async {
    if (ticket.kind != MediaServerKind.plex ||
        account.kind != MediaServerKind.plex) {
      throw const MediaServerException('Invalid media server connection.');
    }
    await _store(ticket, account, label);
  }

  static Future<void> _store(
    MediaServerConnectTicket ticket,
    MediaServerAccount account,
    String label,
  ) async {
    final context = ticket._context;
    await context.validate(ProfileBootstrap.registry);
    final replace = ticket._replace;
    if (replace != null) {
      final existing = await _replaceTarget(context, replace.id, ticket.kind);
      if (existing.authorizationRevision != replace.authorizationRevision) {
        throw const MediaServerException(
          'This connection changed while you were signing in. Please try again.',
        );
      }
      await _resources.updateSecret(
        context: context,
        resourceId: replace.id,
        secretConfig: account.toJson(),
      );
    } else {
      await _resources.create(
        context: context,
        type: ConnectionResourceType.mediaServer,
        label: label.trim().isEmpty ? ticket.kind.label : label.trim(),
        publicConfig: {'accountLabel': ticket.kind.label},
        secretConfig: account.toJson(),
      );
    }
  }

  static Future<void> test(ConnectionResource resource) async {
    final context = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
      resourceId: resource.id,
      resourceAuthorizationRevision: resource.authorizationRevision,
    );
    final secret = await _resources.resolveSecretForUse(
      context: context,
      resourceId: resource.id,
      feature: ProfileFeature.cloud,
    );
    final client = MediaServerService.createClient();
    try {
      await client.testConnection(
        MediaServerAccount.fromJson(secret),
        authorize: () async {
          await capability?.runIfCurrent(() async {});
        },
      );
    } finally {
      client.close();
    }
  }

  static Future<void> remove(
    ConnectionResource resource, {
    bool revokeBorrowers = false,
  }) async {
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    if (resource.ownerProfileId != context.profileId) {
      await registry.detachBorrowedResource(
        profileId: context.profileId,
        authorizationRevision: context.authorizationRevision,
        resourceId: resource.id,
        expectedResourceAuthorizationRevision: resource.authorizationRevision,
      );
    } else {
      // Shared-resource deletion follows the existing explicit-impact guard.
      await ProfileCollectionResourceFacade.deleteOwned(
        resourceId: resource.id,
        revokeBorrowers: revokeBorrowers,
      );
    }
  }
}
