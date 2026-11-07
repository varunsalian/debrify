// Throwaway iPhone Duo tour for the ios-duo-sim-check branch.
//
// Drives a fresh install through the main screens while the CI script folds,
// unfolds and rotates the simulator. The two sides talk through files in the
// app's tmp directory: the test writes `req-N` with a duoctl command or
// `shot NAME`, and the host answers with `ack-N` holding the exit code.
import 'dart:async';
import 'dart:io';

import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:debrify/main.dart' as app;
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/widgets/youtube/youtube_video_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('iPhone Duo tour', (tester) async {
    final tour = _Tour(tester);
    await tour.run();
  }, timeout: const Timeout(Duration(minutes: 30)));
}

class _Tour {
  _Tour(this.tester);

  final WidgetTester tester;
  final Directory _dir = Directory('${Directory.systemTemp.path}/duo');
  final List<String> errors = <String>[];
  final List<String> problems = <String>[];
  final List<String> notes = <String>[];
  String step = 'launch';
  int _seq = 0;

  Future<void> run() async {
    _dir.createSync(recursive: true);
    // ignore: avoid_print
    print('DUO SYNC DIR ${_dir.path}');
    final originalOnError = FlutterError.onError;
    final originalDebugPrint = debugPrint;

    // Device-owned keys only, so bootstrap still treats this as a fresh
    // install. They stop the update dialog and remote-control discovery,
    // which would otherwise raise the local-network prompt.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('update_auto_check_enabled', false);
    await prefs.setBool('remote_control_enabled', false);

    await host('open --duration 1');
    unawaited(app.main(const <String>[]));

    try {
      await _tour();
    } finally {
      step = 'finish';
      final summary = StringBuffer()
        ..writeln('flutter errors: ${errors.length}')
        ..writeAll(errors.map((e) => '  $e\n'))
        ..writeln('problems: ${problems.length}')
        ..writeAll(problems.map((e) => '  $e\n'))
        ..writeln('notes: ${notes.length}')
        ..writeAll(notes.map((e) => '  $e\n'));
      // ignore: avoid_print
      print('DUO TOUR SUMMARY\n$summary');
      File('${_dir.path}/summary.txt').writeAsStringSync(summary.toString());
      await host('end');
      FlutterError.onError = originalOnError;
      debugPrint = originalDebugPrint;
    }
    expect(problems, isEmpty, reason: 'tour problems');
    expect(errors, isEmpty, reason: 'Flutter errors during the tour');
  }

  Finder get _gateTitle => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains('watching?'),
  );
  Finder get _skip => find.textContaining('Skip');
  Finder get _welcome => find.textContaining('WELCOME');

  /// The onboarding choices are a lazy list, so on a short screen the Skip
  /// pill is not built until the list is scrolled to it.
  Future<void> revealSkip() async {
    final list = find.ancestor(
      of: find.text('Log in with WebDAV'),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 12; i++) {
      if (_skip.hitTestable().evaluate().isNotEmpty) return;
      if (list.evaluate().isEmpty) return;
      await tester.drag(list.first, const Offset(0, -200), warnIfMissed: false);
      await idle(const Duration(milliseconds: 500));
    }
    if (_skip.evaluate().isNotEmpty) {
      notes.add('onboarding Skip sits below the fold');
    }
  }

  Future<bool> waitForAny(List<Finder> finders, {int seconds = 30}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    do {
      if (finders.any((f) => f.evaluate().isNotEmpty)) return true;
      await idle(const Duration(milliseconds: 250));
    } while (DateTime.now().isBefore(deadline));
    return false;
  }

  Finder get _pill => find.byKey(const ValueKey('desktop-sidebar-pill'));

  Future<void> _tour() async {
    final appeared = await waitForAny(<Finder>[
      _gateTitle,
      _skip,
      _welcome,
      _pill,
    ], seconds: 180);
    _captureErrors();
    if (!appeared) {
      problems.add('no gate, onboarding or main screen: ${visibleTexts()}');
      await shot('00-unknown-start');
      return;
    }
    if (_gateTitle.evaluate().isNotEmpty) {
      await _gate();
    } else {
      notes.add('profile gate skipped on this launch');
    }
    if (!await _onboarding()) return;
    if (!await _home()) return;
    await _detailAndPlayer();
    await _localPlayer();
    for (final tab in const <String>[
      'Search',
      'Discover',
      'IPTV',
      'YouTube',
      'Stremio TV',
      'Addons',
      'Settings',
    ]) {
      step = tab.toLowerCase().replaceAll(' ', '-');
      if (await goTab(tab)) {
        await idle(const Duration(seconds: 4));
        await everyPosture(step);
        if (tab == 'YouTube') await _youtubePlayer();
      }
    }
  }

  String visibleTexts() => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((t) => t.trim().isNotEmpty)
      .take(60)
      .join(' | ');

  void _captureErrors() {
    FlutterError.onError = (details) {
      errors.add('[$step] ${details.exceptionAsString().split('\n').first}');
      FlutterError.dumpErrorToConsole(details);
    };
    final appAsync = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      errors.add('[$step] async: ${'$error'.split('\n').first}');
      return appAsync?.call(error, stack) ?? true;
    };
  }

  Future<void> _gate() async {
    step = 'gate';
    await everyPosture('00-gate');
    final card = find.byKey(
      const ValueKey('stage-profile-profile-initial-admin-v1'),
    );
    final target = card.evaluate().isNotEmpty ? card : find.text('Admin');
    for (var i = 0; i < 2; i++) {
      await tap(target);
      await idle(const Duration(seconds: 3));
      if (_gateTitle.evaluate().isEmpty) return;
    }
  }

  Future<bool> _onboarding() async {
    step = 'onboarding';
    if (_welcome.evaluate().isNotEmpty) await revealSkip();
    if (!await waitForAny(<Finder>[_skip, _pill], seconds: 60)) {
      problems.add('neither onboarding nor main screen: ${visibleTexts()}');
      await shot('01-onboarding-missing');
      return false;
    }
    if (_skip.evaluate().isEmpty) {
      notes.add('onboarding not shown on this launch');
      return true;
    }
    await everyPosture('01-onboarding');
    await revealSkip();
    await tap(_skip.hitTestable().first);
    return true;
  }

  Future<bool> _home() async {
    step = 'home';
    final campaign = find.text('Maybe later');
    if (await waitFor(campaign, seconds: 15)) {
      await everyPosture('02-campaign-dialog');
      await tap(campaign.hitTestable().first);
    } else {
      notes.add('support campaign dialog did not appear');
    }
    if (!await waitFor(find.byType(SpotlightBoardCard), seconds: 60)) {
      notes.add('Home showed no Spotlight cards (network?)');
    }
    await idle(const Duration(seconds: 3));
    await everyPosture('03-home');
    return true;
  }

  Future<void> _detailAndPlayer() async {
    step = 'detail';
    final cards = find.byType(SpotlightBoardCard);
    if (!await waitFor(cards, seconds: 10)) {
      notes.add('no Home card to open a detail page from');
      return;
    }
    // On the short inner screen the card rows start below the fold.
    await tester.ensureVisible(cards.first);
    await idle(const Duration(seconds: 1));
    if (cards.hitTestable().evaluate().isEmpty) {
      notes.add('Home cards could not be scrolled into view');
      await shot('04-detail-no-card');
      return;
    }
    await tap(cards.hitTestable().first);
    if (!await waitFor(find.byType(MergedDetailScreen), seconds: 20)) {
      problems.add('detail page did not open');
      return;
    }
    await idle(const Duration(seconds: 3));
    await everyPosture('04-detail');

    step = 'trailer';
    final trailer = find.byIcon(Icons.theaters_rounded).hitTestable();
    final trailerTip = find.byTooltip('Trailer').hitTestable();
    if (await waitFor(trailer, seconds: 10)) {
      await tap(trailer.first);
    } else if (trailerTip.evaluate().isNotEmpty) {
      await tap(trailerTip.first);
    } else {
      notes.add('no Trailer button on the detail page');
    }
    if (await waitFor(find.text('Choose trailer'), seconds: 4)) {
      await shot('05-choose-trailer');
      final option = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(InkWell),
      );
      if (option.evaluate().isNotEmpty) await tap(option.first);
    }
    // With autoplay on, the button brings the running trailer forward inside
    // the detail page; otherwise it pushes the full player.
    final pushed = await waitFor(find.byType(VideoPlayerScreen), seconds: 12);
    notes.add(
      pushed
          ? 'trailer opened the full player'
          : 'trailer played in place on the detail page',
    );
    await idle(const Duration(seconds: 5));
    await everyPosture(pushed ? '05-trailer-player' : '05-trailer-in-place');
    await backToMain();
  }

  /// Plays a clip the CI host serves on localhost through the app's real
  /// launcher and player, then folds, unfolds and rotates mid-playback.
  Future<void> _localPlayer() async {
    step = 'player';
    final anchor = _pill.hitTestable();
    if (!await waitFor(anchor, seconds: 10)) {
      problems.add('main screen not reachable before the player check');
      return;
    }
    unawaited(
      VideoPlayerLauncher.push(
        tester.element(anchor.first),
        const VideoPlayerLaunchArgs(
          videoUrl: 'http://127.0.0.1:8765/duo_test.mp4',
          title: 'Duo test clip',
        ),
      ),
    );
    final player = find.byType(VideoPlayerScreen);
    if (!await waitFor(player, seconds: 45)) {
      problems.add('player did not open for the local clip: ${visibleTexts()}');
      await shot('08-player-missing');
      return;
    }
    await idle(const Duration(seconds: 8));
    await everyPosture('08-player');
    if (player.evaluate().isEmpty) {
      problems.add('player closed while folding');
    } else {
      notes.add('local clip played through every fold and rotation');
    }
    await backToMain();
  }

  Future<void> _youtubePlayer() async {
    step = 'youtube-player';
    final field = find.byType(EditableText).hitTestable();
    if (!await waitFor(field, seconds: 10)) {
      notes.add('YouTube search field not found');
      return;
    }
    final editable = tester.state<EditableTextState>(field.first);
    const query = 'big buck bunny';
    editable.updateEditingValue(
      const TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      ),
    );
    editable.performAction(TextInputAction.search);
    final results = find.byType(YoutubeVideoCard).hitTestable();
    if (!await waitFor(results, seconds: 30)) {
      notes.add('YouTube search returned no results: ${visibleTexts()}');
      await shot('09-youtube-no-results');
      return;
    }
    await shot('09-youtube-results');
    final player = find.byType(VideoPlayerScreen);
    final failed = find.text('Could not load this video');
    var opened = false;
    for (var i = 0; i < 3 && !opened; i++) {
      final cards = results.evaluate().length;
      if (i >= cards) break;
      await tap(results.at(i));
      final outcome = find.byWidgetPredicate(
        (w) =>
            w is VideoPlayerScreen ||
            (w is Text && w.data == 'Could not load this video'),
      );
      await waitFor(outcome, seconds: 45);
      opened = player.evaluate().isNotEmpty;
      if (!opened) {
        notes.add(
          failed.evaluate().isNotEmpty
              ? 'YouTube result ${i + 1}: "Could not load this video"'
              : 'YouTube result ${i + 1}: nothing happened in 45 s',
        );
        await idle(const Duration(seconds: 5));
      }
    }
    if (!opened) {
      await shot('10-youtube-player-missing');
      await backToMain();
      return;
    }
    notes.add('YouTube video opened the full player');
    await idle(const Duration(seconds: 10));
    await everyPosture('10-youtube-player');
    await backToMain();
  }

  /// System back until the main screen's nav pill can be tapped again.
  Future<void> backToMain() async {
    for (var i = 0; i < 6; i++) {
      if (_pill.hitTestable().evaluate().isNotEmpty) return;
      // ignore: invalid_use_of_protected_member
      await tester.binding.handlePopRoute();
      await idle(const Duration(seconds: 2));
    }
    if (_pill.hitTestable().evaluate().isEmpty) {
      problems.add('[$step] could not get back to the main screen');
      await shot('back-stuck-$step');
    }
  }

  /// Inner landscape, inner portrait, folded cover, then unfolded again so a
  /// fold mid-session is checked for lost state.
  Future<void> everyPosture(String name) async {
    await shot('$name-a-inner-landscape');
    await host('rotate portrait');
    await shot('$name-b-inner-portrait');
    await host('rotate landscape');
    await host('close --duration 1');
    await shot('$name-c-cover');
    await host('open --duration 1');
    await shot('$name-d-inner-after-unfold');
  }

  Future<bool> goTab(String label) async {
    final pill = _pill;
    if (!await waitFor(pill.hitTestable(), seconds: 10)) {
      problems.add('[$step] nav pill not found');
      return false;
    }
    await tap(pill.hitTestable().first);
    await idle(const Duration(milliseconds: 900));
    final item = find
        .descendant(
          of: find.byKey(const ValueKey('desktop-sidebar-panel')),
          matching: find.text(label),
        )
        .hitTestable();
    if (!await waitFor(item, seconds: 5)) {
      problems.add('[$step] nav item "$label" not found');
      await shot('nav-missing-$label');
      return false;
    }
    await tap(item.first);
    return true;
  }

  Future<void> shot(String name) async {
    await idle(const Duration(seconds: 3));
    await host('shot $name');
  }

  Future<void> tap(Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await idle(const Duration(milliseconds: 600));
  }

  Future<bool> waitFor(Finder finder, {int seconds = 30}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (finder.evaluate().isNotEmpty) return true;
      await idle(const Duration(milliseconds: 250));
    }
    return finder.evaluate().isNotEmpty;
  }

  /// Waits in real time. The binding runs fully live, so the engine keeps
  /// drawing on its own; awaiting tester.pump() here would hang forever if
  /// the simulator stopped producing frames (a sleeping host display).
  Future<void> idle(Duration duration) => Future<void>.delayed(
    duration < const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : duration,
  );

  Future<bool> host(String command) async {
    _seq++;
    final request = File('${_dir.path}/req-$_seq.tmp');
    request.writeAsStringSync(command, flush: true);
    request.renameSync('${_dir.path}/req-$_seq');
    final ack = File('${_dir.path}/ack-$_seq');
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      if (ack.existsSync()) {
        final code = ack.readAsStringSync().trim();
        if (code != '0') problems.add('[$step] host "$command" exited $code');
        return code == '0';
      }
      await idle(const Duration(milliseconds: 250));
    }
    problems.add('[$step] host "$command" timed out');
    return false;
  }
}
