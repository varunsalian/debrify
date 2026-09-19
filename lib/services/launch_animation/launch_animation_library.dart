import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as p;
import '../../utils/app_storage.dart';
import 'package:synchronized/synchronized.dart';

import 'launch_package.dart';

class InstalledLaunchAnimation {
  const InstalledLaunchAnimation({
    required this.id,
    required this.name,
    required this.animationId,
    required this.background,
    required this.warnings,
  });
  final String id;
  final String name;
  final String animationId;
  final int background;
  final List<String> warnings;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'animationId': animationId,
    'background': background,
    'warnings': warnings,
  };
  factory InstalledLaunchAnimation.fromJson(Map<String, dynamic> json) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(json['id'] as String? ?? '') ||
        !safeId(json['animationId']) ||
        json['name'] is! String ||
        (json['name'] as String).length > 120 ||
        !validBackground(json['background']) ||
        json['warnings'] is! List ||
        (json['warnings'] as List).any((w) => w is! String)) {
      throw const FormatException('Invalid library entry');
    }
    return InstalledLaunchAnimation(
      id: json['id'],
      name: json['name'],
      animationId: json['animationId'],
      background: json['background'],
      warnings: List<String>.from(json['warnings']),
    );
  }
  static bool validBackground(Object? value) =>
      value is int && value >= 0xff000000 && value <= 0xffffffff;
}

/// Each load owns its decoded images; no global renderer cache retains deleted
/// packages or accumulates preview frames on TVs.
class LoadedLaunchAnimation {
  LoadedLaunchAnimation(this.composition, this.background, this.warnings);
  final LottieComposition composition;
  final int background;
  final List<String> warnings;
  bool _disposed = false;
  LoadedLaunchAnimation? alternate;
  LottieComposition compositionFor(bool portrait) {
    final other = alternate;
    if (other != null &&
        (composition.bounds.height > composition.bounds.width) != portrait) {
      return other.composition;
    }
    return composition;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    alternate?.dispose();
    for (final asset in composition.images.values) {
      asset.loadedImage?.dispose();
      asset.loadedImage = null;
    }
  }
}

class LaunchAnimationLibrary {
  LaunchAnimationLibrary({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  static final instance = LaunchAnimationLibrary();
  final Future<Directory> Function() _directory;
  final Lock _lock = Lock();
  final Set<String> _preparing = {};
  final ValueNotifier<int> revision = ValueNotifier(0);
  static Future<Directory> _defaultDirectory() async =>
      Directory(p.join((await AppStorage.support()).path, 'launch_animations'));

  Future<Directory> _root() async =>
      (await _directory()).create(recursive: true);
  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<List<InstalledLaunchAnimation>> _readIndex(Directory root) async {
    final file = File(p.join(root.path, 'index.json'));
    if (!await file.exists()) return [];
    try {
      if (await file.length() > 1024 * 1024) throw const FormatException();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['version'] != 1 || json['entries'] is! List) {
        throw const FormatException();
      }
      final entries = (json['entries'] as List)
          .map(
            (e) =>
                InstalledLaunchAnimation.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
      if (entries.map((e) => e.id).toSet().length != entries.length) {
        throw const FormatException();
      }
      return entries;
    } catch (_) {
      throw const LaunchImportException(
        'The animation library index is damaged. Reset the library index in settings, then import your files again.',
      );
    }
  }

  Future<void> _writeIndex(
    Directory root,
    List<InstalledLaunchAnimation> entries,
  ) async {
    final contents = jsonEncode({
      'version': 1,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    if (utf8.encode(contents).length > 1024 * 1024) {
      throw const LaunchImportException(
        'The animation library is full. Delete unused animations.',
      );
    }
    final temp = File(p.join(root.path, 'index.tmp'));
    await temp.writeAsString(contents, flush: true);
    await temp.rename(p.join(root.path, 'index.json'));
    revision.value++;
  }

  Future<List<InstalledLaunchAnimation>> list({bool clean = false}) =>
      _lock.synchronized(() async {
        final root = await _root();
        final entries = await _readIndex(
          root,
        ); // Never clean using a corrupt index.
        if (clean) {
          final keep = entries.map((e) => e.id).toSet();
          await for (final entity in root.list(followLinks: false)) {
            final name = p.basename(entity.path);
            if (entity is Directory &&
                !_preparing.contains(name) &&
                (RegExp(r'^pending-[a-f0-9]{32}$').hasMatch(name) ||
                    (RegExp(r'^[a-f0-9]{32}$').hasMatch(name) &&
                        !keep.contains(name)))) {
              try {
                await entity.delete(recursive: true);
              } catch (_) {
                /* Retry at next settings open. */
              }
            }
          }
        }
        return entries;
      });

  Future<void> resetDamagedIndex() => _lock.synchronized(() async {
    final root = await _root();
    final index = File(p.join(root.path, 'index.json'));
    // Preserve evidence and files. Normal orphan cleanup can run on a later open.
    if (await index.exists()) {
      await index.rename(p.join(root.path, 'index-damaged-${_newId()}.json'));
    }
    await _writeIndex(root, []);
  });

  Future<LaunchPackage> inspectFile(File source) async {
    final bytes = await readBoundedFile(source, LaunchLimits.compressedBytes);
    return compute(LaunchPackage.decode, bytes);
  }

  Future<InstalledLaunchAnimation> install(
    File source, {
    String? animationId,
    int? background,
    Future<void> Function()? beforeCommit,
  }) async {
    if (background != null &&
        !InstalledLaunchAnimation.validBackground(background)) {
      throw const LaunchImportException('Invalid animation background color.');
    }
    final bytes = await readBoundedFile(source, LaunchLimits.compressedBytes);
    final prepared = await compute(_prepare, (bytes: bytes, id: animationId));
    final loaded = await loadPrepared(prepared, background: background);
    try {
      final alternate = await compute(_prepareAlternate, (
        bytes: bytes,
        id: prepared.info.id,
      ));
      if (alternate != null) {
        loaded.alternate = await loadPrepared(
          alternate,
          background: loaded.background,
        );
      }
    } catch (_) {
      loaded.dispose();
      rethrow;
    }
    final entry = InstalledLaunchAnimation(
      id: _newId(),
      name: prepared.info.name,
      animationId: prepared.info.id,
      background: loaded.background,
      warnings: {...loaded.warnings, ...?loaded.alternate?.warnings}.toList(),
    );
    loaded.dispose();
    final root = await _root();
    final pendingName = 'pending-${entry.id}';
    _preparing.add(pendingName);
    final pending = Directory(p.join(root.path, pendingName));
    try {
      await pending.create();
      await File(
        p.join(pending.path, 'original.lottie'),
      ).writeAsBytes(bytes, flush: true);
      await File(
        p.join(pending.path, 'animation.json'),
      ).writeAsBytes(prepared.json, flush: true);
      final imageIndex = <String, String>{};
      var n = 0;
      for (final image in prepared.images.entries) {
        final filename = 'image-${n++}.bin';
        imageIndex[image.key] = filename;
        await File(
          p.join(pending.path, filename),
        ).writeAsBytes(image.value, flush: true);
      }
      await File(
        p.join(pending.path, 'images.json'),
      ).writeAsString(jsonEncode(imageIndex), flush: true);
      await _lock.synchronized(() async {
        final entries = await _readIndex(root);
        await beforeCommit?.call();
        await pending.rename(p.join(root.path, entry.id));
        try {
          await _writeIndex(root, [...entries, entry]);
        } catch (_) {
          try {
            await Directory(
              p.join(root.path, entry.id),
            ).delete(recursive: true);
          } catch (_) {}
          rethrow;
        }
      });
      return entry;
    } finally {
      _preparing.remove(pendingName);
      if (await pending.exists()) await pending.delete(recursive: true);
    }
  }

  Future<void> delete(String id) => _lock.synchronized(() async {
    final root = await _root();
    final entries = await _readIndex(root);
    if (!entries.any((e) => e.id == id)) return;
    await _writeIndex(root, entries.where((e) => e.id != id).toList());
    try {
      await Directory(p.join(root.path, id)).delete(recursive: true);
    } catch (_) {}
  });

  Future<void> setBackground(String id, int color) =>
      _lock.synchronized(() async {
        if (!InstalledLaunchAnimation.validBackground(color)) {
          throw const LaunchImportException('Invalid background color.');
        }
        final root = await _root();
        final entries = await _readIndex(root);
        if (!entries.any((e) => e.id == id)) {
          throw const LaunchImportException(
            'This animation is no longer installed.',
          );
        }
        await _writeIndex(
          root,
          entries
              .map(
                (e) => e.id != id
                    ? e
                    : InstalledLaunchAnimation(
                        id: e.id,
                        name: e.name,
                        animationId: e.animationId,
                        background: color,
                        warnings: e.warnings,
                      ),
              )
              .toList(),
        );
      });

  Future<File> originalFile(String id) async {
    final root = await _root();
    final entries = await _lock.synchronized(() => _readIndex(root));
    if (!entries.any((e) => e.id == id)) {
      throw const LaunchImportException(
        'This animation is no longer installed.',
      );
    }
    return File(p.join(root.path, id, 'original.lottie'));
  }

  Future<LoadedLaunchAnimation> load(String id) async {
    final root = await _root();
    final entries = await _lock.synchronized(() => _readIndex(root));
    final entry = entries.where((e) => e.id == id).firstOrNull;
    if (entry == null) {
      throw const LaunchImportException(
        'This animation is no longer installed.',
      );
    }
    final directory = Directory(p.join(root.path, entry.id));
    final json = await readBoundedFile(
      File(p.join(directory.path, 'animation.json')),
      LaunchLimits.expandedBytes,
    );
    final index = jsonDecode(
      utf8.decode(
        await readBoundedFile(
          File(p.join(directory.path, 'images.json')),
          64 * 1024,
        ),
      ),
    );
    if (index is! Map || index.length > LaunchLimits.entries) {
      throw const LaunchImportException('Invalid stored images.');
    }
    final images = <String, Uint8List>{};
    var remaining = LaunchLimits.expandedBytes - json.length;
    for (final asset in index.entries) {
      if (asset.key is! String ||
          asset.value is! String ||
          !RegExp(r'^image-[0-9]+\.bin$').hasMatch(asset.value)) {
        throw const LaunchImportException('Invalid stored image path.');
      }
      final bytes = await readBoundedFile(
        File(p.join(directory.path, asset.value)),
        remaining,
      );
      remaining -= bytes.length;
      images[asset.key as String] = bytes;
    }
    final loaded = await loadPrepared(
      PreparedLaunchAnimation(
        LaunchAnimationInfo(
          entry.animationId,
          entry.name,
          '',
          entry.background,
        ),
        json,
        images,
        entry.warnings,
      ),
      background: entry.background,
    );
    try {
      if (entry.animationId.endsWith('-portrait') ||
          entry.animationId.endsWith('-landscape')) {
        final bytes = await readBoundedFile(
          File(p.join(directory.path, 'original.lottie')),
          LaunchLimits.compressedBytes,
        );
        final alternate = await compute(_prepareAlternate, (
          bytes: bytes,
          id: entry.animationId,
        ));
        if (alternate != null) {
          loaded.alternate = await loadPrepared(
            alternate,
            background: entry.background,
          );
        }
      }
      return loaded;
    } catch (_) {
      loaded.dispose();
      rethrow;
    }
  }
}

PreparedLaunchAnimation? _prepareAlternate(
  ({Uint8List bytes, String id}) input,
) {
  if (!input.id.endsWith('-portrait') && !input.id.endsWith('-landscape')) {
    return null;
  }
  final package = LaunchPackage.decode(input.bytes);
  final pair = package.orientationPair;
  if (pair == null) return null;
  return package.prepare(
    input.id == pair.portrait.id ? pair.landscape.id : pair.portrait.id,
  );
}

PreparedLaunchAnimation _prepare(({Uint8List bytes, String? id}) input) {
  try {
    final package = LaunchPackage.decode(input.bytes);
    return package.prepare(input.id ?? package.initialId);
  } on LaunchImportException {
    rethrow;
  } catch (_) {
    throw const LaunchImportException(
      'The selected animation contains invalid data.',
    );
  }
}

Future<Uint8List> readBoundedFile(File file, int limit) async {
  if (await file.length() > limit) {
    throw const LaunchImportException('Animation file exceeds its size limit.');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (builder.length + chunk.length > limit) {
      throw const LaunchImportException(
        'Animation file exceeds its size limit.',
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<LoadedLaunchAnimation> loadPrepared(
  PreparedLaunchAnimation prepared, {
  int? background,
}) async {
  final composition = await compute(_parseValidatedComposition, prepared.json);
  final loaded = LoadedLaunchAnimation(
    composition,
    background ?? prepared.info.background ?? 0xff080b12,
    {...prepared.warnings, ...composition.warnings}.toList(),
  );
  var totalPixels = 0;
  try {
    for (final asset in composition.images.values) {
      final bytes = prepared.images[asset.id];
      if (bytes == null) {
        throw const LaunchImportException('Missing image asset.');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final pixels = descriptor.width * descriptor.height;
        totalPixels += pixels;
        if (pixels > LaunchLimits.imagePixels ||
            totalPixels > LaunchLimits.totalImagePixels) {
          throw const LaunchImportException(
            'Images exceed the decoded pixel budget.',
          );
        }
        final codec = await descriptor.instantiateCodec();
        try {
          if (codec.frameCount != 1) {
            throw const LaunchImportException(
              'Animated image assets are unsupported.',
            );
          }
          asset.loadedImage = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
    }
    return loaded;
  } catch (_) {
    loaded.dispose();
    rethrow;
  }
}

/// A bounded startup decision. Late results are disposed, never published. The
/// owner supplies its mounted/session check and owns a successfully returned load.
Future<LoadedLaunchAnimation?> loadLaunchAnimationForStartup(
  Future<LoadedLaunchAnimation> Function() load, {
  required bool Function() isCurrent,
  Duration deadline = const Duration(seconds: 1),
}) async {
  var abandoned = false;
  try {
    final pending = load();
    unawaited(
      pending.then((loaded) {
        if (abandoned || !isCurrent()) loaded.dispose();
      }, onError: (Object _) {}),
    );
    final loaded = await pending.timeout(deadline);
    if (!isCurrent()) {
      loaded.dispose();
      return null;
    }
    return loaded;
  } catch (_) {
    abandoned = true;
    return null;
  }
}

LottieComposition _parseValidatedComposition(Uint8List bytes) {
  validateLaunchJson(bytes);
  return LottieComposition.parseJsonBytes(bytes);
}
