/// What the pane is showing. Sources are identified by playlist id so a
/// refresh that rebuilds the list can't shift the selection onto a neighbour.
sealed class IptvTwoPaneDest {
  const IptvTwoPaneDest();
}

class IptvTwoPaneSourceDest extends IptvTwoPaneDest {
  const IptvTwoPaneSourceDest(this.playlistId);
  final String playlistId;
}

class IptvTwoPaneAddDest extends IptvTwoPaneDest {
  const IptvTwoPaneAddDest();
}

class IptvTwoPaneListsDest extends IptvTwoPaneDest {
  const IptvTwoPaneListsDest();
}

class IptvTwoPaneStartupDest extends IptvTwoPaneDest {
  const IptvTwoPaneStartupDest();
}

class IptvTwoPaneAutoRefreshDest extends IptvTwoPaneDest {
  const IptvTwoPaneAutoRefreshDest();
}

class IptvTwoPaneContinueWatchingDest extends IptvTwoPaneDest {
  const IptvTwoPaneContinueWatchingDest();
}

class IptvTwoPaneChannelPreviewDest extends IptvTwoPaneDest {
  const IptvTwoPaneChannelPreviewDest();
}

class IptvTwoPaneAppearanceDest extends IptvTwoPaneDest {
  const IptvTwoPaneAppearanceDest();
}

class IptvTwoPanePlayerGuideDest extends IptvTwoPaneDest {
  const IptvTwoPanePlayerGuideDest();
}

class IptvTwoPaneRecordingDest extends IptvTwoPaneDest {
  const IptvTwoPaneRecordingDest();
}

/// Sports & leagues: which leagues the IPTV Sports board shows.
class IptvTwoPaneSportsDest extends IptvTwoPaneDest {
  const IptvTwoPaneSportsDest();
}
