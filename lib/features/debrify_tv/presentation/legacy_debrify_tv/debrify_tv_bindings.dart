import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:flutter/material.dart';

class DebrifyTvDependencies {
  final DebrifyTvOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  late final DebrifyTvSections sections;
  DebrifyTvDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
  });
}
