/// Stored Spotlight hero-source mode.
enum HomeHeroSourceMode { auto, random, custom }

/// Custom IDs are retained in every mode so changing modes preserves picks.
typedef HomeHeroSource = ({HomeHeroSourceMode mode, List<String> ids});

/// One opted-in extra Home row, including its configured display title.
typedef HomeExtraRow = ({String id, String title});

/// Artwork orientation for TITLE cards on the Home layouts: portrait 2:3
/// posters or landscape 16:9 backdrops. Favourites, channel, and playlist
/// rows keep their own geometry — a station logo or folder is not a title.
/// Promenade is landscape by design and ignores the portrait setting.
enum HomeCardOrientation { portrait, landscape }
