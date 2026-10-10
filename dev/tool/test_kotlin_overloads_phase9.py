"""Compiled virtual/inherited receiver pins; old argument audits remain intact."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_toolchain import kotlin_jars
from check_kotlin_overloads import audit, bytecode


class Phase9OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase9-overloads')
        cls.original = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase9.kt').read_text()
        unit = k.parse({'base': cls.original})['base']
        node = next(n for n in k.walk(unit['declarations']) if n['id'].endswith('/fun exhaust()'))
        body = cls.original[node['start']:node['end']]
        cls.current = {'Controller.kt': 'package com.debrify.app.tv\nimport androidx.appcompat.app.AppCompatActivity\n'
            'import android.view.View\nimport android.widget.TextView\n'
            'class FixtureController(private val activity: AppCompatActivity) {\n' + body.replace('findViewById', 'activity.findViewById').replace('        finish()', '        activity.finish()') + '\n}\n'}
        cls.manifest = dict(phase=9, declarations=[dict(original=node['id'], fate='moved',
            destination='Controller.kt', target='class FixtureController/fun exhaust()')],
            overload_audit=[], runnable_receivers=[], context_aliases=[])
        for site in unit['implicit_inherited_sites']:
            if not node['start'] <= site['start'] < node['end']: continue
            line = cls.original.count('\n', 0, site['start']) + 1
            descriptor = '()V' if site['callee'] == 'finish' else '(I)Landroid/view/View;'
            cls.manifest['overload_audit'].append(dict(original=node['id'], line=line,
                context=cls.original.splitlines()[line-1].strip(), callee=site['callee'],
                call_start_line=cls.original.count('\n',0,site['call_start'])+1,
                call_end_line=cls.original.count('\n',0,site['call_end'])+1,
                receiver='implicit-inherited', destination='Controller.kt', target='class FixtureController/fun exhaust()',
                expected_before=dict(owner='com/debrify/app/tv/AndroidTvTorrentPlayerActivity',descriptor=descriptor,opcode='invokevirtual'),
                expected_after=dict(owner='androidx/appcompat/app/AppCompatActivity',descriptor=descriptor,opcode='invokevirtual')))
        cls.before = cls.compile('original', None)
        cls.after = cls.compile('virtual', cls.current['Controller.kt'])
        cls.super_current = {'Controller.kt': cls.current['Controller.kt'].replace('activity: AppCompatActivity) {',
            'activity: AppCompatActivity) : AppCompatActivity() {').replace('activity.finish()', 'super.finish()')}
        cls.super_calls = cls.compile('super', cls.super_current['Controller.kt'])
        cls.static_current = {'Controller.kt': cls.current['Controller.kt'].replace('activity.finish()', 'StaticFinish.finish(activity)')}
        cls.static_calls = cls.compile('static', cls.static_current['Controller.kt'])
        cls.wide_current = {'Controller.kt': cls.current['Controller.kt'].replace('activity: AppCompatActivity', 'activity: android.app.Activity')}
        cls.wide_calls = cls.compile('wide', cls.wide_current['Controller.kt'])
        (cls.folder/'manifest.json').write_text(json.dumps(cls.manifest,indent=2)+'\n')

    @classmethod
    def compile(cls, label, controller):
        folder = cls.folder/label; folder.mkdir(parents=True,exist_ok=True)
        original = cls.original
        if controller is not None:
            unit = k.parse({'base':original})['base']
            node = next(n for n in k.walk(unit['declarations']) if n['id'].endswith('/fun exhaust()'))
            original = original[:node['start']]+original[node['end']:]
        sources = {'Original.kt':original,
            'View.kt':'package android.view\nopen class View\n',
            'TextView.kt':'package android.widget\nclass TextView : android.view.View()\n',
            'Activity.kt':'package android.app\nopen class Activity { var baseFinishes=0; open fun finish() { baseFinishes++ }; open fun <T: android.view.View> findViewById(id: Int): T = android.widget.TextView() as T }\n',
            'AppCompatActivity.kt':'package androidx.appcompat.app\nopen class AppCompatActivity : android.app.Activity() { override fun <T: android.view.View> findViewById(id: Int): T = super.findViewById(id) }\n',
            'StaticFinish.kt':'package com.debrify.app.tv\nobject StaticFinish { @JvmStatic fun finish(activity: androidx.appcompat.app.AppCompatActivity) { activity.finish() } }\n',
            'Runner.kt':'package com.debrify.app.tv\nobject Runner { @JvmStatic fun main(args: Array<String>) { val activity=AndroidTvTorrentPlayerActivity(); '+('activity.exhaust()' if controller is None else 'FixtureController(activity).exhaust()')+'; check(activity.overrideFinishes==1 && activity.baseFinishes==1) { "activity override dispatch lost" }; println("override dispatch preserved") } }\n'}
        if controller is not None:sources['Controller.kt']=controller
        paths=[]
        for name,text in sources.items():p=folder/name;p.write_text(text);paths.append(str(p))
        jars = kotlin_jars()
        target=folder/'classes'
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
            '-no-stdlib','-no-reflect','-classpath',':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:raise AssertionError(result.stdout+result.stderr)
        flat=folder/'audit-classes';flat.mkdir(exist_ok=True)
        for p in (target/'com/debrify/app/tv').glob('*.class'):
            if p.name.startswith(('AndroidTvTorrentPlayerActivity','FixtureController')):shutil.copy2(p,flat/p.name)
        run=subprocess.run([str(k.JBR/'bin/java'),'-cp',str(target)+':'+str(jars[1]),'com.debrify.app.tv.Runner'],capture_output=True,text=True)
        (folder/'runtime.log').write_text(run.stdout+run.stderr)
        if label=='super':
            if run.returncode==0 or 'activity override dispatch lost' not in run.stderr:raise AssertionError('super negative did not bypass override')
        elif run.returncode:raise AssertionError(run.stdout+run.stderr)
        return bytecode(flat)

    def test_compiled_virtual_override_and_three_inherited_calls(self):
        results=audit(self.manifest,self.original,self.current,self.before,self.after)
        self.assertEqual(4,len(results));self.assertTrue(all(r['resolved_after']['opcode']=='invokevirtual' for r in results))
        (self.folder/'audit.json').write_text(json.dumps(results,indent=2)+'\n')

    def test_compiled_super_finish_rejected(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.super_current,self.before,self.super_calls)

    def test_compiled_static_finish_rejected(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.static_current,self.before,self.static_calls)

    def test_compiled_widened_receiver_owner_rejected(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.wide_current,self.before,self.wide_calls)

    def test_missing_implicit_receiver_site_rejected(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'].pop()
        with self.assertRaisesRegex(ValueError,'implicit inherited-receiver audit coverage differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_opcode_pin_cannot_be_omitted(self):
        m=copy.deepcopy(self.manifest);del m['overload_audit'][-1]['expected_after']['opcode']
        with self.assertRaisesRegex(ValueError,'pin requires virtual owner/descriptor/opcode'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_nonvirtual_pin_cannot_authorize_super(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'][-1]['expected_after']['opcode']='invokespecial'
        with self.assertRaisesRegex(ValueError,'pin requires virtual owner/descriptor/opcode'):
            audit(m,self.original,self.super_current,self.before,self.super_calls)

    def test_psi_excludes_explicit_super_and_other_receivers(self):
        source=self.original.replace('        finish()', '        super.finish(); this.finish()')
        unit=k.parse({'changed':source})['changed']
        self.assertEqual(3,len(unit['implicit_inherited_sites']))
