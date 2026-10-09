"""Phase-14 production partition, borrowed lifetime and dialog receiver guards."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_earlier, check_initializer_timing

MANIFEST = None


class Phase14MovesTest(unittest.TestCase):
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
        self.assertEqual(1850, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-14 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(43, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(20, len(self.manifest['initializer_timing']))
        self.assertEqual(25, len(self.manifest['overload_audit']))
        self.assertEqual(6, len(self.manifest['preserved_receivers']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase14')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def initializer(self, declaration, expected=None, extra='', imports=''):
        source = 'package fixture\n' + imports + '\nclass Fixture {\nval first = false\n' + declaration + '\n}\n' + extra
        unit = k.parse({'initializer': source})['initializer']
        nodes = {n['id']: n for n in k.walk(unit['declarations'])}
        first = next(n for n in nodes.values() if n['selector'] == 'property first')
        later = next(n for n in nodes.values() if n['selector'] == 'property later')
        manifest = dict(phase=14, declarations=[dict(original=n['id'], fate='moved', destination='Dest.kt')
            for n in (first, later)], added=[dict(slot=first['id'])], nested_construction=[],
            initializer_timing=[dict(original=later['id'], slot=first['id'],
                line=source.count('\n', 0, later['start']) + 1, text=source[later['start']:later['end']],
                kind='allocation', proof='Typed stdlib empty list; no state reads.')])
        errors = []
        check_initializer_timing(manifest, nodes, source, errors)
        if expected:
            self.assertTrue(any(expected in e for e in errors), errors)
        else:
            self.assertEqual([], errors)

    def test_typed_empty_list_and_historical_classification(self):
        self.assertEqual('allocation', initializer_kind('emptyList()'))
        self.initializer('val later: List<String> = emptyList()')
        self.initializer('val later: List<String> = emptyList()', imports='import kotlin.collections.emptyList')

    def test_empty_list_requires_declared_type(self):
        self.initializer('val later = emptyList()', 'emptyList requires an explicit declared property type')

    def test_empty_list_package_shadow(self):
        self.initializer('val later: List<String> = emptyList()', 'emptyList stdlib binding is shadowed',
            extra='fun emptyList(): List<String> = listOf("side effect")')

    def test_empty_list_local_shadow(self):
        self.initializer('val emptyList = { listOf("state") }\nval later: List<String> = emptyList()',
            'emptyList stdlib binding is shadowed')

    def test_empty_list_nonstdlib_import(self):
        self.initializer('val later: List<String> = emptyList()', 'emptyList stdlib binding is shadowed',
            imports='import provider.emptyList')

    def test_empty_list_import_alias(self):
        self.initializer('val later: List<String> = emptyList()', 'emptyList stdlib binding is shadowed',
            imports='import provider.factory as emptyList')

    def test_unreviewed_list_factories_rejected(self):
        for text in ('emptyList(state)', 'emptyList().also { readState() }', 'listOf()', 'listOf(state)',
                     'emptyList<String>().map { readState() }'):
            self.assertIsNone(initializer_kind(text), text)

    def test_each_initializer_proof_required(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                manifest = copy.deepcopy(self.manifest)
                manifest['initializer_timing'].remove(row)
                self.verify(manifest=manifest, reason='initializer timing coverage differs')

    def test_computed_borrowed_forwarders(self):
        for name in ('subtitleController', 'subtitleScope', 'playerPreferences', 'stremioSubtitleService', 'subtitleTrackReadiness'):
            with self.subTest(name=name):
                before = next(line for line in self.current[self.source].splitlines()
                              if 'override val ' + name + ':' in line)
                self.edit(self.source, before, before.replace(' get() = ', ' = '), 'added declaration:', self.current[self.source].count(before))

    def test_host_binding_explicitly_activity_qualified(self):
        self.edit(self.source, 'this@AndroidTvTorrentPlayerActivity.subtitleScope', 'subtitleScope', 'added declaration:', 3)

    def test_fieldless_dialogs_and_eager_construction(self):
        p = self.path('TvSubtitleSearchDialogs')
        self.edit(p, '    private val sources: TvSubtitleSourcesController,',
            '    private val sources: TvSubtitleSourcesController,\n    private val pendingSeason: Int = 1,', 'pinned destination:')
        p = self.path('TvSubtitleSourcesController')
        self.edit(p, 'internal val dialogs = TvSubtitleSearchDialogs(activity, host, this)',
            'internal val dialogs by lazy { TvSubtitleSearchDialogs(activity, host, this) }', 'pinned destination:')

    def test_construction_time_host_read(self):
        self.edit(self.path('TvSubtitleSearchDialogs'), '    private val sources: TvSubtitleSourcesController,\n) {',
            '    private val sources: TvSubtitleSourcesController,\n) {\n    init { host.subtitleScope }', 'unexpected new declaration:')

    def test_construction_time_sources_read(self):
        self.edit(self.path('TvSubtitleSearchDialogs'), '    private val sources: TvSubtitleSourcesController,\n) {',
            '    private val sources: TvSubtitleSourcesController,\n) {\n    init { sources.subtitleSearchResults.clear() }', 'unexpected new declaration:')

    def test_cross_owner_qualification(self):
        for stem, text in [('TvSubtitleSearchDialogs', 'sources.applyManualSubtitleIdentity'),
                           ('TvSubtitleSourcesController', 'dialogs.showSeasonEpisodePrompt')]:
            p = self.path(stem)
            self.edit(p, text, text.split('.')[1], 'token mismatch:', self.current[p].count(text))

    def test_same_name_host_capture_rejected(self):
        p = self.path('TvSubtitleSearchDialogs')
        self.edit(p, 'sources.applyManualSubtitleIdentity', 'host.applyManualSubtitleIdentity',
            'token mismatch:', self.current[p].count('sources.applyManualSubtitleIdentity'))

    def test_listview_inner_this_preserved(self):
        self.edit(self.path('TvSubtitleSearchDialogs'), 'this.adapter = adapter',
            'activity.adapter = adapter', 'receiver-lambda expression substituted or binding changed:')

    def test_listview_transform_and_exclusion_required(self):
        for key, reason in [('receiver_lambda_transformations', 'constructor-receiver transformation coverage differs'),
                            ('receiver_lambda_exclusions', 'receiver-lambda exclusion coverage/classification differs')]:
            m = copy.deepcopy(self.manifest)
            m[key] = []
            self.verify(manifest=m, reason=reason)

    def test_listview_constructor_audit_required(self):
        m = copy.deepcopy(self.manifest)
        m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee'] == 'ListView'))
        self.verify(manifest=m, reason='constructor-receiver transformation requires pinned constructor audit')

    def test_super_constructor_activity_classification(self):
        row = next(r for r in self.manifest['overload_audit'] if r['callee'] == 'ArrayAdapter')
        self.assertEqual('KtSuperTypeCallEntry', row['call_kind'])
        self.assertEqual('(Landroid/content/Context;ILjava/util/List;)V', row['expected_before']['descriptor'])
        self.assertEqual('invokespecial', row['expected_before']['opcode'])

    def test_super_constructor_audit_omission(self):
        m = copy.deepcopy(self.manifest)
        m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee'] == 'ArrayAdapter'))
        self.verify(manifest=m, reason='substituted this-site audit coverage differs')

    def test_super_constructor_wrong_classification(self):
        m = copy.deepcopy(self.manifest)
        next(r for r in m['overload_audit'] if r['callee'] == 'ArrayAdapter').pop('call_kind')
        self.verify(manifest=m, reason='super-constructor audit call kind differs')

    def test_all_non_substitutions_required(self):
        for row in self.manifest['preserved_receivers']:
            with self.subTest(context=row['context']):
                m = copy.deepcopy(self.manifest)
                m['preserved_receivers'].remove(row)
                self.verify(manifest=m, reason='preserved receiver coverage/binding differs')

    def test_context_receiver_substitution(self):
        p = self.path('TvSubtitleSearchDialogs')
        # Every occurrence gets an independent mutation (three adapter, one View).
        occurrences = [i for i in range(len(self.current[p])) if self.current[p].startswith('context', i)]
        self.assertEqual(4, len(occurrences))
        for i in occurrences:
            with self.subTest(offset=i):
                c = dict(self.current)
                c[p] = c[p][:i] + 'activity' + c[p][i + len('context'):]
                self.verify(c, 'preserved receiver expression substituted or binding changed:')

    def test_getitem_receiver_substitution(self):
        self.edit(self.path('TvSubtitleSearchDialogs'), 'val item = getItem(position)', 'val item = sources.getItem(position)',
            'preserved receiver expression substituted or binding changed:')

    def test_resources_named_argument_substitution(self):
        self.edit(self.path('TvSubtitleSourcesController'), 'resources = listOf("subtitles")',
            'activity.resources = listOf("subtitles")', 'preserved receiver expression substituted or binding changed:')

    def test_labels_preserved(self):
        self.edit(self.path('TvSubtitleSearchDialogs'), 'return@requestSubtitleCatalogSearchFromFlutter',
            'return@dialogs.requestSubtitleCatalogSearchFromFlutter', 'token mismatch:', 2)

    def test_braced_retained_templates(self):
        for text in ('${subtitleSourcesController.injectedSubtitles.size}', '${subtitleSourcesController.stremioSubtitles.size}'):
            self.edit(self.source, text, text.replace('${', '$').removesuffix('}'), 'token mismatch:')

    def test_all_host_properties_patched_and_extra_edit_rejected(self):
        for name, count in {'subtitleController': 10, 'iptvStartOverController': 1,
                            'iptvGuideController': 1, 'pikPakRetryController': 1}.items():
            row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property ' + name))
            self.assertEqual('patched', row['fate'])
            self.assertEqual(count, sum(e['count'] for e in row['patches']))
        self.edit(self.source, 'override val isLoadingStremioSubtitles: Boolean get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.isLoadingStremioSubtitles',
            'override val isLoadingStremioSubtitles: Boolean get() = false', 'token mismatch:')

    def test_teardown_order_stays_in_place(self):
        self.edit(self.source, 'subtitleScope.cancel()\n        subtitleSourcesController.stremioSubtitles.clear()\n        stremioSubtitleService = null',
            'subtitleSourcesController.stremioSubtitles.clear()\n        subtitleScope.cancel()\n        stremioSubtitleService = null', 'token mismatch:')

    def test_lint_opt_in_span_pinned(self):
        self.edit(self.path('TvSubtitleSourcesController'), '@OptIn(UnstableApi::class)\n', '', 'pinned destination:')

    def test_borrowed_objects_not_moved(self):
        for name in ('subtitleScope', 'stremioSubtitleService', 'subtitleTrackReadiness'):
            row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property ' + name))
            self.assertEqual('retained', row['fate'])

    def test_all_49_earlier_destinations_frozen(self):
        self.assertEqual(49, len(self.manifest['earlier_destinations']['paths']))
        self.assertEqual([], check_earlier(self.manifest, k.ROOT))

    def test_historical_phase13(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'), '--manifest',
            str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p13.json'), '--at', '82b16832c'], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
