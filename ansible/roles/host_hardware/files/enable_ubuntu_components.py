"""Enable missing Ubuntu components using python-apt on noble and resolute."""

import argparse
import json
from pathlib import Path

import apt_pkg
from aptsources.sourceslist import SourcesList


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    apt_pkg.init()
    path = Path(apt_pkg.config.find_dir('Dir::Etc::sourceparts')) / 'ubuntu.sources'
    if not path.exists():
        path = Path(apt_pkg.config.find_file('Dir::Etc::sourcelist'))

    sources = SourcesList(withMatcher=False, deb822=True)
    sources.list = [entry for entry in sources.list if entry.file == str(path)]
    groups = {}
    for entry in sources.exploded_list():
        if not entry.invalid and not entry.disabled:
            groups.setdefault((entry.uri, entry.dist, entry.type), []).append(entry)
    if not groups:
        raise SystemExit(f'No enabled repository entries found in {path}')

    changed = False
    for entries in groups.values():
        present = {component for entry in entries for component in entry.comps}
        missing = [component for component in ('universe', 'multiverse') if component not in present]
        if missing:
            entries[0].comps = list(entries[0].comps) + missing
            changed = True
    if changed and not args.check:
        sources.save()
    print(json.dumps({'changed': changed}))


if __name__ == '__main__':
    main()
