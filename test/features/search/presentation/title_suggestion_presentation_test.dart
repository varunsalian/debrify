import 'package:debrify/features/search/presentation/title_suggestion_presentation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'selection cancellation preserves newer ownership and IME edit identity',
    () {
      final presentation = TitleSuggestionPresentation();
      addTearDown(presentation.dispose);
      expect(
        presentation.acceptEdit(const TextEditingValue(text: 'title')),
        isTrue,
      );
      expect(
        presentation.acceptEdit(
          const TextEditingValue(
            text: 'title',
            selection: TextSelection.collapsed(offset: 2),
          ),
        ),
        isFalse,
      );
      expect(
        presentation.acceptEdit(
          const TextEditingValue(
            text: 'title',
            composing: TextRange(start: 0, end: 2),
          ),
        ),
        isTrue,
      );
      expect(
        presentation.acceptEdit(
          const TextEditingValue(
            text: 'title',
            composing: TextRange(start: 1, end: 3),
          ),
        ),
        isFalse,
      );
      expect(
        presentation.acceptEdit(const TextEditingValue(text: 'title')),
        isTrue,
      );
      final old = presentation.beginOpen();
      presentation.cancelOpen();
      final current = presentation.beginOpen();
      expect(presentation.accepts(old), isFalse);
      presentation.finishOpen(old);
      expect(presentation.opening, isTrue);
      presentation.finishOpen(current);
      expect(presentation.opening, isFalse);
    },
  );
}
