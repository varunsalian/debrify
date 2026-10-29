// The Storage Usage page with a fake scan: what it lists, the explanation a
// row opens, the copied report, and rescans (including one that supersedes
// a scan still running).
import 'dart:async';

import 'package:debrify/features/storage_usage/application/storage_usage_providers.dart';
import 'package:debrify/features/storage_usage/data/storage_scanner.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:debrify/features/storage_usage/presentation/storage_usage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

StorageScan _scan({int catalogMb = 900}) => StorageScan(
  totalBytes: (catalogMb + 100) * _mb,
  fileCount: 42,
  byCategory: {
    StorageCategory.iptvCatalogs: catalogMb * _mb,
    StorageCategory.imageCache: 100 * _mb,
  },
  byProfile: [
    StorageProfileBytes('p1', {2: (catalogMb - 300) * _mb, 1: 100 * _mb}),
    const StorageProfileBytes('p-old', {1: 200 * _mb}),
  ],
  largest: [
    StorageFile(
      displayPath:
          'App data/app_flutter/profiles/p1/g/2/documents/'
          'iptv_catalog.db',
      bytes: (catalogMb - 300) * _mb,
      category: StorageCategory.iptvCatalogs,
      profileId: 'p1',
      generation: 2,
    ),
  ],
  unreadableFolders: 0,
);

const _profiles = [
  StorageProfileInfo(id: 'p1', name: 'Living room', visibleGeneration: 2),
];

Future<void> _mount(
  WidgetTester tester, {
  required Future<StorageScan> Function(StorageScanCancellation cancel) scan,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: [
        storageScanSourceProvider.overrideWithValue(scan),
        storageProfilesSourceProvider.overrideWithValue(() async => _profiles),
        storageClockProvider.overrideWithValue(
          () => DateTime(2026, 10, 29, 9, 30),
        ),
      ],
      child: const MaterialApp(home: StorageUsagePage()),
    ),
  );
}

void main() {
  testWidgets('lists kinds, profiles and the largest files', (tester) async {
    await _mount(tester, scan: (_) async => _scan());
    expect(find.text('Measuring storage…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('1000 MB'), findsOneWidget);
    expect(find.text('42 files · scanned at 9:30 AM'), findsOneWidget);
    expect(find.text('IPTV catalogs & guide'), findsWidgets);
    expect(find.text('90% of the total'), findsOneWidget);
    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('Includes 100 MB of older copies'), findsOneWidget);
    expect(find.text('Deleted profile'), findsOneWidget);
    expect(find.text('Leftover files from a removed profile'), findsOneWidget);
    expect(find.text('iptv_catalog.db'), findsOneWidget);
    expect(find.text('IPTV catalogs & guide · Living room'), findsOneWidget);
  });

  testWidgets('a kind explains itself', (tester) async {
    await _mount(tester, scan: (_) async => _scan());
    await tester.pumpAndSettle();

    await tester.tap(find.text('90% of the total'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('several profiles using the same'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Copy Report puts the text report on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(tester, scan: (_) async => _scan());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy Report'));
    await tester.pumpAndSettle();

    expect(copied, startsWith('Debrify storage: 1000 MB in 42 files'));
    expect(copied, isNot(contains('Living room')));
    expect(find.text('Storage report copied'), findsOneWidget);
  });

  testWidgets('Scan Again measures again and shows the new sizes', (
    tester,
  ) async {
    var scans = 0;
    await _mount(
      tester,
      scan: (_) async {
        scans++;
        return _scan(catalogMb: scans == 1 ? 900 : 400);
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('1000 MB'), findsOneWidget);

    await tester.tap(find.text('Scan Again'));
    await tester.pumpAndSettle();

    expect(scans, 2);
    expect(find.text('500 MB'), findsOneWidget);
  });

  testWidgets('a superseded scan never replaces the newer result', (
    tester,
  ) async {
    final calls = <Completer<StorageScan>>[];
    final cancels = <StorageScanCancellation>[];
    await _mount(
      tester,
      scan: (cancel) {
        final call = Completer<StorageScan>();
        calls.add(call);
        cancels.add(cancel);
        return call.future;
      },
    );
    calls[0].complete(_scan());
    await tester.pumpAndSettle();

    // A second scan starts and stays pending; a third supersedes it.
    await tester.tap(find.text('Scan Again'));
    await tester.pump();
    expect(find.text('Scanning…'), findsOneWidget);
    ProviderScope.containerOf(
      tester.element(find.byType(StorageUsagePage)),
    ).read(storageUsageProvider.notifier).rescan();
    await tester.pump();
    expect(calls, hasLength(3));
    // The superseded walk is stopped, not just ignored.
    expect(cancels[1].isCancelled, isTrue);
    expect(cancels[2].isCancelled, isFalse);

    calls[2].complete(_scan(catalogMb: 400));
    await tester.pumpAndSettle();
    expect(find.text('500 MB'), findsOneWidget);

    // The superseded scan finishing late changes nothing.
    calls[1].complete(_scan(catalogMb: 2000));
    await tester.pumpAndSettle();
    expect(find.text('500 MB'), findsOneWidget);
    expect(find.text('2.05 GB'), findsNothing);
  });

  testWidgets('a failed scan offers to try again', (tester) async {
    var fail = true;
    await _mount(
      tester,
      scan: (_) async {
        if (fail) throw const FileSystemTestError();
        return _scan();
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not measure storage.'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('1000 MB'), findsOneWidget);
  });
  testWidgets('a failed rescan keeps the old report and says so', (
    tester,
  ) async {
    var fail = false;
    await _mount(
      tester,
      scan: (_) async {
        if (fail) throw const FileSystemTestError();
        return _scan();
      },
    );
    await tester.pumpAndSettle();

    fail = true;
    await tester.tap(find.text('Scan Again'));
    await tester.pumpAndSettle();

    expect(find.text('1000 MB'), findsOneWidget);
    expect(
      find.text('The last scan failed; these are older results'),
      findsOneWidget,
    );
  });

  testWidgets('with a remote, focus starts on the first row and stays on '
      'Scan Again through a rescan', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final pending = <Completer<StorageScan>>[];
    await _mount(
      tester,
      scan: (_) {
        if (pending.isEmpty) return Future.value(_scan());
        final call = Completer<StorageScan>();
        pending.add(call);
        return call.future;
      },
    );
    await tester.pumpAndSettle();

    FocusNode rowNode(String title) => tester
        .widget<InkWell>(
          find
              .ancestor(of: find.text(title), matching: find.byType(InkWell))
              .first,
        )
        .focusNode!;

    // The first kind row: the largest category, first in its section.
    expect(rowNode('90% of the total').hasPrimaryFocus, isTrue);

    rowNode('Scan Again').requestFocus();
    await tester.pump();
    pending.add(Completer<StorageScan>());
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Scanning…'), findsOneWidget);
    expect(rowNode('Scanning…').hasPrimaryFocus, isTrue);

    pending.last.complete(_scan(catalogMb: 400));
    await tester.pumpAndSettle();
    expect(find.text('500 MB'), findsOneWidget);
    expect(rowNode('Scan Again').hasPrimaryFocus, isTrue);
  });
}

final class FileSystemTestError implements Exception {
  const FileSystemTestError();
}
