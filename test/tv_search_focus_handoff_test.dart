import 'package:debrify/utils/tv_search_focus_handoff.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stock IME Search hands focus to the mounted result', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _SearchHarness(stock: true)),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-field-focus')), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('result-focus')), findsOneWidget);
  });

  testWidgets('Debrify keyboard Search keeps the same result handoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _SearchHarness(stock: false)),
    );
    await tester.pump();

    // Shell OK opens the Debrify keyboard. Four downs reach its action row;
    // left wraps from the first action to Search, then OK submits.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('result-focus')), findsOneWidget);
    expect(find.byType(TvKeyboardPanel), findsNothing);
  });

  testWidgets('late results do not steal focus after the user moves away', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _SearchHarness(stock: false, delayed: true)),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final harness = tester.state<_SearchHarnessState>(
      find.byType(_SearchHarness),
    );
    harness.focusOther();
    await tester.pump();
    expect(harness.otherHasFocus, isTrue);

    harness.showAndFocusResult();
    await tester.pump();
    await tester.pump();

    expect(harness.otherHasFocus, isTrue);
  });
}

class _SearchHarness extends StatefulWidget {
  const _SearchHarness({required this.stock, this.delayed = false});

  final bool stock;
  final bool delayed;

  @override
  State<_SearchHarness> createState() => _SearchHarnessState();
}

class _SearchHarnessState extends State<_SearchHarness> {
  final _controller = TextEditingController(text: 'query');
  final _field = FocusNode();
  final _result = FocusNode();
  final _other = FocusNode();
  final _handoff = TvSearchFocusHandoff();
  bool _showResult = false;
  bool _waiting = false;

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    _result.dispose();
    _other.dispose();
    super.dispose();
  }

  void _submit(String _) {
    _handoff.arm(enabled: true);
    if (widget.delayed) {
      setState(() => _waiting = true);
      return;
    }
    showAndFocusResult();
  }

  void focusOther() => _other.requestFocus();

  bool get otherHasFocus => _other.hasFocus;

  void showAndFocusResult() {
    setState(() {
      _waiting = false;
      _showResult = true;
    });
    _handoff.complete(
      field: _field,
      isMounted: () => mounted,
      requestFocus: _result.requestFocus,
      targetHasFocus: () => _result.hasFocus,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Focus(
            onFocusChange: (_) => setState(() {}),
            child: Builder(
              builder: (_) => TvTextField(
                controller: _controller,
                focusNode: _field,
                autofocus: true,
                forceTvKeyboard: !widget.stock,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                decoration: const InputDecoration(),
              ),
            ),
          ),
          if (_field.hasFocus)
            const SizedBox(key: ValueKey('search-field-focus')),
          Focus(
            focusNode: _other,
            onFocusChange: (_) => setState(() {}),
            child: GestureDetector(
              key: const ValueKey('other'),
              onTap: _other.requestFocus,
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
          if (_other.hasFocus) const SizedBox(key: ValueKey('other-focus')),
          if (_waiting)
            TextButton(
              key: const ValueKey('release-results'),
              onPressed: showAndFocusResult,
              child: const Text('Release'),
            ),
          if (_showResult)
            Focus(
              focusNode: _result,
              onFocusChange: (_) => setState(() {}),
              child: SizedBox(
                key: _result.hasFocus
                    ? const ValueKey('result-focus')
                    : const ValueKey('result'),
                width: 40,
                height: 40,
              ),
            ),
        ],
      ),
    );
  }
}
