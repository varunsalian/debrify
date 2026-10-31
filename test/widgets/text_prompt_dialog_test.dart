// Apple TV users could type collection or stream-badge JSON into the import
// prompt but never reach its Import button: the multiline field kept every
// UP/DOWN press for its caret. On TV the prompt's field is one line and DOWN
// goes to the action.

import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/text_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the prompt; the returned list receives its result when it closes.
Future<List<String?>> _open(WidgetTester tester) async {
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showDialog<String>(
              context: context,
              builder: (_) => const TextPromptDialog(
                title: 'Paste collection JSON',
                hint: '[ … ]',
                helper: 'Paste the contents of a collections JSON file.',
                action: 'Import',
                multiline: true,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  final keyboardDefault = TvDisplayStorage.tvKeyboardEnabledCached;
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    TvDisplayStorage.tvKeyboardEnabledCached = keyboardDefault;
  });

  testWidgets('Android TV: DOWN from the field reaches the action', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    TvDisplayStorage.tvKeyboardEnabledCached = true;
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'text-prompt-action',
    );
  });

  testWidgets('Apple TV system keyboard: DOWN reaches Import, which imports', (
    tester,
  ) async {
    PlatformUtil.debugSetTvOS(true);
    TvDisplayStorage.tvKeyboardEnabledCached = false;
    final results = await _open(tester);
    await tester.enterText(find.byType(TextField), '[{"title":"Mine"}]');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'text-prompt-action',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(results, ['[{"title":"Mine"}]']);
  });

  testWidgets('off TV the paste field stays multiline', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    await _open(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 10);
  });
}
