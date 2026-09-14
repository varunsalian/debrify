import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'remote_reliable_transfer.dart';

/// Only small command metadata is JSON on the wire. Bulk profile databases
/// use the file-backed archive format instead of expanding SQLite to base64.
class RemoteTransferEncoding {
  static const maxCommandBytes = 128 * 1024 * 1024;

  static Future<void> writeCommand(File file, Map<String, dynamic> command) =>
      Isolate.run(() async {
        final sink = file.openWrite();
        try {
          final encoded = jsonEncode(command);
          await sink.addStream(
            Stream<String>.value(
              encoded,
            ).transform(utf8.encoder).transform(gzip.encoder),
          );
        } finally {
          await sink.close();
        }
      });

  static Future<Map<String, dynamic>> readCommand(File file) =>
      Isolate.run(() async {
        var length = 0;
        final text = await file
            .openRead()
            .transform(gzip.decoder)
            .map((bytes) {
              length += bytes.length;
              if (length > maxCommandBytes) {
                throw const RemoteTransferException(
                  'Command exceeds supported size',
                );
              }
              return bytes;
            })
            .transform(utf8.decoder)
            .join();
        return jsonDecode(text) as Map<String, dynamic>;
      });
}
