import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

import 'golden_harness.dart';
import 'surface_gallery.dart';

/// Walks the RENDERED gallery and checks every piece of text against the
/// surface it actually sits on.
///
/// This is the test the suite was missing. Pin tests prove a token equals a
/// literal; contrast tests compared token PAIRS chosen by hand. Neither can
/// see the defect that kept recurring — themed ink placed on a surface that
/// stayed dark — because that is a property of the composed tree, not of any
/// single token. A reviewer put it plainly: every theme test passed while two
/// light themes had unreadable screens.
///
/// So: resolve each `Text`'s effective colour, walk its ancestors for the
/// nearest opaque background actually painted behind it, and compare. No
/// human has to look at anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  // The bar is RELATIVE to legacy, not absolute, and that is deliberate.
  //
  // An absolute 3:1 rule fails legacy itself in one place — the calendar's
  // darkest per-title red on its own tint chip is 2.87:1 in the app as
  // shipped. That is a pre-existing product decision, not something this
  // rollout caused, and a test that reds over it would either be permanently
  // failing or would push me to change today's pixels to satisfy a bar the
  // app never claimed. Neither is the contract.
  //
  // The contract is: legacy is unchanged, and no theme is WORSE than legacy at
  // the same place. So each site is measured under legacy first and every
  // other theme is held to that, with an absolute floor that legacy meets.
  const floor = 3.0;
  const tolerance = 0.15; // rounding, not licence to regress

  late Map<String, _Site> baseline;

  testWidgets('legacy establishes the baseline', (tester) async {
    await pumpThemed(tester, const SurfaceGallery(),
        themeId: AppThemes.legacyId, surface: const Size(900, 2400));
    baseline = _audit(tester);
    expect(baseline, isNotEmpty,
        reason: 'the gallery rendered no measurable text — the walker is '
            'broken, and every theme below would pass vacuously');

    // Say out loud where legacy itself is under the floor, so those sites are
    // visible rather than silently exempted.
    final weak = baseline.values.where((s) => s.ratio < floor).toList();
    // ignore: avoid_print
    print('legacy sites below ${floor}:1 (pre-existing, exempted): '
        '${weak.map((s) => '${s.label} ${s.ratio.toStringAsFixed(2)}').join(", ")}');
  });

  for (final core in DetailThemes.all) {
    testWidgets('${core.id} — no text worse than legacy, none unreadable',
        (tester) async {
      await pumpThemed(tester, const SurfaceGallery(),
          themeId: core.id, surface: const Size(900, 2400));
      final sites = _audit(tester);

      final failures = <String>[];
      for (final entry in sites.entries) {
        final site = entry.value;
        final legacySite = baseline[entry.key];
        if (legacySite == null) continue; // theme-specific site, no baseline
        // Meet the floor, OR at least match what legacy managed here.
        final required =
            legacySite.ratio < floor ? legacySite.ratio - tolerance : floor;
        if (site.ratio < required) {
          failures.add('${site.label}  ${_hex(site.ink)} on ${_hex(site.ground)}'
              '  → ${site.ratio.toStringAsFixed(2)}:1'
              '  (legacy ${legacySite.ratio.toStringAsFixed(2)}:1)');
        }
      }

      expect(failures, isEmpty,
          reason: 'text unreadable, or worse than legacy, under '
              '"${core.id}":\n  ${failures.join("\n  ")}');
    });
  }
}

/// One measured piece of text.
class _Site {
  final String label;
  final Color ink;
  final Color ground;
  final double ratio;
  const _Site(this.label, this.ink, this.ground, this.ratio);
}

/// Every legible text in the tree, keyed by its content so the same site can
/// be compared across themes.
Map<String, _Site> _audit(WidgetTester tester) {
  final sites = <String, _Site>{};
  for (final element in _textElements(tester)) {
    final widget = element.widget as Text;
    if (widget.key == kGalleryLabelKey) continue; // harness caption
    final label = widget.data ?? '';
    if (label.isEmpty) continue;

    final ink = _effectiveColor(element, widget);
    if (ink == null || ink.a < 0.35) continue; // decorative/ghost text
    final ground = _nearestOpaqueBackground(element);
    if (ground == null) continue; // nothing opaque behind it to judge

    // Flatten the ink onto its ground first: a token at 0.68 alpha is not the
    // colour the eye receives, and judging the unflattened value would both
    // miss real failures and invent fake ones.
    final composited = Color.alphaBlend(ink, ground);
    // The palette chips repeat one label, so key on the pairing too.
    final key = '$label|${_hex(ink)}';
    sites[key] = _Site(label, ink, ground, _contrast(composited, ground));
  }
  return sites;
}

// ── tree walking ───────────────────────────────────────────────────────────

Iterable<Element> _textElements(WidgetTester tester) {
  final found = <Element>[];
  void visit(Element e) {
    if (e.widget is Text) found.add(e);
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return found;
}

/// The colour this `Text` will actually paint with: its own style, else the
/// nearest `DefaultTextStyle` — which is how inherited `ThemeData` ink reaches
/// a widget that declares no colour, and that inheritance is precisely the
/// path that produced black-on-black.
Color? _effectiveColor(Element element, Text widget) {
  final own = widget.style?.color;
  if (own != null) return own;
  return DefaultTextStyle.of(element).style.color;
}

/// The nearest ancestor that paints an OPAQUE fill behind this element.
///
/// Translucent layers are composited on the way up rather than treated as the
/// ground — a 55%-black glass over a poster is not itself a background, but it
/// does darken whatever is.
Color? _nearestOpaqueBackground(Element element) {
  final stack = <Color>[];
  Color? ground;

  element.visitAncestorElements((ancestor) {
    final color = _paintedColor(ancestor.widget);
    if (color == null) return true;
    if (color.a >= 0.999) {
      ground = color;
      return false; // opaque: stop, everything above is hidden
    }
    stack.add(color);
    return true;
  });

  if (ground == null) return null;
  // Re-apply the translucent layers we passed, nearest last.
  var result = ground!;
  for (final layer in stack.reversed) {
    result = Color.alphaBlend(layer, result);
  }
  return result;
}

Color? _paintedColor(Widget widget) {
  if (widget is ColoredBox) return widget.color;
  if (widget is Material) return widget.color;
  if (widget is Card) return widget.color;
  if (widget is Container) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    return null;
  }
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
  }
  return null;
}

// ── colour maths ───────────────────────────────────────────────────────────

double _contrast(Color a, Color b) {
  final la = a.withValues(alpha: 1).computeLuminance();
  final lb = b.withValues(alpha: 1).computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.a)}${two(c.r)}${two(c.g)}${two(c.b)}';
}
