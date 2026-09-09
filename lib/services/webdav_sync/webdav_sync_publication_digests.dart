import 'dart:isolate';

import '../transfer/transfer_io.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_library_models.dart';

typedef PublicationProfile = ({
  WebDavSyncHotDocument hot,
  WebDavSyncLibraryDocument? library,
  Map<String, WebDavSyncTombstone> tombstones,
});
typedef PublicationProfileDigests = ({
  String hot,
  String? library,
  WebDavSyncTombstoneDocument tombstones,
  String tombstoneDigest,
});
typedef PublicationDigests = ({
  Map<String, PublicationProfileDigests> profiles,
  String? profileDefinitions,
  String? resources,
});

/// Change detection is CPU work too, even when nothing needs publishing.
/// Construct and hash the payloads in the worker, not before entering it.
Future<PublicationDigests> preparePublicationDigests({
  required Map<String, PublicationProfile> profiles,
  required int serverNowMs,
  WebDavSyncProfilesDocument? profileDefinitions,
  WebDavSyncResourcesDocument? resources,
}) => TransferIo.largeWorker.synchronized(
  () => Isolate.run(() {
    final result = <String, PublicationProfileDigests>{};
    for (final entry in profiles.entries) {
      final tombstones = WebDavSyncTombstoneDocument(
        circleProfileId: entry.key,
        items: Map<String, WebDavSyncTombstone>.unmodifiable({
          for (final t in entry.value.tombstones.entries)
            t.key: t.value.copyWith(
              firstPublishedAtMs: t.value.firstPublishedAtMs ?? serverNowMs,
              rawLocalTime: false,
            ),
        }),
      );
      result[entry.key] = (
        hot: entry.value.hot.semanticDigest,
        library: entry.value.library?.semanticDigest,
        tombstones: tombstones,
        tombstoneDigest: tombstones.semanticDigest,
      );
    }
    return (
      profiles: result,
      profileDefinitions: profileDefinitions?.semanticDigest,
      resources: resources?.semanticDigest,
    );
  }),
);

Future<String> libraryPublicationDigest(WebDavSyncLibraryDocument document) =>
    TransferIo.largeWorker.synchronized(
      () => Isolate.run(() => document.semanticDigest),
    );
