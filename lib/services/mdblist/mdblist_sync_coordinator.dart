import '../profiles/profile_credential_facade.dart';
import '../storage_service.dart';
import 'mdblist_calendar_service.dart';
import 'mdblist_continue_watching_service.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

typedef MdblistCheckpointReader = Future<Map<String, dynamic>?> Function();
typedef MdblistCheckpointWriter =
    Future<void> Function(Map<String, dynamic>? value);
typedef MdblistAuthorityReader =
    Future<ProfileCredentialResourceAuthority?> Function();
typedef MdblistSyncInvalidator = void Function(Set<String> buckets, bool all);

class MdblistSyncPoll {
  final MdblistResultKind kind;
  final bool fullSyncRequired;
  final Set<String> changedBuckets;
  final List<Map<String, dynamic>> journal;
  final Map<String, dynamic>? activities;
  final String? resourceId;
  final int authorizationRevision;
  final DateTime? serverTime;

  const MdblistSyncPoll({
    required this.kind,
    required this.fullSyncRequired,
    this.changedBuckets = const {},
    this.journal = const [],
    this.activities,
    this.resourceId,
    this.authorizationRevision = 0,
    this.serverTime,
  });

  bool get isSuccess => kind == MdblistResultKind.success;
}

/// Two-phase incremental sync: [poll] reads server truth without advancing the
/// checkpoint; callers apply/refresh every reported bucket, then [commit].
/// This prevents a crash or partial refresh from silently skipping changes.
class MdblistSyncCoordinator {
  MdblistSyncCoordinator({
    MdblistService? service,
    MdblistCheckpointReader? readCheckpoint,
    MdblistCheckpointWriter? writeCheckpoint,
    MdblistAuthorityReader? readAuthority,
    MdblistSyncInvalidator? invalidate,
  }) : _service = service ?? MdblistService.instance,
       _readCheckpoint =
           readCheckpoint ?? StorageService.getMdblistSyncCheckpoint,
       _writeCheckpoint =
           writeCheckpoint ?? StorageService.setMdblistSyncCheckpoint,
       _readAuthority =
           readAuthority ??
           (() => ProfileCredentialFacade.boundAuthority('mdblist_api_key')),
       _invalidate = invalidate ?? _invalidateAppCaches;

  static final instance = MdblistSyncCoordinator();
  static const retention = Duration(days: 30);

  final MdblistService _service;
  final MdblistCheckpointReader _readCheckpoint;
  final MdblistCheckpointWriter _writeCheckpoint;
  final MdblistAuthorityReader _readAuthority;
  final MdblistSyncInvalidator _invalidate;
  Future<bool>? _syncing;
  DateTime? _lastSyncAt;
  static const _minimumPollInterval = Duration(seconds: 30);

  static void _invalidateAppCaches(Set<String> buckets, bool all) {
    MdblistService.instance.invalidateSyncBuckets(buckets, all: all);
    if (all || buckets.contains('playback') || buckets.contains('watched')) {
      MdblistContinueWatchingService.instance.resetProfileScope();
    }
    if (all || buckets.contains('watchlist')) {
      MdblistCalendarService.instance.invalidate();
    }
  }

  /// Poll, invalidate every changed owning cache, and only then advance the
  /// checkpoint. Concurrent Home/Discover refreshes share one request walk.
  Future<bool> synchronizeInvalidations() {
    final active = _syncing;
    if (active != null) return active;
    final last = _lastSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < _minimumPollInterval) {
      return Future.value(true);
    }
    late Future<bool> guarded;
    guarded = _synchronizeInvalidations().whenComplete(() {
      if (identical(_syncing, guarded)) _syncing = null;
    });
    _syncing = guarded;
    return guarded;
  }

  Future<bool> _synchronizeInvalidations() async {
    final result = await poll();
    if (!result.isSuccess) return false;
    _invalidate(result.changedBuckets, result.fullSyncRequired);
    final committed = await commit(result);
    if (committed) _lastSyncAt = DateTime.now();
    return committed;
  }

  void resetProfileScope() {
    _lastSyncAt = null;
    _syncing = null;
  }

  Future<MdblistSyncPoll> poll() async {
    if (!_service.networkEnabled || !await _service.isAuthenticated()) {
      return const MdblistSyncPoll(
        kind: MdblistResultKind.unauthenticated,
        fullSyncRequired: false,
      );
    }
    final authority = await _readAuthority();
    final resourceId = authority?.resourceId ?? 'legacy-profile-scope';
    final revision = authority?.resourceAuthorizationRevision ?? 0;
    final activitiesResult = await _service.fetchLastActivities();
    if (!activitiesResult.isSuccess) {
      return MdblistSyncPoll(
        kind: activitiesResult.kind,
        fullSyncRequired: false,
        resourceId: resourceId,
        authorizationRevision: revision,
      );
    }
    final activities = activitiesResult.data!;
    final serverTime = DateTime.tryParse(
      activities['server_time']?.toString() ?? '',
    )?.toUtc();
    if (serverTime == null) {
      return MdblistSyncPoll(
        kind: MdblistResultKind.malformedResponse,
        fullSyncRequired: false,
        resourceId: resourceId,
        authorizationRevision: revision,
      );
    }

    final checkpoint = await _readCheckpoint();
    final since = DateTime.tryParse(
      checkpoint?['server_time']?.toString() ?? '',
    )?.toUtc();
    final sameAuthority =
        checkpoint?['resource_id'] == resourceId &&
        checkpoint?['authorization_revision'] == revision;
    final expired = since == null || serverTime.difference(since) >= retention;
    final oldActivities = checkpoint?['activities'];
    final changed = _changedBuckets(
      oldActivities is Map ? oldActivities : const {},
      activities,
    );
    if (!sameAuthority || expired) {
      return MdblistSyncPoll(
        kind: MdblistResultKind.success,
        fullSyncRequired: true,
        changedBuckets: changed,
        activities: activities,
        resourceId: resourceId,
        authorizationRevision: revision,
        serverTime: serverTime,
      );
    }

    final journal = <Map<String, dynamic>>[];
    String? cursor;
    for (var page = 0; page < 100; page++) {
      final result = await _service.fetchJournal(
        since: cursor == null ? since : null,
        cursor: cursor,
      );
      if (!result.isSuccess) {
        return MdblistSyncPoll(
          kind: result.kind,
          fullSyncRequired: false,
          resourceId: resourceId,
          authorizationRevision: revision,
        );
      }
      final data = result.data!;
      if (data['requires_full_sync'] == true) {
        return MdblistSyncPoll(
          kind: MdblistResultKind.success,
          fullSyncRequired: true,
          changedBuckets: changed,
          activities: activities,
          resourceId: resourceId,
          authorizationRevision: revision,
          serverTime: serverTime,
        );
      }
      final values = data['journal'];
      if (values is! List) {
        return MdblistSyncPoll(
          kind: MdblistResultKind.malformedResponse,
          fullSyncRequired: false,
          resourceId: resourceId,
          authorizationRevision: revision,
        );
      }
      for (final value in values) {
        if (value is! Map<String, dynamic>) {
          return MdblistSyncPoll(
            kind: MdblistResultKind.malformedResponse,
            fullSyncRequired: false,
            resourceId: resourceId,
            authorizationRevision: revision,
          );
        }
        journal.add(value);
      }
      final pagination = data['pagination'];
      final next = pagination is Map
          ? pagination['next_cursor']?.toString().trim()
          : null;
      if (next == null || next.isEmpty) break;
      cursor = next;
      if (page == 99) {
        return MdblistSyncPoll(
          kind: MdblistResultKind.partial,
          fullSyncRequired: false,
          resourceId: resourceId,
          authorizationRevision: revision,
        );
      }
    }
    return MdblistSyncPoll(
      kind: MdblistResultKind.success,
      fullSyncRequired: false,
      changedBuckets: changed,
      journal: journal,
      activities: activities,
      resourceId: resourceId,
      authorizationRevision: revision,
      serverTime: serverTime,
    );
  }

  Future<bool> commit(MdblistSyncPoll poll) async {
    if (!poll.isSuccess ||
        poll.activities == null ||
        poll.serverTime == null ||
        poll.resourceId == null) {
      return false;
    }
    final authority = await _readAuthority();
    final currentId = authority?.resourceId ?? 'legacy-profile-scope';
    final currentRevision = authority?.resourceAuthorizationRevision ?? 0;
    if (currentId != poll.resourceId ||
        currentRevision != poll.authorizationRevision) {
      return false;
    }
    await _writeCheckpoint({
      'resource_id': poll.resourceId,
      'authorization_revision': poll.authorizationRevision,
      'server_time': poll.serverTime!.toIso8601String(),
      'activities': poll.activities,
    });
    return true;
  }

  Future<void> reset() async {
    resetProfileScope();
    await _writeCheckpoint(null);
  }

  Set<String> _changedBuckets(Map old, Map<String, dynamic> current) {
    const keys = <String, String>{
      'watchlisted_at': 'watchlist',
      'watched_at': 'watched',
      'season_watched_at': 'watched',
      'episode_watched_at': 'watched',
      'rated_at': 'ratings',
      'collected_at': 'collection',
      'dropped_at': 'dropped',
      'paused_at': 'playback',
      'episode_paused_at': 'playback',
      'list_updated_at': 'lists',
    };
    return {
      for (final entry in keys.entries)
        if (old[entry.key] != current[entry.key]) entry.value,
    };
  }
}
