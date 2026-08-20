import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/tvos_top_shelf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Top Shelf personalization authority', () {
    test('allows only an Admin with profile-management permission', () {
      expect(
        TvosTopShelfService.canManageMultiProfilePersonalization(
          _profile(UserProfileRole.admin),
        ),
        isTrue,
      );
      expect(
        TvosTopShelfService.canManageMultiProfilePersonalization(
          _profile(UserProfileRole.member),
        ),
        isFalse,
      );
      expect(
        TvosTopShelfService.canManageMultiProfilePersonalization(
          _profile(UserProfileRole.child),
        ),
        isFalse,
      );
      expect(
        TvosTopShelfService.canManageMultiProfilePersonalization(
          _profile(
            UserProfileRole.admin,
            policy: const ProfilePolicy(enabled: <ProfileFeature>{}),
          ),
        ),
        isFalse,
      );
      expect(
        TvosTopShelfService.canManageMultiProfilePersonalization(null),
        isFalse,
      );
    });
  });

  group('TvosTopShelfService.buildSnapshot', () {
    test('exports Spotlight metadata and derives missing wide artwork', () {
      const meta = StremioMeta(
        id: 'catalog:one',
        imdbId: 'tt1234567',
        type: 'movie',
        name: '  The Feature  ',
        poster: 'https://example.com/poster.jpg',
        description: '  A useful summary.  ',
        year: '2026',
        imdbRating: 8.25,
        genres: ['Drama', 'Science Fiction', ''],
        runtime: '2h 7m',
      );

      final snapshot = TvosTopShelfService.buildSnapshot(const [
        meta,
      ], sourceTitle: 'Cinemeta: Popular');
      final item = (snapshot['items'] as List).single as Map<String, dynamic>;

      expect(snapshot['version'], 1);
      expect(snapshot['contextTitle'], 'Spotlight · Cinemeta: Popular');
      expect(item, containsPair('identifier', 'movie:tt1234567'));
      expect(item, containsPair('title', 'The Feature'));
      expect(
        item['imageURL'],
        'https://images.metahub.space/background/medium/tt1234567/img.jpg',
      );
      expect(item['runtimeMinutes'], 127);
      expect(item['genres'], ['Drama', 'Science Fiction']);
      expect(item['summary'], 'A useful summary.');
    });

    test('filters unsupported ids, removes duplicates, and caps the reel', () {
      final metas = <StremioMeta>[
        const StremioMeta(
          id: 'tmdb:1',
          type: 'movie',
          name: 'No IMDb identity',
          poster: 'https://example.com/no.jpg',
        ),
        for (var i = 1; i <= 10; i++)
          StremioMeta(
            id: 'tt${i.toString().padLeft(7, '0')}',
            imdbId: 'tt${i.toString().padLeft(7, '0')}',
            type: i.isEven ? 'movie' : 'series',
            name: 'Title $i',
          ),
        const StremioMeta(
          id: 'duplicate',
          imdbId: 'tt0000001',
          type: 'series',
          name: 'Duplicate',
        ),
      ];

      final snapshot = TvosTopShelfService.buildSnapshot(metas);
      final items = snapshot['items'] as List;

      expect(items, hasLength(8));
      expect(
        items.map((item) => (item as Map<String, dynamic>)['imdbId']).toSet(),
        hasLength(8),
      );
      expect(snapshot['contextTitle'], 'Spotlight on Debrify');
    });
  });

  group('Top Shelf local previews', () {
    test(
      'adds a validated shared-container MP4 without mutating the source',
      () {
        final source = <String, dynamic>{
          'version': 1,
          'contextTitle': 'Spotlight on Debrify',
          'items': [
            <String, dynamic>{'imdbId': 'tt1234567', 'title': 'One'},
            <String, dynamic>{'imdbId': 'tt7654321', 'title': 'Two'},
          ],
        };
        const path =
            'Library/Caches/TopShelfPreviews/tt1234567-abc123-audio.mp4';

        final updated = TvosTopShelfService.withPreviewFile(
          source,
          'tt1234567',
          path,
        );

        expect(((updated['items'] as List).first as Map)['previewFile'], path);
        expect(((updated['items'] as List).last as Map)['previewFile'], isNull);
        expect(((source['items'] as List).first as Map)['previewFile'], isNull);
      },
    );

    test(
      'rejects traversal, remote URLs, and files outside the preview cache',
      () {
        expect(
          TvosTopShelfService.isValidPreviewPath(
            'Library/Caches/TopShelfPreviews/tt1234567-audio.mp4',
          ),
          isTrue,
        );
        expect(
          TvosTopShelfService.isValidPreviewPath(
            'Library/Caches/TopShelfPreviews/../secret.mp4',
          ),
          isFalse,
        );
        expect(
          TvosTopShelfService.isValidPreviewPath('https://example.com/a.mp4'),
          isFalse,
        );
        expect(
          TvosTopShelfService.isValidPreviewPath(
            'Library/Caches/not-top-shelf.mp4',
          ),
          isFalse,
        );
      },
    );
  });

  group('Top Shelf detail handoff', () {
    test('opens directly when the mounted Home board is active', () async {
      Map<String, dynamic>? received;
      Future<void> handler(Map<String, dynamic> data) async {
        received = data;
      }

      MainPageBridge.setActiveTvTab(15);
      MainPageBridge.registerCatalogDetailOpenHandler(handler);
      MainPageBridge.requestCatalogDetailOpen(const {'imdbId': 'tt1234567'});
      await Future<void>.delayed(Duration.zero);

      expect(received, {'imdbId': 'tt1234567'});
      expect(MainPageBridge.pendingCatalogDetailOpen, isNull);
      MainPageBridge.unregisterCatalogDetailOpenHandler(handler);
      MainPageBridge.setActiveTvTab(0);
    });

    test('queues the request and switches to Home from another tab', () {
      int? switchedTo;
      MainPageBridge.setActiveTvTab(17);
      MainPageBridge.switchTab = (index) => switchedTo = index;

      MainPageBridge.requestCatalogDetailOpen(const {'imdbId': 'tt7654321'});

      expect(switchedTo, 15);
      expect(MainPageBridge.pendingCatalogDetailOpen?['imdbId'], 'tt7654321');
      MainPageBridge.pendingCatalogDetailOpen = null;
      MainPageBridge.switchTab = null;
      MainPageBridge.setActiveTvTab(0);
    });
  });
}

UserProfile _profile(UserProfileRole role, {ProfilePolicy? policy}) {
  final now = DateTime.utc(2026, 8, 20);
  return UserProfile(
    id: role.name,
    name: role.name,
    role: role,
    policy: policy ?? ProfilePolicy.defaultsFor(role),
    authorizationRevision: 1,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: false,
    hasPin: false,
    lockOnResume: false,
    createdAt: now,
    updatedAt: now,
  );
}
