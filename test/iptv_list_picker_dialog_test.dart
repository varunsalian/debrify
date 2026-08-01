import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/widgets/iptv/iptv_list_picker_dialog.dart';

/// The "add to list" picker applies each row immediately, which makes how it
/// CLOSES load-bearing: the caller reloads its markers and shelf only when
/// told something changed, and it re-reads storage the moment the future
/// resolves. Both of those have to survive a dismissal and a fast close.
void main() {
  const lists = [
    IptvListMeta(
      id: 'favorites',
      name: 'Favorites',
      position: 0,
      isBuiltin: true,
      channelCount: 0,
    ),
    IptvListMeta(
      id: 'l1',
      name: 'Kids',
      position: 1,
      isBuiltin: false,
      channelCount: 2,
    ),
  ];

  /// Pumps the picker and hands back the future its caller would await.
  Future<Future<bool>> openPicker(
    WidgetTester tester, {
    required Future<void> Function(String, bool) onSetMembership,
    Set<String> membership = const {},
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              result = showIptvListPickerDialog(
                context: context,
                channelName: 'Sky News',
                loadLists: () async => lists,
                loadMembership: () async => membership,
                onSetMembership: onSetMembership,
                onCreateList: (name) async => 'new',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a dismissal still reports the writes it already made',
      (tester) async {
    final writes = <String>[];
    final result = await openPicker(
      tester,
      onSetMembership: (listId, inList) async => writes.add('$listId=$inList'),
    );

    await tester.tap(find.text('Kids'));
    await tester.pump();
    // Dismiss by tapping the barrier rather than Done — the route pops with
    // null, which used to read as "nothing changed" and skip the caller's
    // refresh even though the write had landed.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(writes, ['l1=true']);
  });

  testWidgets('closing immediately still waits for the write to land',
      (tester) async {
    final completer = Completer<void>();
    final writes = <String>[];
    final result = await openPicker(
      tester,
      onSetMembership: (listId, inList) async {
        await completer.future;
        writes.add('$listId=$inList');
      },
    );

    await tester.tap(find.text('Kids'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The dialog is gone, but the caller must not be told to re-read yet —
    // reloading mid-write would paint the pre-toggle state back over it.
    var settled = false;
    unawaited(result.then((_) => settled = true));
    await tester.pump();
    expect(settled, isFalse);
    expect(writes, isEmpty);

    completer.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(writes, ['l1=true']);
  });

  testWidgets('untouched, it reports no change', (tester) async {
    final result = await openPicker(
      tester,
      onSetMembership: (_, __) async => fail('nothing was toggled'),
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('rapid toggles reach storage in order', (tester) async {
    final writes = <String>[];
    final result = await openPicker(
      tester,
      membership: const {'l1'},
      onSetMembership: (listId, inList) async {
        // Stagger the first write so an unordered queue would invert them.
        if (inList == false) await Future<void>.delayed(Duration.zero);
        writes.add('$listId=$inList');
      },
    );

    await tester.tap(find.text('Kids'));
    await tester.pump();
    await tester.tap(find.text('Kids'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(writes, ['l1=false', 'l1=true'],
        reason: 'the last toggle must be the one storage ends on');
  });
}
