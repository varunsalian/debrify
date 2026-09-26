class SourcePrioritySettings {
  final List<String> providers;
  final Map<String, String> aliases;

  SourcePrioritySettings({
    List<String> providers = const [],
    Map<String, String> aliases = const {},
  }) : providers = List.unmodifiable(providers),
       aliases = Map.unmodifiable(aliases);
}

class SourcePresentationSettings {
  final SourcePrioritySettings priority;
  final bool useAddonText;
  final bool showAddonLogos;

  SourcePresentationSettings({
    SourcePrioritySettings? priority,
    this.useAddonText = false,
    this.showAddonLogos = false,
  }) : priority = priority ?? SourcePrioritySettings();
}
