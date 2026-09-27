import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/source_appearance.dart';
import '../../../services/source_appearance_preferences.dart';
import '../models/search_session.dart';

final keywordAppearanceReaderProvider = Provider.autoDispose
    .family<SourceAppearanceReader, SearchSession>(
      (ref, session) =>
          () => readSourceAppearance(session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );
