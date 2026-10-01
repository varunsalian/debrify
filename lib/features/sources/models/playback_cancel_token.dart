/// Mutable flag the catalog-play flow polls to abort when the user taps Cancel
/// on the poster loading mask (the mask dismisses itself; the flow just stops).
class PlaybackCancelToken {
  bool cancelled = false;
}
