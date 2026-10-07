import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineDependencies {
  final SpotlightTimelineWidgetView view;
  final SpotlightTimelineOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final TvHoldOk Function() holdOk;
  final SpotlightTimelineSections Function() sections;
  SpotlightTimelineDependencies({
    required this.view,
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.holdOk,
    required this.sections,
  });
}
