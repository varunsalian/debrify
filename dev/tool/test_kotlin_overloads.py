#!/usr/bin/env python3
"""Small javap-parser tests; real compiled positive/negative evidence is external."""
import unittest

from check_kotlin_overloads import invocations, resolve


class KotlinOverloadsTest(unittest.TestCase):
    def test_method_local_line_tables_and_constructor_descriptors(self):
        text = '''public final class Example {
  private final void show();
    descriptor: ()V
    Code:
       0: invokestatic #1 // Method com/bumptech/glide/Glide.with:(Landroidx/fragment/app/FragmentActivity;)Lcom/bumptech/glide/RequestManager;
    LineNumberTable:
      line 41: 0
  public Example();
    descriptor: ()V
    Code:
       0: invokespecial #2 // Method android/content/Intent."<init>":(Landroid/content/Context;Ljava/lang/Class;)V
    LineNumberTable:
      line 52: 0
}'''
        calls = invocations(text)
        self.assertEqual([41, 52], [x['line'] for x in calls])
        self.assertIn('FragmentActivity', resolve(calls, {'callee': 'with'}, 41, 41)[0])
        self.assertIn('Intent.<init>', resolve(calls, {'callee': 'Intent'}, 52, 52)[0])

    def test_missing_call_is_not_accepted(self):
        with self.assertRaisesRegex(ValueError, 'resolve uniquely'):
            resolve([], {'callee': 'with'}, 41, 41)

    def test_ambiguous_overloads_are_not_accepted(self):
        calls = [dict(line=41, call='Glide.with:(' + argument + ')V')
                 for argument in ('Landroid/content/Context;', 'Landroid/app/Activity;')]
        with self.assertRaisesRegex(ValueError, 'resolve uniquely'):
            resolve(calls, {'callee': 'with'}, 41, 41)

    def test_context_free_overload_is_not_accepted(self):
        with self.assertRaisesRegex(ValueError, 'resolve uniquely'):
            resolve([dict(line=41, call='Glide.with:(Ljava/lang/String;)V')], {'callee': 'with'}, 41, 41)


if __name__ == '__main__':
    unittest.main(verbosity=2)
