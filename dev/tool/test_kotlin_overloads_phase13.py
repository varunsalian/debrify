"""Offline compiled layout getter, listener binding and function-reference audit."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest
import check_kotlin_moves as k
from check_kotlin_overloads import audit, bytecode


class Phase13OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/fixtures/phase13-overloads')
        cls.original=(k.ROOT/'dev/tool/fixtures/kotlin_overloads/phase13.kt').read_text()
        u=k.parse({'base':cls.original})['base']
        cls.node=next(n for n in k.walk(u['declarations']) if n['selector']=='fun exhaust()')
        body=cls.original[cls.node['start']:cls.node['end']]
        text=body.replace('layoutInflater.inflate()', 'activity.layoutInflater.inflate()').replace('observer.', 'activity.observer.').replace('::guideSkinBind','guideSkin::guideSkinBind')
        cls.current={'Controller.kt':'package com.debrify.app.tv\nclass FixtureController(private val activity: androidx.appcompat.app.AppCompatActivity, private val guideSkin: AndroidTvTorrentPlayerActivity) {\n'+text+'\n}\n'}
        row=dict(original=cls.node['id'],fate='moved',destination='Controller.kt',target='class FixtureController/fun exhaust()')
        cls.manifest=dict(phase=13,declarations=[row],overload_audit=[],runnable_receivers=[],context_aliases=[],receiver_lambda_exclusions=[],receiver_lambda_transformations=[],listener_receivers=[],function_references=[])
        site=next(s for s in u['implicit_inherited_sites'] if cls.node['start']<=s['start']<cls.node['end'])
        line=cls.original.count('\n',0,site['start'])+1
        cls.manifest['overload_audit']=[dict(original=row['original'],line=line,context=cls.original.splitlines()[line-1].strip(),callee='getLayoutInflater',call_start_line=line,call_end_line=line,receiver='implicit-inherited',destination=row['destination'],target=row['target'],expected_before=dict(owner='com/debrify/app/tv/AndroidTvTorrentPlayerActivity',descriptor='()Landroid/view/LayoutInflater;',opcode='invokevirtual'),expected_after=dict(owner='androidx/appcompat/app/AppCompatActivity',descriptor='()Landroid/view/LayoutInflater;',opcode='invokevirtual'))]
        site=next(s for s in u['all_this_sites'] if s.get('receiver')=='object')
        line=cls.original.count('\n',0,site['start'])+1
        cls.manifest['listener_receivers']=[dict(original=row['original'],line=line,context=cls.original.splitlines()[line-1].strip(),text='this',object_types=site['object_types'],object_method='onGlobalLayout',callee='removeOnGlobalLayoutListener',reason='The registered listener removes itself.')]
        site=next(s for s in u['callable_references'] if s['callee']=='guideSkinBind')
        line=cls.original.count('\n',0,site['start'])+1
        pin=dict(owner='com/debrify/app/tv/AndroidTvTorrentPlayerActivity',callee='guideSkinBind',descriptor='(I)V',opcode='invokevirtual')
        cls.manifest['function_references']=[dict(original=row['original'],line=line,context=cls.original.splitlines()[line-1].strip(),callee='guideSkinBind',receiver='',after_receiver='guideSkin',expected_before=pin,expected_after=pin)]
        cls.before=cls.compile('original',None)
        cls.after=cls.compile('activity',cls.current['Controller.kt'])
        cls.wrong=dict(cls.current);cls.wrong['Controller.kt']=cls.wrong['Controller.kt'].replace('activity.layoutInflater','android.app.Activity().layoutInflater')
        cls.changed=cls.compile('wrong-getter',cls.wrong['Controller.kt'])
        (cls.folder/'manifest.json').write_text(json.dumps(cls.manifest,indent=2)+'\n')

    @classmethod
    def compile(cls,label,controller):
        folder=cls.folder/label;folder.mkdir(parents=True,exist_ok=True)
        original=cls.original if controller is None else cls.original[:cls.node['start']]+cls.original[cls.node['end']:]
        sources={'Original.kt':original,
            'View.kt':'package android.view\nclass LayoutInflater { fun inflate() {} }\nclass ViewTreeObserver { interface OnGlobalLayoutListener { fun onGlobalLayout() }; val listeners=mutableListOf<OnGlobalLayoutListener>(); fun addOnGlobalLayoutListener(x: OnGlobalLayoutListener) { listeners.add(x); x.onGlobalLayout() }; fun removeOnGlobalLayoutListener(x: OnGlobalLayoutListener) { check(listeners.remove(x)) } }\n',
            'Activity.kt':'package android.app\nopen class Activity { open val layoutInflater: android.view.LayoutInflater get() = android.view.LayoutInflater() }\n',
            'Compat.kt':'package androidx.appcompat.app\nopen class AppCompatActivity: android.app.Activity() { val observer = android.view.ViewTreeObserver(); override val layoutInflater get() = super.layoutInflater }\n',
            'Runner.kt':'package com.debrify.app.tv\nobject Runner { @JvmStatic fun main(args: Array<String>) { val a=AndroidTvTorrentPlayerActivity(); '+('a.exhaust()' if controller is None else 'FixtureController(a,a).exhaust()')+'; check(a.calls == 8) { "getter virtual dispatch lost" }; check(a.observer.listeners.isEmpty()); println("getter, listener self and reference preserved") } }\n'}
        # The observer is inherited in the real activity; keep the fixture inherited too.
        sources['Original.kt']=sources['Original.kt'].replace('    val observer = android.view.ViewTreeObserver()\n','')
        if controller:sources['Controller.kt']=controller
        paths=[]
        for name,text in sources.items():
            p=folder/name;p.write_text(text);paths.append(str(p))
        cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
        jars=[next((cache/g/a/v).glob('*/*.jar')) for g,a,v in [('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.2.20'),('org.jetbrains.kotlin','kotlin-stdlib','2.2.20'),('org.jetbrains.kotlin','kotlin-reflect','2.2.0'),('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.0'),('org.jetbrains','annotations','13.0')]]
        target=folder/'classes';r=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(r.stdout+r.stderr)
        if r.returncode:raise AssertionError(r.stdout+r.stderr)
        flat=folder/'audit-classes';flat.mkdir(exist_ok=True)
        for p in (target/'com/debrify/app/tv').glob('*.class'):
            if p.name.startswith(('AndroidTvTorrentPlayerActivity','FixtureController')):shutil.copy2(p,flat/p.name)
        r=subprocess.run([str(k.JBR/'bin/java'),'-cp',str(target)+':'+str(jars[1]),'com.debrify.app.tv.Runner'],capture_output=True,text=True)
        (folder/'runtime.log').write_text(r.stdout+r.stderr)
        if label=='wrong-getter':
            if r.returncode==0 or 'getter virtual dispatch lost' not in r.stderr:raise AssertionError('getter negative did not fail its assertion')
        elif r.returncode:raise AssertionError(r.stdout+r.stderr)
        return bytecode(flat)

    def test_compiled_positive(self):
        r=audit(self.manifest,self.original,self.current,self.before,self.after)
        self.assertEqual(1,len(r))
        (self.folder/'audit.json').write_text(json.dumps(r,indent=2)+'\n')

    def test_compiled_wrong_getter_receiver(self):
        with self.assertRaisesRegex(ValueError,'implicit inherited dispatch changed'):
            audit(self.manifest,self.original,self.wrong,self.before,self.changed)

    def test_getter_opcode_required(self):
        m=copy.deepcopy(self.manifest);m['overload_audit'][0]['expected_after']['opcode']='invokespecial'
        with self.assertRaisesRegex(ValueError,'pin requires virtual owner/descriptor/opcode'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_listener_omission(self):
        m=copy.deepcopy(self.manifest);m['listener_receivers']=[]
        with self.assertRaisesRegex(ValueError,'typed listener exclusion coverage/binding differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_listener_wrong_dispatch(self):
        m=copy.deepcopy(self.manifest);m['listener_receivers'][0]['callee']='removeCallbacks'
        with self.assertRaisesRegex(ValueError,'typed listener exclusion coverage/binding differs'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_listener_substitution(self):
        current={p:s.replace('removeOnGlobalLayoutListener(this)','removeOnGlobalLayoutListener(activity)') for p,s in self.current.items()}
        with self.assertRaisesRegex(ValueError,'typed listener expression substituted or binding changed'):
            audit(self.manifest,self.original,current,self.before,self.after)

    def test_function_reference_dispatch_pin(self):
        m=copy.deepcopy(self.manifest);m['function_references'][0]['expected_after']['callee']='otherBind'
        with self.assertRaisesRegex(ValueError,'compiled function-reference dispatch changed'):
            audit(m,self.original,self.current,self.before,self.after)

    def test_unreviewed_object_still_rejected(self):
        original=self.original.replace('android.view.ViewTreeObserver.OnGlobalLayoutListener','Runnable').replace('override fun onGlobalLayout()', 'override fun run()')
        # Runnable is separately reviewed and cannot masquerade as a listener.
        with self.assertRaisesRegex(ValueError,'typed listener exclusion coverage/binding differs'):
            audit(self.manifest,original,self.current,self.before,self.after)

    def test_other_unreviewed_object_receiver_rejected(self):
        original=self.original.replace('android.view.ViewTreeObserver.OnGlobalLayoutListener','UnreviewedListener')
        with self.assertRaisesRegex(ValueError,'wrong receiver classification: unreviewed object this'):
            audit(self.manifest,original,self.current,self.before,self.after)
