

bool isValidMagnetLink(String link) {
  final trimmed = link.trim();
  if (!trimmed.startsWith('magnet:?')) return false;
  if (!trimmed.toLowerCase().contains('xt=urn:btih:')) return false;
  return trimmed.length >= 50;
}
