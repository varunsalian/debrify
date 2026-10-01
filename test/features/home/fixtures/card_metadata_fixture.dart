import 'package:debrify/core/metadata/metadata_presentation_cache.dart';
import 'package:debrify/features/home/application/home_card_metadata_controller.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_card_metadata_repository.dart';
import 'package:debrify/features/home/models/home_card_metadata.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const cardSource = StremioMeta(
  id: 'card',
  type: 'movie',
  name: 'Catalog',
  poster: 'catalog-art',
  background: 'catalog-backdrop',
);
const approvedCard = StremioMeta(
  id: 'card',
  type: 'movie',
  name: 'Approved',
  poster: 'approved-art',
);

class CardMetadataFake {
  CardMetadataFake({MetadataPresentationCache? cache})
    : cache = cache ?? MetadataPresentationCache();
  final MetadataPresentationCache cache;
  bool current = true;
  int preferenceReads = 0;
  final requests = <({StremioMeta item, bool Function() relevant})>[];
  final diagnostics = <HomeCardMetadataDiagnostic>[];
  Future<MetadataPreferences> Function() preferences = () async =>
      MetadataPreferences(
        providers: {MetadataCategory.posters: 'tmdb'},
        fallback: false,
      );
  Future<MetadataPresentation> Function(StremioMeta) respond = (_) async =>
      const MetadataPresentation(approvedCard);

  HomeCardMetadataRepository repository(HomeCardMetadataEpoch epoch) =>
      HomeCardMetadataRepository(
        epoch: epoch,
        cache: cache,
        isCurrent: () => current,
        readPreferences: () {
          preferenceReads++;
          return preferences();
        },
        present: (item, preferences, relevant) {
          requests.add((item: item, relevant: relevant));
          return respond(item);
        },
        recordReady: diagnostics.add,
      );
}

class CardMetadataHarness {
  CardMetadataHarness({CardMetadataFake? data, HomeCardMetadataState? initial})
    : data = data ?? CardMetadataFake() {
    session = HomeCardMetadataSession(
      epoch: (owner: ProfileSessionMemory.captureOwner(), revision: 0),
      viewIdentity: Object(),
      generation: 0,
      initial: initial ?? const HomeCardMetadataState(original: cardSource),
    );
    container = ProviderContainer(
      overrides: [
        homeCardMetadataRepositoryProvider.overrideWith(
          (ref, epoch) => this.data.repository(epoch),
        ),
      ],
    );
    subscription = container.listen(
      homeCardMetadataProvider(session),
      (_, _) {},
    );
    controller = container.read(homeCardMetadataProvider(session).notifier);
  }
  final CardMetadataFake data;
  late final HomeCardMetadataSession session;
  late final ProviderContainer container;
  late final ProviderSubscription<HomeCardMetadataState> subscription;
  late final HomeCardMetadataController controller;
  HomeCardMetadataState get state => subscription.read();
  Future<void> load() => controller.load(isCurrent: () => true);
  void dispose() {
    subscription.close();
    container.dispose();
  }
}
