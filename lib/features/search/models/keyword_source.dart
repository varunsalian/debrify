/// A keyword engine's dialog-facing settings; executor/config objects stay in
/// the data adapter. IDs and defaults retain the engine registry's semantics.
class KeywordSource {
  final String id;
  final String label;
  final bool enabled;

  const KeywordSource({
    required this.id,
    required this.label,
    required this.enabled,
  });

  KeywordSource withEnabled(bool value) =>
      KeywordSource(id: id, label: label, enabled: value);
}
