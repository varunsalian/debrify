final _rdBlockedPattern = RegExp(
  r'web-dl|webrip|bdrip|hdrip|dvdrip'
  r'|BluRay\.x264|HDTV\.x264|HDTV\.XviD|WEB\.x264|WEB\.h264',
  caseSensitive: false,
);

bool isRdBlockedTorrent(String name) {
  return _rdBlockedPattern.hasMatch(name);
}
