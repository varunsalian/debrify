import 'dart:io';

/// Copies [source] to [destination] in fixed chunks with an explicit flush.
///
/// `File.copy` does not fsync and, on some platforms, materializes the whole
/// file. Both handles are released on every exit path, including a failing
/// destination open, so a permission or disk-full error never leaks the
/// source descriptor (which on Windows would pin the file against deletion).
Future<void> copyFileStreamed(
  File source,
  File destination, {
  int chunkSize = 256 * 1024,
}) async {
  final input = await source.open();
  try {
    final output = await destination.open(mode: FileMode.write);
    try {
      while (true) {
        final chunk = await input.read(chunkSize);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
  } finally {
    await input.close();
  }
}
