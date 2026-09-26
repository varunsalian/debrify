/// Determines which local bookmark owns resume for the current playback.
///
/// Generic files and debrid-library entries keep their source-specific record
/// first. Catalog launches use their authoritative IMDb identity, so changing
/// releases does not move playback back to an older source bookmark.
enum PlaybackResumePolicy { sourceSpecific, catalogCanonical }
