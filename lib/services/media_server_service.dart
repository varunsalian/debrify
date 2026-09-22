import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/media_server.dart';
import '../models/media_server_source.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import '../utils/torrent_filter_matcher.dart';
import 'media_server_client.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/device_key_provider.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_authorization.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/profile_runtime.dart';
import 'stremio_service.dart' show AddonSearchStatus;
import 'series_source_service.dart';

class MediaServerService {
  @visibleForTesting
  static MediaServerClient Function() clientFactory = MediaServerClient.new;
  static const types = {ConnectionResourceType.mediaServer};
  static final _tickets = Expando<Future<void> Function()>();
  static final _bindings = Expando<String>();
  static final _watchTargets = Expando<MediaServerWatchTarget>();

  static MediaServerWatchTarget? watchTargetFor(Torrent source) =>
      owns(source) ? _watchTargets[source] : null;

  static SeriesSource? bindingFor(Torrent source) {
    final descriptor = _bindings[source];
    if (!owns(source) || descriptor == null) return null;
    return SeriesSource(
      torrentHash: '',
      torrentName: source.name,
      debridService: SeriesSource.mediaServerService,
      debridTorrentId: descriptor,
      boundAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<Torrent?> resolvePinned(
    SeriesSource pin, {
    int? season,
    int? episode,
  }) async {
    if (!pin.isMediaServer) return null;
    final descriptor = MediaServerSource.tryDecode(pin.debridTorrentId);
    if (descriptor == null) return null;
    final result = await search(
      id: descriptor.contentId,
      isMovie: descriptor.isMovie,
      season: season,
      episode: episode,
      resourceFilter: descriptor.serverId,
    );
    for (final source in (result['torrents'] as List<Torrent>? ?? [])) {
      if (_bindings[source] == descriptor.encode()) return source;
    }
    return null;
  }

  static ConnectionResourceService get _resources => ConnectionResourceService(
    registry: ProfileBootstrap.registry,
    cipher: DeviceKeyProvider.cipher,
  );

  static bool owns(Torrent source) => source.source.startsWith('mediaserver:');

  // Map cropped originals onto the tiers understood by the shared filters.
  // Both dimensions matter: a 1920x800 movie is still a Full HD source.
  static String _quality(Map video) {
    final width = (video['Width'] as num?)?.toInt() ?? 0;
    final height = (video['Height'] as num?)?.toInt() ?? 0;
    if (width <= 0 && height <= 0) return 'Original';
    if (width > 2560 || height > 1440) return '2160p';
    if (width > 1280 || height > 962) return '1080p';
    if (width > 1024 || height > 576) return '720p';
    return height > 480 ? '576p' : '480p';
  }

  static List<String> _dynamicRangeTags(Map video) {
    final range = [
      video['VideoRangeType'],
      video['VideoRange'],
      video['ExtendedVideoType'],
    ].whereType<String>().join(' ').toUpperCase();
    final transfer = (video['ColorTransfer'] as String? ?? '').toLowerCase();
    final tags = <String>[];
    if (range.contains('DOVI') ||
        range.contains('DOLBY') ||
        RegExp(r'\bDV\b').hasMatch(range) ||
        ((video['DvProfile'] as num?) ?? 0) > 0) {
      tags.add('DV');
    }
    if (range.contains('HDR10PLUS') ||
        range.contains('HDR10+') ||
        video['Hdr10PlusPresentFlag'] == true) {
      tags.add('HDR10+');
    } else if (range.contains('HDR10') || transfer == 'smpte2084') {
      tags.add('HDR10');
    }
    if (range.contains('HLG') || transfer == 'arib-std-b67') tags.add('HLG');
    if (tags.isEmpty && range.contains('HDR')) tags.add('HDR');
    return tags;
  }

  static Future<void> authorize(Torrent source) async {
    if (!owns(source)) return;
    final ticket = _tickets[source];
    if (ticket == null) {
      throw const MediaServerException(
        'Search this media server again before playing.',
      );
    }
    await ticket();
  }

  static Future<List<ConnectionResource>> connections() async {
    if (!ProfileCollectionResourceFacade.active) return [];
    final context = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final list = await ProfileBootstrap.registry.listGrantedResources(
      context.profileId,
    );
    await context.validate(ProfileBootstrap.registry);
    return list.where((r) => types.contains(r.type)).toList();
  }

  static Future<void> connect({
    required MediaServerKind kind,
    required String label,
    required String baseUrl,
    required String username,
    required String password,
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
    Future<void> check() async {
      await context.validate(ProfileBootstrap.registry);
    }

    if (replaceId != null) {
      final existing = await _resources.authorize(
        context: context,
        resourceId: replaceId,
        permission: ResourcePermission.manage,
        feature: ProfileFeature.manageConnections,
      );
      if (existing.type != ConnectionResourceType.mediaServer) {
        throw const MediaServerException('Invalid media server connection.');
      }
    }

    final client = clientFactory();
    try {
      final account = await client.login(
        kind: kind,
        baseUrl: baseUrl,
        username: username,
        password: password,
        deviceId: List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        authorize: check,
      );
      await client.testConnection(account, authorize: check);
      await check();
      if (replaceId != null) {
        final existing = await _resources.authorize(
          context: context,
          resourceId: replaceId,
          permission: ResourcePermission.manage,
          feature: ProfileFeature.manageConnections,
        );
        if (existing.type != ConnectionResourceType.mediaServer) {
          throw const MediaServerException('Invalid media server connection.');
        }
        await _resources.updateSecret(
          context: context,
          resourceId: replaceId,
          secretConfig: account.toJson(),
        );
      } else {
        await _resources.create(
          context: context,
          type: ConnectionResourceType.mediaServer,
          label: label.trim().isEmpty ? kind.label : label.trim(),
          publicConfig: {'accountLabel': kind.label},
          secretConfig: account.toJson(),
        );
      }
    } finally {
      client.close();
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
    final client = clientFactory();
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

  static Future<Map<String, dynamic>> search({
    required String id,
    required bool isMovie,
    int? season,
    int? episode,
    String? resourceFilter,
    void Function(String, List<Torrent>)? onBatch,
  }) async {
    final streams = <Torrent>[];
    final statuses = <AddonSearchStatus>[];
    final errors = <String, String>{};
    Map<String, dynamic> result() => {
      'torrents': streams,
      'addonStatuses': statuses,
      'addonErrors': errors,
    };
    if (!ProfileCollectionResourceFacade.active ||
        (!isMovie && (season == null || episode == null))) {
      return result();
    }
    final scope = ProfileRuntime.scope.value;
    List<Map<String, dynamic>> records;
    try {
      records = await ProfileCollectionResourceFacade.read(
        types: types,
        feature: ProfileFeature.cloud,
      );
      if (resourceFilter != null) {
        records = records.where((r) => r['id'] == resourceFilter).toList();
      }
    } catch (_) {
      return result(); // A restricted profile must not expose another library.
    }
    // Limit concurrent servers, while letting a fast server publish immediately.
    var next = 0;
    Future<void> worker() async {
      while (next < records.length && ProfileRuntime.scope.value == scope) {
        final record = records[next++];
        final resourceId = record['id'] as String;
        final key = 'mediaserver:$resourceId'.toLowerCase();
        var name = 'Media server';
        final client = clientFactory();
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        var searchComplete = false;
        try {
          final resource = await ProfileBootstrap.registry.getResource(
            resourceId,
          );
          if (resource == null) continue;
          name = resource.label;
          final capability = await ProfileAsyncAuthorization.capture(
            ProfileFeature.cloud,
            resourceId: resourceId,
            resourceAuthorizationRevision:
                record['_connectionResourceRevision'] as int,
          );
          Future<void> check() async {
            if (!searchComplete && DateTime.now().isAfter(deadline)) {
              throw const MediaServerException(
                'Server search timed out. Please retry.',
              );
            }
            if (ProfileRuntime.scope.value != scope) {
              throw const MediaServerException('Profile changed.');
            }
            await capability?.runIfCurrent(() async {});
            final local = await ProfileBootstrap.registry
                .getProfileResourceSettings(
                  capability!.authorization.profileId,
                  resourceId,
                );
            if (local?.enabled == false) {
              throw const MediaServerException('This server is disabled.');
            }
          }

          final account = MediaServerAccount.fromJson(record);
          final items = await client.findItems(
            account,
            id: id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            authorize: check,
          );
          final batch = <Torrent>[];
          for (final item in items) {
            final itemId = item['Id'] as String;
            final sources = await client.mediaSources(
              account,
              itemId,
              authorize: check,
            );
            for (final media in sources) {
              final sourceId = media['Id'] as String;
              final video = (media['MediaStreams'] as List? ?? [])
                  .whereType<Map>()
                  .where((s) => s['Type'] == 'Video');
              final videoStream = video.isEmpty
                  ? const <String, dynamic>{}
                  : video.first;
              final codec = videoStream['Codec'];
              final title = item['Name'] as String? ?? 'Untitled';
              final quality = _quality(videoStream);
              final rangeTags = _dynamicRangeTags(videoStream);
              final audioLanguages = (media['MediaStreams'] as List? ?? [])
                  .whereType<Map>()
                  .where(
                    (stream) =>
                        stream['Type'] == 'Audio' &&
                        stream['IsExternal'] != true,
                  )
                  .map((stream) => stream['Language'])
                  .whereType<String>()
                  .map((language) => language.trim().toLowerCase())
                  .where((language) => language.isNotEmpty)
                  .toSet()
                  .toList();
              final languageTags = audioLanguages
                  .map(TorrentFilterMatcher.audioLanguageForCode)
                  .whereType<Enum>()
                  .map((language) => language.name)
                  .toSet();
              final description = [
                quality,
                ...rangeTags,
                ...languageTags,
                if (codec is String) codec.toUpperCase(),
                if (media['Container'] is String)
                  (media['Container'] as String).toUpperCase(),
              ].join(' · ');
              final torrent = Torrent(
                rowid: 0,
                infohash: sha256
                    .convert(utf8.encode('$resourceId:$itemId:$sourceId'))
                    .toString(),
                name: [
                  title,
                  quality,
                  ...rangeTags,
                  ...languageTags,
                  if (!isMovie)
                    'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
                ].join(' '),
                sizeBytes: (media['Size'] as num?)?.toInt() ?? 0,
                createdUnix: 0,
                seeders: 0,
                leechers: 0,
                completed: 0,
                scrapedDate: 0,
                source: key,
                hasRealInfoHash: false,
                audioLanguages: audioLanguages,
                streamType: StreamType.directUrl,
                directUrl: MediaServerClient.playbackUrl(
                  account,
                  itemId,
                  sourceId,
                ).toString(),
                httpHeaders: MediaServerClient.headers(
                  account.deviceId,
                  account.token,
                  account.kind,
                ),
                addonDisplayName: name,
                streamLabel: '${account.kind.label} · $name',
                streamDescription: description,
                streamOriginalTitle: title,
                coverageType: isMovie ? null : 'singleEpisode',
                seasonNumber: season,
                episodeIdentifier: isMovie
                    ? null
                    : 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
              );
              _tickets[torrent] = check;
              if (capability != null) {
                _watchTargets[torrent] = MediaServerWatchTarget(
                  account: account,
                  capability: capability,
                  authorize: check,
                  itemId: itemId,
                  mediaSourceId: sourceId,
                  contentId: id,
                  isMovie: isMovie,
                  season: season,
                  episode: episode,
                  title: title,
                );
              }
              _bindings[torrent] = MediaServerSource(
                serverId: resourceId,
                contentId: id,
                isMovie: isMovie,
                // Movie versions are stable source IDs. Episodes use the
                // selected resolution so a pin can follow the next episode.
                variant: isMovie ? sourceId : quality,
              ).encode();
              batch.add(torrent);
            }
          }
          await check();
          searchComplete = true;
          streams.addAll(batch);
          statuses.add(
            AddonSearchStatus(
              addonId: key,
              name: name,
              sourceKey: key,
              count: batch.length,
            ),
          );
          if (batch.isNotEmpty) onBatch?.call(key, batch);
        } catch (error) {
          if (ProfileRuntime.scope.value != scope) return;
          final message = error is MediaServerException
              ? error.message
              : 'Server unavailable. Test or reconnect it in Settings.';
          errors[key] = message;
          statuses.add(
            AddonSearchStatus(
              addonId: key,
              name: name,
              sourceKey: key,
              count: 0,
              error: message,
            ),
          );
        } finally {
          client.close();
        }
      }
    }

    await Future.wait(
      List.generate(records.length < 3 ? records.length : 3, (_) => worker()),
    );
    if (ProfileRuntime.scope.value != scope) return {'torrents': <Torrent>[]};
    return result();
  }
}

/// In-memory, revocable identity of the exact library item selected for play.
/// Never reconstruct this from a URL or persist the account with progress.
class MediaServerWatchTarget {
  const MediaServerWatchTarget({
    required this.account,
    required this.capability,
    required this.authorize,
    required this.itemId,
    required this.mediaSourceId,
    required this.contentId,
    required this.isMovie,
    required this.season,
    required this.episode,
    required this.title,
  });

  final MediaServerAccount account;
  final ProfileAsyncAuthorization capability;
  final Future<void> Function() authorize;
  final String itemId;
  final String mediaSourceId;
  final String contentId;
  final bool isMovie;
  final int? season;
  final int? episode;
  final String title;
}
