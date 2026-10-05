import 'package:debrify/models/torrent.dart';

class DebrifyTvSessionState {
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> queue = [];
  bool isBusy = false;
  String status = '';
  List<Torrent>? pikpakCandidatePool;
  // Rate-limits the "filter relaxed" snackbar to once per playback session.
  bool qualityFallbackNotified = false;
  int rdSizeRejections = 0;
  bool sizeFilterRelaxed = false;
  // De-dupe sets for RD-restricted entries
  final Set<String> seenRestrictedLinks = {};
  final Set<String> seenLinkWithTorrentId = {};
  int lastQueueSize = 0;
  DateTime? lastSearchAt;
  bool launchedPlayer = false;
  bool watchCancelled = false;
  int? originalMaxCap;
}
