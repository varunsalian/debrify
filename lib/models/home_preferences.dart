/// Stored Spotlight hero-source mode.
enum HomeHeroSourceMode { auto, random, custom }

/// Custom IDs are retained in every mode so changing modes preserves picks.
typedef HomeHeroSource = ({HomeHeroSourceMode mode, List<String> ids});

/// One opted-in extra Home row, including its configured display title.
typedef HomeExtraRow = ({String id, String title});
