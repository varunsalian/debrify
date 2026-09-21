import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Keep the configuration key separate so sync can translate it per device.
String catalogSourceScope(String? catalogId, String? catalogKey) {
  if (catalogId == null || catalogId.trim().isEmpty) return '';
  return 'catalog:${catalogKey ?? ''}:${sha256.convert(utf8.encode(catalogId.trim()))}:';
}
