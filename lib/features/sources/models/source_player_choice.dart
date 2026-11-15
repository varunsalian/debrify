import 'source_row_actions.dart';

/// The player a source row's menu offers for one launch, opposite the
/// profile's default. Picking it never changes the saved default.
enum SourcePlayerChoice {
  debrify('debrify', 'Play in Debrify player'),
  external('external', 'Play in external player');

  const SourcePlayerChoice(this.mode, this.label);

  /// The launch's player mode, as [VideoPlayerLaunchArgs.playerModeOverride].
  final String mode;
  final String label;

  /// The other player for a row of [kind], or null when there is none to
  /// offer: browser links have no player, media-server streams always play in
  /// Debrify (an external app never receives their session headers), and a
  /// profile without external players gets no external offer. [defaultMode] is the stored setting
  /// ('debrify', 'external' or 'deovr').
  static SourcePlayerChoice? alternateTo(
    String defaultMode, {
    required SourceRowActionKind kind,
    required bool externalAllowed,
  }) {
    if (kind == SourceRowActionKind.external ||
        kind == SourceRowActionKind.mediaServer) {
      return null;
    }
    if (defaultMode != 'debrify') return SourcePlayerChoice.debrify;
    return externalAllowed ? SourcePlayerChoice.external : null;
  }
}
