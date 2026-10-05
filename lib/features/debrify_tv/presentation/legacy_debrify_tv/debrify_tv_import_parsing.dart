import 'dart:async';

import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:flutter/foundation.dart';

Future<DebrifyTvZipImportResult> parseZipInBackground(Uint8List bytes) {
  return compute(_parseZipCompute, bytes);
}

DebrifyTvZipImportResult _parseZipCompute(Uint8List bytes) {
  return DebrifyTvZipImporter.parseZip(bytes);
}

Future<DebrifyTvZipImportedChannel> parseYamlInBackground(
  String sourceName,
  String content,
) {
  return compute(_parseYamlCompute, <String, String>{
    'sourceName': sourceName,
    'content': content,
  });
}

DebrifyTvZipImportedChannel _parseYamlCompute(Map<String, String> payload) {
  final sourceName = payload['sourceName'] ?? 'channel.yaml';
  final content = payload['content'] ?? '';
  return DebrifyTvZipImporter.parseYaml(
    sourceName: sourceName,
    content: content,
  );
}
