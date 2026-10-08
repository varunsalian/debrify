"""Positive complete extraction + rule-2 negatives, exercising the actual PSI."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k

FIXTURES = k.ROOT / 'dev/tool/fixtures/kotlin_moves'


def extraction(manifest, original):
    """Materialize fixtures only: exact declared text edits, no production writes."""
    if manifest['phase'] >= 3:
        from kotlin_move_partition import extraction
        return extraction(manifest, original)
    unit = k.parse({'base': original})['base']
    spans, _ = k.spans(unit, set(manifest['split_containers']))
    destinations = {p: spec['prefix'] for p, spec in manifest['destinations'].items()}
    replacements = []
    for row in manifest['declarations']:
        if row['fate'] == 'retained':
            continue
        start, end = spans[row['original']]
        text = original[start:end]
        for edit in row.get('substitutions', []) + row.get('patches', []):
            if text.count(edit['before']) != edit['count']:
                raise ValueError('fixture text substitution occurrence count')
            text = text.replace(edit['before'], edit['after'])
        if row['fate'] == 'moved':
            destinations[row['destination']] += text
            replacements.append((start, end, ''))
        elif row['fate'] == 'patched':
            replacements.append((start, end, text))
        else:
            raise ValueError('fixture unknown fate: ' + row['fate'])
    for start, end, text in sorted(replacements, reverse=True):
        original = original[:start] + text + original[end:]
    return {manifest['source']: original, **{p: s + manifest['destinations'][p].get('tail', '\n') for p, s in destinations.items()}}


def fixture():
    original = (FIXTURES / 'original.kt').read_text()
    unit = k.parse({'base': original})['base']
    container = unit['declarations'][0]
    manifest = dict(base='fixture', phase=1, source='Activity.kt', split_containers=[container['id']],
                    destinations={'Model.kt': {'prefix': 'package fixture\n\nimport kotlin.math.abs', 'tail': '\n'}}, declarations=[])
    for node in k.members(container):
        row = dict(original=node['id'], subtree=True, fate='retained')
        if node['selector'] == 'class Model':
            row.update(fate='moved', destination='Model.kt', target='class Model', substitutions=[
                dict(before='private data class Model', after='internal data class Model', count=1)])
        manifest['declarations'].append(row)
    return original, manifest, extraction(manifest, original)


class KotlinMovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original, cls.manifest, cls.current = fixture()

    def verify(self, manifest, current, reason=None):
        errors, count = k.check(manifest, self.original, current)
        self.assertGreater(count, 20)
        if reason is None:
            self.assertEqual([], errors)
        else:
            self.assertTrue(any(reason in error for error in errors), '\n'.join(errors))
            print('EXPECTED FAILURE:', reason)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(self.manifest, current, reason)

    def test_positive_syntax_and_complete_subtree_partition(self):
        self.verify(self.manifest, self.current)
        manifest = k.retained_manifest('Activity.kt', self.original)
        self.verify(manifest, {'Activity.kt': self.original})

    def test_complete_real_phase1_extraction(self):
        manifest = json.loads(k.MANIFEST.read_text())
        original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show', manifest['base'] + ':' + manifest['source']]).decode()
        current = extraction(manifest, original)
        errors, count = k.check(manifest, original, current)
        self.assertEqual(3477, count)
        self.assertEqual([], errors)
        folder = k.evidence_root(k.ROOT) / k.EVIDENCE_PHASE / 'fixtures/phase1'
        for path, text in current.items():
            destination = folder / Path(path).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text)

    def test_changed_literal(self):
        self.edit('Model.kt', 'id + 2', 'id + 3', 'token mismatch: class Activity/class Model')

    def test_dropped_comment(self):
        self.edit('Model.kt', '/** Move this KDoc and the nested /* block */ comment. */', '', 'token mismatch: class Activity/class Model')

    def test_edited_comment(self):
        self.edit('Model.kt', 'nested /* block */ comment', 'nested /* changed */ comment', 'token mismatch: class Activity/class Model')

    def test_reordered_statement(self):
        self.edit('Activity.kt', 'first()\n        second()', 'second()\n        first()', 'token mismatch: class Activity/fun statements()')

    def test_newline_only(self):
        self.edit('Activity.kt', '(1\n        + 2)', '(1 + 2)', 'token mismatch: class Activity/fun multiline()')

    def test_undeclared_receiver(self):
        self.edit('Model.kt', 'fun expression() = id', 'fun expression() = host.id', 'token mismatch: class Activity/class Model')

    def test_undeclared_visibility(self):
        self.edit('Model.kt', 'internal data class Model', 'public data class Model', 'token mismatch: class Activity/class Model')

    def test_missing_declaration(self):
        self.verify(self.manifest, {'Activity.kt': self.current['Activity.kt'], 'Model.kt': 'package fixture\n\nimport kotlin.math.abs\n'}, 'missing declaration: class Model')

    def test_unassigned_declaration(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['declarations'].pop()
        self.verify(manifest, self.current, 'unassigned declaration: class Activity/class Model')

    def test_duplicate_move(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['declarations'].append(copy.deepcopy(manifest['declarations'][-1]))
        self.verify(manifest, self.current, 'duplicate ownership: class Activity/class Model')

    def test_original_and_destination_survive(self):
        self.verify(self.manifest, {**self.current, 'Activity.kt': self.original}, 'surviving-after-move: class Activity/class Model')

    def test_unexpected_new_declaration_in_original(self):
        self.verify(self.manifest, {**self.current, 'Activity.kt': self.current['Activity.kt'] + '\nfun surprise() = 3\n'}, 'unexpected new declaration: Activity.kt:fun surprise()')

    def test_unexpected_new_declaration_in_destination(self):
        self.verify(self.manifest, {**self.current, 'Model.kt': self.current['Model.kt'] + '\nval surprise = 3\n'}, 'unexpected new declaration: Model.kt:property surprise')

    def test_retained_body_edit(self):
        self.edit('Activity.kt', 'value + "!"', 'value + "?"', 'token mismatch: class Activity/fun overloaded(String)')

    def test_property_initializer_reorder(self):
        self.edit('Activity.kt', 'val first = 1_000L\n    val second = 2u', 'val second = 2u\n    val first = 1_000L', 'retained declaration order changed: class Activity')

    def test_template_content(self):
        self.edit('Model.kt', 'hello $name', 'goodbye $name', 'token mismatch: class Activity/class Model')

    def test_original_import_change(self):
        self.edit('Activity.kt', 'import kotlin.math.abs', 'import kotlin.math.max', 'token mismatch: :prefix')

    def test_destination_import_mismatch(self):
        self.edit('Model.kt', 'import kotlin.math.abs', 'import kotlin.math.max', 'destination imports/package/file annotations: Model.kt')

    def test_overloaded_function_mixup(self):
        self.edit('Activity.kt', 'fun overloaded(value: Int) = value + 1', 'fun overloaded(value: Int) = value + 2', 'token mismatch: class Activity/fun overloaded(Int)')

    def test_patched_extra_edit(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['phase'] = 2
        row = next(r for r in manifest['declarations'] if r['original'] == 'class Activity/fun overloaded(Int)')
        row.update(fate='patched', reason='fixture wiring', test='fixture', patches=[dict(before='value + 1', after='host.value + 1', count=1)])
        current = dict(self.current)
        current['Activity.kt'] = current['Activity.kt'].replace('value + 1', 'host.value + 2')
        self.verify(manifest, current, 'token mismatch: class Activity/fun overloaded(Int)')

    def test_patched_forbidden_in_phase1(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['declarations'][0]['fate'] = 'patched'
        self.verify(manifest, self.current, 'patched forbidden in phase 1')

    def test_substitution_counts(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['declarations'][-1]['substitutions'][0]['count'] = 2
        with self.assertRaisesRegex(ValueError, 'substitution occurrence count'):
            self.verify(manifest, self.current)


def run(manifest_path=k.MANIFEST):
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(KotlinMovesTest)
    manifest = json.loads(Path(manifest_path).read_text())
    k.EVIDENCE_PHASE = 'p' + str(manifest['phase'])
    if manifest['phase'] >= 2:
        import test_kotlin_moves_phase2
        test_kotlin_moves_phase2.MANIFEST = (manifest if manifest['phase'] == 2 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p2.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase2.Phase2MovesTest))
    if manifest['phase'] >= 3:
        import test_kotlin_moves_phase3
        test_kotlin_moves_phase3.MANIFEST = (manifest if manifest['phase'] == 3 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p3.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase3.Phase3MovesTest))
        from test_kotlin_overloads import KotlinOverloadsTest
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(KotlinOverloadsTest))
    if manifest['phase'] >= 4:
        import test_kotlin_moves_phase4
        test_kotlin_moves_phase4.MANIFEST = (manifest if manifest['phase'] == 4 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p4.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase4.Phase4MovesTest))
        from test_kotlin_overloads_phase4 import Phase4OverloadsTest
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(Phase4OverloadsTest))
    if manifest['phase'] >= 5:
        import test_kotlin_moves_phase5
        test_kotlin_moves_phase5.MANIFEST = (manifest if manifest['phase'] == 5 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p5.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase5.Phase5MovesTest))
    if manifest['phase'] >= 6:
        import test_kotlin_moves_phase6
        test_kotlin_moves_phase6.MANIFEST = (manifest if manifest['phase'] == 6 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p6.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase6.Phase6MovesTest))
    if manifest['phase'] >= 7:
        import test_kotlin_moves_phase7
        test_kotlin_moves_phase7.MANIFEST = (manifest if manifest['phase'] == 7 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p7.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase7.Phase7MovesTest))
    if manifest['phase'] >= 8:
        import test_kotlin_moves_phase8
        test_kotlin_moves_phase8.MANIFEST = (manifest if manifest["phase"] == 8 else
            json.loads((k.ROOT / "dev/tool/kotlin_moves/tvplayer_p8.json").read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase8.Phase8MovesTest))
    if manifest['phase'] >= 9:
        import test_kotlin_moves_phase9
        test_kotlin_moves_phase9.MANIFEST = (manifest if manifest['phase'] == 9 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p9.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase9.Phase9MovesTest))
        from test_kotlin_overloads_phase9 import Phase9OverloadsTest
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(Phase9OverloadsTest))
    if manifest['phase'] >= 10:
        import test_kotlin_moves_phase10
        test_kotlin_moves_phase10.MANIFEST = (manifest if manifest['phase'] == 10 else
            json.loads((k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p10.json').read_text()))
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase10.Phase10MovesTest))
        from test_kotlin_overloads_phase10 import Phase10OverloadsTest
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(Phase10OverloadsTest))
    if manifest['phase'] >= 11:
        import test_kotlin_moves_phase11
        test_kotlin_moves_phase11.MANIFEST = manifest
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(test_kotlin_moves_phase11.Phase11MovesTest))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return not result.wasSuccessful()


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=k.MANIFEST)
    raise SystemExit(run(parser.parse_args().manifest))
