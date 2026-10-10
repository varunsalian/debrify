"""Two entry-lambda exclusions and the Activity EditText constructor argument."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest
import check_kotlin_moves as k
from kotlin_toolchain import kotlin_jars
from check_kotlin_overloads import audit, bytecode

class Phase11OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase11-overloads')
        cls.original = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase11.kt').read_text()
        unit = k.parse({'original': cls.original})['original']
        node = next(n for n in k.walk(unit['declarations']) if n['id'].endswith('/fun receivers()'))
        body = cls.original[node['start']:node['end']]
        cls.current = {'Controller.kt': 'package com.debrify.app.tv\nimport androidx.appcompat.app.AppCompatActivity\nimport android.widget.EditText\nclass FixtureController(private val activity: AppCompatActivity) {\n' + body.replace('EditText(this)', 'EditText(activity)') + '\n}\n'}
        cls.manifest = dict(phase=11, declarations=[dict(original=node['id'],fate='moved',destination='Controller.kt',target='class FixtureController/fun receivers()')], overload_audit=[],runnable_receivers=[],context_aliases=[],receiver_lambda_exclusions=[])
        for site in unit['all_this_sites']:
            line = cls.original.count('\n',0,site['start']) + 1
            common = dict(original=node['id'],line=line,context=cls.original.splitlines()[line-1].strip())
            if 'lambda_receiver' in site:
                cls.manifest['receiver_lambda_exclusions'].append(dict(**common,text=site['text'],receiver='receiver-lambda',lambda_callee=site['lambda_callee'],lambda_receiver=site['lambda_receiver'],reason='Entry-owned this.index must retain its apply receiver.'))
            else:
                cls.manifest['overload_audit'].append(dict(**common,callee='EditText',call_start_line=cls.original.count('\n',0,site['call_start'])+1,call_end_line=cls.original.count('\n',0,site['call_end'])+1,destination='Controller.kt',target='class FixtureController/fun receivers()',expected_before=dict(owner='android/widget/EditText',descriptor='(Landroid/content/Context;)V',opcode='invokespecial'),expected_after=dict(owner='android/widget/EditText',descriptor='(Landroid/content/Context;)V',opcode='invokespecial')))
        cls.before = cls.compile('original',None)
        cls.after = cls.compile('activity',cls.current['Controller.kt'])
        cls.wrong = {'Controller.kt': cls.current['Controller.kt'].replace('EditText(activity)','EditText(activity, 3)')}
        cls.changed = cls.compile('other-constructor',cls.wrong['Controller.kt'])
        (cls.folder/'manifest.json').write_text(json.dumps(cls.manifest,indent=2)+'\n')

    @classmethod
    def compile(cls,label,controller):
        folder=cls.folder/label;folder.mkdir(parents=True,exist_ok=True)
        original=cls.original
        if controller is not None:
            node=next(n for n in k.walk(k.parse({'o':original})['o']['declarations']) if n['id'].endswith('/fun receivers()'))
            original=original[:node['start']]+original[node['end']:]
        sources={'Original.kt':original,'Context.kt':'package android.content\nopen class Context\n',
            'Activity.kt':'package androidx.appcompat.app\nopen class AppCompatActivity : android.content.Context()\n',
            'EditText.kt':'package android.widget\nclass EditText(val context: android.content.Context) { var inputType = 0; constructor(context: android.content.Context, style: Int) : this(context) }\n',
            'Runner.kt':'package com.debrify.app.tv\nobject Runner { @JvmStatic fun main(args: Array<String>) { val activity = AndroidTvTorrentPlayerActivity(); '+('activity.receivers()' if controller is None else 'FixtureController(activity).receivers()')+'; println("entry receivers and constructor preserved") } }\n'}
        if controller is not None:sources['Controller.kt']=controller
        paths=[]
        for name,text in sources.items():p=folder/name;p.write_text(text);paths.append(str(p))
        jars = kotlin_jars()
        target=folder/'classes';result=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:raise AssertionError(result.stdout+result.stderr)
        flat=folder/'audit-classes';flat.mkdir(exist_ok=True)
        for p in (target/'com/debrify/app/tv').glob('*.class'):
            if p.name.startswith(('AndroidTvTorrentPlayerActivity','FixtureController')):shutil.copy2(p,flat/p.name)
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',str(target)+':'+str(jars[1]),'com.debrify.app.tv.Runner'],capture_output=True,text=True)
        (folder/'runtime.log').write_text(result.stdout+result.stderr)
        if result.returncode:raise AssertionError(result.stdout+result.stderr)
        return bytecode(flat)

    def test_compiled_two_entry_receivers_and_activity_constructor(self):
        self.assertEqual(2,len(self.manifest['receiver_lambda_exclusions']))
        result=audit(self.manifest,self.original,self.current,self.before,self.after)
        self.assertEqual(1,len(result));(self.folder/'audit.json').write_text(json.dumps(result,indent=2)+'\n')

    def test_changed_constructor_rejected(self):
        with self.assertRaisesRegex(ValueError,'argument receiver dispatch changed'):
            audit(self.manifest,self.original,self.wrong,self.before,self.changed)

    def test_omitted_entry_receiver_rejected(self):
        m=copy.deepcopy(self.manifest);m['receiver_lambda_exclusions'].pop()
        with self.assertRaisesRegex(ValueError,'receiver-lambda exclusion coverage/classification differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_constructor_exclusion_rejected(self):
        m=copy.deepcopy(self.manifest);m['receiver_lambda_exclusions'].append(dict(m['receiver_lambda_exclusions'][0],context='val input = EditText(this).apply {',line=12))
        with self.assertRaisesRegex(ValueError,'receiver-lambda exclusion coverage/classification differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_constructor_audit_required(self):
        m=copy.deepcopy(self.manifest);m['overload_audit']=[]
        with self.assertRaisesRegex(ValueError,'substituted this-site audit coverage differs'):
            audit(m,self.original,self.current,self.before,self.after)
