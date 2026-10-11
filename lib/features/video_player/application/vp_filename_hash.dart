/// Generate a stable hash from filename for non-series playlist state tracking
String vpFilenameHash(String filename) {
  // Remove file extension and normalize
  final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
  // Create a simple hash (we could use a proper hash function, but this is sufficient for our needs)
  final hash = nameWithoutExt.hashCode.toString();
  return hash;
}
