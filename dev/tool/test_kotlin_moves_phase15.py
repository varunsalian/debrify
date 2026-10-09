"""Phase-15 production partitions, inert allocation proofs and dock receiver guards."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_initializer_timing, check_earlier

MANIFEST = None


class Phase15MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show', cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.source = cls.manifest['source']

    def path(self, name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == name)

    def verify(self, current=None, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current or self.current)
        self.assertEqual(1730, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-15 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(68, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(31, len(self.manifest['initializer_timing']))
        self.assertEqual(17, len(self.manifest['overload_audit']))
        sites = self.manifest['find_view_assignments']
        self.assertEqual(23, len(sites)); self.assertEqual(12, sum(r['cast'] is not None for r in sites))
        self.assertEqual(3, sum('[' in r['assignment_target'] for r in sites))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase15')
        for path, text in self.current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def initializer(self, declaration, reason=None, extra='', imports=''):
        source = 'package fixture\n' + imports + '\nclass Fixture {\nval first = false\n' + declaration + '\n}\n' + extra
        unit = k.parse({'initializer': source})['initializer']
        nodes = {n['id']: n for n in k.walk(unit['declarations'])}
        first = next(n for n in nodes.values() if n['selector'] == 'property first')
        later = next(n for n in nodes.values() if n['selector'] == 'property later')
        manifest = dict(phase=15, declarations=[dict(original=n['id'], fate='moved', destination='Dest.kt') for n in (first, later)], added=[dict(slot=first['id'])], nested_construction=[], initializer_timing=[dict(original=later['id'], slot=first['id'], line=source.count('\n',0,later['start'])+1, text=source[later['start']:later['end']], kind='allocation', proof='Reviewed inert allocation.')])
        errors=[];check_initializer_timing(manifest,nodes,source,errors)
        if reason:self.assertTrue(any(reason in e for e in errors),errors)
        else:self.assertEqual([],errors)

    def test_typed_hash_maps(self):
        for text in ('HashMap<View, Typeface?>()', 'HashMap<View, android.content.res.ColorStateList?>()'):
            self.assertEqual('allocation', initializer_kind(text))
            self.initializer('val later = '+text)

    def test_hash_map_arguments_and_factories(self):
        for text in ('HashMap()', 'HashMap<View, Typeface?>(16)', 'HashMap<View, Typeface?>(other)', 'hashMapOf(view to typeface)'):
            self.assertIsNone(initializer_kind(text))
            self.initializer('val later = '+text,'initializer timing not proven inert')

    def test_hash_map_binding_shadow(self):
        for imports,extra in [('import provider.HashMap',''),('import provider.Factory as HashMap',''),('', 'class HashMap<T,U>')]:
            self.initializer('val later = HashMap<View, Typeface?>()','phase-15 initializer binding is shadowed',imports=imports,extra=extra)

    def test_literal_arrays(self):
        for text in ('arrayOf(0, 500, 1_000)', 'arrayOf(0.5f, 0.75f, 1.0f)', 'arrayOf("Fit", "Cinema Zoom")', 'arrayOf(AspectRatioFrameLayout.RESIZE_MODE_FIT, AspectRatioFrameLayout.RESIZE_MODE_FILL, AspectRatioFrameLayout.RESIZE_MODE_ZOOM)'):
            self.assertEqual('allocation',initializer_kind(text));self.initializer('val later = '+text)

    def test_array_state_call_template_and_nonreviewed_constants(self):
        for text in ('arrayOf(readState())','arrayOf(state)','arrayOf("$state")','arrayOf("${readState()}")','arrayOf(Other.FIT)','arrayOf(AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH)'):
            self.assertIsNone(initializer_kind(text));self.initializer('val later = '+text,'initializer timing not proven inert')

    def test_array_binding_shadow(self):
        self.initializer('val later = arrayOf(1)','phase-15 initializer binding is shadowed',extra='fun arrayOf(x: Int) = state')
        self.initializer('val later = arrayOf(AspectRatioFrameLayout.RESIZE_MODE_FIT)','phase-15 initializer binding is shadowed',imports='import provider.AspectRatioFrameLayout')

    def test_reviewed_listener_with_deferred_callback(self):
        self.initializer('val later = object : AnalyticsListener { private var inputFormat: Format? = null\nfun callback() { host.readState() } }')

    def test_listener_construction_reads_init_and_supertype(self):
        for text in ('object : AnalyticsListener { private var inputFormat: Format? = host.format }', 'object : AnalyticsListener { private var inputFormat: Format? = null\ninit { host.readState() } }', 'object : OtherListener { private var inputFormat: Format? = null }','object : AnalyticsListener { private var inputFormat: Format? = null\nval other = host.other }'):
            self.assertIsNone(initializer_kind(text));self.initializer('val later = '+text,'initializer timing not proven inert')

    def test_listener_binding_shadow(self):
        self.initializer('val later = object : AnalyticsListener { private var inputFormat: Format? = null }','phase-15 initializer binding is shadowed',imports='import provider.AnalyticsListener')

    def test_every_initializer_proof_required_including_first_styler_field(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m=copy.deepcopy(self.manifest);m['initializer_timing'].remove(row)
                self.verify(manifest=m,reason='initializer timing coverage differs')

    def test_computed_shared_views_and_routing(self):
        for name in ('ottQualityChips','nativeAudioRouting','displayController','controlsDockController'):
            before=next(line for line in self.current[self.source].splitlines() if ('override val '+name+':') in line)
            self.edit(self.source,before,before.replace(' get() = ',' = '),'added declaration:')

    def test_shared_var_extra_logic(self):
        before='set(value) { this@AndroidTvTorrentPlayerActivity.pauseButton = value }'
        self.edit(self.source,before,before[:-1]+'; value?.requestFocus() }','added declaration:')

    def test_borrowed_routing_must_not_allocate(self):
        self.edit(self.source,'override val nativeAudioRouting: NativeAudioRouting get() = this@AndroidTvTorrentPlayerActivity.nativeAudioRouting','override val nativeAudioRouting: NativeAudioRouting get() = NativeAudioRouting()','added declaration:')

    def test_eager_styler_and_position(self):
        p=self.path('TvControlsDockController');before='internal val styler = TvLiveDockStyler(activity, host, this)'
        self.edit(p,before,'internal val styler by lazy { TvLiveDockStyler(activity, host, this) }','pinned destination:')
        m=copy.deepcopy(self.manifest);m['destinations'][p]['order']['class TvControlsDockController'].remove('class TvControlsDockController/property styler');m['destinations'][p]['order']['class TvControlsDockController'].append('class TvControlsDockController/property styler')
        self.verify(manifest=m,reason='destination declaration order changed')

    def test_construction_time_owner_or_host_read(self):
        p=self.path('TvLiveDockStyler');before='    private val controlsDock: TvControlsDockController,\n) {'
        for read in ('host.playerView','controlsDock.iptvNextButton'):
            self.edit(p,before,before+'\n    init { '+read+' }','unexpected new declaration:')

    def test_sibling_slot_cannot_move(self):
        m=copy.deepcopy(self.manifest);m['added'][1]['slot']=m['added'][0]['slot'];self.verify(manifest=m,reason='destination lacks effective construction slot')

    def test_controls_dock_cross_qualifications(self):
        p=self.path('TvLiveDockStyler');self.assertEqual(48,self.current[p].count('controlsDock.'))
        before='controlsDock.iptvPrevButton';self.edit(p,before,'host.iptvPrevButton','token mismatch:',self.current[p].count(before))
        before='controlsDock.iptvNextButton';self.edit(p,before,'iptvNextButton','token mismatch:',self.current[p].count(before))

    def test_dock_shadowing_negative(self):
        p=self.path('TvLiveDockStyler');before='controlsDock.iptvNextButton';self.edit(p,before,'dock.iptvNextButton','token mismatch:',self.current[p].count(before))
        self.assertIn('val dock =',self.current[p]);self.assertIn('dock: LinearLayout',self.current[p])

    def test_sibling_cross_qualification(self):
        for stem,before in [('TvControlsDockController','host.displayController.cycleAspectRatio'),('TvPlaybackDisplayController','host.controlsDockController.aspectButton')]:
            p=self.path(stem);self.edit(p,before,before.split('.')[-1],'token mismatch:',self.current[p].count(before))

    def test_find_target_type_and_nullability(self):
        p=self.path('TvControlsDockController')
        for before,after in [('var pauseButton: AppCompatButton?','var pauseButton: View?'),('val ottQualityChips: Array<TextView?>','val ottQualityChips: Array<View?>'),('var ottIdentityTitle: TextView?','var ottIdentityTitle: TextView')]:
            self.edit(p,before,after,'findViewById Host target type/nullability differs')

    def test_find_every_cast_or_absence_site_required(self):
        for row in self.manifest['find_view_assignments']:
            with self.subTest(line=row['line']):
                m=copy.deepcopy(self.manifest);m['find_view_assignments'].remove(row);self.verify(manifest=m,reason='findViewById assignment audit coverage differs')

    def test_constant_inlining_row_required(self):
        m=copy.deepcopy(self.manifest);m['constant_inlining']=[];self.verify(manifest=m,reason='array constant-inlining proof coverage differs')

    def test_context_label_preserved_activity_binding(self):
        p=self.path('TvLiveDockStyler');before='ContextCompat.getColorStateList(activity,';self.edit(p,before,'ContextCompat.getColorStateList(this,','token mismatch:',self.current[p].count(before))

    def test_host_templates_braced(self):
        p=self.path('TvPlaybackDisplayController');self.edit(p,'${host.skipSegmentsEnabled}','$host.skipSegmentsEnabled','token mismatch:')

    def test_whole_property_repoint_extra_edit(self):
        self.edit(self.source,'this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvRecordButton','this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvNextButton','token mismatch:')

    def test_three_destroy_statements_stay_in_place(self):
        self.edit(self.source,'displayController.displayModeController?.clear()\n        displayController.displayModeController = null','displayController.displayModeController = null\n        displayController.displayModeController?.clear()','token mismatch:')

    def test_missed_styler_dispatch(self):
        self.edit(self.source,'controlsDockController.styler.updateIptvControlPresentation(entry)','controlsDockController.updateIptvControlPresentation(entry)','token mismatch:',self.current[self.source].count('controlsDockController.styler.updateIptvControlPresentation(entry)'))

    def test_both_effect_session_call_shapes(self):
        p=self.path('TvPlaybackDisplayController');self.edit(p,'syncAudioEffectSession()','syncAudioEffectSession(0)','token mismatch:',self.current[p].count('syncAudioEffectSession()'))
        self.edit(self.source,'displayController.syncAudioEffectSession(audioSessionId)','displayController.syncAudioEffectSession()','token mismatch:')

    def test_type_constants_and_banner_trivia(self):
        dock=self.current[self.path('TvControlsDockController')];display=self.current[self.path('TvPlaybackDisplayController')]
        self.assertIn('internal data class DockSkinSpec',dock);self.assertIn('private const val USE_UNIFIED_MENU',dock);self.assertIn('private const val DECODER_LOG_TAG',display)
        self.edit(self.path('TvPlaybackDisplayController'),'// Track selection','// changed banner','token mismatch:')

    def test_all_51_earlier_destinations_frozen(self):
        self.assertEqual([],check_earlier(self.manifest,k.ROOT));self.assertEqual(51,len(self.manifest['earlier_destinations']['paths']))

    def test_historical_phase14(self):
        m=json.loads((k.ROOT/'dev/tool/kotlin_moves/tvplayer_p14.json').read_text());s=subprocess.check_output(['git','-C',str(k.ROOT),'show',m['base']+':'+m['source']],text=True);files={p:subprocess.check_output(['git','-C',str(k.ROOT),'show','ce3ddfb06:'+p],text=True) for p in [m['source'],*m['destinations']]};errors,count=k.check(m,s,files);self.assertEqual(1850,count);self.assertEqual([],errors)
