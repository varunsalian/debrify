import 'package:debrify/features/sources/presentation/source_row_actions_sheet.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/utils/dialog_tap_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PopObserver extends NavigatorObserver {
  PopObserver(this.events);
  final List<String> events;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop');
  }
}

Future<void> openSheet(
  WidgetTester tester,
  List<String> events, {
  SourceRowActionKind kind = SourceRowActionKind.addon,
  bool bound = false,
  bool copy = true,
  bool download = false,
}) async {
  void action(String value) {
    expect(DialogTapGuard.shouldIgnoreTap(), isTrue);
    events.add(value);
  }

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [PopObserver(events)],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppThemes.legacy.home.sheetBg,
              builder: (_) => SourceRowActionsSheet(
                app: AppThemes.legacy,
                kind: kind,
                bound: bound,
                onPlay: () => action('play'),
                onTogglePin: () => action('pin'),
                onCopy: copy ? () => action('copy') : null,
                onDownload: download ? () => action('download') : null,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (kind, title, description) in [
    (
      SourceRowActionKind.torrent,
      'Play',
      'Reuse this source for instant playback',
    ),
    (
      SourceRowActionKind.addon,
      'Play now',
      'Re-fetch a fresh link from this addon when played',
    ),
    (
      SourceRowActionKind.iptv,
      'Play now',
      'Resolve it from this IPTV catalog when played',
    ),
    (
      SourceRowActionKind.mediaServer,
      'Play now',
      'Resolve this version from your media server when played',
    ),
    (
      SourceRowActionKind.external,
      'Open externally',
      'Open this link in your browser',
    ),
  ]) {
    testWidgets('$kind retains its labels and eligible actions', (
      tester,
    ) async {
      await openSheet(
        tester,
        [],
        kind: kind,
        copy: kind != SourceRowActionKind.torrent,
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(description), findsOneWidget);
      expect(
        find.text('Pin as source'),
        kind == SourceRowActionKind.external ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Copy link'),
        kind == SourceRowActionKind.torrent ? findsNothing : findsOneWidget,
      );
      expect(find.text('Download to device'), findsNothing);
      final play = tester.widget<ListTile>(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      );
      expect((play.leading! as Icon).color, AppThemes.legacy.core.tx);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (kind, subtitle) in [
    (SourceRowActionKind.torrent, 'Stop reusing this source'),
    (SourceRowActionKind.addon, 'Stop refreshing this stream for playback'),
  ]) {
    testWidgets('bound $kind exposes its unpin wording', (tester) async {
      await openSheet(tester, [], kind: kind, bound: true);
      expect(find.text('Unpin source'), findsOneWidget);
      expect(find.text('Pin as source'), findsNothing);
      expect(find.text(subtitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (label, event) in [
    ('Play now', 'play'),
    ('Pin as source', 'pin'),
    ('Copy link', 'copy'),
    ('Download to device', 'download'),
  ]) {
    testWidgets('keyboard $event guards input and closes before dispatch', (
      tester,
    ) async {
      final events = <String>[];
      await openSheet(tester, events, download: true);
      Focus.of(tester.element(find.text(label))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(events, ['pop', event]);
      expect(find.byType(SourceRowActionsSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
