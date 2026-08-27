import 'session.dart';
import '../../../services/storage_service.dart';

/// [PikPakSession] over the app's existing credential storage.
///
/// Recovery is injected rather than reached for: [PikPakApi] needs a token
/// refresh and a logout, both of which live on `PikPakApiService`, and taking
/// the service directly would close a cycle (service → api → session →
/// service). Tear-offs break it.
class StoragePikPakSession implements PikPakSession {
  final Future<bool> Function() _onRefresh;
  final Future<void> Function() _onExpire;

  const StoragePikPakSession({
    required Future<bool> Function() onRefresh,
    required Future<void> Function() onExpire,
  }) : _onRefresh = onRefresh,
       _onExpire = onExpire;

  @override
  Future<String?> accessToken() => StorageService.getPikPakAccessToken();

  @override
  Future<String?> deviceId() => StorageService.getPikPakDeviceId();

  @override
  Future<String?> captchaToken() => StorageService.getPikPakCaptchaToken();

  @override
  Future<bool> refresh() => _onRefresh();

  @override
  Future<void> invalidateCaptcha() => StorageService.clearPikPakCaptchaToken();

  @override
  Future<void> expire() => _onExpire();
}
