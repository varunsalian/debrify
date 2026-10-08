"""Phase-11 single-state-owner extraction and receiver binding fixtures."""
import copy
import json
from pathlib import Path
import subprocess
import unittest
import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_earlier

MANIFEST = None

class Phase11MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git','-C',str(k.ROOT),'show',cls.manifest['base']+':'+cls.manifest['source']],text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.source = cls.manifest['source']

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current, reason=None, manifest=None, original=None):
        errors,count=k.check(manifest or self.manifest, original or self.original, current)
        self.assertEqual(2295,count)
        if reason:
            self.assertTrue(any(reason in e for e in errors),'\n'.join(errors))
            print('EXPECTED PHASE-11 FAILURE:',reason)
        else: self.assertEqual([],errors)

    def edit(self,path,before,after,reason,count=1):
        current=dict(self.current)
        self.assertGreater(count, 0)
        self.assertEqual(count,current[path].count(before),before)
        current[path]=current[path].replace(before,after)
        self.verify(current,reason)

    def test_complete_production_extraction_all_47_proofs(self):
        self.verify(self.current)
        self.assertEqual(92,sum(r['fate']=='moved' for r in self.manifest['declarations']))
        self.assertEqual(47,len(self.manifest['initializer_timing']))
        self.assertEqual(13,len(self.manifest['overload_audit']))
        self.assertEqual(2,len(self.manifest['receiver_lambda_exclusions']))
        for name,count in [('iptvStartOverController',8),('iptvZapBannerController',4)]:
            row=next(r for r in self.manifest['declarations'] if r['original'].endswith('/property '+name))
            self.assertEqual('patched',row['fate']); self.assertEqual(count,sum(e['count'] for e in row['patches']))
        folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/fixtures/phase11')
        for p,t in self.current.items():
            target=folder/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(t)

    def test_only_literal_strings_and_empty_typed_deque(self):
        for form in ['"IPTV"','"live"','""']:self.assertEqual('constant',initializer_kind(form))
        self.assertEqual('allocation',initializer_kind('java.util.ArrayDeque<Int>()'))
        for form in ['host.name','name()','"$name"','"${host.name}"','"a\\nb"','"a\nb"','"live" + suffix','java.util.ArrayDeque<Int>(10)','java.util.ArrayDeque<Int>(list)','ArrayDeque<Int>()','java.util.ArrayDeque()']:
            self.assertIsNone(initializer_kind(form),form)

    def test_every_later_field_proof_required(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m=copy.deepcopy(self.manifest);m['initializer_timing'].remove(row)
                self.verify(self.current,'initializer timing coverage differs',m)

    def test_fieldless_pager_cannot_own_state(self):
        self.edit(self.path('TvIptvZapPager'),'    private val guide: TvIptvGuideController,','    private val guide: TvIptvGuideController,\n    private val iptvZapRequestToken: Int = 0,','pinned destination:')

    def test_fieldless_navigator_cannot_own_state(self):
        self.edit(self.path('TvIptvChannelNavigator'),'    private val guide: TvIptvGuideController,','    private val guide: TvIptvGuideController,\n    private val iptvUiContextToken: Int = 0,','pinned destination:')

    def test_collaborator_cannot_read_shared_state_from_host(self):
        p=self.path('TvIptvZapPager');before='guide.iptvZapRequestToken';self.edit(p,before,'host.iptvZapRequestToken','token mismatch:',self.current[p].count(before))

    def test_missed_owner_qualification(self):
        p=self.path('TvIptvChannelNavigator');before='guide.iptvZapOwnsUiContext';self.edit(p,before,'iptvZapOwnsUiContext','token mismatch:',self.current[p].count(before))

    def test_missed_two_level_qualification(self):
        p=self.path('TvIptvChannelNavigator');before='guide.pager.requestIptvZapPage';self.edit(p,before,'guide.requestIptvZapPage','token mismatch:',self.current[p].count(before))

    def test_cross_destination_dispatch_cannot_swap(self):
        p=self.path('TvIptvGuideController');before='pager.trimHiddenIptvZapWindow';self.edit(p,before,'navigator.trimHiddenIptvZapWindow','token mismatch:',self.current[p].count(before))

    def test_return_labels_cannot_be_qualified(self):
        p=self.path('TvIptvChannelNavigator');before='return@requestIptvZapPage';self.edit(p,before,'return@guide.pager.requestIptvZapPage','token mismatch:',self.current[p].count(before))

    def test_shadowed_window_stays_local(self):
        p=self.path('TvIptvZapPager');before='val window =';self.edit(p,before,'val activityWindow =','token mismatch:',self.current[p].count(before))

    def test_shadowed_current_index_stays_local(self):
        p=self.path('TvIptvChannelNavigator');before='val currentIndex =';self.edit(p,before,'val hostIndex =','token mismatch:',self.current[p].count(before))

    def test_title_parameter_stays_local(self):
        p=self.path('TvIptvGuideController');before='title ?: when (iptvContentType)';self.edit(p,before,'activity.title ?: when (iptvContentType)','token mismatch:',self.current[p].count(before))

    def test_browse_default_remains_call_time_owner_read(self):
        p=self.path('TvIptvGuideController');before='query: String = iptvGuideSearch?.text?.toString()?.trim().orEmpty()';self.edit(p,before,'query: String = ""','token mismatch:')

    def test_start_over_forwards_all_three_switch_arguments(self):
        self.edit(self.source,'iptvGuideController.navigator.switchToIptvChannel(entry, adoptVisibleBrowseList, checkpointOutgoing)','iptvGuideController.navigator.switchToIptvChannel(entry, true, true)','token mismatch:')

    def test_start_over_extra_property_edit(self):
        self.edit(self.source,'override val iptvEpgToken: Int get() = this@AndroidTvTorrentPlayerActivity.iptvEpgToken','override val iptvEpgToken: Int get() = 0','token mismatch:')

    def test_zap_banner_extra_property_edit(self):
        p=self.source;before='override val iptvZapCategoryTotal: Int get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvZapCategoryTotal';self.edit(p,before,before.replace('get() =','='),'token mismatch:')

    def test_host_handler_cannot_be_snapshot(self):
        before='override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler';self.edit(self.source,before,before.replace('get() =','='),'added declaration:',2)

    def test_controller_slot_cannot_move(self):
        current=dict(self.current);row=self.manifest['added'][0];current[self.source]=current[self.source].replace(row['text'],'');current[self.source]=current[self.source].replace('    private var iptvSources =',row['text']+'\n    private var iptvSources =');self.verify(current,'retained declaration order changed:')

    def test_eager_pager_cannot_be_lazy(self):
        self.edit(self.path('TvIptvGuideController'),'internal val pager = TvIptvZapPager(activity, host, this)','internal val pager by lazy { TvIptvZapPager(activity, host, this) }','pinned destination:')

    def test_nested_construction_order_pinned(self):
        before='    internal val pager = TvIptvZapPager(activity, host, this)\n    internal val navigator = TvIptvChannelNavigator(activity, host, this)';self.edit(self.path('TvIptvGuideController'),before,'\n'.join(reversed(before.splitlines())),'destination declaration order changed:')

    def test_constructing_collaborator_cannot_read_host(self):
        p=self.path('TvIptvZapPager');self.edit(p,'    private val guide: TvIptvGuideController,\n) {','    private val guide: TvIptvGuideController,\n) {\n    init { host.iptvBrowseHandler.post {} }','unexpected new declaration:',1)

    def test_borrowed_handler_cannot_be_cleared(self):
        p=self.path('TvIptvGuideController');before='host.iptvBrowseHandler.post { pager.trimHiddenIptvZapWindow() }';self.edit(p,before,'host.iptvBrowseHandler.removeCallbacksAndMessages(null)','token mismatch:')

    def test_teardown_order_unchanged(self):
        before='iptvGuideController.iptvUiContextToken++\n        iptvGuideController.iptvBrowseToken++';self.edit(self.source,before,'iptvGuideController.iptvBrowseToken++\n        iptvGuideController.iptvUiContextToken++','token mismatch:')

    def test_receiver_exclusion_cannot_be_omitted(self):
        m=copy.deepcopy(self.manifest);m['receiver_lambda_exclusions'].pop();self.verify(self.current,'receiver-lambda exclusion coverage/classification differs',m)

    def test_receiver_exclusion_cannot_be_activity_classified(self):
        m=copy.deepcopy(self.manifest);m['receiver_lambda_exclusions'][0]['receiver']='activity';self.verify(self.current,'receiver-lambda exclusion coverage/classification differs',m)

    def test_receiver_exclusion_source_context_pinned(self):
        m=copy.deepcopy(self.manifest);m['receiver_lambda_exclusions'][0]['context']='this.index = 0';self.verify(self.current,'receiver-lambda exclusion coverage/classification differs',m)

    def test_entry_owned_this_cannot_be_substituted(self):
        p=self.path('TvIptvZapPager');self.edit(p,'this.index = index','activity.index = index','receiver-lambda expression substituted or binding changed:')

    def test_missing_toast_audit(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee']=='makeText'));self.verify(self.current,'substituted this-site audit coverage differs',m)

    def test_missing_inherited_audit(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee']=='findViewById'));self.verify(self.current,'implicit inherited-receiver audit coverage differs',m)

    def test_earlier_40_destinations_frozen(self):
        self.assertEqual(40,len(self.manifest['earlier_destinations']['paths']));self.assertEqual([],check_earlier(self.manifest,k.ROOT))

    def test_historical_phase10_manifest(self):
        r=subprocess.run(['python3',str(k.ROOT/'dev/tool/check_kotlin_moves.py'),'--manifest',str(k.ROOT/'dev/tool/kotlin_moves/tvplayer_p10.json'),'--at','00c60870e'],text=True,capture_output=True);self.assertEqual(0,r.returncode,r.stdout+r.stderr)

    def test_retained_edit_text_this_is_constructor_argument(self):
        unit = k.parse({'base': self.original})['base']
        constructor = next(site for site in unit['all_this_sites'] if
            site.get('callee') == 'EditText' and self.original.count('\n', 0, site['start']) + 1 == 10001)
        self.assertEqual('activity', constructor['receiver'])
        self.assertNotIn('lambda_receiver', constructor)
        self.assertEqual('this', constructor['text'])
        self.assertIn('EditText(this).apply {', self.current[self.source])

    def test_constructor_cannot_be_forged_as_receiver_lambda_exclusion(self):
        m = copy.deepcopy(self.manifest)
        m['receiver_lambda_exclusions'].append(dict(
            original='class AndroidTvTorrentPlayerActivity/fun showIptvChannelJumpDialog()',
            line=10001, context='val input = EditText(this).apply {', text='this',
            receiver='receiver-lambda', lambda_callee='apply', lambda_receiver='EditText',
            reason='This deliberately false exclusion must be rejected.'))
        self.verify(self.current, 'receiver-lambda exclusion coverage/classification differs', m)

    def test_navigator_entry_this_cannot_be_substituted(self):
        self.edit(self.path('TvIptvChannelNavigator'), 'this.index = index',
            'activity.index = index', 'receiver-lambda expression substituted or binding changed:')

    def test_implicit_entry_index_receiver_cannot_be_activity(self):
        self.edit(self.path('TvIptvChannelNavigator'), 'entry.apply { index = 0 }',
            'entry.apply { activity.index = 0 }', 'token mismatch:')

    def test_shared_fields_have_only_guide_owner(self):
        for name in ('iptvUiContextToken', 'iptvBrowseToken', 'iptvZapRequestToken',
                     'iptvZapOwnsUiContext', 'iptvZapRequestInFlight', 'iptvZapPendingInputs'):
            row = next(r for r in self.manifest['declarations']
                if r['original'].endswith('/property ' + name))
            self.assertTrue(row['destination'].endswith('TvIptvGuideController.kt'))
            self.assertEqual('moved', row['fate'])

    def test_same_name_host_cannot_capture_missed_qualification(self):
        current = dict(self.current)
        guide = self.path('TvIptvGuideController')
        current[guide] = current[guide].replace('    interface Host {',
            '    interface Host {\n        val iptvZapRequestToken: Int')
        pager = self.path('TvIptvZapPager')
        current[pager] = current[pager].replace('guide.iptvZapRequestToken', 'host.iptvZapRequestToken')
        self.verify(current, 'pinned destination:')
        self.verify(current, 'token mismatch:')

    def test_constructor_fixture_pins_original_activity_site(self):
        proof, = self.manifest['constructor_audit_fixtures']
        node = next(n for n in k.walk(k.parse({'original': self.original})['original']['declarations'])
                    if n['id'] == proof['original'])
        self.assertEqual('val input = EditText(this).apply {', proof['context'])
        self.assertEqual(proof['context'], self.original.splitlines()[proof['line'] - 1].strip())
        self.assertIn('EditText(this)', self.original[node['start']:node['end']])
        self.assertEqual('EditText(activity)', proof['after'])
        self.assertEqual('(Landroid/content/Context;)V', proof['expected']['descriptor'])
        self.assertEqual('invokespecial', proof['expected']['opcode'])
        self.assertTrue((k.ROOT / proof['fixture']).is_file())
