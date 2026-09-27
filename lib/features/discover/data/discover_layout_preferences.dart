/// Storage and warm-start boundary. The reader must check request ownership
/// before publishing any shared cache side effects after its await.
class DiscoverLayoutPreferences {
  const DiscoverLayoutPreferences({
    required this.readCached,
    required this.readSaved,
    required this.remember,
  });

  final String Function() readCached;
  final Future<String> Function(bool Function() isCurrent) readSaved;
  final void Function(String layout) remember;
}
