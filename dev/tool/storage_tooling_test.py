"""Fixtures for executable repointing, tracked scope and fail-closed checks."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from repoint_storage import rewrite, run
from storage_dart import members, tokens

ROWS = [
    dict(member='getApiKey',ref_kind='static',target='RealDebridStorage.getApiKey',
         file='lib/services/storage/real_debrid_storage.dart',step=2,kind='method',shared='no'),
    dict(member='appThemeCached',ref_kind='static',target='ThemeStorage.appThemeCached',
         file='lib/services/storage/theme_storage.dart',step=4,kind='field',shared='no'),
    dict(member='resetProfileCaches',ref_kind='static',target='resetStorageProfileCaches',
         file='lib/services/storage/storage_profile_caches.dart',step=1,kind='reset_entry',shared='no'),
    dict(member='TvRenderQuality',ref_kind='type',target='TvRenderQuality',
         file='lib/models/tv_render_quality.dart',step=1,kind='enum',shared='no'),
]


class RepointFixtures(unittest.TestCase):
    def test_calls_tearoffs_assignments_types_and_imports(self):
        for suffix,prefix in [('', ''),(' show StorageService', ''),(' as old', 'old.'),
                              (' hide ApiKeyValidator','')]:
            source = f"import 'package:debrify/services/storage_service.dart'{suffix};\n"+f'''
void f() {{
  {prefix}StorageService.appThemeCached = 'legacy';
  final action = {prefix}StorageService.resetProfileCaches;
  {prefix}StorageService.getApiKey();
  final quality = {prefix}TvRenderQuality.auto;
}}
'''
            new = rewrite(source,'tool/probe.dart',ROWS,4)
            self.assertIn("ThemeStorage.appThemeCached = 'legacy'",new)
            self.assertIn('final action = resetStorageProfileCaches;',new)
            self.assertIn('RealDebridStorage.getApiKey()',new)
            self.assertIn('TvRenderQuality.auto',new)
            self.assertNotIn('storage_service.dart',new)
            self.assertEqual(new,rewrite(new,'tool/probe.dart',ROWS,4))
    def test_unmoved_calls_keep_legacy_import(self):
        source = "import 'package:debrify/services/storage_service.dart' show StorageService;\nvoid f() { StorageService.getApiKey(); StorageService.appThemeCached = 'x'; }"
        new = rewrite(source,'test/probe.dart',ROWS,2)
        self.assertIn('storage_service.dart',new)
        self.assertIn('StorageService.appThemeCached',new)
        self.assertNotIn('theme_storage.dart',new)
    def test_interpolation_nested_strings_raw_text_and_comments(self):
        source = '''import 'package:debrify/services/storage_service.dart';
void f() {
  final a = '${StorageService.getApiKey()}';
  final b = "${'nested ${StorageService.getApiKey()} text'}";
  final c = 'StorageService.getApiKey()';
  final d = r'${StorageService.getApiKey()}';
  // StorageService.getApiKey()
  /* StorageService.getApiKey() */
}
'''
        new = rewrite(source,'dev/perf/probe.dart',ROWS,2)
        self.assertIn("'${RealDebridStorage.getApiKey()}'",new)
        self.assertIn("nested ${RealDebridStorage.getApiKey()} text",new)
        self.assertIn("'StorageService.getApiKey()'",new)
        self.assertIn("r'${StorageService.getApiKey()}'",new)
        self.assertIn('// StorageService.getApiKey()',new)
        self.assertIn('/* StorageService.getApiKey() */',new)
    def test_string_only_reference_does_not_add_import(self):
        source = "void f() { final reason = 'StorageService.getApiKey'; }"
        self.assertEqual(source,rewrite(source,'test/guard.dart',ROWS,2))
    def test_reexported_home_type_gets_direct_import(self):
        source = "import 'package:debrify/services/storage_service.dart' as old;\nvoid f(old.HomeExtraRow row) { old.StorageService.getApiKey(); }"
        new = rewrite(source,'test/probe.dart',ROWS,2)
        self.assertIn('models/home_preferences.dart',new)
        self.assertIn('void f(HomeExtraRow row)',new)
        self.assertNotIn('storage_service.dart',new)
    def test_tracked_reset_entry_point_survives_two_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = root / 'lib/services/storage/storage_profile_caches.dart'
            entry.parent.mkdir(parents=True)
            forwarding = "import '../storage_service.dart';\nvoid resetStorageProfileCaches() { StorageService.resetProfileCaches(); }\n"
            entry.write_text(forwarding)
            external = root / 'tool/probe.dart'
            external.parent.mkdir()
            external.write_text("import 'package:debrify/services/storage_service.dart';\nvoid f() { StorageService.resetProfileCaches(); }\n")
            untracked = root/'tool/untracked.dart'
            untracked.write_text(external.read_text())
            subprocess.run(['git','init','-q'],cwd=root,check=True)
            subprocess.run(['git','add',str(entry),str(external)],cwd=root,check=True)
            self.assertEqual(['tool/probe.dart'],run(root,ROWS,1))
            self.assertEqual([],run(root,ROWS,1))
            self.assertEqual(forwarding,entry.read_text())
            self.assertIn('resetStorageProfileCaches()',external.read_text())
            self.assertIn('StorageService.resetProfileCaches()',untracked.read_text())
    def test_unsupported_import_fails_loudly(self):
        with self.assertRaises(ValueError):
            rewrite("import 'storage_service.dart' deferred as old;",'lib/x.dart',ROWS,2)
    def test_declarations_cover_record_types_arrow_methods_and_annotations(self):
        source = '''class StorageService {
  static const inferred = {'key'};
  static Future<Map<String, ({int x, int y})>> _iptvResumeStates() async { return {}; }
  @visibleForTesting
  static bool helper({bool option = false}) => option;
  static int get cached => 1;
  static Set<String> recordKeys() => {'one', 'two'};
}'''
        found = members(source)
        self.assertEqual(['inferred','_iptvResumeStates','helper','cached','recordKeys'],[m.name for m in found])
        self.assertEqual(['const','method','method','getter','method'],[m.kind for m in found])
        self.assertIn('@visibleForTesting',found[2].declaration)
        self.assertTrue(found[4].declaration.endswith('};'))
    def test_literal_whitespace_is_preserved(self):
        source = '''"${'x  ${StorageService.getApiKey()}  y'}"'''
        literals = [t.text for t in tokens(source) if t.kind=='literal']
        self.assertIn("'x  ${",literals)
        self.assertIn("}  y'",literals)


if __name__ == '__main__':
    unittest.main()
