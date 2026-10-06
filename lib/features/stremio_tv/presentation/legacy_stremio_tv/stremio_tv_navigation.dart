import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';

import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StremioTvNavigation {
  StremioTvNavigation(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;
  // ============================================================================
  // Search
  // ============================================================================
  List<StremioTvChannel> get filteredChannels {
    if (_owners.focus.searchQuery.isEmpty) return _owners.library.channels;
    return _owners.library.channels.where((ch) {
      final q = _owners.focus.searchQuery;
      return ch.displayName.toLowerCase().contains(q) ||
          ch.addon.displayName.toLowerCase().contains(q) ||
          ch.addon.name.toLowerCase().contains(q) ||
          ch.catalog.name.toLowerCase().contains(q) ||
          (ch.genre?.toLowerCase().contains(q) ?? false) ||
          ch.type.toLowerCase().contains(q);
    }).toList();
  }

  String? currentFocusedChannelId() {
    final focusedNodeIndex = _owners.focus.rowFocusNodes.indexWhere(
      (node) => node.hasFocus,
    );
    if (focusedNodeIndex >= 0 &&
        focusedNodeIndex < _owners.library.channels.length) {
      return _owners.library.channels[focusedNodeIndex].id;
    }
    if (_owners.focus.focusedIndex >= 0 &&
        _owners.focus.focusedIndex < _owners.library.channels.length) {
      return _owners.library.channels[_owners.focus.focusedIndex].id;
    }
    return null;
  }

  /// Returns focus from the header back into the Dial. Targets the card the
  /// user last had focused (so it works after surfing right) rather than
  /// always the first channel — whose card is scrolled off-screen and
  /// focus-detached, which is why down-arrow silently did nothing.
  void focusDialFromHeader() {
    if (_owners.focus.rowFocusNodes.isEmpty) return;
    final filtered = _sections.navigation.filteredChannels;
    if (filtered.isEmpty) return;
    // Preferred target: the last-focused channel if it's still displayed;
    // otherwise the first visible channel.
    int targetIdx = -1;
    if (_owners.focus.focusedIndex >= 0 &&
        _owners.focus.focusedIndex < _owners.focus.rowFocusNodes.length &&
        _owners.focus.focusedIndex < _owners.library.channels.length &&
        filtered.contains(
          _owners.library.channels[_owners.focus.focusedIndex],
        )) {
      targetIdx = _owners.focus.focusedIndex;
    } else {
      targetIdx = _owners.library.channels.indexOf(filtered.first);
    }
    if (targetIdx < 0 || targetIdx >= _owners.focus.rowFocusNodes.length)
      return;
    // Route through the tuner so an off-screen (recycled) dial card is scrolled
    // into view *before* focusing — a bare requestFocus on an unmounted
    // ListView child silently no-ops, which is why down-arrow from the header
    // could fail to return focus to the channels after a long surf.
    if (_owners.focus.tunerController.focusRealIndex(targetIdx)) return;
    // Fallback (narrow layout / tuner not mounted): best-effort direct focus.
    _owners.focus.rowFocusNodes[targetIdx].requestFocus();
  }

  void reorderRowFocusNodes(
    List<StremioTvChannel> previousChannels,
    List<StremioTvChannel> reorderedChannels,
  ) {
    final nodeByChannelId = <String, FocusNode>{};
    final previousLength =
        previousChannels.length < _owners.focus.rowFocusNodes.length
        ? previousChannels.length
        : _owners.focus.rowFocusNodes.length;
    for (int i = 0; i < previousLength; i++) {
      nodeByChannelId[previousChannels[i].id] = _owners.focus.rowFocusNodes[i];
    }

    final reorderedNodes = <FocusNode>[];
    for (int i = 0; i < reorderedChannels.length; i++) {
      reorderedNodes.add(
        nodeByChannelId.remove(reorderedChannels[i].id) ??
            FocusNode(debugLabel: 'stremioTvRow$i'),
      );
    }

    for (final leftover in nodeByChannelId.values) {
      leftover.dispose();
    }

    _owners.focus.rowFocusNodes
      ..clear()
      ..addAll(reorderedNodes);
  }

  /// Back/Escape ladder for the search bar: clear text first, then hide the
  /// field. Sits on an ancestor Focus of the search field so it runs when the
  /// TvTextField shell lets the key bubble.
  KeyEventResult handleSearchBarBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_owners.focus.searchController.text.isNotEmpty) {
        _owners.focus.searchController.clear();
        return KeyEventResult.handled;
      }
      // Hide search field on back when empty
      if (_owners.focus.showSearchField) {
        _deps.setState(() => _owners.focus.showSearchField = false);
        _owners.focus.searchBtnFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}
