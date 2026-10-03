import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:debrify/widgets/iptv/iptv_centered_selector.dart';
import 'package:debrify/widgets/iptv/iptv_channel_row.dart';
import 'package:flutter/material.dart';

typedef IptvTabletSelectionDeps = ({
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  List<IptvListMeta> Function() customLists,
  bool Function() mounted,
  void Function(IptvChannel channel, {bool fromPointer}) onChannelFocused,
  Future<void> Function(IptvChannel channel) openListPicker,
  VoidCallback? Function(IptvChannel channel, {bool inPlace}) scheduleActionFor,
  Future<void> Function(IptvChannel channel) showContinueWatchingActions,
  bool Function() showsPosterRows,
  Future<void> Function(IptvChannel channel, bool isFavorited) toggleFavorite,
});

class IptvTabletSelection {
  final IptvTabletSelectionDeps _deps;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvTabletSelection(this._deps)
    : _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  bool get _showsPosterRows => _deps.showsPosterRows();

  Widget buildTabletCenteredSelector(
    List<IptvChannel> channels, {
    required double rowExtent,
    required bool epgRows,
  }) {
    final selection = reconcileTabletSelection(channels);
    return IptvCenteredSelector(
      key: const ValueKey('iptv-tablet-centered-selector'),
      itemCount: channels.length,
      itemExtent: rowExtent,
      initialIndex: selection.index,
      selectionToken: selection.identity,
      onSelected: (index) {
        if (!_deps.mounted() || index < 0 || index >= channels.length) return;
        selectTabletChannel(index, channels[index]);
      },
      itemBuilder: (context, index, selected, centerItem) {
        final channel = channels[index];
        final openSchedule = _deps.scheduleActionFor(channel, inPlace: true);
        return IptvChannelRow(
          key: ObjectKey(channel),
          channel: channel,
          isPreviewSelected: selected,
          onTap: centerItem,
          onLongPress:
              (_settingsState.selectedPlaylist?.isContinueWatching ?? false)
              ? () => _deps.showContinueWatchingActions(channel)
              : null,
          isFavorited: _membershipState.favoriteUrls.contains(channel.url),
          inAnyList:
              _membershipState.membership[channel.url]?.isNotEmpty ?? false,
          onFavoriteToggle: channel.contentType == 'series'
              ? null
              : (isFavorited) => _deps.toggleFavorite(channel, isFavorited),
          onOpenListPicker: channel.contentType == 'series'
              ? null
              : () => _deps.openListPicker(channel),
          hasCustomLists: _customLists.isNotEmpty,
          onSchedule: openSchedule == null
              ? null
              : () {
                  centerItem();
                  selectTabletChannel(index, channel);
                  openSchedule();
                },
          progress: _membershipState.progressByUrl[channel.url],
          poster: _showsPosterRows,
          epg: epgRows,
        );
      },
    );
  }

  TabletChannelIdentity tabletIdentityOf(IptvChannel channel) => (
    channelNumber: channel.channelNumber,
    name: channel.name,
    url: channel.url,
    group: channel.group,
    contentType: channel.contentType,
  );

  ({int index, TabletChannelIdentity identity}) reconcileTabletSelection(
    List<IptvChannel> channels,
  ) {
    assert(channels.isNotEmpty);
    final wanted = _selectionState.tabletSelectedIdentity;
    if (wanted != null) {
      final previous = _selectionState.tabletSelectedIndex;
      if (previous >= 0 &&
          previous < channels.length &&
          tabletIdentityOf(channels[previous]) == wanted) {
        return (index: previous, identity: wanted);
      }

      // Materialized lists (including progressive Stremio snapshots) can
      // cheaply find a row that moved after filtering. Never walk a paged DB
      // facade here: that could fault tens of thousands of rows during build.
      if (channels is! DbChannelList) {
        for (var index = 0; index < channels.length; index++) {
          if (tabletIdentityOf(channels[index]) == wanted) {
            _selectionState.tabletSelectedIndex = index;
            return (index: index, identity: wanted);
          }
        }
      } else {
        final shown = _previewState.previewShown.value;
        final index = shown == null ? null : channels.indexOfInstance(shown);
        if (index != null && tabletIdentityOf(channels[index]) == wanted) {
          _selectionState.tabletSelectedIndex = index;
          return (index: index, identity: wanted);
        }
      }
    }

    final identity = tabletIdentityOf(channels.first);
    _selectionState.tabletSelectedIndex = 0;
    _selectionState.tabletSelectedIdentity = identity;
    return (index: 0, identity: identity);
  }

  void selectTabletChannel(int index, IptvChannel channel) {
    _selectionState.tabletSelectedIndex = index;
    _selectionState.tabletSelectedIdentity = tabletIdentityOf(channel);
    _deps.onChannelFocused(channel);
  }
}
