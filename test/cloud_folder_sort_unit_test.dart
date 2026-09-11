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
}
