/// Effective presentation values. Muting preserves the stored volume preference.
typedef HomeTrailerPreferences = ({bool enabled, double volume});

const initialHomeTrailerPreferences = (enabled: false, volume: 0.0);
