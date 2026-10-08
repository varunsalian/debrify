"""Phase-6 nested construction and exact cross-object qualification fixtures."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier, initializer_kind

MANIFEST = None


class Phase6MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current, reason=None, manifest=None, original=None):
        errors, count = k.check(manifest or self.manifest, original or self.original, current)
        self.assertEqual(2567, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-6 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction_all_28_proofs(self):
        self.verify(self.current)
        self.assertEqual(47, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(28, len(self.manifest['initializer_timing']))
        self.assertEqual(1, len(self.manifest['added']))
        self.assertEqual(42, len(self.manifest['overload_audit']))
        self.assertEqual(4, sum(r['callee'] == 'with' for r in self.manifest['overload_audit']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/production')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_any_and_literal_parse_color_only(self):
        self.assertEqual('allocation', initializer_kind('Any()'))
        for form in ('Color.parseColor("#00E5FF")', 'Color.parseColor("red")'):
            self.assertEqual('constant', initializer_kind(form))
        for form in ('Any(host)', 'factory()', 'Color.parseColor(host.color)',
                     'Color.parseColor("$color")', 'Color.parseColor("${host.color}")',
                     'Color.parseColor("red" + suffix)', 'Color.parseColor(getColor())', 'Color.parseColor("not-a-color")'):
            self.assertIsNone(initializer_kind(form), form)

    def test_renderer_first_field_requires_effective_slot_proof(self):
        m = copy.deepcopy(self.manifest)
        m['initializer_timing'] = [r for r in m['initializer_timing']
                                  if not r['original'].endswith('/property iptvZapStyledScrim')]
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_renderer_slot_cannot_be_its_original_first_field(self):
        m = copy.deepcopy(self.manifest)
        for row in m['initializer_timing']:
            if 'iptvZapStyled' in row['original'] or 'iptvZapGlassCardWidth' in row['original']:
                row['slot'] = 'class AndroidTvTorrentPlayerActivity/property iptvZapStyledScrim'
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_missing_nested_mapping_rejected(self):
        m = copy.deepcopy(self.manifest); m['nested_construction'] = []
        with self.assertRaisesRegex(ValueError, 'lacks effective construction slot'):
            self.verify(self.current, manifest=m)

    def reject_read(self, expression):
        m = copy.deepcopy(self.manifest)
        row = next(r for r in m['initializer_timing'] if r['original'].endswith('/property iptvZapGlassCardWidth'))
        original = self.original.replace('private var iptvZapGlassCardWidth = 0',
                                          'private var iptvZapGlassCardWidth = ' + expression)
        unit = k.parse({'changed': original})['changed']
        node = next(n for n in k.walk(unit['declarations']) if n['id'] == row['original'])
        row['text'] = original[node['start']:node['end']]
        row['line'] = original.count('\n', 0, node['start']) + 1
        row['kind'] = 'constant'; row['proof'] = 'Forged proof must not bypass inert classifier.'
        self.verify(extraction(m, original), 'initializer timing not proven inert:', m, original)

    def test_renderer_initializer_classic_read_rejected(self):
        self.reject_read('iptvZapBanner?.height ?: 0')

    def test_renderer_initializer_host_read_rejected(self):
        self.reject_read('controlsOverlay?.height ?: 0')

    def test_effectful_initializer_with_forged_proof_rejected(self):
        self.reject_read('System.currentTimeMillis().toInt()')

    def test_renderer_added_init_classic_read_rejected(self):
        path = self.path('TvIptvZapBannerStyledRenderer')
        self.edit(path, '    private var iptvZapStyledScrim:',
            '    init { classic.hideIptvZapBanner() }\n    private var iptvZapStyledScrim:',
            'unexpected new declaration:')

    def test_renderer_added_init_host_read_rejected(self):
        path = self.path('TvIptvZapBannerStyledRenderer')
        self.edit(path, '    private var iptvZapStyledScrim:',
            '    init { host.progressHandler.post {} }\n    private var iptvZapStyledScrim:',
            'unexpected new declaration:')

    def test_renderer_lazy_instead_of_eager_rejected(self):
        self.edit(self.path('TvIptvZapBannerController'),
            'private val styled = TvIptvZapBannerStyledRenderer(activity, host, this)',
            'private val styled by lazy { TvIptvZapBannerStyledRenderer(activity, host, this) }',
            'pinned destination:')

    def test_renderer_constructor_argument_pinned(self):
        self.edit(self.path('TvIptvZapBannerController'),
            'TvIptvZapBannerStyledRenderer(activity, host, this)',
            'TvIptvZapBannerStyledRenderer(activity, host, host)', 'pinned destination:')

    def test_renderer_initializer_position_pinned(self):
        current = dict(self.current); path = self.path('TvIptvZapBannerController')
        text = self.manifest['nested_construction'][0]['text']
        current[path] = current[path].replace(text, '')
        marker = 'private var iptvZapBanner: FrameLayout? = null'
        current[path] = current[path].replace(marker, marker + text)
        self.verify(current, 'destination declaration order changed:')

    def test_classic_qualification_missing_rejected(self):
        self.edit(self.path('TvIptvZapBannerStyledRenderer'),
            'val banner = classic.iptvZapBanner ?: return',
            'val banner = iptvZapBanner ?: return', 'token mismatch:')

    def test_missed_qualification_captured_by_same_name_host_member(self):
        current = dict(self.current); styled = self.path('TvIptvZapBannerStyledRenderer')
        classic = self.path('TvIptvZapBannerController')
        current[classic] = current[classic].replace('    interface Host {',
            '    interface Host {\n        val iptvZapBanner: FrameLayout? get() = null')
        current[styled] = current[styled].replace('val banner = classic.iptvZapBanner ?: return',
                                               'val banner = host.iptvZapBanner ?: return')
        self.verify(current, 'token mismatch: class AndroidTvTorrentPlayerActivity/fun applyStyledZapBannerMode')
        # This mutant is compilable; the Step-T bytecode fixture run compiles it.
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/host-capture')
        for path, text in current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def test_swapped_dispatch_target_rejected(self):
        self.edit(self.path('TvIptvZapBannerController'),
            'styled.paintStyledZapBannerIdentity(entry, it)',
            'styled.paintStyledZapBannerEpg(entry, it)', 'token mismatch:')

    def test_default_host_read_remains_at_call_time(self):
        self.edit(self.path('TvIptvZapBannerController'), 'docked: Boolean = host.controlsMenuVisible',
                  'docked: Boolean = false', 'token mismatch:')

    def test_guide_lazy_forwarder_cannot_snapshot(self):
        self.edit(self.manifest['source'],
            'override val guideStyle: GuideStyle get() = this@AndroidTvTorrentPlayerActivity.guideStyle',
            'override val guideStyle: GuideStyle = this@AndroidTvTorrentPlayerActivity.guideStyle',
            'added declaration:')

    def test_cross_substitution_occurrence_count_pinned(self):
        m = copy.deepcopy(self.manifest)
        row = next(r for r in m['declarations'] if r['fate'] == 'moved' and any(
            'classic.' in x['after'] for x in r['substitutions']))
        edit = next(x for x in row['substitutions'] if 'classic.' in x['after']); edit['count'] += 1
        with self.assertRaisesRegex(ValueError, 'substitution occurrence count'):
            self.verify(self.current, manifest=m)

    def test_all_31_earlier_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(31, len(current)); self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        path = next(p for p in current if Path(p).stem == 'TvProgressReporter')
        current[path] += '\nfun unreviewed() = 1\n'
        self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                      check_earlier(self.manifest, k.ROOT, current))

    def test_historical_phase5_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p5.json'), '--at', 'e71ddac3a'],
            capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
