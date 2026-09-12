import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveIptvSpotlightLayout', () {
    test('uses the wide layout at standard TV logical sizes', () {
      expect(
        resolveIptvSpotlightLayout(const Size(896, 540)),
        IptvSpotlightLayoutMode.wide,
      );
      expect(
        resolveIptvSpotlightLayout(const Size(960, 540)),
        IptvSpotlightLayoutMode.wide,
      );
    });

    test('uses compact at its inclusive width and height boundary', () {
      expect(
        resolveIptvSpotlightLayout(const Size(760, 480)),
        IptvSpotlightLayoutMode.compact,
      );
      expect(
        resolveIptvSpotlightLayout(const Size(859, 540)),
        IptvSpotlightLayoutMode.compact,
      );
    });

    test('uses classic below either compact boundary', () {
      expect(
        resolveIptvSpotlightLayout(const Size(759, 540)),
        IptvSpotlightLayoutMode.classic,
      );
      expect(
        resolveIptvSpotlightLayout(const Size(960, 479)),
        IptvSpotlightLayoutMode.classic,
      );
    });
  });
}
