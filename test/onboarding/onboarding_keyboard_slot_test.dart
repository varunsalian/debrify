import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/onboarding/tv_keyboard_slot.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
  });

  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets('slot owns panel and Back tears it down without an overlay', (
    tester,
  ) async {
    final session = TvKeyboardSession();
    final text = TextEditingController();
    final fieldKey = GlobalKey<TvTextFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvKeyboardSlot(
            session: session,
            child: Column(
              children: [
                TvTextField(key: fieldKey, controller: text),
                ValueListenableBuilder<TvKeyboardController?>(
                  valueListenable: session.panel,
                  builder: (_, controller, __) => controller == null
                      ? const SizedBox.shrink()
                      : TvKeyboardPanel(controller: controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TvTextField));
    await tester.pump();
    expect(session.panel.value, isNotNull);
    expect(find.byType(TvKeyboardPanel), findsOneWidget);
    expect(fieldKey.currentState!.debugHasKeyboardOverlay, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.panel.value, isNull);
    expect(find.byType(TvKeyboardPanel), findsNothing);
    expect(session.ownsBack, isTrue);
    await tester.pump(const Duration(milliseconds: 301));
    expect(session.ownsBack, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    text.dispose();
  });

  testWidgets('without a slot the historical root overlay path is retained', (
    tester,
  ) async {
    final text = TextEditingController();
    final fieldKey = GlobalKey<TvTextFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvTextField(key: fieldKey, controller: text),
        ),
      ),
    );

    await tester.tap(find.byType(TvTextField));
    await tester.pump();
    expect(fieldKey.currentState!.debugHasKeyboardOverlay, isTrue);
    expect(find.byType(TvKeyboardPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(fieldKey.currentState!.debugHasKeyboardOverlay, isFalse);
    expect(find.byType(TvKeyboardPanel), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    text.dispose();
  });

  testWidgets('system IME and widget removal clear the slotted controller', (
    tester,
  ) async {
    final session = TvKeyboardSession();
    final text = TextEditingController();
    var showField = true;
    late StateSetter setHarnessState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return Scaffold(
              body: TvKeyboardSlot(
                session: session,
                child: Column(
                  children: [
                    if (showField) TvTextField(controller: text),
                    ValueListenableBuilder<TvKeyboardController?>(
                      valueListenable: session.panel,
                      builder: (_, controller, __) => controller == null
                          ? const SizedBox.shrink()
                          : TvKeyboardPanel(controller: controller),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(TvTextField));
    await tester.pump();
    final controller = session.panel.value!;
    final systemIme = controller.rows
        .expand((row) => row)
        .firstWhere((key) => key.action == TvKeyAction.systemIme);
    controller.activate(systemIme);
    await tester.pump();
    expect(session.panel.value, isNull);

    setHarnessState(() => showField = false);
    await tester.pump();
    setHarnessState(() => showField = true);
    await tester.pump();
    await tester.tap(find.byType(TvTextField));
    await tester.pump();
    expect(session.panel.value, isNotNull);
    setHarnessState(() => showField = false);
    await tester.pump();
    await tester.pump();
    expect(session.panel.value, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    text.dispose();
  });

  test('a stale detach cannot blank a newer controller', () {
    final session = TvKeyboardSession();
    final first = _controller();
    final second = _controller();

    session.attach(first);
    session.attach(second);
    session.detach(first);
    expect(session.panel.value, same(second));
    session.detach(second);
    expect(session.panel.value, isNull);

    first.dispose();
    second.dispose();
    session.dispose();
  });
}

TvKeyboardController _controller() => TvKeyboardController(
  onInsert: (_) {},
  onBackspace: () {},
  onClear: () {},
  onSubmit: () {},
  onSystemIme: () {},
  onVoice: () {},
  onVoiceStop: () {},
  onPaste: () {},
);
