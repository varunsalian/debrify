import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/saved_sources_repository.dart';
import '../data/stored_saved_sources_repository.dart';
import '../models/sources_session.dart';

final savedSourcesRepositoryProvider = Provider.autoDispose
    .family<SavedSourcesRepository, SourcesSession>(
      (ref, session) => StoredSavedSourcesRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );
