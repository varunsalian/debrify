class SourceSeasonsState {
  final int? selected;
  final List<int> available;
  final List<int> derived;

  SourceSeasonsState({
    this.selected,
    List<int> available = const [],
    List<int> derived = const [],
  }) : available = List.unmodifiable(available),
       derived = List.unmodifiable(derived);
}
