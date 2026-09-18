import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Portable, deliberately bounded dotLottie playback profile. No file-system or
/// renderer side effects: this parser also runs in an isolate during import.
abstract final class LaunchLimits {
  static const compressedBytes = 10 * 1024 * 1024;
  static const expandedBytes = 40 * 1024 * 1024;
  static const entries = 256;
  static const durationSeconds = 5;
  static const imagePixels = 8 * 1024 * 1024;
  static const totalImagePixels = 16 * 1024 * 1024;
  static const jsonDepth = 64;
  static const jsonNodes = 200000;
  static const layers = 200;
}

class LaunchImportException implements Exception {
  const LaunchImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LaunchAnimationInfo {
  const LaunchAnimationInfo(this.id, this.name, this.path, this.background);
  final String id;
  final String name;
  final String path;
  final int? background;
}

class LaunchPackage {
  LaunchPackage(this.files, this.animations, this.initialId, this.warnings);
  final Map<String, Uint8List> files;
  final List<LaunchAnimationInfo> animations;
  final String initialId;
  final List<String> warnings;

  /// Portable convention: exactly one matching `<name>-portrait` /
  /// `<name>-landscape` pair, with correctly shaped canvases and equal timing.
  ({LaunchAnimationInfo portrait, LaunchAnimationInfo landscape})?
  get orientationPair {
    if (animations.length != 2) return null;
    final portrait = animations
        .where((a) => a.id.endsWith('-portrait'))
        .firstOrNull;
    final landscape = animations
        .where((a) => a.id.endsWith('-landscape'))
        .firstOrNull;
    if (portrait == null ||
        landscape == null ||
        portrait.id.replaceFirst(RegExp(r'-portrait$'), '') !=
            landscape.id.replaceFirst(RegExp(r'-landscape$'), '')) {
      return null;
    }
    try {
      final p = jsonDecode(utf8.decode(files[portrait.path]!)) as Map;
      final l = jsonDecode(utf8.decode(files[landscape.path]!)) as Map;
      if ((p['w'] as num) >= (p['h'] as num) ||
          (l['w'] as num) <= (l['h'] as num) ||
          p['fr'] != l['fr'] ||
          p['ip'] != l['ip'] ||
          p['op'] != l['op']) {
        return null;
      }
      return (portrait: portrait, landscape: landscape);
    } catch (_) {
      return null;
    }
  }

  static LaunchPackage decode(Uint8List bytes) {
    try {
      return _decode(bytes);
    } on LaunchImportException {
      rethrow;
    } catch (_) {
      throw const LaunchImportException('The animation package is damaged.');
    }
  }

  static LaunchPackage _decode(Uint8List bytes) {
    if (bytes.length > LaunchLimits.compressedBytes) {
      throw const LaunchImportException(
        'Animation files must be 10 MiB or smaller.',
      );
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.filePosition < 0 ||
        directory.fileHeaders.isEmpty ||
        directory.fileHeaders.length > LaunchLimits.entries ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.fileHeaders.length !=
            directory.totalCentralDirectoryEntries) {
      throw const LaunchImportException(
        'Invalid or oversized animation archive.',
      );
    }
    final files = <String, Uint8List>{};
    final names = <String>{};
    var total = 0;
    for (final header in directory.fileHeaders) {
      final name = header.filename;
      final isDirectory = name.endsWith('/');
      final clean = isDirectory ? name.substring(0, name.length - 1) : name;
      if (!_safePath(clean) ||
          !names.add(clean.toLowerCase()) ||
          header.file?.filename != name ||
          (header.externalFileAttributes >> 16 & 0xf000) == 0xa000 ||
          header.generalPurposeBitFlag & 1 != 0 ||
          header.file!.flags & 1 != 0 ||
          !const [0, 8].contains(header.compressionMethod)) {
        throw const LaunchImportException(
          'Unsafe or unsupported archive entry.',
        );
      }
      if (header.uncompressedSize < 0 ||
          total + header.uncompressedSize > LaunchLimits.expandedBytes) {
        throw const LaunchImportException('Expanded animation exceeds 40 MiB.');
      }
      final output = _BoundedOutput(LaunchLimits.expandedBytes - total);
      final raw = header.file!.getRawContent();
      if (header.compressionMethod == 8) {
        // Force streaming Dart inflate: native decodeBytes may allocate the
        // complete expanded data before the caller can enforce a byte budget.
        Inflate(raw, output: output);
      } else {
        output.writeBytes(raw);
      }
      final content = output.getBytes();
      if (content.length != header.uncompressedSize ||
          getCrc32(content) != header.crc32) {
        throw const LaunchImportException(
          'Animation archive checksum or size is invalid.',
        );
      }
      total += content.length;
      if (!isDirectory) files[name] = content;
    }
    // A file cannot also be the parent directory of another file.
    for (final name in files.keys) {
      var parent = p.posix.dirname(name);
      while (parent != '.') {
        if (files.keys.any((n) => n.toLowerCase() == parent.toLowerCase())) {
          throw const LaunchImportException('Conflicting archive paths.');
        }
        parent = p.posix.dirname(parent);
      }
    }
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null) {
      throw const LaunchImportException('Missing dotLottie manifest.');
    }
    final manifest = boundedJson(manifestBytes);
    if (manifest is! Map ||
        !const ['1.0', '2.0'].contains(manifest['version'])) {
      throw const LaunchImportException(
        'Supported dotLottie versions are 1.0 and 2.0.',
      );
    }
    final declarations = manifest['animations'];
    if (declarations is! List || declarations.isEmpty) {
      throw const LaunchImportException('The package contains no animations.');
    }
    final animations = <LaunchAnimationInfo>[];
    final ids = <String>{};
    final folder = manifest['version'] == '2.0' ? 'a' : 'animations';
    for (final declaration in declarations) {
      if (declaration is! Map || !safeId(declaration['id'])) {
        throw const LaunchImportException('Invalid animation ID.');
      }
      final id = declaration['id'] as String;
      if (!ids.add(id) || !files.containsKey('$folder/$id.json')) {
        throw const LaunchImportException('Duplicate or missing animation.');
      }
      final rawName = declaration['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : id;
      animations.add(
        LaunchAnimationInfo(
          id,
          name.substring(0, name.length.clamp(0, 120)),
          '$folder/$id.json',
          parseBackground(declaration['background']),
        ),
      );
    }
    final initial = manifest['initial'];
    final desired = initial is Map
        ? initial['animation']
        : manifest['activeAnimationId'];
    final warnings = <String>[];
    if (manifest['stateMachines'] != null || manifest['themes'] != null) {
      warnings.add(
        'Package state machines and dynamic themes are not applied.',
      );
    }
    return LaunchPackage(
      files,
      animations,
      ids.contains(desired) ? desired as String : animations.first.id,
      warnings,
    );
  }

  PreparedLaunchAnimation prepare(String id) {
    final info = animations.where((a) => a.id == id).firstOrNull;
    if (info == null) {
      throw const LaunchImportException(
        'The selected animation does not exist.',
      );
    }
    final json = validateLaunchJson(files[info.path]!);
    final images = <String, Uint8List>{};
    final assets = json['assets'];
    if (assets != null && assets is! List) {
      throw const LaunchImportException('Invalid animation assets.');
    }
    for (final asset in (assets as List? ?? const [])) {
      if (asset is! Map) {
        throw const LaunchImportException('Invalid animation asset.');
      }
      if (!asset.containsKey('p')) continue;
      final imageId = asset['id'];
      final filename = asset['p'];
      final dir = asset['u'] ?? '';
      if (imageId is! String ||
          filename is! String ||
          dir is! String ||
          images.containsKey(imageId)) {
        throw const LaunchImportException('Invalid image reference.');
      }
      Uint8List? content;
      if (filename.startsWith('data:image/png;base64,') ||
          filename.startsWith('data:image/jpeg;base64,')) {
        try {
          content = base64Decode(filename.substring(filename.indexOf(',') + 1));
        } catch (_) {
          throw const LaunchImportException('Invalid embedded image.');
        }
      } else {
        final reference = '$dir$filename';
        if (reference.contains(':') ||
            reference.contains('\\') ||
            reference.startsWith('/')) {
          throw const LaunchImportException(
            'Images must be included in the package.',
          );
        }
        // dotLottie exporters use either archive-root or animation-relative paths.
        final relative = p.posix.normalize(
          p.posix.join(p.posix.dirname(info.path), reference),
        );
        final root = p.posix.normalize(reference);
        content = _safePath(root) ? files[root] : null;
        content ??= _safePath(relative) ? files[relative] : null;
      }
      if (content == null) {
        throw const LaunchImportException(
          'An image is missing from the package.',
        );
      }
      images[imageId] = content;
    }
    return PreparedLaunchAnimation(
      info,
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
      images,
      warnings,
    );
  }
}

/// Validate persisted JSON again before constructing renderer objects.
Map<String, dynamic> validateLaunchJson(Uint8List bytes) {
  final json = boundedJson(bytes);
  if (json is! Map<String, dynamic>) {
    throw const LaunchImportException('Invalid animation JSON.');
  }
  final width = _number(json['w']);
  final height = _number(json['h']);
  final fps = _number(json['fr']);
  final start = _number(json['ip']);
  final end = _number(json['op']);
  if (width <= 0 ||
      height <= 0 ||
      width > 8192 ||
      height > 8192 ||
      fps <= 0 ||
      fps > 60 ||
      end <= start) {
    throw const LaunchImportException(
      'Invalid dimensions or frame rate (maximum 60 fps).',
    );
  }
  if ((end - start) / fps > LaunchLimits.durationSeconds) {
    throw const LaunchImportException(
      'Launch animations must be five seconds or shorter.',
    );
  }
  if (json['slots'] is Map && (json['slots'] as Map).isNotEmpty) {
    throw const LaunchImportException(
      'Export fixed colors and values instead of dynamic slots.',
    );
  }
  var layerCount = 0;
  var masks = 0;
  var vertices = 0;
  void inspect(Object? node) {
    if (node is num && !node.isFinite) {
      throw const LaunchImportException(
        'Animation contains non-finite values.',
      );
    }
    if (node is Map) {
      if (node['ty'] == 'mm') {
        throw const LaunchImportException(
          'Flatten merged paths before exporting.',
        );
      }
      if (node['tt'] is num && !const [0, 1, 2].contains(node['tt'])) {
        throw const LaunchImportException(
          'Only alpha and inverted alpha mattes are supported.',
        );
      }
      if (node['ty'] == 'rp') {
        throw const LaunchImportException(
          'Expand repeaters into a bounded number of shapes before exporting.',
        );
      }
      if (node['masksProperties'] is List) {
        masks += (node['masksProperties'] as List).length;
      }
      if (node['tt'] is num && node['tt'] != 0) masks++;
      if (node['v'] is List) vertices += (node['v'] as List).length;
      if (masks > 16 || vertices > 10000) {
        throw const LaunchImportException(
          'Animation exceeds the mask or path complexity limit.',
        );
      }
      if (node['ty'] is num && node.containsKey('ks')) {
        layerCount++;
        if (!const [0, 1, 2, 3, 4].contains(node['ty']) || node['ddd'] == 1) {
          throw const LaunchImportException(
            'Use 2D shapes and images; convert text to vector paths.',
          );
        }
        if (node['ef'] is List && (node['ef'] as List).isNotEmpty) {
          throw const LaunchImportException(
            'Layer effects are unsupported. Export shapes instead.',
          );
        }
      }
      if (node['x'] is String || node.containsKey('sid')) {
        throw const LaunchImportException(
          'Expressions and dynamic slots are unsupported.',
        );
      }
      for (final value in node.values) {
        inspect(value);
      }
    } else if (node is List) {
      for (final value in node) {
        inspect(value);
      }
    }
  }

  inspect(json);
  if (layerCount > LaunchLimits.layers) {
    throw const LaunchImportException(
      'Animation has too many layers (maximum 200).',
    );
  }
  _validateLayerGraphs(json);
  return json;
}

class PreparedLaunchAnimation {
  const PreparedLaunchAnimation(
    this.info,
    this.json,
    this.images,
    this.warnings,
  );
  final LaunchAnimationInfo info;
  final Uint8List json;
  final Map<String, Uint8List> images;
  final List<String> warnings;
}

bool safeId(Object? value) =>
    value is String &&
    RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}$').hasMatch(value);

int? parseBackground(Object? value) {
  if (value == null) return null;
  if (value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return 0xff000000 | int.parse(value.substring(1), radix: 16);
  }
  return null;
}

bool _safePath(String value) =>
    value.isNotEmpty &&
    value.length <= 512 &&
    !value.contains('\\') &&
    !value.contains(':') &&
    !value.contains('\u0000') &&
    !value.startsWith('/') &&
    value
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

double _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const LaunchImportException(
      'Invalid animation dimensions or timing.',
    );
  }
  return value.toDouble();
}

Object? boundedJson(Uint8List bytes) {
  // Bound nesting before jsonDecode allocates a recursive object graph.
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final byte in bytes) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (byte == 92) {
        escaped = true;
      } else if (byte == 34) {
        quoted = false;
      }
    } else if (byte == 34) {
      quoted = true;
    } else if (byte == 123 || byte == 91) {
      if (++depth > LaunchLimits.jsonDepth) {
        throw const LaunchImportException('Animation nesting is too deep.');
      }
    } else if (byte == 125 || byte == 93) {
      depth--;
    }
  }
  var nodes = 0;
  return jsonDecode(
    utf8.decode(bytes),
    reviver: (key, value) {
      if (++nodes > LaunchLimits.jsonNodes) {
        throw const LaunchImportException('Animation is too complex.');
      }
      return value;
    },
  );
}

void _validateLayerGraphs(Map<String, dynamic> json) {
  final groups = <String, List>{'root': json['layers'] as List? ?? const []};
  for (final asset in json['assets'] as List? ?? const []) {
    if (asset is Map && asset['layers'] is List) {
      final id = asset['id'];
      if (id is! String || groups.containsKey(id)) {
        throw const LaunchImportException('Invalid composition reference.');
      }
      groups[id] = asset['layers'] as List;
    }
  }
  final active = <String>{};
  var expandedLayers = 0;
  var expandedMasks = 0;
  var expandedVertices = 0;
  void countRenderedContent(Object? node) {
    if (node is Map) {
      if (node['masksProperties'] is List) {
        expandedMasks += (node['masksProperties'] as List).length;
      }
      if (node['tt'] is num && node['tt'] != 0) expandedMasks++;
      if (node['v'] is List) expandedVertices += (node['v'] as List).length;
      if (expandedMasks > 16 || expandedVertices > 10000) {
        throw const LaunchImportException(
          'Expanded compositions exceed the mask or path complexity limit.',
        );
      }
      for (final value in node.values) {
        countRenderedContent(value);
      }
    } else if (node is List) {
      for (final value in node) {
        countRenderedContent(value);
      }
    }
  }

  void visit(String id, int depth) {
    if (depth > 16 || !active.add(id)) {
      throw const LaunchImportException(
        'Composition references are cyclic or too deep.',
      );
    }
    final layers = groups[id];
    if (layers == null) {
      throw const LaunchImportException('Missing composition.');
    }
    final parents = <Object, Object?>{};
    for (final layer in layers) {
      if (++expandedLayers > LaunchLimits.layers) {
        throw const LaunchImportException(
          'Expanded compositions exceed 200 layers.',
        );
      }
      if (layer is! Map) throw const LaunchImportException('Invalid layer.');
      countRenderedContent(layer);
      final index = layer['ind'];
      if (index != null) {
        if (parents.containsKey(index)) {
          throw const LaunchImportException('Duplicate layer ID.');
        }
        parents[index] = layer['parent'];
      }
      if (layer['ty'] == 2 &&
          !(json['assets'] as List? ?? const []).any(
            (asset) =>
                asset is Map &&
                asset['id'] == layer['refId'] &&
                asset['p'] is String,
          )) {
        throw const LaunchImportException('Missing image reference.');
      }
      if (layer['ty'] == 0) {
        final ref = layer['refId'];
        if (ref is! String) {
          throw const LaunchImportException('Missing composition reference.');
        }
        visit(ref, depth + 1);
      }
    }
    for (final index in parents.keys) {
      final chain = <Object>{};
      Object? current = index;
      while (current != null) {
        if (!chain.add(current)) {
          throw const LaunchImportException('Cyclic layer parents.');
        }
        current = parents[current];
      }
    }
    active.remove(id);
  }

  visit('root', 0);
}

class _BoundedOutput extends OutputMemoryStream {
  _BoundedOutput(this.limit) : super(size: 1024);
  final int limit;
  void _admit(int count) {
    if (count < 0 || length + count > limit) {
      throw const LaunchImportException(
        'Expanded animation exceeds its size limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _admit(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _admit(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _admit(stream.length);
    super.writeStream(stream);
  }
}
