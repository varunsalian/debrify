import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class SpotlightTimelineWidgetView {
  List<IptvChannel> get channels;
  String get sourceId;
  int get loadGeneration;
  SpotlightScheduleLoader get scheduleLoader;
  SpotlightChannelActivate get onChannelActivate;
  SpotlightProgrammeActivate get onProgrammeActivate;
  int get epgContextVersion;
  ValueChanged<SpotlightTimelineSelection>? get onSelectionChanged;
  bool get autofocus;
  VoidCallback? get onExitUp;
  VoidCallback? get onExitLeft;
  SpotlightChannelActivate? get onChannelActions;
  bool get selectBeforeActivate;
  DateTime Function() get now;
  Duration get windowDuration;
  Duration get viewportSettleDelay;
  double get height;
  bool get dense;
  double get identityWidth;
  double get rowHeight;
  double get rulerHeight;
}
