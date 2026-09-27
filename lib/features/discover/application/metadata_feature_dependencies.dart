import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/metadata_feature_policy.dart';

final metadataFeatureReaderProvider = Provider.autoDispose
    .family<MetadataFeatureReader, MetadataFeatureSession>(
      (ref, session) => () async {
        if (session.owner != ProfileSessionMemory.captureOwner()) {
          throw StateError('Metadata policy owner retired');
        }
        final scope = session.owner.scope;
        return scope == null
            ? MetadataPreferencesService.load()
            : ProfileRuntime.withCapturedScope(
                scope,
                MetadataPreferencesService.load,
              );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
