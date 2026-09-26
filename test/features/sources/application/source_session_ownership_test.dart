import 'package:debrify/features/sources/application/source_session_ownership.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'captured ownership reader detects lifecycle clears without scope changes',
    () {
      ProfileSessionMemory.debugReset();
      addTearDown(ProfileSessionMemory.debugReset);
      final container = ProviderContainer();
      final ownership = container.read(sourceSessionOwnershipProvider);
      final owner = ownership.capture();
      final session = SourcesSession(
        owner: owner,
        viewIdentity: Object(),
        selection: const AdvancedSearchSelection(
          imdbId: 'tt123',
          title: 'Example',
          isSeries: false,
        ),
      );
      expect(ownership.isCurrent(session), isTrue);
      container.dispose();
      ProfileSessionMemory.clearAll();
      final next = ownership.capture();
      expect(next.scope, owner.scope);
      expect(next.runtimeMode, owner.runtimeMode);
      expect(next.lifecycleRevision, greaterThan(owner.lifecycleRevision));
      expect(ownership.isCurrent(session), isFalse);
      expect(
        ownership.isCurrent(
          SourcesSession(
            owner: next,
            viewIdentity: Object(),
            selection: session.selection,
          ),
        ),
        isTrue,
      );
    },
  );
}
