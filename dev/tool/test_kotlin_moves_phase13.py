"""Phase-13 complete production extraction and narrow construction/binding guards."""
import copy
import json
from pathlib import Path
import subprocess
import unittest
import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_earlier, check_initializer_timing

MANIFEST = None


class Phase13MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show', cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.source = cls.manifest['source']

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current=None, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current or self.current)
        self.assertEqual(2013, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-13 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(60, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(28, len(self.manifest['initializer_timing']))
        self.assertEqual(23, len(self.manifest['overload_audit']))
        self.assertEqual(2, len(self.manifest['function_references']))
        self.assertEqual(1, len(self.manifest['listener_receivers']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase13')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_negative_literal_and_allowlisted_enum_only(self):
        for form in ('-1', '-1_000L', 'PlaylistMode.NONE'):
            self.assertEqual('constant', initializer_kind(form))
        for form in ('-x', '-f()', '-false', '-null', 'Other.NONE', 'PlaylistMode.NONE()', 'PlaylistMode.NONE(1)', 'PlaylistMode.current', 'PlaylistMode.Companion.NONE'):
            self.assertIsNone(initializer_kind(form), form)

    def getter(self, declaration, expected):
        source = 'class Fixture {\n' + declaration + '\n}'
        unit = k.parse({'getter': source})['getter']
        node = next(n for n in k.walk(unit['declarations']) if n['selector'] == 'property later')
        first = next(n for n in k.walk(unit['declarations']) if n['selector'] == 'property first')
        manifest = dict(phase=13, declarations=[dict(original=n['id'], fate='moved', destination='Dest.kt') for n in (first,node)], added=[dict(slot=first['id'])], nested_construction=[], initializer_timing=[dict(original=node['id'], slot=first['id'], line=source.count('\n',0,node['start'])+1, text=source[node['start']:node['end']], kind='none', proof='Accessor only; nothing executes at construction.')])
        errors=[]
        check_initializer_timing(manifest, {n['id']:n for n in k.walk(unit['declarations'])}, source, errors)
        if expected:
            self.assertTrue(any('not proven inert' in e for e in errors), errors)
        else:
            self.assertEqual([], errors)

    def test_accessor_only_no_construction(self):
        self.getter('val first = false\n val later: Int get() = if (first) 1 else 2', False)

    def test_accessor_call_side_effect_rejected(self):
        self.getter('val first = false\n val later: Int get() = readState()', True)

    def test_accessor_write_side_effect_rejected(self):
        self.getter('var first = 0\n val later: Int get() { first++; return first }', True)

    def test_accessor_backing_initializer_rejected(self):
        self.getter('val first = false\n val later: Int = 1\n get() = field', True)

    def test_accessor_delegate_rejected(self):
        self.getter('val first = false\n val later: Int by lazy { 1 }', True)

    def test_every_initializer_proof_required(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m=copy.deepcopy(self.manifest);m['initializer_timing'].remove(row)
                self.verify(manifest=m, reason='initializer timing coverage differs')

    def test_getter_proofs_required(self):
        self.assertEqual(2, sum(r['kind']=='none' for r in self.manifest['initializer_timing']))

    def test_listener_exclusion_omission(self):
        m=copy.deepcopy(self.manifest);m['listener_receivers']=[]
        self.verify(manifest=m, reason='typed listener exclusion coverage/binding differs')

    def test_listener_wrong_dispatch_pin(self):
        m=copy.deepcopy(self.manifest);m['listener_receivers'][0]['object_method']='run'
        self.verify(manifest=m, reason='typed listener exclusion coverage/binding differs')

    def test_listener_substitution_rejected(self):
        self.edit(self.path('TvPlaylistFocusNavigator'), 'removeOnGlobalLayoutListener(this)', 'removeOnGlobalLayoutListener(activity)', 'typed listener expression substituted or binding changed:')

    def test_listener_type_change_rejected(self):
        self.edit(self.path('TvPlaylistFocusNavigator'), 'object : android.view.ViewTreeObserver.OnGlobalLayoutListener', 'object : Runnable', 'typed listener expression substituted or binding changed:')

    def test_layout_inflater_getter_pin_required(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee']=='getLayoutInflater'))
        self.verify(manifest=m, reason='implicit inherited-receiver audit coverage differs')

    def test_layout_inflater_must_use_activity(self):
        self.edit(self.path('TvPlaylistGuideSkin'), 'activity.layoutInflater', 'host.layoutInflater', 'token mismatch:')

    def test_function_reference_audit_omission(self):
        m=copy.deepcopy(self.manifest);m['function_references'].pop()
        self.verify(manifest=m, reason='function-reference audit coverage differs')

    def test_function_reference_wrong_receiver(self):
        self.edit(self.path('TvPlaylistOverlayController'), 'guideSkin::guideSkinBind', 'host::guideSkinBind', 'function-reference receiver/dispatch changed:', 2)

    def test_unbound_reference_rejected(self):
        self.edit(self.path('TvPlaylistOverlayController'), 'guideSkin::guideSkinBind', '::guideSkinBind', 'function-reference receiver/dispatch changed:', 2)

    def test_nested_eager_construction(self):
        self.edit(self.path('TvPlaylistOverlayController'), 'internal val navigator = TvPlaylistFocusNavigator(activity, host, this)', 'internal val navigator by lazy { TvPlaylistFocusNavigator(activity, host, this) }', 'pinned destination:')

    def test_nested_skin_construction(self):
        self.edit(self.path('TvPlaylistOverlayController'), 'internal val guideSkin = TvPlaylistGuideSkin(activity, host, this)', 'internal val guideSkin by lazy { TvPlaylistGuideSkin(activity, host, this) }', 'pinned destination:')

    def test_constructor_side_effect_rejected(self):
        self.edit(self.path('TvPlaylistFocusNavigator'), '    private val playlist: TvPlaylistOverlayController,\n) {', '    private val playlist: TvPlaylistOverlayController,\n) {\n    init { host.playlistView.requestFocus() }', 'unexpected new declaration:')

    def test_computed_view_forwarder(self):
        self.edit(self.source, 'override val playlistView: RecyclerView get() = this@AndroidTvTorrentPlayerActivity.playlistView', 'override val playlistView: RecyclerView = this@AndroidTvTorrentPlayerActivity.playlistView', 'added declaration:')

    def test_qualified_host_binding(self):
        self.edit(self.source, 'this@AndroidTvTorrentPlayerActivity.playlistView', 'playlistView', 'added declaration:')

    def test_cross_owner_focus_field(self):
        p=self.path('TvPlaylistGuideSkin');before='playlist.navigator.navigationTargetPosition'
        self.edit(p,before,'host.navigationTargetPosition','token mismatch:',self.current[p].count(before))

    def test_teardown_order(self):
        self.edit(self.source, 'playlistController.seriesPlaylistAdapter = null\n        playlistController.moviePlaylistAdapter = null', 'playlistController.moviePlaylistAdapter = null\n        playlistController.seriesPlaylistAdapter = null', 'token mismatch:')

    def test_all_six_earlier_host_properties_patched(self):
        counts={'upNextController':1,'startupGateController':1,'progressReporter':2,'stremioTvGuideController':1,'skipSegmentController':1,'sourceSwitchController':1}
        for name,count in counts.items():
            row=next(r for r in self.manifest['declarations'] if r['original'].endswith('/property '+name))
            self.assertEqual('patched',row['fate']);self.assertEqual(count,sum(e['count'] for e in row['patches']))

    def test_extra_host_property_edit(self):
        self.edit(self.source, 'override val playlistVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.playlistController.playlistVisible', 'override val playlistVisible: Boolean get() = false', 'token mismatch:',2)

    def test_all_46_earlier_destinations_frozen(self):
        self.assertEqual(46,len(self.manifest['earlier_destinations']['paths']))
        self.assertEqual([],check_earlier(self.manifest,k.ROOT))

    def test_historical_phase12(self):
        r=subprocess.run(['python3',str(k.ROOT/'dev/tool/check_kotlin_moves.py'),'--manifest',str(k.ROOT/'dev/tool/kotlin_moves/tvplayer_p12.json'),'--at','315448a3c'],capture_output=True,text=True)
        self.assertEqual(0,r.returncode,r.stdout+r.stderr)

    def test_reflected_getters_are_public_on_the_internal_skin(self):
        text=self.current[self.path('TvPlaylistGuideSkin')]
        for name in ('guideOverlayLayoutRes','guideItemLayoutRes'):
            self.assertIn('    val '+name, text)
            self.assertNotIn('    internal val '+name, text)
            self.assertNotIn('    private val '+name, text)
