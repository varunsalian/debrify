import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const maxBadgeSvgBytes = 128 * 1024;

bool isBadgeSvgUrl(String url) =>
    Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false;

bool isBadgeBitmapUrl(String url) => RegExp(
  r'\.(png|jpe?g|webp|gif|bmp|avif|ico)$',
  caseSensitive: false,
).hasMatch(Uri.tryParse(url)?.path ?? '');

/// Static, self-contained vector artwork only. Run outside the UI isolate.
/// Returns normalized XML: render this result, never the original input. The
/// renderer must not get a second chance to interpret CSS differently from us.
String validateBadgeSvg(Uint8List bytes) {
  if (bytes.length > maxBadgeSvgBytes) {
    throw const FormatException('SVG too large');
  }
  final text = utf8.decode(bytes);
  if (text.contains('\u0000') ||
      RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    throw const FormatException('SVG document declarations are not supported');
  }
  // Check depth before constructing a tree (the Android DOM parser recurses).
  var xmlDepth = 0;
  var xmlElements = 0;
  for (final event in parseEvents(text, validateNesting: true)) {
    if (event is XmlStartElementEvent) {
      if (++xmlElements > 2048 || xmlDepth > 32) {
        throw const FormatException('Unsupported SVG structure');
      }
      final names = <String>{};
      if (event.attributes.any((attribute) => !names.add(attribute.name))) {
        throw const FormatException('Duplicate SVG attribute');
      }
      if (!event.isSelfClosing) xmlDepth++;
    } else if (event is XmlEndElementEvent) {
      xmlDepth--;
    }
  }
  final parsed = XmlDocument.parse(text);
  if (parsed.rootElement.name.local != 'svg' ||
      !_isSvgNamespace(parsed.rootElement.namespaceUri)) {
    throw const FormatException('Not SVG');
  }
  final document = XmlDocument([_badgeSvgElement(parsed.rootElement)]);
  document.rootElement.setAttribute('xmlns', _svgNamespace);
  _setSvgAttribute(document.rootElement, 'xmlns:xlink', _xlinkNamespace);
  const forbidden = {
    'script',
    'foreignObject',
    'image',
    'use',
    'pattern',
    // Markers multiply work per vertex, including inherited/recursive uses.
    'marker',
    // Flutter's renderer ignores stylesheets, silently changing artwork colours.
    // Use the same supported subset on native; inline style attributes work.
    'style',
    'filter',
    'animate',
    'animateMotion',
    'animateTransform',
    'set',
  };
  final urls = RegExp(r'url\s*\(([^)]*)\)', caseSensitive: false);
  final graph = <String, List<String>>{};
  final nodes = <String, int>{};
  final masks = <String>{};
  final referencedIds = <String>[];
  var elements = 0;
  var references = 0;
  var sourceWork = 0;
  void checkProperty(String name, String value) {
    // The compiler expands dashes by path length / interval before raster size
    // limits apply. Reject patterns everywhere, including inheritable parents;
    // the explicit solid-stroke reset used by SVG editors is harmless.
    if (name.toLowerCase() == 'stroke-dasharray' && value.trim() != 'none') {
      throw const FormatException('SVG dash patterns are not supported');
    }
  }

  String checkValue(String value, List<String> owners, {bool href = false}) {
    final refs = <String>[
      if (href) value,
      for (final match in urls.allMatches(value))
        match.group(1)!.trim().replaceAll(RegExp("^[\"']|[\"']\$"), ''),
    ];
    if (value.toLowerCase().contains('@import')) {
      throw const FormatException('External SVG styles');
    }
    for (final ref in refs) {
      if (!ref.startsWith('#') || ++references > 256) {
        throw const FormatException('Unsupported SVG reference');
      }
      final id = ref.substring(1);
      if (RegExp(r'''[\s'"()\\]''').hasMatch(id)) {
        throw const FormatException('Unsupported SVG fragment');
      }
      referencedIds.add(id);
      for (final owner in owners) {
        graph.putIfAbsent(owner, () => []).add(id);
      }
    }
    // Flutter resolves the literal url(#id) string, unlike AndroidSVG's URL
    // parser. Canonicalize quotes, case and whitespace after validating refs.
    return value.replaceAllMapped(urls, (match) {
      final ref = match
          .group(1)!
          .trim()
          .replaceAll(RegExp("^[\"']|[\"']\$"), '');
      return 'url($ref)';
    });
  }

  void visit(XmlElement element, List<String> owners, int depth) {
    if (++elements > 2048 ||
        depth > 32 ||
        forbidden.contains(element.name.local)) {
      throw const FormatException('Unsupported SVG structure');
    }
    // Inline CSS has higher specificity than presentation attributes, regardless
    // of their XML order. Only presentation properties can become attributes:
    // flutter_svg otherwise accepts structural CSS such as `id` and `href`.
    final style = element.getAttribute('style');
    if (style != null) {
      final declarations = _badgeSvgStyle(style);
      for (final declaration in declarations.entries) {
        checkProperty(declaration.key, declaration.value);
        if (_badgeSvgPresentationProperties.contains(declaration.key)) {
          element.setAttribute(declaration.key, declaration.value);
        }
      }
      element.removeAttribute('style');
    }
    final id = element.getAttribute('id')?.trim();
    if (id != null) {
      if (id.isEmpty || RegExp(r'''[\s'"()\\]''').hasMatch(id)) {
        throw const FormatException('Unsupported SVG id');
      }
      element.setAttribute('id', id);
    }
    if (id != null && nodes.containsKey(id)) {
      throw const FormatException('Duplicate SVG id');
    }
    if (element.name.local == 'mask' && id != null) masks.add(id);
    final active = id == null ? owners : [...owners, id];
    // A path with thousands of segments is not equivalent to one rectangle.
    // Charge its geometry to every containing definition before multiplying
    // reference costs, so short mask chains cannot repeatedly redraw huge paths.
    final geometry =
        (element.getAttribute('d')?.length ?? 0) +
        (element.getAttribute('points')?.length ?? 0) +
        (element.getAttribute('transform')?.length ?? 0) +
        element.children.whereType<XmlText>().fold<int>(
          0,
          (sum, text) => sum + text.value.trim().length,
        ) +
        element.children.whereType<XmlCDATA>().fold<int>(
          0,
          (sum, text) => sum + text.value.trim().length,
        );
    final work = 1 + (geometry + 31) ~/ 32;
    sourceWork += work;
    for (final owner in active) {
      nodes[owner] = (nodes[owner] ?? 0) + work;
    }
    for (final attribute in element.attributes) {
      if (attribute.name.local.toLowerCase().startsWith('on')) {
        throw const FormatException('SVG event handler');
      }
      checkProperty(attribute.name.local, attribute.value);
      attribute.value = checkValue(
        attribute.value,
        active,
        href: attribute.name.local == 'href',
      );
    }
    for (final child in element.childElements) {
      visit(child, active, depth + 1);
    }
  }

  visit(document.rootElement, const [], 0);
  final costs = <String, int>{};
  int expansionCost(String id, Set<String> chain) {
    if (chain.contains(id) || chain.length > 32) {
      throw const FormatException('Cyclic SVG reference');
    }
    if (costs.containsKey(id)) return costs[id]!;
    var cost = nodes[id] ?? 1;
    for (final ref in graph[id] ?? const <String>[]) {
      cost += expansionCost(ref, {...chain, id});
      if (cost > 4096) {
        throw const FormatException('SVG reference expansion too large');
      }
    }
    // Match the native budget: AndroidSVG renders masks twice, including their
    // descendants, so linear mask-reference chains have multiplicative cost.
    if (masks.contains(id)) cost *= 2;
    if (cost > 4096) {
      throw const FormatException('SVG reference expansion too large');
    }
    return costs[id] = cost;
  }

  for (final id in graph.keys) {
    expansionCost(id, {});
  }
  var totalCost = sourceWork;
  if (totalCost > 4096) {
    throw const FormatException('SVG geometry too large');
  }
  for (final id in referencedIds) {
    totalCost += expansionCost(id, {});
    if (totalCost > 4096) {
      throw const FormatException('SVG reference expansion too large');
    }
  }
  return document.toXmlString();
}

const _svgNamespace = 'http://www.w3.org/2000/svg';
const _xlinkNamespace = 'http://www.w3.org/1999/xlink';
bool _isSvgNamespace(String? uri) =>
    uri == null || uri.isEmpty || uri == _svgNamespace;

/// Build a namespace-unambiguous tree. The Flutter compiler uses local attribute
/// names, including xmlns declarations; AndroidSVG uses namespace-aware SAX.
/// Do not forward editor namespace aliases/annotations as rendering attributes.
XmlElement _badgeSvgElement(XmlElement source) {
  final target = XmlElement(XmlName(source.name.local));
  for (final attribute in source.attributes) {
    final name = attribute.name.local;
    final prefix = attribute.name.prefix;
    if (name == 'xmlns' || prefix == 'xmlns') continue;
    if (name == 'href' &&
        (prefix == null || attribute.namespaceUri == _xlinkNamespace)) {
      _setSvgAttribute(target, 'xlink:href', attribute.value);
    } else if (prefix == null) {
      target.setAttribute(name, attribute.value);
    } else if (prefix == 'xml' && name == 'space') {
      _setSvgAttribute(target, 'xml:space', attribute.value);
    }
  }
  // SVG 2 href takes precedence over the legacy xlink spelling.
  final href = source.getAttribute('href');
  if (href != null) _setSvgAttribute(target, 'xlink:href', href);
  for (final child in source.children) {
    if (child is XmlElement && _isSvgNamespace(child.namespaceUri)) {
      target.children.add(_badgeSvgElement(child));
    } else if (child is XmlText || child is XmlCDATA) {
      target.children.add(child.copy());
    }
  }
  return target;
}

void _setSvgAttribute(XmlElement element, String qualifiedName, String value) {
  final existing = element.getAttributeNode(qualifiedName);
  if (existing != null) {
    existing.value = value;
  } else {
    // XmlElement.setAttribute without a namespace creates a *local* name even
    // for strings containing a colon; keep the qualified name structured.
    element.attributes.add(
      XmlAttribute(XmlName.fromString(qualifiedName), value),
    );
  }
}

// Keep in sync with StreamBadgeSvg.kt; shared fixtures exercise both renderers.
const _badgeSvgPresentationProperties = {
  'color',
  'display',
  'visibility',
  'opacity',
  'overflow',
  'clip',
  'clip-path',
  'clip-rule',
  'mask',
  'fill',
  'fill-rule',
  'fill-opacity',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'stroke-opacity',
  'stroke-dasharray',
  'stroke-dashoffset',
  'stop-color',
  'stop-opacity',
  'font-family',
  'font-size',
  'font-style',
  'font-weight',
  'font-variant',
  'font-stretch',
  'text-anchor',
  'text-decoration',
  'letter-spacing',
  'word-spacing',
  'direction',
  'unicode-bidi',
  'vector-effect',
  'marker',
  'marker-start',
  'marker-mid',
  'marker-end',
  'solid-color',
  'solid-opacity',
  'paint-order',
};

/// A linear inline-declaration parser, not a stylesheet engine. Comments are
/// removed outside strings; quoted semicolons are preserved in attribute values.
/// No CSS survives into either renderer, including ignored/unknown properties.
Map<String, String> _badgeSvgStyle(String input) {
  if (input.contains(r'\')) {
    throw const FormatException('SVG CSS escapes are not supported');
  }
  final declarations = <String>[];
  final value = StringBuffer();
  String? quote;
  var parentheses = 0;
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (quote != null) {
      value.write(char);
      if (char == quote) quote = null;
    } else if (char == '/' && i + 1 < input.length && input[i + 1] == '*') {
      final end = input.indexOf('*/', i + 2);
      if (end < 0) throw const FormatException('Unclosed SVG CSS comment');
      i = end + 1;
    } else if (char == '"' || char == "'") {
      quote = char;
      value.write(char);
    } else if (char == '(') {
      parentheses++;
      value.write(char);
    } else if (char == ')') {
      if (--parentheses < 0) throw const FormatException('Invalid SVG CSS');
      value.write(char);
    } else if (char == ';' && parentheses == 0) {
      declarations.add(value.toString());
      value.clear();
    } else {
      value.write(char);
    }
  }
  if (quote != null || parentheses != 0) {
    throw const FormatException('Unclosed SVG CSS value');
  }
  declarations.add(value.toString());
  final result = <String, String>{};
  final important = <String>{};
  final priority = RegExp(r'\s*!\s*important\s*$', caseSensitive: false);
  for (final declaration in declarations) {
    if (declaration.trim().isEmpty) continue;
    final colon = declaration.indexOf(':');
    if (colon < 0) throw const FormatException('Invalid SVG CSS declaration');
    final name = declaration.substring(0, colon).trim().toLowerCase();
    final raw = declaration.substring(colon + 1).trim();
    final isImportant = priority.hasMatch(raw);
    final property = raw.replaceFirst(priority, '').trim();
    // Reject unsafe patterns even when a later declaration would override them.
    if (name == 'stroke-dasharray' && property != 'none') {
      throw const FormatException('SVG dash patterns are not supported');
    }
    if (isImportant || !important.contains(name)) result[name] = property;
    if (isImportant) important.add(name);
  }
  return result;
}
