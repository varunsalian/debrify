/// Coarse progress reporting for a blocking IPTV catalog load.
///
/// A first load of a big panel is several seconds of silence behind a bare
/// spinner, and silence reads as "frozen". These phases exist to say what is
/// happening, and to carry a real number whenever one is genuinely available
/// rather than invented.
///
/// [bytes]/[totalBytes] are only passed where the transfer is actually
/// observable — a streamed download with a running total. A buffered fetch
/// reports its size once, after it lands, which is still worth saying ("42.1
/// MB" explains a long pause better than nothing does).
typedef IptvLoadPhase = void Function(
  String phase, {
  int? bytes,
  int? totalBytes,
});

/// The phase labels, shared so the services and the page cannot drift apart —
/// the page derives "Step 2 of 4" from this order, so an unrecognized label
/// silently loses the step counter.
class IptvLoadPhases {
  const IptvLoadPhases._();

  static const contacting = 'Contacting provider';
  static const downloading = 'Downloading channel list';
  static const processing = 'Processing channel list';
  static const preparing = 'Preparing channels';

  /// Ordered, for the step counter.
  static const ordered = [contacting, downloading, processing, preparing];
}
