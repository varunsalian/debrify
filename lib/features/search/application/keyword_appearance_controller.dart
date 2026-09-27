import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/source_appearance.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/search_session.dart';
import 'keyword_appearance_dependencies.dart';
import 'search_session_provider.dart';

final keywordAppearanceProvider = NotifierProvider.autoDispose
    .family<KeywordAppearanceController, SourceAppearance, SearchSession>(
      KeywordAppearanceController.new,
      retry: (count, error) => null,
      dependencies: [
        keywordAppearanceReaderProvider,
        searchSessionActiveProvider,
      ],
    );

class KeywordAppearanceController extends Notifier<SourceAppearance> {
  KeywordAppearanceController(this.session);
  final SearchSession session;
  late SourceAppearanceReader _read;
  SourceAppearance? _accepted;
  int _generation = 0;

  @override
  SourceAppearance build() {
    _read = ref.watch(keywordAppearanceReaderProvider(session));
    final active = ref.watch(searchSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    if (!active) _accepted = null;
    return _accepted ?? initialSourceAppearance;
  }

  Future<void> load({
    required bool Function() isCurrent,
    required void Function() onAccepted,
  }) async {
    bool active() =>
        ref.mounted &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!active()) return;
    final generation = ++_generation;
    final appearance = await _read();
    bool current() => active() && generation == _generation;
    if (!current()) return;
    _accepted = appearance;
    state = appearance;
    if (current()) onAccepted();
  }
}
