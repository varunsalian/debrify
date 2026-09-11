import 'dart:math';

import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/cloud/cloud_folder_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RDFileNode file(String name) => RDFileNode.file(
    name: name,
    fileId: 7,
    path: '/unchanged/$name',
    bytes: 123,
    linkIndex: 4,
    selected: false,
  );

  test(
    'empty and singleton input produce independent lists of the same nodes',
    () {
      const empty = <RDFileNode>[];
      final result = CloudFolderSort.sortedView(empty);
      final node = file('only.mkv');
      result.add(node);
      expect(empty, isEmpty);
      final input = List<RDFileNode>.unmodifiable([node]);
      final sorted = CloudFolderSort.sortedView(input);
      expect(sorted.single, same(node));
      sorted.clear();
      expect(input.single, same(node));
    },
  );

  test(
    'keeps duplicate identities, metadata and unsorted children untouched',
    () {
      final childB = file('b.mkv');
      final childA = file('a.mkv');
      final children = <RDFileNode>[childB, childA];
      final folder = RDFileNode.folder(name: 'Extras', children: children);
      final input = List<RDFileNode>.unmodifiable([
        childB,
        folder,
        childA,
        childB,
      ]);
      final sorted = CloudFolderSort.sortedView(input);
      expect(sorted, [folder, childA, childB, childB]);
      expect(input, [childB, folder, childA, childB]);
      expect(folder.children, same(children));
      expect(children, [childB, childA]);
      expect(sorted.last.path, '/unchanged/b.mkv');
      expect(sorted.last.fileId, 7);
      expect(sorted.last.linkIndex, 4);
      expect(sorted.last.bytes, 123);
      expect(sorted.last.selected, isFalse);
    },
  );

  test('folder patterns retain priority and sort numerically before names', () {
    final names = [
      'Season 10',
      'Extras',
      'Module-4',
      'Episode 5',
      'chapter_3',
      'Part 2',
      '01. Season 99',
    ];
    final nodes = names.map((name) => RDFileNode.folder(name: name)).toList();
    expect(CloudFolderSort.sortedView(nodes).map((node) => node.name), [
      '01. Season 99',
      'Part 2',
      'chapter_3',
      'Module-4',
      'Episode 5',
      'Season 10',
      'Extras',
    ]);
  });

  test(
    'digits without separators and overflowing numbers stay ordinary names',
    () {
      const overflow = '99999999999999999999999999999999_oversize.mkv';
      final nodes = [
        'zeta.mkv',
        overflow,
        '12',
        'Alpha.mkv',
        '10. ten.mkv',
        '2no-separator.mkv',
        '02_two.mkv',
      ].map(file).toList();
      expect(CloudFolderSort.sortedView(nodes).map((node) => node.name), [
        '02_two.mkv',
        '10. ten.mkv',
        '12',
        '2no-separator.mkv',
        overflow,
        'Alpha.mkv',
        'zeta.mkv',
      ]);
    },
  );

  for (final folders in [true, false]) {
    final kind = folders ? 'folders' : 'files';
    RDFileNode node(String name) =>
        folders ? RDFileNode.folder(name: name) : file(name);

    test('$kind with equal numbers do not gain a name tiebreaker', () {
      final names = folders
          ? ['Season 2 zebra', 'Chapter 02 alpha', 'Part 2 middle']
          : ['2. zebra.mkv', '02_alpha.mkv', '2-middle.mkv'];
      final input = List<RDFileNode>.unmodifiable(names.map(node));
      expect(CloudFolderSort.sortedView(input), orderedEquals(input));
    });

    test('$kind with case-insensitive name ties retain distinct nodes', () {
      final input = List<RDFileNode>.unmodifiable(
        ['extras', 'EXTRAS', 'Extras'].map(node),
      );
      expect(CloudFolderSort.sortedView(input), orderedEquals(input));
    });

    test('$kind retain SDK quicksort ordering across large tie groups', () {
      // These ranks explicitly describe the fixture's intended order. They do
      // not parse names or duplicate CloudFolderSort's comparator. List.sort is
      // intentionally not stable: equal-ranked identities must follow the SDK's
      // ordering, including on cohorts larger than its insertion-sort cutoff.
      final names = folders
          ? [
              ('Season 2 zebra', 0),
              ('Chapter 02 alpha', 0),
              ('Part 2 middle', 0),
              ('Episode 10', 1),
              ('Extras', 2),
              ('EXTRAS', 2),
              ('extras', 2),
              ('Zebra', 3),
            ]
          : [
              ('2. zebra.mkv', 0),
              ('02_alpha.mkv', 0),
              ('2-middle.mkv', 0),
              ('10. episode.mkv', 1),
              ('Alpha.mkv', 2),
              ('ALPHA.mkv', 2),
              ('alpha.mkv', 2),
              ('Zebra.mkv', 3),
            ];
      for (final size in [31, 32, 33, 34, 64, 129]) {
        for (var seed = 0; seed < 12; seed++) {
          final random = Random(seed);
          final entries = [
            for (var i = 0; i < size; i++)
              (
                node: node(names[i % names.length].$1),
                rank: names[i % names.length].$2,
              ),
          ]..shuffle(random);
          final input = List<RDFileNode>.unmodifiable(
            entries.map((entry) => entry.node),
          );
          final expected = [...entries]
            ..sort((a, b) => a.rank.compareTo(b.rank));
          expect(
            CloudFolderSort.sortedView(input),
            orderedEquals(expected.map((entry) => entry.node)),
            reason: '$kind cohort=$size seed=$seed; preserve exact identities',
          );
          expect(input, orderedEquals(entries.map((entry) => entry.node)));
        }
      }
    });
  }
}
