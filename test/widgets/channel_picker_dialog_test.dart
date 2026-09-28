import 'dart:async';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/widgets/channel_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DebrifyTvChannelRecord channel() => DebrifyTvChannelRecord(
    channelId: 'id',
    name: 'Existing channel',
    keywords: ['word'],
    avoidNsfw: true,
    channelNumber: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  testWidgets('existing channel returns identity and Back cancels', (
    tester,
  ) async {
    ChannelPickerResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<ChannelPickerResult>(
                context: context,
                builder: (_) => ChannelPickerDialog(
                  searchKeyword: 'Word',
                  loadChannels: () async => [channel()],
                  createChannel: (_, _) async =>
                      throw StateError('unexpected create'),
                  canContinue: () => true,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing channel'));
    await tester.pumpAndSettle();
    expect(result!.channelId, 'id');
    expect(result!.isNewChannel, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
  testWidgets('create passes trimmed name and revokes guard on dismissal', (
    tester,
  ) async {
    late Completer<ChannelPickerResult> pending;
    await tester.runAsync(() async {
      pending = Completer<ChannelPickerResult>();
    });
    bool Function()? active;
    String? name;
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return TextButton(
              onPressed: () {
                showDialog<ChannelPickerResult>(
                  context: context,
                  builder: (_) => ChannelPickerDialog(
                    searchKeyword: 'Word',
                    loadChannels: () async => [],
                    createChannel: (value, guard) {
                      name = value;
                      active = guard;
                      return pending.future;
                    },
                    canContinue: () => true,
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New Channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  New channel  ');
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(name, 'New channel');
    expect(active!(), isTrue);
    Navigator.of(host).pop();
    await tester.pumpAndSettle();
    expect(active!(), isFalse);
    await tester.runAsync(() async {
      pending.complete(
        const ChannelPickerResult(
          channelId: 'new',
          channelName: 'New channel',
          isNewChannel: true,
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
