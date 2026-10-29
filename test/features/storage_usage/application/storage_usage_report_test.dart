// The report built from a scan: current data against older copies, removed
// profiles, unreadable profile names, and the text copied for bug reports.
import 'package:debrify/features/storage_usage/application/storage_usage_report.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

StorageScan _scan() => StorageScan(
  totalBytes: 1100 * _mb,
  fileCount: 3,
  byCategory: const {
    StorageCategory.iptvCatalogs: 1000 * _mb,
    StorageCategory.imageCache: 100 * _mb,
  },
  byProfile: const [
    StorageProfileBytes('p-alice', {3: 600 * _mb, 2: 200 * _mb, null: _mb}),
    StorageProfileBytes('p-gone', {1: 250 * _mb}),
  ],
  largest: const [
    StorageFile(
      displayPath: 'App data/app_flutter/profiles/p-alice/g/3/iptv_catalog.db',
      bytes: 600 * _mb,
      category: StorageCategory.iptvCatalogs,
      profileId: 'p-alice',
      generation: 3,
    ),
  ],
  unreadableFolders: 0,
);

const _alice = StorageProfileInfo(
  id: 'p-alice',
  name: 'Alice',
  visibleGeneration: 3,
);

void main() {
  final now = DateTime(2026, 10, 29, 14, 5);

  test('splits a profile into current data and older copies', () {
    final report = buildStorageUsageReport(_scan(), const [_alice], now);

    final alice = report.profiles.firstWhere((p) => p.profileId == 'p-alice');
    expect(alice.name, 'Alice');
    // The visible generation plus files outside any generation folder.
    expect(alice.currentBytes, 601 * _mb);
    expect(alice.olderCopyBytes, 200 * _mb);
    expect(report.profilesKnown, isTrue);
  });

  test('folders of a profile that no longer exists are unnamed', () {
    final report = buildStorageUsageReport(_scan(), const [_alice], now);

    final gone = report.profiles.firstWhere((p) => p.profileId == 'p-gone');
    expect(gone.name, isNull);
    expect(gone.total, 250 * _mb);
    // Largest profile first.
    expect(report.profiles.map((p) => p.profileId), ['p-alice', 'p-gone']);
  });

  test('without profile names nothing counts as an older copy', () {
    final report = buildStorageUsageReport(_scan(), null, now);

    final alice = report.profiles.firstWhere((p) => p.profileId == 'p-alice');
    expect(alice.currentBytes, 801 * _mb);
    expect(alice.olderCopyBytes, 0);
    expect(report.profilesKnown, isFalse);
  });

  test('the copied text has the sizes but never a profile name or id', () {
    final report = buildStorageUsageReport(_scan(), const [_alice], now);

    final text = storageUsageReportText(report);

    expect(text, contains('Debrify storage: 1.07 GB in 3 files'));
    expect(text, contains('2026-10-29 14:05'));
    expect(text, contains('IPTV catalogs & guide: 1000 MB'));
    expect(text, contains('Profile 1: 601 MB, older copies 200 MB'));
    expect(text, contains('Deleted profile 2: 250 MB'));
    expect(
      text,
      contains('600 MB  App data/app_flutter/profiles/<Profile 1>/g/3/'),
    );
    expect(text, isNot(contains('Alice')));
    expect(text, isNot(contains('p-alice')));
    // Categories run largest first.
    expect(
      text.indexOf('IPTV catalogs'),
      lessThan(text.indexOf('Image cache')),
    );
  });

  test('copied recordings, downloads and unknown files lose their names', () {
    final scan = StorageScan(
      totalBytes: 300 * _mb,
      fileCount: 3,
      byCategory: const {
        StorageCategory.recordings: 200 * _mb,
        StorageCategory.downloads: 100 * _mb,
        StorageCategory.other: 50 * _mb,
      },
      byProfile: const [],
      largest: const [
        StorageFile(
          displayPath: 'App files/Debrify/Recordings/Secret Channel_0101.ts',
          bytes: 200 * _mb,
          category: StorageCategory.recordings,
        ),
        StorageFile(
          displayPath: 'Documents/downloads/Some Movie (2024)/movie.mkv',
          bytes: 100 * _mb,
          category: StorageCategory.downloads,
        ),
        StorageFile(
          displayPath: 'App files/Another Film.mp4',
          bytes: 50 * _mb,
          category: StorageCategory.other,
        ),
      ],
      unreadableFolders: 0,
    );

    final text = storageUsageReportText(
      buildStorageUsageReport(scan, const [], now),
    );

    expect(text, contains('200 MB  App files/…/<recording>.ts'));
    expect(text, contains('100 MB  Documents/…/<download>.mkv'));
    expect(text, isNot(contains('Secret Channel')));
    expect(text, contains('50.0 MB  App files/…/<file>.mp4'));
    expect(text, isNot(contains('Some Movie')));
    expect(text, isNot(contains('Another Film')));
  });

  test('sortedStorageCategories drops empty categories', () {
    final scan = StorageScan(
      totalBytes: 5,
      fileCount: 1,
      byCategory: const {StorageCategory.logs: 5, StorageCategory.other: 0},
      byProfile: const [],
      largest: const [],
      unreadableFolders: 0,
    );

    expect(sortedStorageCategories(scan).map((e) => e.key), [
      StorageCategory.logs,
    ]);
  });
}
