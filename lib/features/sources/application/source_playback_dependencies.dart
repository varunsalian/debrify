import '../data/source_download.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/automatic_source_bindings.dart';

final automaticSourceBindingsFactoryProvider =
    Provider<AutomaticSourceBindings Function()>(
      (ref) => AutomaticSourceBindings.capture,
    );

final sourceDownloadProvider = Provider<SourceDownload>(
  (ref) => const SourceDownload(),
);
