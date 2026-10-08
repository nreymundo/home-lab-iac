"""Exercise Ubuntu's real source editor against isolated APT configuration."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


@unittest.skipUnless(Path('/usr/bin/add-apt-repository').exists(), 'Requires Ubuntu software-properties-common')
class UbuntuRepositoryTests(unittest.TestCase):
    def exercise(self, components, legacy=False):
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
            # Bypass only the CLI's root check. All file IO targets temporary
            # sources; this grants no OS privileges and --no-update avoids APT IO.
            runner = (
                'import os,runpy,sys; os.geteuid=lambda:0; '
                'sys.argv=["/usr/bin/add-apt-repository",*sys.argv[1:],"--yes","--no-update",'
                '"--component","universe","--component","multiverse"]; '
                'runpy.run_path(sys.argv[0],run_name="__main__")'
            )
            env = {**os.environ, 'APT_CONFIG': str(config), 'LC_ALL': 'C'}
            def apply():
                before = {p: p.read_bytes() for p in parts.iterdir()}
                probe = subprocess.run(['/usr/bin/python3', '-c', runner, '--dry-run'], env=env,
                                       capture_output=True, text=True, check=True)
                self.assertEqual(before, {p: p.read_bytes() for p in parts.iterdir()})
                if 'Added ' in probe.stdout:
                    return subprocess.run(['/usr/bin/python3', '-c', runner], env=env,
                                          capture_output=True, text=True, check=True)
                return probe
            first = apply()
            self.assertEqual('Added ' in first.stdout, not {'universe', 'multiverse'} <= set(components.split()))
            if 'Added ' not in first.stdout:
                self.assertEqual(source.read_bytes(), before_source)
            if not legacy:
                self.assertIn('Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg', source.read_text())
            second = apply()
            self.assertNotIn('Added ', second.stdout)
            self.assertEqual(before_other, (third_party.read_bytes(), disabled.read_bytes()))
            # Ask APT's own parser for the effective repository index targets.
            inspect = (
                'import apt_pkg,json; from aptsources.sourceslist import SourcesList; '
                'apt_pkg.init(); sources=SourcesList(deb822=True); '
                'print(json.dumps([(s.uri,s.dist,list(s.comps)) '
                'for s in sources.exploded_list() '
                'if not s.invalid and not s.disabled and ".ubuntu.com/" in s.uri]))'
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


if __name__ == '__main__':
    unittest.main()
