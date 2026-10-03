bool isValidPikPakLink(String link) {
  final trimmedLink = link.trim();
  return trimmedLink.startsWith('http://') ||
      trimmedLink.startsWith('https://') ||
      trimmedLink.startsWith('magnet:');
}
