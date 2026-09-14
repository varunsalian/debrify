import 'package:debrify/widgets/text_field_suggestions.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController text;
  late ValueNotifier<List<TextFieldSuggestion>> suggestions;
  late List<String> selected;
  late List<String> submitted;

  List<TextFieldSuggestion> choices() => [
    for (final year in ['1984', '2021'])
      TextFieldSuggestion(
        id: year,
        title: 'Dune',
        subtitle: 'Movie · $year',
        year: year,
        onSelected: () => selected.add(year),
      ),
  ];

  setUp(() {
    text = TextEditingController(text: 'Dune');
    selected = [];
    submitted = [];
    suggestions = ValueNotifier(choices());
  });
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    StorageService.tvKeyboardEnabledCached = true;
    text.dispose();
    suggestions.dispose();
  });

  Future<void> mount(WidgetTester tester, {bool tv = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TvTextField(
                controller: text,
                suggestions: suggestions,
                suggestionsLabel: 'Titles from TMDB',
                autofocus: true,
                forceTvKeyboard: tv,
                textInputAction: TextInputAction.search,
                onSubmitted: submitted.add,
              ),
              TextButton(onPressed: () {}, child: const Text('Elsewhere')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'stock keyboard arrows select the intended remake without submitting',
    (tester) async {
      await mount(tester);
      expect(find.text('Dune (1984)'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, ['2021']);
      expect(submitted, isEmpty);
      expect(find.byType(TextFieldSuggestions), findsNothing);
    },
  );

  testWidgets('Android TV system keyboard routes arrows to titles', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = false;
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, ['1984']);
    expect(find.byType(TvKeyboardPanel), findsNothing);
  });

  testWidgets(
    'Apple TV keyboard dismissal reveals choices and preserves ordinary fields',
    (tester) async {
      PlatformUtil.debugSetTvOS(true);
      StorageService.tvKeyboardEnabledCached = false;
      await mount(tester);
      Future<void> endEditing() async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'debrify/tvkeyboard',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('endEditing'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await endEditing();
      expect(submitted, isEmpty);
      expect(find.byType(TextFieldSuggestions), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selected, ['1984']);

      suggestions.value = [];
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await endEditing();
      expect(submitted, ['Dune']);
    },
  );

  testWidgets('stock IME Search keeps explicit raw-query submission', (
    tester,
  ) async {
    await mount(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(submitted, ['Dune']);
    expect(selected, isEmpty);
    expect(find.byType(TextFieldSuggestions), findsNothing);
  });

  testWidgets('touch selects a title while the IME is open', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Dune (1984)'));
    await tester.pumpAndSettle();
    expect(selected, ['1984']);
    expect(submitted, isEmpty);
  });

  testWidgets(
    'Debrify keyboard moves between titles and keys without typing a title selection',
    (tester) async {
      await mount(tester, tv: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TvKeyboardPanel), findsOneWidget);
      expect(find.byType(TextFieldSuggestions), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(text.text, 'Dune1');
      expect(selected, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selected, ['2021']);
      expect(text.text, 'Dune1');
      expect(submitted, isEmpty);
      expect(find.byType(TvKeyboardPanel), findsNothing);
    },
  );

  testWidgets(
    'TV shell can select suggestions after closing the Debrify keyboard',
    (tester) async {
      await mount(tester, tv: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selected, ['1984']);
      expect(find.byType(TvKeyboardPanel), findsNothing);
    },
  );

  testWidgets('cleared choices remove a highlighted title safely', (
    tester,
  ) async {
    await mount(tester, tv: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    suggestions.value = [];
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(text.text, 'Dune1');
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escape dismisses suggestions until text changes', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextFieldSuggestions), findsNothing);
    suggestions.value = choices();
    await tester.pumpAndSettle();
    expect(find.byType(TextFieldSuggestions), findsNothing);
    await tester.enterText(find.byType(TextField), 'Dune part');
    suggestions.value = choices();
    await tester.pumpAndSettle();
    expect(find.byType(TextFieldSuggestions), findsOneWidget);
  });

  testWidgets('late choices do not take focus from another control', (
    tester,
  ) async {
    await mount(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    suggestions.value = choices();
    await tester.pumpAndSettle();
    expect(find.byType(TextFieldSuggestions), findsNothing);
  });

  testWidgets('the horizontal strip follows the top of the system keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    const title =
        'An unusually long movie title with enough words to span several lines on a phone';
    suggestions.value = [
      TextFieldSuggestion(
        id: 'long',
        title: title,
        subtitle: 'Movie · 2026',
        onSelected: () {},
      ),
    ];
    await mount(tester);
    final strip = find.byType(TextFieldSuggestions);
    expect(tester.widget<Text>(find.text(title)).maxLines, 1);
    expect(tester.getSize(find.text(title)).width, greaterThan(390));
    expect(tester.getSize(strip).height, lessThanOrEqualTo(60));
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.descendant(
              of: strip,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .scrollDirection,
      Axis.horizontal,
    );
    expect(
      find.descendant(of: strip, matching: find.byType(Image)),
      findsNothing,
    );
    expect(tester.getBottomRight(strip).dy, closeTo(370, 0.1));
    tester.view.viewInsets = const FakeViewPadding(bottom: 450);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(strip).dy, closeTo(250, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Down leaves the strip and restores left/right caret movement', (
    tester,
  ) async {
    await mount(tester);
    text.selection = const TextSelection.collapsed(offset: 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(text.selection.baseOffset, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(text.selection.baseOffset, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(text.selection.baseOffset, 2);
    expect(selected, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(submitted, ['Dune']);
  });

  testWidgets('touch can scroll the strip and select an offscreen title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    suggestions.value = [
      for (var i = 0; i < 6; i++)
        TextFieldSuggestion(
          id: '$i',
          title: 'Movie $i',
          subtitle: 'Movie · 2026',
          year: '2026',
          onSelected: () => selected.add('$i'),
        ),
    ];
    await mount(tester);
    final strip = find.byType(TextFieldSuggestions);
    await tester.drag(strip, const Offset(-1500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movie 5 (2026)'));
    await tester.pumpAndSettle();
    expect(selected, ['5']);
    expect(submitted, isEmpty);
    expect(strip, findsNothing);
  });

  testWidgets('remote selection scrolls horizontal choices into view', (
    tester,
  ) async {
    suggestions.value = [
      for (var i = 0; i < 7; i++)
        TextFieldSuggestion(
          id: '$i',
          title: 'A different movie $i',
          subtitle: 'Movie · 2026',
          year: '2026',
          onSelected: () => selected.add('$i'),
        ),
    ];
    await mount(tester, tv: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final strip = find.byType(TextFieldSuggestions);
    expect(
      tester.getTopLeft(find.text('A different movie 0 (2026)')).dy,
      tester.getTopLeft(find.text('A different movie 1 (2026)')).dy,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(strip)
          .contains(tester.getCenter(find.text('A different movie 6 (2026)'))),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, ['6']);
    expect(submitted, isEmpty);
  });
}
