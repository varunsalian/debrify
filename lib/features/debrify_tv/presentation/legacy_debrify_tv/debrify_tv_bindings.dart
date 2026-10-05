import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:flutter/material.dart';

class DebrifyTvDependencies {
  final DebrifyTvOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  late final DebrifyTvSections sections;

  // TEMP(debrify_tv): exact borrowed State tear-offs until their move step.
  final Future<void> Function() loadSettings;
  final Future<void> Function() loadChannels;
  final void Function() handleSyncedDebrifyTvLibraryChanged;
  final Future<void> Function() loadFavoriteChannels;
  final Future<void> Function(String) watchChannelById;
  final Future<void> Function() checkPendingAutoPlay;
  final DebrifyTvView Function() buildSpotlightView;
  final Widget Function(double) buildTvGridLayout;
  final Future<void> Function() stopPrefetch;
  DebrifyTvDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.loadSettings,
    required this.loadChannels,
    required this.handleSyncedDebrifyTvLibraryChanged,
    required this.loadFavoriteChannels,
    required this.watchChannelById,
    required this.checkPendingAutoPlay,
    required this.buildSpotlightView,
    required this.buildTvGridLayout,
    required this.stopPrefetch,
  });
}
