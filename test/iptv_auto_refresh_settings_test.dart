import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide settings exposes global refresh and returns DPAD to rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nodes = List.generate(3, (_) => FocusNode());
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvSettingsTwoPane(
            playlists: const [],
            defaultPlaylistId: null,
            refreshingIds: const {},
            customLists: const [],
            startupEnabled: false,
            startupMode: 'last',
            startupChannelLabel: '',
            lastLiveChannelLabel: '',
            hasStartupChannel: false,
            hasLastLiveChannel: false,
            addMethod: 0,
            onAddMethodChanged: (_) {},
            urlFormBuilder: (_) => const SizedBox(),
            fileFormBuilder: (_) => const SizedBox(),
            xtreamFormBuilder: (_) => const SizedBox(),
            urlMethodFocusNode: nodes[0],
            fileMethodFocusNode: nodes[1],
            xtreamMethodFocusNode: nodes[2],
            onSetDefault: (_) {},
            onRefresh: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onCreateList: () {},
            onManageChannelOrder: () {},
            onFocusFirstFormField: () {},
            onListActions: (_) {},
            onToggleStartup: (_) {},
            onStartupModeChanged: (_) {},
            onPickStartupChannel: () {},
            channelPreviewEnabled: true,
            onToggleChannelPreview: (_) {},
            trackContinueWatching: true,
            onToggleTrackContinueWatching: (_) {},
            onPickAutoRefresh: () => opened++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Auto-refresh'));
    await tester.tap(find.text('Auto-refresh'));
    await tester.pumpAndSettle();
    expect(find.text('All sources in this profile'), findsOneWidget);
    expect(find.text('Every 24 hours'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('All sources in this profile'), findsNothing);
  });

  for (final hours in [0, 6, 12, 24, 48]) {
    testWidgets('picker returns $hours hours', (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showDialog<int>(
                    context: context,
                    builder: (_) =>
                        const IptvAutoRefreshDialog(intervalHours: 24),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.byType(TextButton),
        ),
        findsNWidgets(5),
      );
      expect(find.textContaining('operating system permits'), findsOneWidget);
      expect(
        find.textContaining('all sources in this profile'),
        findsOneWidget,
      );
      await tester.tap(find.text(iptvAutoRefreshLabel(hours)));
      await tester.pumpAndSettle();
      expect(selected, hours);
    });
  }

  testWidgets('DPAD starts at current interval and selects next choice', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<int>(
                  context: context,
                  builder: (_) =>
                      const IptvAutoRefreshDialog(intervalHours: 24),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 48);
  });
}
