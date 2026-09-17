import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);
  test('player ignores stored MDBList history without credentials', () async {
    await StorageService.saveEpisodeMdblistProgress(
      imdbId: 'tt001',
      percents: {'1_1': 80},
    );
    expect(await StorageService.getEpisodeMdblistProgress(imdbId: 'tt001'), {
      '1_1': 80.0,
    });
    expect(
      await StorageService.getConnectedEpisodeMdblistProgress(imdbId: 'tt001'),
      isEmpty,
    );
  });
  test('connected player can read cached MDBList progress', () async {
    SharedPreferences.setMockInitialValues({'mdblist_api_key': 'test-key'});
    await StorageService.saveEpisodeMdblistProgress(
      imdbId: 'tt001',
      percents: {'1_1': 80},
    );
    expect(
      await StorageService.getConnectedEpisodeMdblistProgress(imdbId: 'tt001'),
      {'1_1': 80.0},
    );
  });
}
