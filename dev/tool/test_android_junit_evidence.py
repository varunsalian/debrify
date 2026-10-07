import copy
from pathlib import Path
import tempfile
import unittest

from android_junit_evidence import compare, identities


class EvidenceTest(unittest.TestCase):
    def setUp(self):
        self.baseline = {'meta': {'count': 2, 'gradle_exit': 1},
                         'tests': {'A::a': 'pass', 'A::b': 'failure'}}

    def test_reference_format_and_additions(self):
        current = copy.deepcopy(self.baseline)
        current['tests']['B::new'] = 'pass'
        current['meta']['count'] = 3
        self.assertEqual([], compare(current, self.baseline))

    def test_each_gate_rejects_its_failure(self):
        changes = [({'A::a': 'failure', 'A::b': 'failure'}, {}, 'new failure'),
                   ({'A::a': 'error', 'A::b': 'failure'}, {}, 'new error'),
                   ({'A::a': 'skipped', 'A::b': 'failure'}, {}, 'new skip'),
                   ({'A::a': 'pass'}, {'count': 1}, 'missing identity'),
                   ({}, {'count': 0}, 'no/partial XML'),
                   (None, {'count': 3}, 'no/partial XML'),
                   (None, {'tree_changed': True}, 'tree changed'),
                   (None, {'aborted': True}, 'Gradle aborted'),
                   ({'A::a': 'pass', 'A::b': 'pass'}, {}, 'without test failures')]
        for tests, meta, reason in changes:
            with self.subTest(reason=reason):
                current = copy.deepcopy(self.baseline)
                if tests is not None:
                    current['tests'] = tests
                current['meta'].update(meta)
                self.assertTrue(any(reason in e for e in compare(current, self.baseline)))

    def test_raw_xml_missing_partial_duplicate_and_statuses(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaisesRegex(ValueError, 'no XML'):
                identities(path)
            xml = path / 'TEST-A.xml'
            xml.write_text('<testsuite tests="4"><testcase classname="A" name="a"/><testcase classname="A" name="b"><failure/></testcase><testcase classname="A" name="c"><error/></testcase><testcase classname="A" name="d"><skipped/></testcase></testsuite>')
            self.assertEqual({'A::a': 'pass', 'A::b': 'failure', 'A::c': 'error', 'A::d': 'skipped'}, identities(path))
            xml.write_text('<testsuite tests="2"><testcase classname="A" name="a"/></testsuite>')
            with self.assertRaisesRegex(ValueError, 'partial XML'):
                identities(path)
            xml.write_text('<testsuite tests="2"><testcase classname="A" name="a"/><testcase classname="A" name="a"/></testsuite>')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                identities(path)


if __name__ == '__main__':
    unittest.main()
