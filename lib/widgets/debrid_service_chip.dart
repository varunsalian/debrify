import 'package:flutter/material.dart';

import '../features/debrid/descriptor.dart';
import '../services/series_source_service.dart';
import '../theme/debrid_brand.dart';

/// Colour and name for the service a bound source is pinned to: a debrid
/// provider's brand, the on-device blue for a local binding, or a neutral chip
/// for anything unrecognised.
({Color color, String label}) debridServiceChip(String service) {
  final descriptor = DebridProviders.find(service);
  if (descriptor != null) {
    return (color: debridBrandFor(service).tile, label: descriptor.displayName);
  }
  if (service == SeriesSource.localService) {
    return (color: const Color(0xFF60A5FA), label: 'Local');
  }
  return (color: Colors.white54, label: service);
}
