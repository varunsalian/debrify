import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/remote/remote_pairing_dialog.dart';
import 'package:debrify/widgets/tv_text_field.dart';

void main() {
  testWidgets('receiver cancellation dismisses only its pairing dialog', (
    tester,
  ) async {
    final session = await tester.runAsync(() async {
      final key = await RemoteSessionCrypto.x25519.newKeyPair();
      final sender = RemoteSessionManager(
        loadStaticKeyPair: () async => key,
        deviceName: () => 'sender',
      );
      final receiver = RemoteSessionManager(
        loadStaticKeyPair: () async => key,
        deviceName: () => 'receiver',
      );
      final hs2 = await receiver.handle(await sender.startHandshake());
      final hs3 = await sender.handle(hs2.outgoing.single);
      return (await receiver.handle(hs3.outgoing.single)).established!;
    });
    final gate = PairingGate(isRemembered: (_) => false);
    addTearDown(gate.dispose);
    gate.request(session!);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Receiver'));
          },
        ),
      ),
    );
    showRemotePairingDialog(context, gate);
    await tester.pumpAndSettle();
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Unrelated dialog')),
    );
    await tester.pumpAndSettle();
    gate.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(RemotePairingPanel), findsNothing);
    expect(find.text('Unrelated dialog'), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('receiver expiry dismisses only its own code entry route', (
    tester,
  ) async {
    final ended = ValueNotifier<String?>(null);
    addTearDown(ended.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Sender'));
          },
        ),
      ),
    );
    final result = showPairingCodeEntrySheet(
      context,
      tvName: 'Receiver',
      ended: ended,
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Unrelated dialog')),
    );
    await tester.pumpAndSettle();
    ended.value = 'expired';
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(find.text('Unrelated dialog'), findsOneWidget);
    expect(find.text('Enter the code shown on "Receiver"'), findsNothing);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });
  Future<Completer<String?>> openDialog(WidgetTester tester) async {
    final result = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showPairingCodeEntrySheet(
                context,
                tvName: 'Living Room',
              ).then(result.complete),
              child: const Text('Pair'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('uses the TV-safe field and confirms on the sixth digit', (
    tester,
  ) async {
    final result = await openDialog(tester);

    expect(find.byType(TvTextField), findsOneWidget);
    expect(find.text('Enter the code shown on "Living Room"'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(await result.future, '123456');
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('TV keyboard input is digit-only, bounded, and auto-confirms', (
    tester,
  ) async {
    final oldKeyboardSetting = StorageService.tvKeyboardEnabledCached;
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() {
      PlatformUtil.debugSetAndroidTvCached(null);
      StorageService.tvKeyboardEnabledCached = oldKeyboardSetting;
    });

    final result = await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    tester
        .state<TvTextFieldState>(find.byType(TvTextField))
        .insertText('12a345678');
    await tester.pumpAndSettle();

    expect(await result.future, '123456');
  });
}
