import 'package:debrify/services/webdav_sync/webdav_sync_graph_tier.dart';
import 'package:debrify/screens/settings/widgets/sync_device_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'relative sync times handle boundaries, missing and future timestamps',
    () {
      final now = DateTime.utc(2026, 9, 14, 12);
      String label(Duration age) =>
          syncDeviceLastSynced(now.subtract(age).millisecondsSinceEpoch, now);
      expect(syncDeviceLastSynced(0, now), 'No sync time available');
      expect(label(const Duration(seconds: -30)), 'Last synced just now');
      expect(label(const Duration(seconds: 59)), 'Last synced just now');
      expect(label(const Duration(minutes: 1)), 'Last synced 1 minute ago');
      expect(label(const Duration(minutes: 59)), 'Last synced 59 minutes ago');
      expect(label(const Duration(hours: 1)), 'Last synced 1 hour ago');
      expect(label(const Duration(hours: 23)), 'Last synced 23 hours ago');
      expect(label(const Duration(days: 1)), 'Last synced 1 day ago');
      expect(label(const Duration(days: 10)), 'Last synced 10 days ago');
    },
  );
  testWidgets('device dialog refreshes time and fits a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = DateTime.utc(2026, 9, 14, 12);
    final timestamp = now
        .subtract(const Duration(seconds: 50))
        .millisecondsSinceEpoch;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SyncDevicesDialog(
              canRename: true,
              clock: () => now,
              devices: [
                WebDavSyncDeviceSummary(
                  deviceId: 'one',
                  lastSeenMs: timestamp,
                  isThisDevice: true,
                  displayName: 'Living room television with a long name',
                ),
                WebDavSyncDeviceSummary(
                  deviceId: 'two',
                  lastSeenMs: timestamp,
                  isThisDevice: false,
                  isRegistered: false,
                  displayName: 'Bedroom TV',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Living room television with a long name'),
      100,
    );
    expect(find.text('Last synced just now'), findsWidgets);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Last synced 1 minute ago'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('device rows fit a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var renamed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: AlertDialog(
              title: const Text('Connected devices'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: SyncDeviceTile(
                    name: 'Living room television with a long descriptive name',
                    status: 'This device · Last seen 9/14/2026 9:43 AM',
                    onRename: () => renamed = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Rename'));
    await tester.tap(find.text('Rename'));
    expect(renamed, isTrue);
    expect(find.text('Remove'), findsNothing);
  });
  testWidgets('rename validates input and submits a trimmed name', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (_) => const SyncDeviceNameDialog(initialName: 'TV'),
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
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('1–60'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' Bedroom TV ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, 'Bedroom TV');
    expect(tester.takeException(), isNull);
  });
}
