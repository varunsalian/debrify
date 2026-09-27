/// Storage boundary for the first-frame mirror and the saved layout preference.
class HomeLayoutPreferences {
  const HomeLayoutPreferences({
    required this.readCached,
    required this.readSaved,
  });

  final String Function() readCached;
  final Future<String> Function() readSaved;
}
