import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:flutter/material.dart';

class StremioTvTunerDependencies {
  final StremioTvTunerWidgetView view;
  final StremioTvTunerOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final StremioTvTunerSections Function() sections;
  StremioTvTunerDependencies({
    required this.view,
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.sections,
  });
}
