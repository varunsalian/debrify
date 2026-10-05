import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';

class DebrifyTvPrefetchState {
  bool prefetchRunning = false;
  bool prefetchStopRequested = false;
  Future<void>? prefetchTask;
  // Invalidates an async start when playback exits while the preference is
  // still being read. Without this, a stopped player could start a late
  // prefetch loop after _stopPrefetch returned.
  int prefetchEpoch = 0;
  String? activeApiKey;
  // Which provider the active prefetch run resolves through. RD and AllDebrid
  // are the two cache-check-less providers that use the background prefetcher;
  // this tells _prefetchOneAtIndex / requestMagicNext which add+resolve path to
  // use against _activeApiKey.
  String activeProvider = DebrifyTvConstants.providerRealDebrid;
  final Set<String> inflightInfohashes = {};
}
