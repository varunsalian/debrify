import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/remote/remote_send_browser.dart';
import 'package:debrify/widgets/remote/remote_control_screen.dart';

const choices = [
  RemoteSendChoice(
    id: 'a',
    label: 'Addon Alpha',
    group: RemoteSendGroup.addons,
  ),
  RemoteSendChoice(id: 'b', label: 'Addon Beta', group: RemoteSendGroup.addons),
  RemoteSendChoice(id: 'c', label: 'News', group: RemoteSendGroup.channels),
  RemoteSendChoice(id: 'd', label: 'Trakt', group: RemoteSendGroup.setup),
];

void main() {
  testWidgets('WebDAV Sync is a root category independent of media servers', (
    tester,
  ) async {
    final basket = RemoteSendBasket();
    addTearDown(basket.dispose);
    List<RemoteSendChoice>? sent;
    const sync = RemoteSendChoice(
      id: 'setup:webdav_sync_account',
      label: 'WebDAV Sync account',
      group: RemoteSendGroup.webDavSync,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteSendBrowser(
              choices: const [sync],
              basket: basket,
              onSend: (items) => sent = items,
              onEverything: () {},
              onPhoto: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Send everything'), findsOneWidget);
    expect(find.text('Addons'), findsOneWidget);
    expect(find.text('WebDAV Sync'), findsOneWidget);
    await tester.tap(find.text('WebDAV Sync'));
    await tester.pump();
    expect(find.text('WebDAV Sync account'), findsOneWidget);
    expect(find.text('WebDAV media servers'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Send WebDAV Sync account only'));
    expect(sent, [sync]);
  });

  testWidgets(
    'disconnected remote fits a narrow screen and preserves manual connection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: RemoteControlScreen()));
      await tester.pump();
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Receive instead'), findsOneWidget);
      expect(find.text('Connect by IP (Tailscale / VPN)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'individual send preserves mixed basket; category clear is scoped',
    (tester) async {
      final basket = RemoteSendBasket();
      addTearDown(basket.dispose);
      List<RemoteSendChoice>? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RemoteSendBrowser(
                choices: choices,
                basket: basket,
                onSend: (items) => sent = items,
                onEverything: () {},
                onPhoto: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Addons'));
      await tester.pump();
      await tester.tap(find.text('Addon Alpha'));
      await tester.pump();
      await tester.tap(find.text('Send').last);
      expect(sent!.map((c) => c.id), ['b']);
      expect(basket.ids, {'a'});
      await tester.tap(find.text('Add items from another category'));
      await tester.pump();
      await tester.tap(find.text('Accounts & setup'));
      await tester.pump();
      await tester.tap(find.text('Trakt'));
      await tester.pump();
      await tester.tap(find.text('Review 2 selected items'));
      expect(sent!.map((c) => c.id), ['a', 'd']);
      await tester.tap(find.text('Clear selection'));
      await tester.pump();
      expect(basket.ids, {'a'});
    },
  );

  testWidgets('small screen keeps full and granular actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final basket = RemoteSendBasket();
    addTearDown(basket.dispose);
    var everything = 0;
    var photo = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteSendBrowser(
              choices: choices,
              basket: basket,
              onSend: (_) {},
              onEverything: () => everything++,
              onPhoto: () => photo++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Send everything'));
    await tester.tap(find.text('Profile photo'));
    expect(everything, 1);
    expect(photo, 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Debrify TV channels'));
    await tester.pump();
    expect(find.text('News'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading cannot send an incomplete inventory', (tester) async {
    final basket = RemoteSendBasket()..select(['a']);
    addTearDown(basket.dispose);
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteSendBrowser(
              choices: choices,
              basket: basket,
              loading: true,
              onSend: (_) => sends++,
              onEverything: () {},
              onPhoto: () {},
            ),
          ),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Review 1 selected item'),
    );
    expect(button.onPressed, isNull);
    expect(sends, 0);
  });
}
