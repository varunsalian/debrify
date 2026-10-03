import 'dart:async';
import 'dart:collection';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvCatalogFacadesDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvSettingsState settingsState,

  void Function() applyFilters,
  bool Function() mounted,
  StateSetter setState,
});

class IptvCatalogFacades {
  final IptvCatalogFacadesDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvSettingsState _settingsState;

  IptvCatalogFacades(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _settingsState = _deps.settingsState;

  DbChannelList makeDbList(
    CatalogSnapshot snap, {
    String? group,
    String? search,
  }) {
    final ticket = _catalogState.loadTicket;
    return DbChannelList(
      snap,
      group: group,
      search: search,
      onPageLoaded: (page) => loadPageProgress(ticket, page),
      onEvicted: retireEvictedInstances,
      instanceCache: instanceCacheFor(snap),
    );
  }

  /// The shared instance cache for [snap]'s generation, cleared when the
  /// catalog or generation changes so a stale instance (old data) can never
  /// be reused.
  LinkedHashMap<int, IptvChannel> instanceCacheFor(CatalogSnapshot snap) {
    final key = '${snap.catalogKey}#${snap.generation}';
    if (_catalogState.dbInstanceCacheKey != key) {
      _catalogState.dbInstanceCache.clear();
      _catalogState.dbInstanceCacheKey = key;
    }
    return _catalogState.dbInstanceCache;
  }

  /// Progress bars for a freshly faulted page — the DB-mode replacement for
  /// [_loadProgress]'s whole-catalog scan. Fired synchronously during a page
  /// fault (possibly mid-build), so all state changes happen after the
  /// storage read's async gap.
  void loadPageProgress(int ticket, List<IptvChannel> page) {
    final onDemand = [
      for (final channel in page)
        if (!channel.isLive && channel.contentType != 'series') channel.url,
    ];
    if (onDemand.isEmpty) return;
    unawaited(
      IptvHistoryStorage.getIptvProgressForUrls(onDemand).then((progress) {
        if (!_deps.mounted() ||
            ticket != _catalogState.loadTicket ||
            progress.isEmpty) {
          return;
        }

        _deps.setState(
          () => _membershipState.progressByUrl = {
            ..._membershipState.progressByUrl,
            ...progress,
          },
        );
      }),
    );
  }

  /// An evicted page's instances can never be handed out again — retire
  /// their focus nodes. Attached or focused nodes are kept (their rows are
  /// still built); the next full reload sweeps them as always. Detachment
  /// comes from the row's own dispose report ([detachedRows]) — never from
  /// node.context, which stays non-null forever after the first attach.
  void retireEvictedInstances(List<IptvChannel> evicted) {
    for (final channel in evicted) {
      final node = _focusState.cardFocusNodes[channel];
      if (node == null ||
          !_focusState.detachedRows.contains(channel) ||
          node.hasFocus) {
        continue;
      }
      _focusState.detachedRows.remove(channel);
      _focusState.cardFocusNodes.remove(channel)?.dispose();
    }
  }

  /// Re-fault the visible rows from the DB at the SAME generation — for a
  /// change written in place (channel numbers), where [DbChannelList.repin]
  /// does not apply because the generation never moved. Dropping the instance
  /// cache is what forces the stale [IptvChannel] objects to be rebuilt.
  void rebuildDbFacades(CatalogSnapshot snap) {
    _catalogState.dbInstanceCache.clear();
    _catalogState.dbInstanceCacheKey = null;
    _deps.setState(() {
      _catalogState.dbSnapshot = snap;
      _catalogState.allChannels = makeDbList(snap);
    });
    _deps.applyFilters();
  }

  /// True when a background revalidate's result no longer belongs on screen.
  /// The ticket covers playlist switches (they bump it synchronously), but a
  /// content-type switch clears the list and only bumps the ticket after its
  /// 350ms debounce — without the extra guards a revalidate completing in
  /// that window would resurrect the outgoing type's rows under the new
  /// type's layout.
  bool revalidateSuperseded(
    IptvPlaylist playlist,
    String contentType,
    int ticket,
  ) =>
      !_deps.mounted() ||
      ticket != _catalogState.loadTicket ||
      _catalogState.isLoading ||
      _settingsState.selectedPlaylist?.id != playlist.id ||
      (playlist.isXtreamCodes &&
          _catalogState.selectedContentType != contentType);
}
