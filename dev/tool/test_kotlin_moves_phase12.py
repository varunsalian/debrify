"""Complete phase-12 partition, receiver preservation and structural negatives."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase12MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.source = cls.manifest['source']

    def path(self, name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == name)

    def verify(self, current=None, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current or self.current)
        self.assertEqual(2139, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-12 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(39, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(20, len(self.manifest['initializer_timing']))
        self.assertEqual(77, len(self.manifest['overload_audit']))
        self.assertEqual(53, sum(r.get('receiver') == 'implicit-inherited' for r in self.manifest['overload_audit']))
        self.assertEqual(1, len(self.manifest['receiver_lambda_exclusions']))
        self.assertEqual(1, len(self.manifest['receiver_lambda_transformations']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase12')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_every_initializer_proof_required(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m = copy.deepcopy(self.manifest)
                m['initializer_timing'].remove(row)
                self.verify(manifest=m, reason='initializer timing coverage differs')

    def test_receiver_constructor_transform_preserves_inner_this(self):
        p = self.path('TvIptvGuidePickers')
        self.assertIn('val searchInput = EditText(activity).apply {', self.current[p])
        self.assertIn('TextViewCompat.setCompoundDrawableTintList(\n                    this,', self.current[p])
        self.verify()

    def test_inner_this_rewrite_rejected(self):
        self.edit(self.path('TvIptvGuidePickers'), 'TextViewCompat.setCompoundDrawableTintList(\n                    this,',
            'TextViewCompat.setCompoundDrawableTintList(\n                    activity,',
            'receiver-lambda expression substituted or binding changed:')

    def test_inner_receiver_type_change_rejected(self):
        self.edit(self.path('TvIptvGuidePickers'), 'val searchInput = EditText(activity).apply {',
            'val searchInput = TextView(activity).apply {', 'receiver-lambda expression substituted or binding changed:')

    def test_inner_receiver_lambda_change_rejected(self):
        self.edit(self.path('TvIptvGuidePickers'), 'val searchInput = EditText(activity).apply {',
            'val searchInput = EditText(activity).run {', 'receiver-lambda expression substituted or binding changed:')

    def test_constructor_audit_omission_rejected(self):
        m = copy.deepcopy(self.manifest)
        line = m['receiver_lambda_transformations'][0]['constructor_line']
        m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['line'] == line))
        self.verify(manifest=m, reason='constructor-receiver transformation requires pinned constructor audit')

    def test_constructor_transform_omission_rejected(self):
        m = copy.deepcopy(self.manifest)
        m['receiver_lambda_transformations'] = []
        self.verify(manifest=m, reason='constructor-receiver transformation coverage differs')

    def test_constructor_transform_cannot_change_type(self):
        m = copy.deepcopy(self.manifest)
        m['receiver_lambda_transformations'][0]['after'] = 'TextView(activity)'
        self.verify(manifest=m, reason='constructor-receiver transformation coverage differs')

    def test_inner_receiver_exclusion_omission_rejected(self):
        m = copy.deepcopy(self.manifest)
        m['receiver_lambda_exclusions'] = []
        self.verify(manifest=m, reason='receiver-lambda exclusion coverage/classification differs')

    def test_resources_getter_audit_omission_rejected(self):
        m = copy.deepcopy(self.manifest)
        m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee'] == 'getResources'))
        self.verify(manifest=m, reason='implicit inherited-receiver audit coverage differs')

    def test_current_focus_getter_audit_omission_rejected(self):
        m = copy.deepcopy(self.manifest)
        m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee'] == 'getCurrentFocus'))
        self.verify(manifest=m, reason='implicit inherited-receiver audit coverage differs')

    def test_resources_receiver_change_rejected(self):
        p = self.path('TvIptvGuidePickers')
        self.edit(p, 'activity.resources', 'host.resources', 'token mismatch:', 2)

    def test_current_focus_receiver_change_rejected(self):
        self.edit(self.path('TvIptvGuideChromeController'), 'activity.currentFocus', 'host.currentFocus', 'token mismatch:')

    def test_cross_file_adapter_write_must_target_owner(self):
        self.edit(self.path('TvIptvGuideOverlayBuilder'), 'chrome.iptvEpgAdapter = IptvEpgAdapter(',
            'iptvEpgAdapter = IptvEpgAdapter(', 'token mismatch:')

    def test_cross_file_picker_dispatch_cannot_swap(self):
        self.edit(self.path('TvIptvGuideOverlayBuilder'), 'chrome.pickers.showIptvCategoryPicker()',
            'chrome.overlay.showIptvCategoryPicker()', 'token mismatch:')

    def test_fieldless_overlay_cannot_own_state(self):
        self.edit(self.path('TvIptvGuideOverlayBuilder'), '    private val chrome: TvIptvGuideChromeController,',
            '    private val chrome: TvIptvGuideChromeController,\n    private val iptvEpgToken: Int = 0,', 'pinned destination:')

    def test_eager_collaborators_cannot_be_lazy(self):
        self.edit(self.path('TvIptvGuideChromeController'), 'internal val overlay = TvIptvGuideOverlayBuilder(activity, host, this)',
            'internal val overlay by lazy { TvIptvGuideOverlayBuilder(activity, host, this) }', 'pinned destination:')

    def test_owner_property_cannot_move_slot(self):
        row = self.manifest['added'][0]
        current = dict(self.current)
        current[self.source] = current[self.source].replace(row['text'], '')
        anchor = '    private var iptvSourceId: String? = null'
        self.assertEqual(1, current[self.source].count(anchor))
        current[self.source] = current[self.source].replace(anchor, row['text'] + '\n' + anchor)
        self.verify(current, 'retained declaration order changed:')

    def test_phase11_host_whole_property_is_patched(self):
        row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property iptvGuideController'))
        self.assertEqual('patched', row['fate'])
        self.assertEqual(2, sum(e['count'] for e in row['patches']))
        self.edit(self.source, 'this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.hideIptvEpgPane()',
            'this@AndroidTvTorrentPlayerActivity.hideIptvEpgPane()', 'token mismatch:')

    def test_teardown_statement_cannot_move(self):
        self.edit(self.source, 'iptvGuideController.iptvUiContextToken++\n        iptvGuideController.iptvBrowseToken++',
            'iptvGuideController.iptvBrowseToken++\n        iptvGuideController.iptvUiContextToken++', 'token mismatch:')

    def test_shadowed_title_stays_local(self):
        self.edit(self.path('TvIptvGuideOverlayBuilder'), 'title.setTextColor(t.fg)', 'host.title.setTextColor(t.fg)', 'token mismatch:')

    def test_borrowed_handler_cannot_clear_all_posts(self):
        self.edit(self.path('TvIptvGuideChromeController'), 'host.iptvBrowseHandler.postDelayed({',
            'host.iptvBrowseHandler.removeCallbacksAndMessages(null)\n                host.iptvBrowseHandler.postDelayed({', 'token mismatch:')

    def test_all_43_earlier_destinations_are_frozen(self):
        self.assertEqual(43, len(self.manifest['earlier_destinations']['paths']))
        self.assertEqual([], check_earlier(self.manifest, k.ROOT))

    def test_historical_phase11_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'), '--manifest',
            str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p11.json'), '--at', 'b870a16b1'], text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
