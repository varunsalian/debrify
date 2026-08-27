import 'session.dart';
import '../../../services/storage_service.dart';

/// [PikPakSession] over the app's existing credential storage.
///
/// Recovery is injected rather than reached for: [PikPakApi] needs a token
/// refresh, which lives on `PikPakApiService`, and taking the service directly
/// would close a cycle (service → api → session → service). A tear-off breaks
/// it.
class StoragePikPakSession implements PikPakSession {
  final Future<bool> Function() _onRefresh;

  const StoragePikPakSession({required Future<bool> Function() onRefresh})
    : _onRefresh = onRefresh;

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
}
