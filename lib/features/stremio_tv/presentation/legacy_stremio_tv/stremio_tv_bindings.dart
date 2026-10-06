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
  StremioTvDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.isTelevision,
  });
}
