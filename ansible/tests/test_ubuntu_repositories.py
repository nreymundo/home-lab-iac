"""Exercise the repository helper with real python-apt and isolated sources."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / 'roles/host_hardware/files/enable_ubuntu_components.py'


@unittest.skipUnless(Path('/usr/lib/python3/dist-packages/aptsources').exists(), 'Requires system python3-apt')
class UbuntuRepositoryTests(unittest.TestCase):
    def exercise(self, components, legacy=False, grouped=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parts = root / 'sources.list.d'
            parts.mkdir()
            (root / 'apt.conf.d').mkdir()
            config = root / 'apt.conf'
            config.write_text(
                f'Dir::Etc::sourcelist "{root}/sources.list";\n'
                f'Dir::Etc::sourceparts "{parts}";\n'
                f'Dir::Etc::parts "{root}/apt.conf.d";\n'
                f'Dir::Etc::main "{root}/unused.conf";\n'
            )
            source = root / 'sources.list' if legacy else parts / 'ubuntu.sources'
            suites = ['noble', 'noble-updates', 'noble-backports', 'noble-security']
            mirrors = {
                suite: 'http://security.ubuntu.com/ubuntu/' if suite.endswith('-security')
                else 'http://de.archive.ubuntu.com/ubuntu/' for suite in suites
            }
            if legacy:
                source.write_text(''.join(
                    f'deb {mirrors[suite]} {suite} {components}\n'
                    for suite in suites
                ))
            elif grouped:
                source.write_text(
                    f'Types: deb deb-src\nURIs: {mirrors["noble"]}\n'
                    f'Suites: noble noble-updates noble-backports\nComponents: {components}\n'
                    'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\n'
                    f'Types: deb\nURIs: {mirrors["noble-security"]}\n'
                    f'Suites: noble-security\nComponents: {components}\n'
                    'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n'
                )
            else:
                source.write_text(''.join(
                    f'Types: deb\nURIs: {mirrors[suite]}\n'
                    f'Suites: {suite}\nComponents: {components}\n'
                    'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\n'
                    for suite in suites
                ))
            third_party = parts / 'vendor.list'
            third_party.write_text('deb https://vendor.invalid/ubuntu stable main\n')
            disabled = parts / 'disabled.sources'
            disabled.write_text('Enabled: no\nTypes: deb\nURIs: http://archive.ubuntu.com/ubuntu/\nSuites: noble\nComponents: main\n')
            before_other = (third_party.read_bytes(), disabled.read_bytes())
            before_source = source.read_bytes()
            runner = HELPER.read_text()
            env = {**os.environ, 'APT_CONFIG': str(config), 'LC_ALL': 'C'}
            def apply():
                before = {p: p.read_bytes() for p in parts.iterdir()}
                source_before_probe = source.read_bytes()
                probe = subprocess.run(['/usr/bin/python3', '-c', runner, '--check'], env=env,
                                       capture_output=True, text=True, check=True)
                self.assertEqual(before, {p: p.read_bytes() for p in parts.iterdir()})
                self.assertEqual(source_before_probe, source.read_bytes())
                if json.loads(probe.stdout)['changed']:
                    return subprocess.run(['/usr/bin/python3', '-c', runner], env=env,
                                          capture_output=True, text=True, check=True)
                return probe
            first = apply()
            self.assertEqual(json.loads(first.stdout)['changed'], not {'universe', 'multiverse'} <= set(components.split()))
            if not json.loads(first.stdout)['changed']:
                self.assertEqual(source.read_bytes(), before_source)
            if not legacy:
                self.assertIn('Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg', source.read_text())
            second = apply()
            self.assertFalse(json.loads(second.stdout)['changed'])
            self.assertEqual(before_other, (third_party.read_bytes(), disabled.read_bytes()))
            # Ask APT's own parser for the effective repository index targets.
            inspect = (
                'import apt_pkg,json; from aptsources.sourceslist import SourcesList; '
                'apt_pkg.init(); sources=SourcesList(deb822=True); '
                'print(json.dumps([(s.uri,s.dist,list(s.comps)) '
                'for s in sources.exploded_list() '
                'if not s.invalid and not s.disabled and s.type == "deb" and ".ubuntu.com/" in s.uri]))'
            )
            result = subprocess.run(['/usr/bin/python3', '-c', inspect], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = json.loads(result.stdout)
            for suite in suites:
                selected = [comps for uri, dist, comps in entries if dist == suite and uri == mirrors[suite]]
                flattened = [component for comps in selected for component in comps]
                for component in ['main', 'restricted', 'universe', 'multiverse']:
                    self.assertEqual(flattened.count(component), 1, (suite, entries))

    def test_deb822_components_already_enabled(self):
        self.exercise('main restricted universe multiverse')

    def test_deb822_one_component_missing(self):
        self.exercise('main restricted universe')

    def test_deb822_both_components_missing(self):
        self.exercise('main restricted')

    def test_legacy_sources_components_missing(self):
        self.exercise('main restricted', legacy=True)

    def test_deb822_grouped_suites_and_types(self):
        self.exercise('main restricted', grouped=True)


if __name__ == '__main__':
    unittest.main()
