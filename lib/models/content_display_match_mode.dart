enum ContentDisplayMatchMode {
  /// Preserve the platform/player behavior from before display matching was
  /// configurable. On Android TV this includes Media3's seamless frame-rate
  /// hinting; on tvOS Debrify does not publish display criteria.
  systemDefault('system', 'System managed'),

  /// Explicitly disable player-owned display matching requests.
  off('off', 'Off'),

  /// Match the content cadence while keeping the configured output raster.
  frameRate('frame_rate', 'Match frame rate'),

  /// Publish the content cadence and dimensions. Android TV can select an
  /// exact output mode; tvOS treats the dimensions as best-effort criteria.
  frameRateAndResolution(
    'frame_rate_resolution',
    'Match frame rate and resolution',
  );

  const ContentDisplayMatchMode(this.storageKey, this.label);

  final String storageKey;
  final String label;

  bool get requestsMatching =>
      this == frameRate || this == frameRateAndResolution;

  bool get matchesResolution => this == frameRateAndResolution;

  static ContentDisplayMatchMode fromStorage(String? value) {
    return ContentDisplayMatchMode.values.firstWhere(
      (mode) => mode.storageKey == value,
      orElse: () => ContentDisplayMatchMode.systemDefault,
    );
  }
}
