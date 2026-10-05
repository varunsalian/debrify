import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter/material.dart';

class DebrifyTvLibraryState {
  final TextEditingController keywordsController = TextEditingController();
  List<DebrifyTvChannel> channels = <DebrifyTvChannel>[];

  /// `debrify_tv_style`, read once per mount from the mirror warmed in
  /// `main()`: tabs are keyed by index and rebuilt on switch, so a picker
  /// change is picked up on the next entry — no bridge, like `iptv_style`.
  final String debrifyTvStyle = DebrifyTvStorage.debrifyTvStyleCached;
  final Map<String, DebrifyTvChannelCacheEntry> channelCache = {};
  String?
  currentWatchingChannelId; // Track currently playing channel for switching
  Set<String> favoriteChannelIds = {};
}
