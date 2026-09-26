import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/keyword_sources_repository.dart';
import '../models/keyword_source.dart';
import '../models/search_session.dart';
import 'keyword_sources_dependencies.dart';
import 'search_session_provider.dart';

/// Null means the original loading presentation; an empty list means no engines.
final keywordSourcesProvider = NotifierProvider.autoDispose
    .family<KeywordSourcesController, List<KeywordSource>?, SearchSession>(
      KeywordSourcesController.new,
      retry: (count, error) => null,
    );

class KeywordSourcesController extends Notifier<List<KeywordSource>?> {
  KeywordSourcesController(this.session);
  final SearchSession session;
  late KeywordSourcesRepository _repository;
  int _generation = 0;

  @override
  List<KeywordSource>? build() {
    _repository = ref.watch(keywordSourcesRepositoryProvider(session));
    ref.watch(searchSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    return null;
  }

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final sources = await _repository.load();
      if (!ref.mounted || generation != _generation || !_repository.isCurrent) {
        return;
      }
      state = List.unmodifiable(sources);
    } catch (_) {
      debugPrint('Keyword search sources could not be loaded.');
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final sources = state;
    if (sources == null || !_repository.isCurrent) return;
    state = List.unmodifiable([
      for (final source in sources)
        source.id == id ? source.withEnabled(enabled) : source,
    ]);
    await _save(id, enabled);
  }

  Future<void> setAll(bool enabled) async {
    final sources = state;
    if (sources == null || !_repository.isCurrent) return;
    state = List.unmodifiable(
      sources.map((source) => source.withEnabled(enabled)),
    );
    // Start each immediate write in registry order, as the old dialog did.
    await Future.wait([
      for (final source in sources) _save(source.id, enabled),
    ]);
  }

  Future<void> _save(String id, bool enabled) async {
    try {
      await _repository.setEnabled(id, enabled);
    } catch (_) {
      debugPrint('Keyword search source settings could not be saved.');
    }
  }
}
