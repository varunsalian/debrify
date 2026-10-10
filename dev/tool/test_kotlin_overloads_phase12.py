"""Compiled constructor receiver, resource and focus getters for phase 12."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_toolchain import kotlin_jars
from check_kotlin_overloads import audit, bytecode


class Phase12OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase12-overloads')
        cls.original = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase12.kt').read_text()
        unit = k.parse({'original': cls.original})['original']
        cls.node = next(n for n in k.walk(unit['declarations']) if n['id'].endswith('/fun exhaust()'))
        body = cls.original[cls.node['start']:cls.node['end']]
        cls.current = {'Controller.kt': 'package com.debrify.app.tv\nimport androidx.appcompat.app.AppCompatActivity\nimport android.widget.EditText\nimport androidx.core.widget.TextViewCompat\nclass FixtureController(private val activity: AppCompatActivity) {\n' + body.replace('EditText(this)', 'EditText(activity)').replace('resources.heightPixels', 'activity.resources.heightPixels').replace('= currentFocus', '= activity.currentFocus') + '\n}\n'}
        cls.manifest = dict(phase=12, declarations=[dict(original=cls.node['id'], fate='moved', destination='Controller.kt', target='class FixtureController/fun exhaust()')], overload_audit=[], runnable_receivers=[], context_aliases=[], receiver_lambda_exclusions=[], receiver_lambda_transformations=[])
        for site in unit['all_this_sites']:
            if not cls.node['start'] <= site['start'] < cls.node['end']: continue
            line = cls.original.count('\n', 0, site['start']) + 1
            common = dict(original=cls.node['id'], line=line, context=cls.original.splitlines()[line-1].strip())
            if 'lambda_receiver' in site:
                cls.manifest['receiver_lambda_exclusions'].append(dict(**common, text=site['text'], receiver='receiver-lambda', lambda_callee=site['lambda_callee'], lambda_receiver=site['lambda_receiver'], reason='The tint receiver remains the constructed EditText.'))
                constructor_line = cls.original.count('\n', 0, site['lambda_receiver_start']) + 1
                cls.manifest['receiver_lambda_transformations'].append(dict(original=cls.node['id'], line=line, constructor_line=constructor_line, context=cls.original.splitlines()[constructor_line-1].strip(), before='EditText(this)', after='EditText(activity)', callee='EditText', reason='Only the enclosing constructor Activity argument moves.'))
            else:
                cls.manifest['overload_audit'].append(dict(**common, callee='EditText', call_start_line=cls.original.count('\n',0,site['call_start'])+1, call_end_line=cls.original.count('\n',0,site['call_end'])+1, destination='Controller.kt', target='class FixtureController/fun exhaust()', expected_before=dict(owner='android/widget/EditText', descriptor='(Landroid/content/Context;)V', opcode='invokespecial'), expected_after=dict(owner='android/widget/EditText', descriptor='(Landroid/content/Context;)V', opcode='invokespecial')))
        for site in unit['implicit_inherited_sites']:
            if not cls.node['start'] <= site['start'] < cls.node['end']: continue
            line = cls.original.count('\n',0,site['start'])+1
            descriptor = {'getResources':'()Landroid/content/res/Resources;', 'getCurrentFocus':'()Landroid/view/View;'}[site['callee']]
            cls.manifest['overload_audit'].append(dict(original=cls.node['id'], line=line, context=cls.original.splitlines()[line-1].strip(), callee=site['callee'], call_start_line=line, call_end_line=line, receiver='implicit-inherited', destination='Controller.kt', target='class FixtureController/fun exhaust()', expected_before=dict(owner='com/debrify/app/tv/AndroidTvTorrentPlayerActivity', descriptor=descriptor, opcode='invokevirtual'), expected_after=dict(owner='androidx/appcompat/app/AppCompatActivity', descriptor=descriptor, opcode='invokevirtual')))
        cls.before = cls.compile('original', None)
        cls.after = cls.compile('activity', cls.current['Controller.kt'])
        cls.wrong = {'Controller.kt': cls.current['Controller.kt'].replace('activity.resources', 'android.content.Context().resources')}
        cls.changed = cls.compile('wrong-resources', cls.wrong['Controller.kt'])
        cls.wrong_focus = {'Controller.kt': cls.current['Controller.kt'].replace('activity.currentFocus', '(activity as android.app.Activity).currentFocus')}
        cls.changed_focus = cls.compile('widened-focus', cls.wrong_focus['Controller.kt'])
        (cls.folder/'manifest.json').write_text(json.dumps(cls.manifest,indent=2)+'\n')

    @classmethod
    def compile(cls, label, controller):
        folder = cls.folder/label; folder.mkdir(parents=True,exist_ok=True)
        original = cls.original
        if controller is not None:
            original = original[:cls.node['start']] + original[cls.node['end']:]
        sources = {'Original.kt':original,
            'Resources.kt':'package android.content.res\nclass Resources { val heightPixels = 42 }\n',
            'View.kt':'package android.view\nopen class View\n',
            'Context.kt':'package android.content\nopen class Context { open val resources: android.content.res.Resources get() = android.content.res.Resources() }\n',
            'BaseActivity.kt':'package android.app\nopen class Activity : android.content.Context() { open val currentFocus: android.view.View? get() = android.view.View() }\n',
            'Activity.kt':'package androidx.appcompat.app\nopen class AppCompatActivity : android.app.Activity() { override val resources: android.content.res.Resources get() = super.resources; override val currentFocus: android.view.View? get() = super.currentFocus }\n',
            'EditText.kt':'package android.widget\nclass EditText(val context: android.content.Context) : android.view.View()\n',
            'TextViewCompat.kt':'package androidx.core.widget\nobject TextViewCompat { var last: android.widget.EditText? = null; @JvmStatic fun setCompoundDrawableTintList(view: android.widget.EditText, tint: Int) { last = view } }\n',
            'Runner.kt':'package com.debrify.app.tv\nobject Runner { @JvmStatic fun main(args: Array<String>) { val activity=AndroidTvTorrentPlayerActivity(); '+('activity.exhaust()' if controller is None else 'FixtureController(activity).exhaust()')+'; check(activity.resourceReads==1 && activity.focusReads==1) { "activity getter dispatch lost" }; check(androidx.core.widget.TextViewCompat.last!!.context === activity) { "constructor activity lost" }; println("constructor and virtual getter dispatch preserved") } }\n'}
        if controller is not None: sources['Controller.kt']=controller
        paths=[]
        for name,text in sources.items():
            p=folder/name; p.write_text(text); paths.append(str(p))
        jars = kotlin_jars()
        target=folder/'classes'
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode: raise AssertionError(result.stdout+result.stderr)
        flat=folder/'audit-classes'; flat.mkdir(exist_ok=True)
        for p in (target/'com/debrify/app/tv').glob('*.class'):
            if p.name.startswith(('AndroidTvTorrentPlayerActivity','FixtureController')): shutil.copy2(p,flat/p.name)
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',str(target)+':'+str(jars[1]),'com.debrify.app.tv.Runner'],capture_output=True,text=True)
        (folder/'runtime.log').write_text(result.stdout+result.stderr)
        if label.startswith('wrong-'):
            if result.returncode==0 or 'activity getter dispatch lost' not in result.stderr: raise AssertionError('wrong receiver did not lose the activity override')
        elif result.returncode: raise AssertionError(result.stdout+result.stderr)
        return bytecode(flat)

    def test_compiled_constructor_and_getter_dispatch(self):
        result=audit(self.manifest,self.original,self.current,self.before,self.after)
        self.assertEqual(3,len(result)); (self.folder/'audit.json').write_text(json.dumps(result,indent=2)+'\n')

    def test_compiled_wrong_resource_receiver_rejected(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.wrong,self.before,self.changed)

    def test_compiled_wrong_focus_receiver_rejected(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.wrong_focus,self.before,self.changed_focus)

    def test_each_getter_audit_required(self):
        for callee in ('getResources','getCurrentFocus'):
            with self.subTest(callee=callee):
                m=copy.deepcopy(self.manifest); m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee']==callee))
                with self.assertRaisesRegex(ValueError,'implicit inherited-receiver audit coverage differs'):
                    audit(m,self.original,self.current,self.before,self.after)

    def test_getter_virtual_opcode_pin_required(self):
        m=copy.deepcopy(self.manifest); next(r for r in m['overload_audit'] if r['callee']=='getResources')['expected_after']['opcode']='invokespecial'
        with self.assertRaisesRegex(ValueError,'pin requires virtual owner/descriptor/opcode'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_constructor_transform_required(self):
        m=copy.deepcopy(self.manifest); m['receiver_lambda_transformations']=[]
        with self.assertRaisesRegex(ValueError,'constructor-receiver transformation coverage differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_constructor_pin_required(self):
        m=copy.deepcopy(self.manifest); m['overload_audit'].remove(next(r for r in m['overload_audit'] if r['callee']=='EditText'))
        with self.assertRaisesRegex(ValueError,'constructor-receiver transformation requires pinned constructor audit'):
            audit(m,self.original,self.current,self.before,self.after)
