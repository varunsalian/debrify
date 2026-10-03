import 'package:debrify/services/iptv_catalog_db.dart';

class IptvLandingPolicy {
  /// Pure decision behind [_landingCategory], split out for tests.

  static String? landingCategoryFor({
    required String? orderKey,
    required List<String> categories,
    required bool manuallyChosen,
    required bool searching,
  }) {
    if (manuallyChosen || searching || orderKey == null || categories.isEmpty) {
      return null;
    }
    final stored = IptvCatalogDb.defaultCategory(orderKey);
    if (stored != null && categories.contains(stored)) return stored;
    return categories.first;
  }
}
