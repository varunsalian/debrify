"""Phase-16 production fixture, nested timing and controls/identity/scrub guards."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_initializer_timing, check_earlier

MANIFEST = None


class Phase16MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest=MANIFEST
        cls.original=subprocess.check_output(['git','-C',str(k.ROOT),'show',MANIFEST['base']+':'+MANIFEST['source']],text=True)
        cls.current=extraction(MANIFEST,cls.original)
        cls.source=MANIFEST['source']

    def path(self,name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem==name)

    def verify(self,current=None,reason=None,manifest=None):
        errors,count=k.check(manifest or self.manifest,self.original,current or self.current)
        self.assertEqual(1727,count)
        if reason:
            self.assertTrue(any(reason in e for e in errors),'\n'.join(errors))
            print('EXPECTED PHASE-16 FAILURE:',reason)
        else:self.assertEqual([],errors)

    def edit(self,path,before,after,reason,count=1):
        current=dict(self.current);self.assertEqual(count,current[path].count(before),before)
        current[path]=current[path].replace(before,after);self.verify(current,reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(81,sum(r['fate']=='moved' for r in self.manifest['declarations']))
        self.assertEqual(38,len(self.manifest['initializer_timing']))
        self.assertEqual(7,len(self.manifest['overload_audit']))
        self.assertEqual(23,len(self.manifest['retained_view_bindings']))
        self.assertEqual(12,sum(r['cast'] is not None for r in self.manifest['retained_view_bindings']))
        self.assertEqual(3,sum('[' in r['assignment_target'] for r in self.manifest['retained_view_bindings']))
        folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/fixtures/phase16')
        for path,text in self.current.items():
            target=folder/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)

    def initializer(self,expression,kind='allocation',reason=None,extra='',imports=''):
        source='package fixture\n'+imports+'\nclass Fixture { val first=false\nval later='+expression+'\n}\n'+extra
        unit=k.parse({'initializer':source})['initializer'];nodes={n['id']:n for n in k.walk(unit['declarations'])}
        first=next(n for n in nodes.values() if n['selector']=='property first');later=next(n for n in nodes.values() if n['selector']=='property later')
        m=dict(phase=16,declarations=[dict(original=n['id'],fate='moved',destination='Dest.kt') for n in (first,later)],added=[dict(slot=first['id'])],nested_construction=[],initializer_timing=[dict(original=later['id'],slot=first['id'],line=source.count('\n',0,later['start'])+1,text=source[later['start']:later['end']],kind=kind,proof='Reviewed inert initializer.')])
        errors=[];check_initializer_timing(m,nodes,source,errors)
        if reason:self.assertTrue(any(reason in e for e in errors),errors)
        else:self.assertEqual([],errors)

    def test_float_literals(self):
        for text in ('0f','1.0f','30f','0.25f'):
            self.assertEqual('constant',initializer_kind(text));self.initializer(text,kind='constant')

    def test_float_negative_exponent_double_call_and_property(self):
        for text in ('-1.0f','1e3f','1.0','readFloat()','host.progress'):
            self.assertIsNone(initializer_kind(text));self.initializer(text,kind='constant',reason='initializer timing not proven inert')

    def test_typed_null_arrays(self):
        for text in ('arrayOfNulls<TextView>(3)','arrayOfNulls<String>(0)'):
            self.assertEqual('allocation',initializer_kind(text));self.initializer(text)

    def test_null_array_expression_implicit_type_lambda_negative_size(self):
        for text in ('arrayOfNulls<TextView>(count)','arrayOfNulls<TextView>(1+2)','arrayOfNulls(3)','Array(3) { host.view }','arrayOfNulls<TextView>(-1)'):
            self.assertIsNone(initializer_kind(text));self.initializer(text,reason='initializer timing not proven inert')

    def test_null_array_binding_shadows(self):
        for extra,imports in [('fun <T> arrayOfNulls(n: Int): Array<T?> = TODO()',''),('','import provider.arrayOfNulls'),('','import provider.factory as arrayOfNulls')]:
            self.initializer('arrayOfNulls<TextView>(3)',reason='initializer binding is shadowed',extra=extra,imports=imports)

    def test_fieldless_runnable_deferred_reads(self):
        self.initializer('object : Runnable { override fun run() { host.read(); handler.postDelayed(this, 100) } }')

    def test_runnable_init_property_second_supertype_constructor_read(self):
        for text in ('object : Runnable { init { host.read() }; override fun run() {} }','object : Runnable { val view=host.view; override fun run() {} }','object : Runnable, Other { override fun run() {} }','object : Runnable(host.view) { override fun run() {} }','object : Runnable { override fun run() {}; fun other() {} }'):
            self.assertIsNone(initializer_kind(text));self.initializer(text,reason='initializer timing not proven inert')

    def test_runnable_binding_shadows(self):
        for extra,imports in [('interface Runnable { fun run() }',''),('','import provider.Runnable'),('','import provider.Callback as Runnable')]:
            self.initializer('object : Runnable { override fun run() {} }',reason='initializer binding is shadowed',extra=extra,imports=imports)

    def test_all_38_proofs_including_nested_first_fields(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m=copy.deepcopy(self.manifest);m['initializer_timing'].remove(row);self.verify(manifest=m,reason='initializer timing coverage differs')

    def test_nested_eager_construction_and_exact_position(self):
        p=self.path('TvControlsOverlayController')
        for child in ('identity','seek'):
            before=next(line for line in self.current[p].splitlines() if 'internal val '+child+' =' in line)
            self.edit(p,before,before.replace(' = ',' by lazy { ')+' }','pinned destination:')
            m=copy.deepcopy(self.manifest);order=m['destinations'][p]['order']['class TvControlsOverlayController'];name='class TvControlsOverlayController/property '+child;order.remove(name);order.append(name);self.verify(manifest=m,reason='destination declaration order changed')

    def test_nested_slot_mapping_required(self):
        m=copy.deepcopy(self.manifest);m['nested_construction']=[];self.verify(manifest=m,reason='destination lacks effective construction slot')

    def test_construction_time_host_or_controls_read(self):
        for stem,read in [('TvDockIdentityPresenter','host.player'),('TvSeekScrubController','controls.controlsOverlay')]:
            p=self.path(stem);before=self.manifest['destinations'][p]['pinned_spans']['class '+stem+':header'];self.edit(p,before,before+'\n    init { '+read+' }','unexpected new declaration:',1)

    def test_forwarder_get_without_set_repoint(self):
        before='set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.pauseButton = value }'
        self.edit(self.source,before,before.replace('controlsOverlayController.',''),'token mismatch:')

    def test_shared_view_snapshot_and_extra_setter_logic(self):
        before='override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView'
        self.edit(self.source,before,before.replace(' get() = ',' = '),'added declaration:',self.current[self.source].count(before))
        before='set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.pauseButton = value }'
        self.edit(self.source,before,before[:-1]+'; value?.requestFocus() }','token mismatch:')

    def test_moved_target_type_and_nullability(self):
        for stem,before,after in [('TvControlsOverlayController','var pauseButton: AppCompatButton?','var pauseButton: View?'),('TvDockIdentityPresenter','var ottIdentityTitle: TextView?','var ottIdentityTitle: TextView'),('TvDockIdentityPresenter','arrayOfNulls<TextView>(3)','arrayOfNulls<View>(3)')]:
            p=self.path(stem);self.edit(p,before,after,'retained dock target type/nullability differs')

    def test_ott_skin_installed_stays(self):
        before='set(value) { this@AndroidTvTorrentPlayerActivity.ottSkinInstalled = value }'
        self.edit(self.source,before,before.replace('.ottSkinInstalled','.controlsOverlayController.ottSkinInstalled'),'token mismatch:')

    def test_owned_name_cannot_be_added_to_host(self):
        p=self.path('TvControlsOverlayController');self.edit(p,'    interface Host {','    interface Host {\n        val controlsMenuVisible: Boolean','pinned destination:')

    def test_controls_not_overlay_shadow_capture(self):
        p=self.path('TvSeekScrubController');before='controls.showControlsMenu()'
        self.edit(p,before,'overlay.showControlsMenu()','token mismatch:',self.current[p].count(before))
        self.assertEqual(3,self.current[self.path('TvControlsOverlayController')].count('val overlay ='))
        p=self.path('TvControlsOverlayController');before='if (!controlsMenuVisible) {'
        self.edit(p,before,'if (!overlay.controlsMenuVisible) {','token mismatch:',self.current[p].count(before))

    def test_local_player_rhs_only(self):
        p=self.path('TvSeekScrubController');self.assertIn('val player = host.player ?: return',self.current[p])
        self.edit(p,'val currentPosition = player.currentPosition','val currentPosition = host.player.currentPosition','token mismatch:')

    def test_readiness_snapshot_and_missing_substitution(self):
        before='private val startupGateViewReady: Boolean get() = ::startupGateView.isInitialized'
        self.edit(self.source,before,before.replace(' get() = ',' = '),'added declaration:',self.current[self.source].count(before))
        self.edit(self.path('TvControlsOverlayController'),'if (!host.nextBackdropReady) return','if (!::nextBackdrop.isInitialized) return','token mismatch:')

    def test_readiness_audit_row_required(self):
        m=copy.deepcopy(self.manifest);m['readiness_reads'].pop();self.verify(manifest=m,reason='readiness reference audit coverage differs')

    def test_volatile_annotation_and_access_proof(self):
        p=self.path('TvDockIdentityPresenter');self.edit(p,'@Volatile','', 'volatile identity annotation must remain')
        m=copy.deepcopy(self.manifest);m['volatile_identity']['writers'].pop();self.verify(manifest=m,reason='volatile identity ownership/access proof coverage differs')

    def test_lazy_activity_state_computed_only(self):
        for name in ('iptvLiveRecovery','dockSkinSpec','controlsSkin'):
            before=next(line for line in self.current[self.source].splitlines() if 'override val '+name+':' in line and 'this@AndroidTvTorrentPlayerActivity.'+name in line)
            self.edit(self.source,before,before.replace(' get() = ',' = '),'added declaration:',self.current[self.source].count(before))

    def test_destroy_statements_in_place(self):
        before='controlsOverlayController.controlsHandler.removeCallbacksAndMessages(null)\n        controlsOverlayController.seek.seekbarHandler.removeCallbacksAndMessages(null)'
        self.edit(self.source,before,'controlsOverlayController.seek.seekbarHandler.removeCallbacksAndMessages(null)\n        controlsOverlayController.controlsHandler.removeCallbacksAndMessages(null)','token mismatch:')

    def test_named_arguments_and_defaults_preserved(self):
        p=self.path('TvSeekScrubController')
        for before,after in [('confirm =','commit ='),('focused =','focus ='),('stepMs: Long = 10_000L','stepMs: Long = 5_000L')]:
            self.edit(p,before,after,'token mismatch:',self.current[p].count(before))

    def test_router_patch_extra_edit_and_missed_cinema_field(self):
        before='controlsOverlayController.seek.cinemaSeekMode';self.edit(self.source,before,'cinemaSeekMode','token mismatch:',self.current[self.source].count(before))
        before='isContinuous = event.repeatCount > 0';self.edit(self.source,before,'isContinuous = false','token mismatch:',self.current[self.source].count(before))

    def test_runnable_self_receiver_not_activity(self):
        p=self.path('TvSeekScrubController');self.edit(p,'seekbarHandler.postDelayed(this, 100)','seekbarHandler.postDelayed(activity, 100)','token mismatch:')
        m=copy.deepcopy(self.manifest);m['runnable_receivers']=[];self.verify(manifest=m,reason='reviewed Runnable receiver list differs')

    def test_owner_optin_children_no_optin(self):
        self.edit(self.path('TvControlsOverlayController'),'@OptIn(UnstableApi::class)','', 'pinned destination:')
        for stem in ('TvDockIdentityPresenter','TvSeekScrubController'):
            p=self.path(stem);self.edit(p,'internal class '+stem,'@OptIn(UnstableApi::class)\ninternal class '+stem,'pinned destination:')

    def test_all_23_retained_pins_required(self):
        for pin in self.manifest['retained_view_bindings']:
            m=copy.deepcopy(self.manifest);m['retained_view_bindings'].remove(pin);self.verify(manifest=m,reason='retained phase-15 view-binding coverage/descriptors differ')

    def test_retained_pin_cast_and_descriptor_cannot_change(self):
        for field,value in [('cast',None),('descriptor','Landroid/view/View;')]:
            m=copy.deepcopy(self.manifest);m['retained_view_bindings'][0][field]=value;self.verify(manifest=m,reason='retained phase-15 view-binding coverage/descriptors differ')

    def test_all_54_earlier_destinations_frozen(self):
        self.assertEqual([],check_earlier(self.manifest,k.ROOT));self.assertEqual(54,len(self.manifest['earlier_destinations']['paths']))
        spec=self.manifest['earlier_destinations'];current={p:subprocess.check_output(['git','-C',str(k.ROOT),'show',spec['revision']+':'+p],text=True) for p in spec['paths']}
        p=next(p for p in current if Path(p).stem=='TvControlsDockController');current[p]=current[p].replace('host.pauseButton =','host.aspectButton =')
        self.assertTrue(any('changed beyond reviewed whitelist' in e for e in check_earlier(self.manifest,k.ROOT,current)))

    def test_historical_phase15_merge(self):
        m=json.loads((k.ROOT/'dev/tool/kotlin_moves/tvplayer_p15.json').read_text())
        original=subprocess.check_output(['git','-C',str(k.ROOT),'show',m['base']+':'+m['source']],text=True)
        files={p:subprocess.check_output(['git','-C',str(k.ROOT),'show','df439aed1:'+p],text=True) for p in [m['source'],*m['destinations']]}
        errors,count=k.check(m,original,files);self.assertEqual(1730,count);self.assertEqual([],errors)
