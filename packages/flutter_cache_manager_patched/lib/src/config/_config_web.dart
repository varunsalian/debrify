import 'package:flutter_cache_manager/src/config/config.dart' as def;
import 'package:flutter_cache_manager/src/storage/cache_info_repositories/cache_info_repository.dart';
import 'package:flutter_cache_manager/src/storage/cache_info_repositories/non_storing_object_provider.dart';
import 'package:flutter_cache_manager/src/storage/file_system/file_system.dart';
import 'package:flutter_cache_manager/src/web/file_service.dart';

class Config implements def.Config {
  Config(
    this.cacheKey, {
    Duration? stalePeriod,
    int? maxNrOfCacheObjects,
    int? maxCacheSizeBytes,
    CacheInfoRepository? repo,
    FileSystem? fileSystem,
    FileService? fileService,
  })  : stalePeriod = stalePeriod ?? const Duration(days: 30),
        maxNrOfCacheObjects = maxNrOfCacheObjects ?? 200,
        maxCacheSizeBytes = maxCacheSizeBytes ?? 64 * 1024 * 1024,
        repo = repo ?? NonStoringObjectProvider(),
        fileSystem = fileSystem ?? MemoryCacheSystem(),
        fileService = fileService ?? HttpFileService();

  @override
  final CacheInfoRepository repo;

  @override
  final FileSystem fileSystem;

  @override
  final String cacheKey;

  @override
  final Duration stalePeriod;

  @override
  final int maxNrOfCacheObjects;

  @override
  final int maxCacheSizeBytes;

  @override
  final FileService fileService;
}
