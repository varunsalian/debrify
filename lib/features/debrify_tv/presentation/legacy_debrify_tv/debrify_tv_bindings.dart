import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:flutter/material.dart';

class DebrifyTvDependencies {
  final DebrifyTvOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  late final DebrifyTvSections sections;

  // TEMP(debrify_tv): exact borrowed State tear-offs until their move step.
  final Future<void> Function() handleImportChannels;
  final Future<void> Function() handleExportChannels;
  final Future<void> Function() handleAddChannel;
  final Future<void> Function(DebrifyTvChannel) handleEditChannel;
  final Future<void> Function(DebrifyTvChannel) handleDeleteChannel;
  final Future<void> Function(DebrifyTvChannel) handleShareChannelAsMagnet;
  final Future<void> Function() handleDeleteAllChannels;
  final Future<void> Function(DebrifyTvChannel, {CachedTorrent? leadWith})
  watchChannel;
  final Widget Function(double) buildTvGridLayout;
  final Future<void> Function() showQuickPlayDialog;
  final Future<void> Function() showGlobalSettingsDialog;
  final Future<void> Function() stopPrefetch;
  DebrifyTvDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.handleImportChannels,
    required this.handleExportChannels,
    required this.handleAddChannel,
    required this.handleEditChannel,
    required this.handleDeleteChannel,
    required this.handleShareChannelAsMagnet,
    required this.handleDeleteAllChannels,
    required this.watchChannel,
    required this.buildTvGridLayout,
    required this.showQuickPlayDialog,
    required this.showGlobalSettingsDialog,
    required this.stopPrefetch,
  });
}
