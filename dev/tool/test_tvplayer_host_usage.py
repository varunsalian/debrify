"""Real Kotlin controls for setter-only usage and default-helper reachability."""
from pathlib import Path
import unittest

import check_kotlin_moves as k
from check_tvplayer_host_usage import audit, compiled_methods, host_members
import test_kotlin_overloads_phase19 as fixtures


SOURCE = '''package com.debrify.app.tv
class TvUsageController(private val host: Host) {
    interface Host {
        var speechTap: Any?
        var offsetRenderersFactory: Any?
        var iptvNetworkCallback: Any?
        fun send(value: String = "default")
    }
    fun productionCaller() {
        host.speechTap = null
        host.offsetRenderersFactory = null
        host.iptvNetworkCallback = null
        host.send()
    }
}
'''


class HostUsageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        evidence = k.evidence_root(k.ROOT) / 'p20/host-selftests'
        k.evidence_root = lambda root: evidence / 'psi-root'
        cls.folder = evidence

    def compile(self, label, source):
        fixtures.Phase19OverloadsTest.folder = self.folder
        folder, _ = fixtures.Phase19OverloadsTest.compile(label, source)
        return host_members({'fixture': source}), compiled_methods(folder)

    def test_setter_only_properties_are_used(self):
        members, methods = self.compile('positive', SOURCE)
        result = audit(members, methods)
        self.assertEqual(4, len(result))
        for row in result[:3]:
            self.assertEqual(1, len(row['used']))
            self.assertTrue(row['used'][0][1].startswith('set'))

    def test_default_call_traces_to_production_caller(self):
        members, methods = self.compile('default-positive', SOURCE)
        row = audit(members, methods)[-1]
        self.assertEqual('productionCaller', row['caller_paths'][0][0][1])
        self.assertTrue(any(key[1] == 'send$default' for key in row['caller_paths'][0]))

    def test_removed_caller_does_not_credit_generated_default_helper(self):
        source = SOURCE.replace('        host.send()\n', '')
        members, methods = self.compile('removed-caller', source)
        self.assertTrue(any(key[1] == 'send$default' for key in methods))
        with self.assertRaisesRegex(ValueError, 'unused Host member: .*fun send'):
            audit(members, methods)


if __name__ == '__main__':
    unittest.main(verbosity=2)
