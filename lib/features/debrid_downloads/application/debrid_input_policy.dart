bool isValidMagnetLink(String link) {
  final trimmedLink = link.trim();
  if (!trimmedLink.startsWith('magnet:?')) {
    return false;
  }

  // Check for required magnet link components
  if (!trimmedLink.contains('xt=urn:btih:')) {
    return false;
  }

  // Basic length check (magnet links are typically longer than 50 characters)
  if (trimmedLink.length < 50) {
    return false;
  }

  return true;
}

bool isValidLink(String link) {
  final trimmedLink = link.trim();
  return trimmedLink.startsWith('http://') ||
      trimmedLink.startsWith('https://');
}
