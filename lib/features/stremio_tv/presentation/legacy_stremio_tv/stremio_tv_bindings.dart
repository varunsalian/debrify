import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';

import 'package:flutter/material.dart';

class StremioTvDependencies {
  final StremioTvOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final bool Function() isTelevision;
  late final StremioTvSections sections;
  // TEMP(stremio_tv): borrowed State tear-offs; removed with their scheduled moves.
  final Future<void> Function() loadSettings;
  final Future<void> Function() discoverAndLoad;
  final void Function(String channelId) playChannelById;
  StremioTvDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.isTelevision,
    required this.loadSettings,
    required this.discoverAndLoad,
    required this.playChannelById,
  });
}
