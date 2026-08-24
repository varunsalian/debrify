import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:debrify/widgets/tv_text_field.dart';

/// The live input preview on the TV Debrify keyboard: the bottom-anchored
/// panel can cover the very field it edits, so the panel's top row mirrors
/// the field's content — pre-existing text included — as it is typed.
void main() {
  const previewKey = ValueKey('tv-keyboard-preview');

  Finder previewText(String text) =>
      find.descendant(of: find.byKey(previewKey), matching: find.text(text));

  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    String initialText = '',
    bool obscure = false,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initialText);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TvTextField(
              controller: controller,
              forceTvKeyboard: true,
              autofocus: true,
              obscureText: obscure,
              hintText: hint,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // OK on the shell opens the keyboard overlay.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('pre-existing text appears in the preview when the keyboard '
      'opens', (tester) async {
    await pumpField(tester, initialText: 'hello world');
    expect(find.byKey(previewKey), findsOneWidget);
    expect(previewText('hello world'), findsOneWidget);
  });

  testWidgets('preview tracks typing live', (tester) async {
    await pumpField(tester);
    // Fresh keyboard highlight sits on '1' — OK types it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(previewText('1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(previewText('11'), findsOneWidget);
  });

  testWidgets('empty field shows the hint dimmed', (tester) async {
    await pumpField(tester, hint: 'Search titles');
    expect(previewText('Search titles'), findsOneWidget);
  });

  testWidgets('obscured fields preview bullets, never the secret', (
    tester,
  ) async {
    await pumpField(tester, initialText: 'secret', obscure: true);
    expect(previewText('••••••'), findsOneWidget);
    // (The field's own EditableText still *matches* 'secret' by controller
    // text even though it renders bullets — only the preview is assertable.)
    expect(previewText('secret'), findsNothing);
  });

  testWidgets('preview stays up while dictation takes over the keys', (
    tester,
  ) async {
    final kb = TvKeyboardController(
      onInsert: (_) {},
      onBackspace: () {},
      onClear: () {},
      onSubmit: () {},
      onSystemIme: () {},
      onVoice: () {},
      onVoiceStop: () {},
      onPaste: () {},
      voiceAvailable: true,
    );
    addTearDown(kb.dispose);
    final text = TextEditingController(text: 'so far');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvKeyboardPanel(controller: kb, previewController: text),
        ),
      ),
    );
    expect(previewText('so far'), findsOneWidget);

    kb.beginListening();
    await tester.pump();
    // The mic view replaced the keys, but the live field view survived.
    expect(find.text('Speak now'), findsOneWidget);
    expect(previewText('so far'), findsOneWidget);
  });

  testWidgets('a panel without a preview controller renders no preview bar', (
    tester,
  ) async {
    final kb = TvKeyboardController(
      onInsert: (_) {},
      onBackspace: () {},
      onClear: () {},
      onSubmit: () {},
      onSystemIme: () {},
      onVoice: () {},
      onVoiceStop: () {},
      onPaste: () {},
    );
    addTearDown(kb.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvKeyboardPanel(controller: kb)),
      ),
    );
    expect(find.byKey(previewKey), findsNothing);
  });
}
