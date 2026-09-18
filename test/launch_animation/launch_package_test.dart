import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/launch_animation/launch_package.dart';

Map<String, Object?> animation({int frames = 60}) => {
  'v': '5.7.4',
  'w': 1920,
  'h': 1080,
  'fr': 30,
  'ip': 0,
  'op': frames,
  'layers': <Object?>[],
  'assets': <Object?>[],
};
Uint8List packageBytes({
  String version = '2.0',
  Map<String, Object?>? json,
  Map<String, Object?> extraFiles = const {},
  List<Map<String, Object?>>? animations,
}) {
  final archive = Archive();
  void add(String name, Object? value) {
    final bytes = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('manifest.json', {
    'version': version,
    'animations':
        animations ??
        [
          {'id': 'main'},
        ],
  });
  add(
    '${version == '2.0' ? 'a' : 'animations'}/main.json',
    json ?? animation(),
  );
  for (final entry in extraFiles.entries) {
    add(entry.key, entry.value);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('only recognizes a matching orientation pair with equal timing', () {
    LaunchPackage pair({
      String stem = 'ident',
      int frames = 60,
      bool tall = true,
      bool extra = false,
    }) => LaunchPackage.decode(
      packageBytes(
        animations: [
          {'id': 'ident-landscape'},
          {'id': '$stem-portrait'},
          if (extra) {'id': 'main'},
        ],
        extraFiles: {
          'a/ident-landscape.json': animation(),
          'a/$stem-portrait.json': {
            ...animation(frames: frames),
            'w': tall ? 1080 : 1920,
            'h': tall ? 1920 : 1080,
          },
        },
      ),
    );
    expect(pair().orientationPair?.portrait.id, 'ident-portrait');
    expect(pair(stem: 'other').orientationPair, isNull);
    expect(pair(frames: 30).orientationPair, isNull);
    expect(pair(tall: false).orientationPair, isNull);
    expect(pair(extra: true).orientationPair, isNull);
  });
  for (final version in ['1.0', '2.0']) {
    test('reads dotLottie $version and prepares chosen animation', () {
      final package = LaunchPackage.decode(packageBytes(version: version));
      expect(package.initialId, 'main');
      expect(package.prepare('main').images, isEmpty);
    });
  }
  test('supports multiple explicit compositions without guessing variants', () {
    final package = LaunchPackage.decode(
      packageBytes(
        animations: [
          {'id': 'main'},
          {'id': 'portrait'},
        ],
        extraFiles: {'a/portrait.json': animation()},
      ),
    );
    expect(package.animations.length, 2);
    expect(package.orientationPair, isNull);
    expect(package.prepare('portrait').info.id, 'portrait');
    expect(
      () => package.prepare('missing'),
      throwsA(isA<LaunchImportException>()),
    );
  });
  test('rejects long, malformed, external and live-text animations', () {
    final fixtures = [
      animation(frames: 151),
      {...animation(), 'w': -1},
      {
        ...animation(),
        'layers': [
          {'ty': 5, 'ks': {}, 'ind': 1},
        ],
      },
      {
        ...animation(),
        'assets': [
          {'id': 'image', 'u': 'https://example.com/', 'p': 'a.png'},
        ],
      },
      {
        ...animation(),
        'layers': [
          {'ty': 0, 'ks': {}, 'ind': 1, 'refId': 'missing'},
        ],
      },
      {
        ...animation(),
        'layers': [
          {'ty': 3, 'ks': {}, 'ind': 1, 'parent': 1},
        ],
      },
    ];
    for (final json in fixtures) {
      expect(
        () => LaunchPackage.decode(packageBytes(json: json)).prepare('main'),
        throwsA(isA<LaunchImportException>()),
      );
    }
  });
  test('bounds expanded precompositions and rejects recursive artwork', () {
    Map<String, Object?> ref(int index, String id) => {
      'ty': 0,
      'ind': index,
      'refId': id,
      'ks': {},
    };
    final fixtures = [
      {
        ...animation(),
        'layers': [ref(1, 'nested')],
        'assets': [
          {
            'id': 'nested',
            'layers': [ref(2, 'nested')],
          },
        ],
      },
      {
        ...animation(),
        'layers': List.generate(20, (i) => ref(i, 'nested')),
        'assets': [
          {
            'id': 'nested',
            'layers': List.generate(20, (i) => {'ty': 3, 'ind': i, 'ks': {}}),
          },
        ],
      },
      {
        ...animation(),
        'layers': [
          {
            'ty': 4,
            'ks': {},
            'shapes': [
              {'ty': 'rp'},
            ],
          },
        ],
      },
      {
        ...animation(),
        'slots': {
          'color': {'p': 1},
        },
      },
    ];
    fixtures.addAll([
      {
        ...animation(),
        'layers': [
          {'ty': 4, 'ks': {}, 'tt': 3},
        ],
      },
      {
        ...animation(),
        'layers': [
          {
            'ty': 4,
            'ks': {},
            'shapes': [
              {'ty': 'mm'},
            ],
          },
        ],
      },
    ]);
    fixtures.add({
      ...animation(),
      'layers': List.generate(21, (i) => ref(i, 'detailed')),
      'assets': [
        {
          'id': 'detailed',
          'layers': [
            {
              'ty': 4,
              'ind': 1,
              'ks': {},
              'shapes': [
                {
                  'ty': 'sh',
                  'ks': {
                    'a': 0,
                    'k': {
                      'v': List.generate(600, (i) => [i, i]),
                    },
                  },
                },
              ],
            },
          ],
        },
      ],
    });
    for (final fixture in fixtures) {
      expect(
        () => LaunchPackage.decode(packageBytes(json: fixture)).prepare('main'),
        throwsA(isA<LaunchImportException>()),
      );
    }
  });
  test('rejects traversal, conflicting and case-ambiguous paths', () {
    for (final files in [
      {'../escape': {}},
      {'a': {}},
      {'A/main.json': {}},
    ]) {
      expect(
        () => LaunchPackage.decode(packageBytes(extraFiles: files)),
        throwsA(isA<LaunchImportException>()),
      );
    }
  });
  test('rejects absent manifests and corrupt archives', () {
    expect(
      () => LaunchPackage.decode(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<LaunchImportException>()),
    );
    final bytes = packageBytes();
    expect(
      () => LaunchPackage.decode(
        Uint8List.sublistView(bytes, 0, bytes.length ~/ 2),
      ),
      throwsA(isA<LaunchImportException>()),
    );
  });
  test('checks JSON depth before constructing the graph', () {
    final json =
        '${List.filled(65, '[').join()}0${List.filled(65, ']').join()}';
    expect(
      () => boundedJson(Uint8List.fromList(utf8.encode(json))),
      throwsA(isA<LaunchImportException>()),
    );
  });
  test('expanded bytes are bounded even when ZIP metadata lies', () {
    final archive = Archive();
    final bomb = Uint8List(LaunchLimits.expandedBytes + 1);
    archive.addFile(ArchiveFile('large.bin', bomb.length, bomb));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    // Lie in both size declarations; the streaming output must still refuse.
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 28; i++) {
      final signature = data.getUint32(i, Endian.little);
      if (signature == 0x04034b50) data.setUint32(i + 22, 1, Endian.little);
      if (signature == 0x02014b50) data.setUint32(i + 24, 1, Endian.little);
    }
    expect(
      () => LaunchPackage.decode(bytes),
      throwsA(isA<LaunchImportException>()),
    );
  });
}
