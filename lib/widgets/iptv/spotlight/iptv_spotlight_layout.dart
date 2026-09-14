import 'package:flutter/widgets.dart';

/// The presentation that can fit inside the IPTV result area's logical
/// constraints. Physical 1080p TVs commonly expose roughly 896x540 logical
/// pixels after the app rail, so these thresholds deliberately use the
/// available Flutter size rather than the display's physical resolution.
enum IptvSpotlightLayoutMode { classic, compact, wide }

const double kIptvSpotlightCompactMinWidth = 760;
// Below 480px the embedded search, category control and hero leave room for
// only one guide row. The existing classic layout is the useful fallback.
const double kIptvSpotlightCompactMinHeight = 480;
const double kIptvSpotlightWideMinWidth = 860;
const double kIptvSpotlightWideMinHeight = 480;

IptvSpotlightLayoutMode resolveIptvSpotlightLayout(Size availableSize) {
  if (availableSize.width >= kIptvSpotlightWideMinWidth &&
      availableSize.height >= kIptvSpotlightWideMinHeight) {
    return IptvSpotlightLayoutMode.wide;
  }
  if (availableSize.width >= kIptvSpotlightCompactMinWidth &&
      availableSize.height >= kIptvSpotlightCompactMinHeight) {
    return IptvSpotlightLayoutMode.compact;
  }
  return IptvSpotlightLayoutMode.classic;
}
