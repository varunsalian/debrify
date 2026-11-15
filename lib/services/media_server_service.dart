import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/media_server.dart';
import '../models/media_server_library.dart';
import '../models/media_server_source.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import '../utils/torrent_filter_matcher.dart';
import '../features/media_servers/data/media_server_stream_tags.dart';
import 'media_server_client.dart';
import 'diagnostic_log.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/device_key_provider.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_authorization.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/profile_runtime.dart';
import 'stremio_service.dart' show AddonSearchStatus;
import 'series_source_service.dart';
import 'source_search_preferences.dart';

class MediaServerService {
  @visibleForTesting
  static MediaServerClient Function() clientFactory = MediaServerClient.new;

  /// A client from [clientFactory], for callers outside this file.
  static MediaServerClient createClient() => clientFactory();
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

  static Future<List<ConnectionResource>> libraryConnections(
    MediaServerKind kind,
  ) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
    );
    if (capability == null) return [];
    return capability.runIfCurrent(() async {
      final profile = await capability.authorization.validate(
        ProfileBootstrap.registry,
      );
      if (!profile.allows(ProfileFeature.trackersAndDiscovery)) return [];
      final result = <ConnectionResource>[];
      for (final resource in await connections()) {
        final grant = await ProfileBootstrap.registry.getGrant(
          profile.id,
          resource.id,
        );
        final local = await ProfileBootstrap.registry
            .getProfileResourceSettings(profile.id, resource.id);
        if (resource.enabled &&
            grant?.allows(ResourcePermission.use) == true &&
            local?.enabled != false &&
            resource.publicConfig['accountLabel'] == kind.label) {
          result.add(resource);
        }
      }
      await capability.runIfCurrent(() async {});
      return result;
    });
  }

  static Future<MediaServerLibrarySession> openLibrary(
    String resourceId,
  ) async {
    final context = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final resource = await _resources.authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.use,
      feature: ProfileFeature.cloud,
    );
    if (resource.type != ConnectionResourceType.mediaServer) {
      throw const MediaServerException('Invalid media server connection.');
    }
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
      resourceId: resourceId,
      resourceAuthorizationRevision: resource.authorizationRevision,
    );
    if (capability == null) {
      throw const MediaServerException('An active profile is required.');
    }
    final secret = await _resources.resolveSecretForUse(
      context: context,
      resourceId: resourceId,
      feature: ProfileFeature.cloud,
    );
    final session = MediaServerLibrarySession._(
      resource,
      MediaServerAccount.fromJson(secret),
      capability,
    );
    await session.authorize();
    return session;
  }

  static List<Torrent> _librarySources({
    required MediaServerAccount account,
    required String resourceId,
    required String name,
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> sources,
    required String id,
    required bool isMovie,
    required int? season,
    required int? episode,
    required Future<void> Function() check,
    required ProfileAsyncAuthorization? capability,
    bool bind = true,
  }) {
    final batch = <Torrent>[];
    final itemId = item['Id'] as String;
    final key = 'mediaserver:$resourceId'.toLowerCase();
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
      final quality = MediaServerStreamTags.quality(videoStream);
      final rangeTags = MediaServerStreamTags.dynamicRange(videoStream);
      final audioLanguages = (media['MediaStreams'] as List? ?? [])
          .whereType<Map>()
          .where(
            (stream) =>
                stream['Type'] == 'Audio' && stream['IsExternal'] != true,
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
        if (!isMovie &&
            item['IndexNumberEnd'] is int &&
            item['IndexNumber'] is int &&
            (item['IndexNumberEnd'] as int) > (item['IndexNumber'] as int))
          'Combined episodes ${item['IndexNumber']}–${item['IndexNumberEnd']}',
        ...rangeTags,
        ...languageTags,
        if (codec is String) codec.toUpperCase(),
        if (media['Container'] is String)
          (media['Container'] as String).toUpperCase(),
        if (account.usesRelay) 'Relay (limited speed)',
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
      if (bind) {
        _bindings[torrent] = MediaServerSource(
          serverId: resourceId,
          contentId: id,
          isMovie: isMovie,
          // Movie versions are stable source IDs. Episodes use the
          // selected resolution so a pin can follow the next episode.
          variant: isMovie ? sourceId : quality,
        ).encode();
      }
      batch.add(torrent);
    }
    return batch;
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
    // A disabled source search must not query any media server.
    if (!(await SourceSearchPreferences.readOrDefault()).mediaServers ||
        !ProfileCollectionResourceFacade.active ||
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

          // An id no server can match needs no address lookup.
          final stored = MediaServerAccount.fromJson(record);
          final account = !MediaServerClient.canMatch(id)
              ? stored
              : await client.resolve(
                  stored,
                  authorize: check,
                  cacheScope: (
                    scope,
                    resourceId,
                    record['_connectionResourceRevision'],
                  ),
                  deadline: deadline,
                );
          var lookupIncomplete = false;
          final items = await client.findItems(
            account,
            id: id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            authorize: check,
            cacheScope: (
              scope,
              resourceId,
              record['_connectionResourceRevision'],
            ),
            onIncomplete: () => lookupIncomplete = true,
          );
          final batch = <Torrent>[];
          var failedItems = 0;
          var unsupportedItems = 0;
          for (final item in items) {
            final itemId = item['Id'] as String;
            List<Map<String, dynamic>> sources;
            try {
              sources = await client.mediaSources(
                account,
                itemId,
                authorize: check,
              );
            } on MediaServerException {
              // A bad version must not discard other playable library items.
              // Recheck revocation and the deadline before continuing.
              final expired = DateTime.now().isAfter(deadline);
              // Stop searching on deadline, but retain already resolved items.
              // Authorization remains mandatory even when the search is done.
              if (expired) searchComplete = true;
              await check();
              failedItems++;
              if (expired) break;
              continue;
            }
            if (sources.isEmpty) unsupportedItems++;
            batch.addAll(
              _librarySources(
                account: account,
                resourceId: resourceId,
                name: name,
                item: item,
                sources: sources,
                id: id,
                isMovie: isMovie,
                season: season,
                episode: episode,
                check: check,
                capability: capability,
              ),
            );
          }
          searchComplete = true;
          await check();
          streams.addAll(batch);
          final warning = lookupIncomplete
              ? 'Search incomplete. Showing verified sources found so far; retry to continue searching.'
              : failedItems > 0
              ? 'Some matching items could not be checked. Retry or test this server in Settings.'
              : unsupportedItems > 0
              ? 'Some matching items have no supported original-file stream. Remote streams and transcoding are not supported.'
              : null;
          if (warning != null) errors[key] = warning;
          DiagnosticLog.instance.recordEvent(
            source: 'media_server',
            event: 'search_completed',
            fields: {
              'kind': DiagnosticLabel(account.kind.name),
              'matched_items': items.length,
              'sources': batch.length,
              'failed_items': failedItems,
              'unsupported_items': unsupportedItems,
            },
          );
          statuses.add(
            AddonSearchStatus(
              addonId: key,
              name: name,
              sourceKey: key,
              count: batch.length,
              error: warning,
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

/// A revocable browsing session. Credentials never leave the service layer.
abstract interface class MediaServerLibraryAccess {
  ConnectionResource get resource;
  MediaServerKind get kind;
  Future<void> authorize();
  Future<MediaServerLibraryPage> browse({
    String? parentId,
    bool views = false,
    int offset = 0,
    String search = '',
    String sort = 'SortName',
    String mode = 'browse',
    bool episodeOrder = false,
  });
  Future<MediaServerLibraryItem> item(String id);
  Future<Uint8List?> image(String id);
  Future<List<Torrent>> sources(MediaServerLibraryItem item);
}

class MediaServerLibrarySession implements MediaServerLibraryAccess {
  MediaServerLibrarySession._(this.resource, this._account, this._capability);
  @override
  final ConnectionResource resource;
  final MediaServerAccount _account;
  final ProfileAsyncAuthorization _capability;
  @override
  MediaServerKind get kind => _account.kind;

  @override
  Future<void> authorize() => _capability.runIfCurrent(() async {
    final registry = ProfileBootstrap.registry;
    final profile = await _capability.authorization.validate(registry);
    if (!profile.allows(ProfileFeature.trackersAndDiscovery)) {
      throw const MediaServerException(
        'Discovery is disabled for this profile.',
      );
    }
    final local = await registry.getProfileResourceSettings(
      profile.id,
      resource.id,
    );
    if (local?.enabled == false) {
      throw const MediaServerException('This server is disabled.');
    }
  });

  /// Resolves the address on every call (cached), so Retry recovers after a
  /// network change.
  Future<T> _withClient<T>(
    Future<T> Function(MediaServerClient, MediaServerAccount) action,
  ) async {
    await authorize();
    final client = MediaServerService.clientFactory();
    try {
      final account = await client.resolve(
        _account,
        authorize: authorize,
        cacheScope: (
          _capability.authorization.profileId,
          resource.id,
          resource.authorizationRevision,
        ),
      );
      final result = await action(client, account);
      await authorize();
      return result;
    } finally {
      client.close();
    }
  }

  @override
  Future<MediaServerLibraryPage> browse({
    String? parentId,
    bool views = false,
    int offset = 0,
    String search = '',
    String sort = 'SortName',
    String mode = 'browse',
    bool episodeOrder = false,
  }) => _withClient(
    (client, account) => client.library(
      account,
      parentId: parentId,
      views: views,
      offset: offset,
      search: search,
      sort: sort,
      mode: mode,
      episodeOrder: episodeOrder,
      authorize: authorize,
    ),
  );

  @override
  Future<MediaServerLibraryItem> item(String id) => _withClient(
    (client, account) => client.libraryItem(account, id, authorize: authorize),
  );

  @override
  Future<Uint8List?> image(String id) => _withClient(
    (client, account) => client.libraryImage(account, id, authorize: authorize),
  );

  @override
  Future<List<Torrent>> sources(MediaServerLibraryItem item) => _withClient((
    client,
    account,
  ) async {
    // Refresh the exact item before playback; never trust a stale browse row.
    final fresh = await client.libraryItem(
      account,
      item.id,
      authorize: authorize,
    );
    if (!fresh.playable) {
      throw const MediaServerException(
        'This item is not available for playback.',
      );
    }
    final media = await client.mediaSources(
      account,
      fresh.id,
      authorize: authorize,
    );
    final sources = MediaServerService._librarySources(
      account: account,
      resourceId: resource.id,
      name: resource.label,
      item: fresh.data,
      sources: media,
      id: fresh.progressId(
        sha256
            .convert(utf8.encode('${account.serverId}:${account.userId}'))
            .toString(),
      ),
      isMovie: !fresh.numberedEpisode,
      season: fresh.numberedEpisode ? fresh.season : null,
      episode: fresh.numberedEpisode ? fresh.episode : null,
      check: authorize,
      capability: _capability,
      bind: false,
    );
    if (sources.isEmpty) {
      throw const MediaServerException(
        'No original-file stream is available. Server transcoding is not supported yet.',
      );
    }
    return sources;
  });
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
