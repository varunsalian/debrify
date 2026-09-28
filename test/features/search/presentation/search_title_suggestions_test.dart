import 'package:debrify/features/search/presentation/search_query_field.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'suggestion actions retain displayed query and title after inputs change',
    () {
      const title = StremioMeta(
        id: 'one',
        type: 'series',
        name: 'Show',
        year: '2020',
      );
      final items = [title];
      var query = 'original';
      final opened = <StremioMeta>[];
      final submitted = <String>[];
      final suggestions = buildSearchTitleSuggestions(
        items,
        query: query,
        onOpen: opened.add,
        onSubmit: submitted.add,
      );
      items.clear();
      query = 'new';
      suggestions.first.onSelected();
      suggestions.last.onSelected();
      expect(opened, [title]);
      expect(submitted, ['original']);
      expect(suggestions.first.subtitle, 'TV show · 2020');
      expect(suggestions.last.title, 'Search for “original”');
      expect(
        buildSearchTitleSuggestions(
          items,
          query: query,
          onOpen: opened.add,
          onSubmit: submitted.add,
        ),
        isEmpty,
      );
    },
  );
}
