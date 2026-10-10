"""Phase-17 complete production fixture and tune/trial boundary negatives."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_initializer_timing, check_earlier

MANIFEST = None


class Phase17MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git','-C',str(k.ROOT),'show',MANIFEST['base']+':'+MANIFEST['source']],text=True)
        cls.current = extraction(MANIFEST, cls.original)
        cls.source = MANIFEST['source']

    def path(self, name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == name)

    def verify(self, current=None, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current or self.current)
        self.assertEqual(1676, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-17 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(41, sum(r['fate']=='moved' for r in self.manifest['declarations']))
        self.assertEqual(21, len(self.manifest['initializer_timing']))
        self.assertEqual(8, len(self.manifest['overload_audit']))
        self.assertEqual(2, len(self.manifest['receiver_lambda_exclusions']))
        self.assertEqual(2, len(self.manifest['receiver_lambda_transformations']))
        self.assertEqual(23, len(self.manifest['retained_view_bindings']))
        folder = k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/fixtures/phase17')
        for path, text in self.current.items():
            target = folder/path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def initializer(self, expression, reason=None, extra='', imports='', delegated=False):
        source = 'package fixture\n'+imports+'\nclass Fixture { val first=false\nval later '+('by ' if delegated else '= ')+expression+'\n}\n'+extra
        nodes = {n['id']:n for n in k.walk(k.parse({'initializer':source})['initializer']['declarations'])}
        first = next(n for n in nodes.values() if n['selector']=='property first')
        later = next(n for n in nodes.values() if n['selector']=='property later')
        m = dict(phase=17,declarations=[dict(original=n['id'],fate='moved',destination='Dest.kt') for n in (first,later)],added=[dict(slot=first['id'])],nested_construction=[],initializer_timing=[dict(original=later['id'],slot=first['id'],line=source.count('\n',0,later['start'])+1,text=source[later['start']:later['end']],kind='allocation',proof='Reviewed allocation with deferred execution.')])
        errors=[]
        check_initializer_timing(m,nodes,source,errors)
        if reason:
            self.assertTrue(any(reason in e for e in errors),errors)
        else:
            self.assertEqual([],errors)

    def test_typed_empty_stdlib_collections(self):
        for text in ('HashSet<String>()','HashSet<String?>()','HashMap<String, String>()'):
            self.assertEqual('allocation',initializer_kind(text))
            self.initializer(text)

    def test_collection_inference_capacity_copy_factory_rejected(self):
        for text in ('HashSet()','HashSet<String>(16)','HashSet(other)','HashMap()','HashMap<String,String>(16)','HashMap(other)','hashSetOf(x)','hashMapOf(x)'):
            self.assertIsNone(initializer_kind(text))
            self.initializer(text,reason='initializer timing not proven inert')

    def test_collection_same_package_import_alias_shadows(self):
        for name,expression in [('HashSet','HashSet<String>()'),('HashMap','HashMap<String,String>()')]:
            for extra,imports in [('class '+name+'<T>',''),('','import provider.'+name),('','import provider.Collection as '+name),('','import java.util.'+name)]:
                self.initializer(expression,reason='initializer binding is shadowed',extra=extra,imports=imports)

    def test_synchronized_lazy_body_is_deferred(self):
        for text in ('lazy { host.read() }','lazy { IptvLiveRecovery(handler, callbacks) }'):
            self.assertEqual('allocation',initializer_kind(text))
            self.initializer(text,delegated=True)

    def test_lazy_requires_delegate_not_an_eager_property_initializer(self):
        self.initializer('lazy { host.read() }',reason='initializer timing not proven inert')

    def test_collection_and_lazy_wildcard_import_shadows(self):
        self.initializer('HashSet<String>()',reason='initializer binding is shadowed',imports='import provider.*')
        self.initializer('lazy { host.read() }',reason='initializer binding is shadowed',imports='import provider.*',delegated=True)

    def test_lazy_modes_named_argument_other_delegates_rejected(self):
        for text in ('lazy(LazyThreadSafetyMode.NONE) { value }','lazy(LazyThreadSafetyMode.PUBLICATION) { value }','lazy(initializer = f())','Delegates.observable(false) { _, _, _ -> host.read() }','custom { value }','lazy { first } + lazy { second }','lazy { first } { second }'):
            self.assertIsNone(initializer_kind(text))
            self.initializer(text,reason='initializer timing not proven inert',delegated=True)

    def test_lazy_same_package_import_alias_shadows(self):
        for extra,imports in [('fun <T> lazy(block: () -> T) = block',''),('','import provider.lazy'),('','import provider.factory as lazy')]:
            self.initializer('lazy { host.read() }',reason='initializer binding is shadowed',delegated=True,extra=extra,imports=imports)

    def test_every_initializer_proof_including_first_trial_field(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m=copy.deepcopy(self.manifest)
                m['initializer_timing'].remove(row)
                self.verify(manifest=m,reason='initializer timing coverage differs')

    def test_eager_trial_at_exact_slot(self):
        p=self.path('TvIptvTuneController')
        before='internal val trial = TvIptvTwinTrial(activity, host, this)'
        self.edit(p,before,'internal val trial by lazy { TvIptvTwinTrial(activity, host, this) }','pinned destination:')
        m=copy.deepcopy(self.manifest)
        order=m['destinations'][p]['order']['class TvIptvTuneController']
        target='class TvIptvTuneController/property trial'
        order.remove(target);order.append(target)
        self.verify(manifest=m,reason='destination declaration order changed')

    def test_nested_effective_slot_required(self):
        m=copy.deepcopy(self.manifest);m['nested_construction']=[]
        self.verify(manifest=m,reason='destination lacks effective construction slot')

    def test_construction_time_host_or_tune_read(self):
        for stem,read in [('TvIptvTuneController','host.currentIptvHttpHeaders'),('TvIptvTwinTrial','tune.currentIptvStreamUrl')]:
            p=self.path(stem);before=self.manifest['destinations'][p]['pinned_spans']['class '+stem+':header']
            self.edit(p,before,before+'\n    init { '+read+' }','unexpected new declaration:')

    def test_missed_tune_and_trial_qualification(self):
        for stem,prefix in [('TvIptvTwinTrial','tune.'),('TvIptvTuneController','trial.')]:
            p=self.path(stem);before=prefix+('setIptvMediaItem' if prefix=='tune.' else 'iptvTwinTrialUrl')
            self.edit(p,before,before.removeprefix(prefix),'token mismatch:',self.current[p].count(before))

    def test_owned_name_added_to_host_cannot_capture_missing_qualification(self):
        p=self.path('TvIptvTuneController')
        for name in ('setIptvMediaItem','currentIptvStreamUrl','iptvLiveRetuneInFlight','iptvLiveRecovery','iptvHlsForcedUrls','hideIptvReconnectPill','clearIptvTwinTrial','iptvTwinTrialUrl','iptvTwinPreferredUrls','restoreParkedIptvTwinIfNeeded'):
            self.edit(p,'    interface Host {','    interface Host {\n        val '+name+': Any','pinned destination:')

    def test_twin_local_and_parameter_not_qualified(self):
        p=self.path('TvIptvTwinTrial')
        self.edit(p,'val twin = iptvTwinTrialUrl','val twin = trial.iptvTwinTrialUrl','token mismatch:',self.current[p].count('val twin = iptvTwinTrialUrl'))
        self.edit(p,'twin: String','trial: String','token mismatch:')

    def test_trial_field_left_in_owner_is_split_ownership(self):
        p=self.path('TvIptvTwinTrial');owner=self.path('TvIptvTuneController')
        before=next(line for line in self.current[p].splitlines() if 'var iptvTwinTrialOriginalUrl:' in line)
        current=dict(self.current);current[p]=current[p].replace(before,'',1)
        header=self.manifest['destinations'][owner]['pinned_spans']['class TvIptvTuneController:header']
        current[owner]=current[owner].replace(header,header+'\n'+before,1)
        self.verify(current,reason='missing declaration:')

    def test_same_name_host_cannot_capture_unqualified_owner_read(self):
        p=self.path('TvIptvTuneController');child=self.path('TvIptvTwinTrial')
        current=dict(self.current)
        current[p]=current[p].replace('    interface Host {','    interface Host {\n        val currentIptvStreamUrl: String?',1)
        current[child]=current[child].replace('tune.currentIptvStreamUrl','host.currentIptvStreamUrl')
        self.verify(current,reason='pinned destination:')

    def test_volatile_snapshot_and_forwarder_setter_extra_edit(self):
        before='override var currentIptvHttpHeaders: Map<String, String>\n                get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders'
        self.edit(self.source,before,before.replace('var ','val ').replace('\n                get() = ',' = '),'added declaration:')
        before='set(value) { this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive = value }'
        self.edit(self.source,before,before.replace(' = value',' = false'),'added declaration:')

    def test_volatile_annotation_and_proof_required(self):
        for row in self.manifest['borrowed_volatile']:
            unit=k.parse({'source':self.current[self.source]})['source']
            node=next(n for n in k.walk(unit['declarations']) if n['id']==row['original'])
            before=self.current[self.source][node['start']:node['end']]
            self.edit(self.source,before,before.replace('@Volatile',''),'borrowed loader-thread field must retain @Volatile')
            m=copy.deepcopy(self.manifest);m['borrowed_volatile'].remove(row)
            self.verify(manifest=m,reason='borrowed volatile field proof coverage differs')

    def test_resolver_and_extractor_reads_untouched(self):
        for before,after in [('val headers = currentIptvHttpHeaders','val headers = emptyMap<String, String>()'),('if (iptvStrictTsActive) strictTs else aggressiveTs','if (true) strictTs else aggressiveTs')]:
            self.edit(self.source,before,after,'token mismatch:',self.current[self.source].count(before))
        before='currentIptvHttpHeaders';p=self.source
        row=next(r for r in self.manifest['declarations'] if r['original'].endswith('/fun setupPlayer()'))
        self.assertEqual(3,sum(e['count'] for e in row['patches']))
        self.assertTrue(all('setOffline' in e['before'] for e in row['patches']))

    def test_headers_and_strict_writes_before_prepare(self):
        p=self.path('TvIptvTuneController')
        before='host.currentIptvHttpHeaders = entry.httpHeaders'
        current=dict(self.current);current[p]=current[p].replace(before,'',1).replace('            prepare()','            prepare()\n        '+before,1)
        self.verify(current,reason='token mismatch:')
        before='        host.iptvStrictTsActive =\n            iptvStartsWithStrictTs ||\n            iptvStrictTsUrls.contains(streamUrl) || iptvStrictTsUrls.size >= 2 ||\n            streamUrl == trial.iptvTwinTrialUrl ||\n            trial.iptvTwinPreferredUrls.containsValue(streamUrl)'
        self.assertEqual(1,self.current[p].count(before))
        current=dict(self.current);current[p]=current[p].replace(before,'',1).replace('            prepare()','            prepare()\n'+before,1)
        self.verify(current,reason='token mismatch:')

    def test_recovery_lazy_not_eager_or_none(self):
        p=self.path('TvIptvTuneController')
        for before,after in [('iptvLiveRecovery: IptvLiveRecovery by lazy {','iptvLiveRecovery: IptvLiveRecovery = run {'),('iptvStartsWithStrictTs by lazy {','iptvStartsWithStrictTs by lazy(LazyThreadSafetyMode.NONE) {')]:
            self.edit(p,before,after,'must remain synchronized lazy delegates')
        m=copy.deepcopy(self.manifest);m['deferred_lazy'].pop()
        self.verify(manifest=m,reason='deferred lazy proof coverage differs')

    def test_controls_lazy_forwarder_never_snapshot(self):
        before='override val iptvLiveRecovery: IptvLiveRecovery get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.iptvLiveRecovery'
        self.edit(self.source,before,before.replace(' get() = ',' = '),'token mismatch:')

    def test_textview_inner_receiver_and_constructor_pin(self):
        p=self.path('TvIptvTuneController')
        for before,after in [('activity.addContentView(this, params)','activity.addContentView(activity, params)'),('iptvReconnectPill = this','iptvReconnectPill = activity')]:
            self.edit(p,before,after,'receiver-lambda expression substituted or binding changed')
        self.edit(p,'activity.addContentView(this, params)','this.addContentView(this, params)','token mismatch:')
        m=copy.deepcopy(self.manifest);m['overload_audit']=[r for r in m['overload_audit'] if r['callee']!='TextView']
        self.verify(manifest=m,reason='constructor-receiver transformation requires pinned constructor audit')

    def test_add_content_view_requires_inherited_virtual_pin(self):
        m=copy.deepcopy(self.manifest)
        m['overload_audit']=[r for r in m['overload_audit'] if r['callee']!='addContentView']
        self.verify(manifest=m,reason='implicit inherited-receiver audit coverage differs')
        m=copy.deepcopy(self.manifest)
        row=next(r for r in m['overload_audit'] if r['callee']=='addContentView')
        row['expected_after']['opcode']='invokespecial'
        self.verify(manifest=m,reason='implicit inherited-receiver pin requires virtual')

    def test_dp_parameter_is_local(self):
        self.edit(self.path('TvIptvTuneController'),'(dp * activity.resources','(activity.dp * activity.resources','token mismatch:')

    def test_channel_identity_get_and_set_computed(self):
        before='set(value) { this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl = value }'
        self.edit(self.source,before,before.replace('iptvTuneController.',''),'token mismatch:')
        self.edit(self.source,before,'','token mismatch:')
        before='get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl'
        self.edit(self.source,before,before.replace('get() =','='),'token mismatch:',self.current[self.source].count(before))

    def test_patched_host_row_rejects_extra_logic(self):
        before='get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl'
        self.edit(self.source,before,before+'?.trim()','token mismatch:',self.current[self.source].count(before))

    def test_on_start_branch_cannot_be_folded(self):
        before='liveEntry != null && iptvTuneController.trial.restoreParkedIptvTwinIfNeeded()'
        self.edit(self.source,before,'iptvTuneController.trial.restoreParkedIptvTwinIfNeeded()','token mismatch:')

    def test_retune_brackets_and_parked_restore_remain_distinct(self):
        p=self.path('TvIptvTwinTrial')
        self.edit(p,'tune.iptvLiveRetuneInFlight = false','tune.iptvLiveRetuneInFlight = true','token mismatch:',3)
        before='        tune.setIptvMediaItem(entry, original)\n        return true'
        self.edit(p,before,'        tune.iptvLiveRetuneInFlight = true\n'+before,'token mismatch:')

    def test_trial_deadline_remove_before_post(self):
        p=self.path('TvIptvTwinTrial');before='iptvTwinTrialHandler.removeCallbacks(it)'
        self.edit(p,before,'iptvTwinTrialHandler.removeCallbacksAndMessages(null)','token mismatch:',self.current[p].count(before))

    def test_error_branch_priority_and_short_circuit(self):
        before='iptvTuneController.iptvLiveRecoveryEligible() && iptvTuneController.retryIptvAsHlsIfUnrecognized(error)'
        self.edit(self.source,before,before.replace(' && ',' || '),'token mismatch:')
        before='iptvTuneController.trial.restoreAcceptedIptvTwinAfterAuth(error)'
        self.edit(self.source,before,'iptvTuneController.retryIptvAsHlsIfUnrecognized(error)','token mismatch:')

    def test_twin_error_branch_cannot_follow_hls_retry(self):
        start=self.current[self.source].index('            if (isLiveIptvError && iptvTuneController.trial.iptvTwinTrialUrl != null &&')
        end=self.current[self.source].index('\n            }',start)+len('\n            }')
        branch=self.current[self.source][start:end]
        retry='            if (isLiveIptvError && iptvTuneController.retryIptvAsHlsIfUnrecognized(error)) return'
        self.assertEqual(1,self.current[self.source].count(retry))
        current=dict(self.current);current[self.source]=current[self.source].replace(branch,'',1).replace(retry,retry+'\n'+branch,1)
        self.verify(current,reason='token mismatch:')

    def test_start_over_token_owning_controller(self):
        p=self.path('TvIptvTuneController');before='host.iptvStartOverController.iptvCatchupToken++'
        self.edit(p,before,'host.iptvStartOverController.iptvCatchupToken','token mismatch:')

    def test_dock_styler_prefix_stays(self):
        p=self.path('TvIptvTuneController');before='host.controlsDockController.styler.updateIptvControlPresentation(entry)'
        self.edit(p,before,before.replace('.styler',''),'token mismatch:')

    def test_lifecycle_calls_stay_ordered(self):
        before='iptvTuneController.trial.clearIptvTwinTrial()\n        iptvTuneController.iptvLiveRecovery.cancel()'
        self.edit(self.source,before,'iptvTuneController.iptvLiveRecovery.cancel()\n        iptvTuneController.trial.clearIptvTwinTrial()','token mismatch:',self.current[self.source].count(before))

    def test_owner_optin_trial_stable(self):
        self.edit(self.path('TvIptvTuneController'),'@OptIn(UnstableApi::class)','', 'pinned destination:')
        self.edit(self.path('TvIptvTwinTrial'),'internal class TvIptvTwinTrial','@OptIn(UnstableApi::class)\ninternal class TvIptvTwinTrial','pinned destination:')

    def test_all_frozen_view_binding_pins_required(self):
        for pin in self.manifest['retained_view_bindings']:
            m=copy.deepcopy(self.manifest);m['retained_view_bindings'].remove(pin)
            self.verify(manifest=m,reason='retained phase-15 view-binding coverage/descriptors differ')

    def test_frozen_identity_writers_and_reader_required(self):
        for key in ('writers','reader','descriptor'):
            m=copy.deepcopy(self.manifest);m['retained_identity'].pop(key)
            self.verify(manifest=m,reason='frozen identity writer/reader proof coverage differs')

    def test_all_57_earlier_destinations_frozen(self):
        self.assertEqual(57,len(self.manifest['earlier_destinations']['paths']))
        self.assertEqual([],check_earlier(self.manifest,k.ROOT))
        spec=self.manifest['earlier_destinations']
        current={p:subprocess.check_output(['git','-C',str(k.ROOT),'show',spec['revision']+':'+p],text=True) for p in spec['paths']}
        p=next(p for p in current if Path(p).stem=='TvControlsOverlayController')
        current[p]=current[p].replace('host.iptvLiveRecovery','host.otherRecovery')
        self.assertTrue(any('changed beyond reviewed whitelist' in e for e in check_earlier(self.manifest,k.ROOT,current)))

    def test_historical_phase16_merge(self):
        m=json.loads((k.ROOT/'dev/tool/kotlin_moves/tvplayer_p16.json').read_text())
        original=subprocess.check_output(['git','-C',str(k.ROOT),'show',m['base']+':'+m['source']],text=True)
        files={p:subprocess.check_output(['git','-C',str(k.ROOT),'show','be5635fae:'+p],text=True) for p in [m['source'],*m['destinations']]}
        errors,count=k.check(m,original,files);self.assertEqual(1727,count);self.assertEqual([],errors)
