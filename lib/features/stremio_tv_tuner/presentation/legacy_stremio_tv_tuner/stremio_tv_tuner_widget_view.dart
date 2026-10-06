import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/services/stremio_tv_service.dart';
import 'package:flutter/material.dart';

abstract class StremioTvTunerWidgetView {
  List<StremioTvChannel> get channels;
  List<StremioTvChannel> get allChannels;
  List<FocusNode> get rowFocusNodes;
  StremioTvService get service;
  int Function(StremioTvChannel channel) get rotationFor;
  int get mixSalt;
  bool get hideNowPlaying;
  bool get autoRefresh;
  bool get isTelevision;
  Set<String> get loadingChannelIds;
  void Function(StremioTvChannel channel) get ensureLoaded;
  void Function(StremioTvChannel channel) get onOpenDetail;
  void Function(StremioTvChannel channel) get onPlay;
  double Function(StremioTvChannel channel, double rawProgress)
  get displayProgress;
  void Function(StremioTvChannel channel) get onToggleFavorite;
  void Function(StremioTvChannel channel) get onShowGuide;
  void Function(StremioTvChannel channel)? get onEditLocal;
  void Function(StremioTvChannel channel)? get onExportLocal;
  VoidCallback get onFocusSidebar;
  VoidCallback get onFocusHeader;
  void Function(int realIndex) get onFocusedIndexChanged;
}
