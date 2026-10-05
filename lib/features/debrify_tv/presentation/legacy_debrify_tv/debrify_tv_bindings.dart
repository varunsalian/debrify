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
    required this.watchChannel,
    required this.buildTvGridLayout,
    required this.showQuickPlayDialog,
    required this.showGlobalSettingsDialog,
    required this.stopPrefetch,
  });
}
