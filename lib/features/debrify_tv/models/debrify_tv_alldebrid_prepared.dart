/// Result of adding an AllDebrid magnet for Debrify TV: the resolved (still
/// locked) video-file links plus identifiers for the created magnet.
class DebrifyTvAllDebridPrepared {
  final String magnetId;
  final String name;
  final List<String> lockedLinks;
  DebrifyTvAllDebridPrepared({
    required this.magnetId,
    required this.name,
    required this.lockedLinks,
  });
}
