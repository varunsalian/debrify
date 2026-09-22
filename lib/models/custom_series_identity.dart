import 'dart:convert';

/// Local content identity for an addon's independently numbered series.
/// Hex keeps existing case-insensitive persistence keys lossless. No URLs or
/// credentials are stored: addonKey is the existing configuration fingerprint.
class CustomSeriesIdentity {
  static const prefix = 'custom-series:';
  final String addonKey;
  final String catalogId;

  const CustomSeriesIdentity(this.addonKey, this.catalogId);

  String get id =>
      prefix +
      utf8
          .encode(jsonEncode([addonKey, catalogId]))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  static bool isCustom(String? id) => id?.startsWith(prefix) == true;

  static String? resumeBookmarkKey(String? id, int? season, int? episode) =>
      isCustom(id) ? '$id:S$season:E$episode' : null;

  // Scoped source keys contain a reversible identity, not just an IMDb ID.
  // Keep the normal preference limit; permit only validated scoped pin keys
  // a bounded larger size so backup/sync do not silently drop them.
  static bool isPortableSourceKey(String key) =>
      key.length <= 8192 && key.startsWith('series_source_$prefix') &&
      parse(key.substring('series_source_'.length)) != null;

  static CustomSeriesIdentity? parse(String? id) {
    if (!isCustom(id)) return null;
    try {
      final hex = id!.substring(prefix.length);
      final bytes = [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      final values = jsonDecode(utf8.decode(bytes));
      if (values is! List ||
          values.length != 2 ||
          values.any((v) => v is! String || v.isEmpty))
        return null;
      return CustomSeriesIdentity(values[0] as String, values[1] as String);
    } catch (_) {
      return null;
    }
  }
}
