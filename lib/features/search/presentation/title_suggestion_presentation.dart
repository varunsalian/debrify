import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/text_field_suggestions.dart';
import 'search_query_field.dart';

/// Route-local suggestion presentation and selection ownership. Lookup/profile
/// eligibility remain host decisions; cancelled selections cannot finish newer ones.
class TitleSuggestionPresentation {
  final suggestions = ValueNotifier<List<TextFieldSuggestion>>(const []);
  String _text = '';
  bool _composing = false;
  int _generation = 0;
  bool opening = false;

  bool acceptEdit(TextEditingValue editing) {
    final composing =
        editing.composing.isValid && !editing.composing.isCollapsed;
    if (editing.text == _text && composing == _composing) return false;
    _text = editing.text;
    _composing = composing;
    return true;
  }

  void cancelOpen() {
    _generation++;
    opening = false;
  }

  int beginOpen() {
    opening = true;
    return _generation;
  }

  bool accepts(int generation) => generation == _generation;

  void finishOpen(int generation) {
    if (accepts(generation)) opening = false;
  }

  void publish(
    List<StremioMeta> items, {
    required String query,
    required ValueChanged<StremioMeta> onOpen,
    required ValueChanged<String> onSubmit,
  }) {
    suggestions.value = buildSearchTitleSuggestions(
      items,
      query: query,
      onOpen: onOpen,
      onSubmit: onSubmit,
    );
  }

  void dispose() => suggestions.dispose();
}
