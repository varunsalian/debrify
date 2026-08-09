import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/theme/app_sound.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/ui_feedback.dart';

/// The dispatcher's whole value is what it REFUSES to do.
///
/// A `FocusManager` listener that ticks on every notification is three lines
/// and would fire on dialog autofocus, route entry, and every one of the ~776
/// programmatic `requestFocus` restorations in this app. So most of what is
/// below asserts silence, which is only observable through the backend seam —
/// you cannot watch a `SystemSound` that did not happen.
class _RecordingBackend extends FeedbackBackend {
  final List<(SoundCharacter, HapticCharacter)> plays = [];

  @override
  void play(SoundCharacter sound, HapticCharacter haptic) =>
      plays.add((sound, haptic));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingBackend backend;
  late Duration now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = _RecordingBackend();
    now = Duration.zero;
    UiFeedback.instance.uninstall();
    UiFeedback.instance.backend = backend;
    UiFeedback.instance.clock = () => now;
    UiFeedback.instance.installForTest();
    // The singleton starts frozen (the launch ident owns the screen from
    // process start), which would mute everything.
    AppSurfaceState.instance
      ..reset()
      ..publishBootstrap(false);
    // Console is the one look that ticks.
    await AppThemeController.instance.select('console');
  });

  tearDown(() async {
    UiFeedback.instance.uninstall();
    AppSurfaceState.instance.reset();
    await AppThemeController.instance.select('legacy');
  });

  Future<void> pumpFocusable(WidgetTester tester, List<FocusNode> nodes) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final n in nodes) Focus(focusNode: n, child: const SizedBox()),
          ],
        ),
      ),
    );
  }

  testWidgets('a directional key followed by a focus change ticks once',
      (tester) async {
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);

    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    b.requestFocus();
    await tester.pump();

    expect(backend.plays, hasLength(1));
    // The test host is a DESKTOP: it traverses with a keyboard, so it gets
    // the sound; it has no actuator, so it gets no haptic. That split is the
    // platform matrix working, not a missing tick.
    expect(backend.plays.single.$1, SoundCharacter.click);
    expect(backend.plays.single.$2, HapticCharacter.none);
  });

  testWidgets('a programmatic focus restore is silent', (tester) async {
    // The case that matters most: returning from the player, rebuilding a
    // shelf, restoring a remembered row. No key, no evidence, no sound.
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);

    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    b.requestFocus();
    await tester.pump();
    a.requestFocus();
    await tester.pump();

    expect(backend.plays, isEmpty);
  });

  testWidgets('select and back never mint a token', (tester) async {
    // A select that pushes a route must not authorise the new route's
    // autofocus tick. (`goBack` has no physical key the simulator knows, so
    // escape stands in for the back button — the handler treats them the same
    // way it treats every non-directional key: it ignores them.)
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);
    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.space,
    ]) {
      await simulateKeyDownEvent(key);
      expect(UiFeedback.instance.debugHasToken, isFalse, reason: key.debugName);
    }

    b.requestFocus();
    await tester.pump();
    expect(backend.plays, isEmpty);
  });

  testWidgets('key-up does not mint', (tester) async {
    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    UiFeedback.instance.resetForTest();
    await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(UiFeedback.instance.debugHasToken, isFalse);
  });

  testWidgets('one token authorises exactly one focus change', (tester) async {
    final a = FocusNode();
    final b = FocusNode();
    final c = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(c.dispose);
    await pumpFocusable(tester, [a, b, c]);
    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    b.requestFocus();
    await tester.pump();
    // The second move has no key behind it — a shelf that re-homes focus after
    // the traversal must not get a free tick.
    now += const Duration(milliseconds: 200);
    c.requestFocus();
    await tester.pump();

    expect(backend.plays, hasLength(1));
  });

  testWidgets('a stale token cannot authorise a later autofocus',
      (tester) async {
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);
    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    now += const Duration(milliseconds: 400);
    b.requestFocus();
    await tester.pump();

    expect(backend.plays, isEmpty);
  });

  testWidgets('a held DPAD is rate limited, not silenced', (tester) async {
    // Repeats DO mint — each one is a real traversal — so the limiter is the
    // stated defence rather than an accident.
    final nodes = List.generate(8, (_) => FocusNode());
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    await pumpFocusable(tester, nodes);
    nodes.first.requestFocus();
    await tester.pump();
    backend.plays.clear();

    // Eight repeats 20ms apart — faster than the 60ms floor.
    for (var i = 1; i < 8; i++) {
      UiFeedback.instance.debugMintToken();
      nodes[i].requestFocus();
      await tester.pump();
      now += const Duration(milliseconds: 20);
    }

    expect(backend.plays, isNotEmpty, reason: 'a hold must still be audible');
    expect(backend.plays.length, lessThan(7), reason: 'and must not buzz');
  });

  testWidgets('a frozen surface mutes everything', (tester) async {
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);
    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    // The player and the launch ident own the screen and its audio.
    AppSurfaceState.instance.publishBootstrap(true);
    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    b.requestFocus();
    await tester.pump();
    UiFeedback.instance.activate();

    expect(backend.plays, isEmpty);
  });

  testWidgets('a silent theme never reaches the backend', (tester) async {
    await AppThemeController.instance.select('legacy');
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpFocusable(tester, [a, b]);
    a.requestFocus();
    await tester.pump();
    backend.plays.clear();

    await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
    b.requestFocus();
    await tester.pump();
    UiFeedback.instance.activate();

    expect(backend.plays, isEmpty);
  });

  testWidgets('activation is explicit and is not rate limited', (tester) async {
    // A select immediately after a move is two events and should sound like
    // two.
    final a = FocusNode();
    addTearDown(a.dispose);
    await pumpFocusable(tester, [a]);
    backend.plays.clear();

    UiFeedback.instance.activate();
    UiFeedback.instance.activate();
    expect(backend.plays, hasLength(2));
  });

  test('the key handler never consumes the key', () {
    // A true return would swallow the DPAD and break every screen in the app.
    expect(
      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
  });

  group('platform gating', () {
    const t = SoundTokens(
      traversal: SoundCharacter.click,
      activation: SoundCharacter.click,
      traversalHaptic: HapticCharacter.selection,
      activationHaptic: HapticCharacter.impact,
    );

    test('traversal sound belongs to devices with a cursor', () {
      // A TV remote and a desktop keyboard both traverse; a finger does not.
      // "Has a cursor" and "is a TV" are two different questions, and asking
      // only the second silenced every desktop user.
      expect(t.traversalFor(true), SoundCharacter.click);
      expect(t.traversalFor(false), SoundCharacter.silent);
      expect(t.activation, SoundCharacter.click);
    });

    test('haptics belong to devices with an actuator', () {
      // Not "not a TV": a desktop has no vibration motor either, and asking
      // it to buzz is a channel call into nothing.
      expect(t.hapticFor(false, activation: false), HapticCharacter.none);
      expect(t.hapticFor(false, activation: true), HapticCharacter.none);
      expect(t.hapticFor(true, activation: false), HapticCharacter.selection);
      expect(t.hapticFor(true, activation: true), HapticCharacter.impact);
    });

    test('the user can veto either half', () async {
      // The theme decides what there is to play; the user decides whether
      // they want it. Both default on, because every look but two is already
      // silent and a default cannot surprise someone who has not chosen one
      // of those two.
      expect(StorageService.uiSoundsCached, isTrue);
      expect(StorageService.uiHapticsCached, isTrue);
    });

    test('legacy is silent on both', () {
      expect(SoundTokens.legacy.isSilent, isTrue);
      expect(soundTokensFor(FeedbackCharacter.none), SoundTokens.legacy);
    });
  });
}
