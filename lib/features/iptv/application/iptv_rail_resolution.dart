/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)"
/// — pulled out of the rail's big title into its sub-line (the channel rows do
/// the same split for themselves).
final RegExp railResExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);
