#!/usr/bin/env bash
set -euo pipefail
UNRAID_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export UNRAID_ROOT
exec python3 - "$@" << 'PY'
import argparse
import base64
import json
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import sys


ROOT = Path(os.environ['UNRAID_ROOT'])
TERMINFO_SOURCE = '/boot/config/terminfo.src'
TERMINALS = ('xterm-kitty', 'xterm-ghostty', 'tmux-256color')


def fail(message):
    raise ValueError(message)


def run(command, data=None):
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        fail(f'{command[0]} failed')
    return result.stdout


def valid_target(target):
    if not isinstance(target, str) or str(Path(target)) != target:
        return False
    path = Path(target)
    if not path.is_absolute() or '..' in path.parts:
        return False
    return (
        target in ('/boot/config/go', '/boot/config/stop', '/boot/config/ssh/root/authorized_keys', TERMINFO_SOURCE)
        or target.startswith('/boot/config/plugins/')
    )


def authorized_keys_from_1password(tag):
    for name in ('OP_SERVICE_ACCOUNT_TOKEN', 'IAC_1PASSWORD_VAULT_ID'):
        if not os.environ.get(name):
            fail(f'{name} must be set for 1Password public-key discovery')
    vault = os.environ['IAC_1PASSWORD_VAULT_ID']
    items = json.loads(run([
        'op', 'item', 'list', '--vault', vault, '--categories', 'SSH Key',
        '--tags', tag, '--format', 'json',
    ]))
    if not isinstance(items, list) or not items:
        fail('no SSH Key items match the configured 1Password vault and tag')
    if any(not isinstance(item, dict) or not isinstance(item.get('id'), str) or not item['id'] for item in items):
        fail('invalid 1Password SSH Key item list')
    keys = []
    for item in sorted(items, key=lambda item: item['id']):
        public = run(['op', 'read', f'op://{vault}/{item["id"]}/public key']).decode('utf-8')
        keys.extend(line.strip() for line in public.splitlines() if line.strip())
    if not keys:
        fail('1Password returned no authorized public keys')
    return ('\n'.join(keys) + '\n').encode('utf-8')




def validate_keys(files):
    authorized = files.get('/boot/config/ssh/root/authorized_keys')
    lines = [] if authorized is None else [
        line for line in authorized.splitlines() if line.strip() and not line.lstrip().startswith(b'#')
    ]
    if authorized is not None and not lines:
        fail('authorized_keys must contain at least one key')
    for line in lines:
        run(['ssh-keygen', '-l', '-f', '/dev/stdin'], line + b'\n')


def load_configuration(manifest):
    document = json.loads(run(['yq', '-o=json', '.', str(manifest)]))
    if (not isinstance(document, dict) or set(document) != {'files', 'secret_files'}
            or not isinstance(document['files'], list) or not isinstance(document['secret_files'], list)):
        fail('invalid configuration manifest')
    secrets = {}
    encrypted_sources = set()
    for name in document['secret_files']:
        if not isinstance(name, str):
            fail('invalid encrypted configuration source')
        encrypted = (ROOT / name).resolve()
        if (not encrypted.is_relative_to(ROOT) or not encrypted.is_file()
                or not encrypted.name.endswith(('.sops.yaml', '.sops.yml')) or encrypted in encrypted_sources):
            fail('invalid or duplicate encrypted configuration source')
        encrypted_sources.add(encrypted)
        secrets_doc = json.loads(run(['yq', '-o=json', '.'], run(['sops', '--decrypt', str(encrypted)])))
        if (not isinstance(secrets_doc, dict) or set(secrets_doc) != {'data'}
                or not isinstance(secrets_doc['data'], dict)):
            fail('invalid encrypted configuration envelope')
        for key, value in secrets_doc['data'].items():
            if not isinstance(key, str) or not isinstance(value, str):
                fail('encrypted configuration values must be text')
            if key in secrets:
                fail('duplicate encrypted configuration key')
            secrets[key] = value.encode('utf-8')
    files = {}
    for entry in document['files']:
        if not isinstance(entry, dict) or set(entry) not in (
                {'source', 'target', 'mode'}, {'secret', 'target', 'mode'},
                {'onepassword_tag', 'target', 'mode'}, {'content', 'target', 'mode'}):
            fail('invalid file mapping')
        target = entry['target']
        kind = next(name for name in ('source', 'secret', 'onepassword_tag', 'content') if name in entry)
        if (not valid_target(target) or target in files or not isinstance(entry[kind], str)
                or not entry[kind].strip() or entry['mode'] != '0600'):
            fail('unexpected or duplicate file mapping')
        if kind == 'source':
            source = (ROOT / entry[kind]).resolve()
            if not source.is_relative_to(ROOT) or not source.is_file():
                fail('invalid configuration source')
            value = source.read_bytes()
        elif kind == 'content':
            value = entry[kind].encode('utf-8')
        elif kind == 'onepassword_tag':
            if target != '/boot/config/ssh/root/authorized_keys':
                fail('1Password public keys must target root authorized_keys')
            value = authorized_keys_from_1password(entry[kind])
        else:
            try:
                value = secrets[entry[kind]]
            except KeyError:
                fail('unknown encrypted configuration key')
        if not value:
            fail('empty configuration source: ' + target)
        files[target] = value
        if target in ('/boot/config/go', '/boot/config/stop'):
            run(['sh', '-n'], value)
    validate_keys(files)
    return files


def reconcile(files, host, apply):
    # Payload is passed on SSH stdin, never in process arguments or output.
    script = [r'''set -eu
umask 077
if [ "$(id -u)" != 0 ]; then echo 'SSH user must be root' >&2; exit 1; fi
if [ "$(readlink /root/.ssh || :)" != /boot/config/ssh/root ]; then
  echo 'Unexpected /root/.ssh; refusing to replace it' >&2
  exit 1
fi
changed=0
check_file() {
  target=$1 expected=$2 mode=$3
  if [ -L "$target" ]; then echo "Refusing symlink: $target" >&2; exit 1; fi
  drift=0
  if [ ! -f "$target" ] || [ "$(sha256sum "$target" | cut -d ' ' -f 1)" != "$expected" ]; then drift=1; fi
  if [ -f "$target" ]; then
    case "$target" in /boot/config/*) fs=$(stat -f -c %T /boot/config);; *) fs=$(stat -f -c %T "$target");; esac
    if [ "$fs" != msdos ] && [ "$(stat -c %a "$target")" != "$mode" ]; then drift=1; fi
        if [ "$(stat -c %u:%g "$target")" != 0:0 ]; then drift=1; fi
  fi
}
write_file() {
  target=$1 encoded=$2 mode=$3
  dir=${target%/*}
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.unraid-config.XXXXXXXX")
  trap 'rm -f "$tmp"' EXIT
  printf '%s' "$encoded" | base64 -d > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$target"
  trap - EXIT
}
''']
    if TERMINFO_SOURCE in files:
        script.append('command -v tic >/dev/null && command -v infocmp >/dev/null || exit 1\n')
    if apply:
        for target, content in files.items():
            digest = hashlib.sha256(content).hexdigest()
            script.append(f'check_file {shlex.quote(target)} {digest} 600\n')
    for target, content in files.items():
        digest = hashlib.sha256(content).hexdigest()
        script.append(f'check_file {shlex.quote(target)} {digest} 600\n')
        if target == TERMINFO_SOURCE:
            script.append('terminfo_source_changed=$drift\n')
        script.append('if [ "$drift" -eq 1 ]; then\n  changed=$((changed + 1))\n')
        if apply:
            encoded = base64.b64encode(content).decode('ascii')
            script.append(f'  write_file {shlex.quote(target)} {encoded} 600\n')
        script.append(f'  printf "%s\\n" {shlex.quote(("changed " if apply else "drift ") + target)}\nfi\n')
    if TERMINFO_SOURCE in files:
        terminals = ' '.join(shlex.quote(name) for name in TERMINALS)
        script.append('terminfo_missing=0\n')
        script.append(f'for terminal in {terminals}; do\n')
        script.append('  if ! infocmp -x "$terminal" >/dev/null 2>&1; then terminfo_missing=1; fi\ndone\n')
        script.append('if [ "$terminfo_source_changed" -eq 1 ] || [ "$terminfo_missing" -eq 1 ]; then\n')
        script.append('  changed=$((changed + 1))\n')
        if apply:
            script.append(f'  (umask 022; tic -x -o /usr/share/terminfo {shlex.quote(TERMINFO_SOURCE)})\n')
            script.append(f'  for terminal in {terminals}; do infocmp -x "$terminal" >/dev/null; done\n')
        script.append(f'  echo {shlex.quote(("changed" if apply else "drift") + " system terminfo")}\nfi\n')
    script.append('printf "changed=%s\\n" "$changed"\n')
    if not apply:
        script.append('[ "$changed" -eq 0 ] || exit 2\n')
    result = subprocess.run(['ssh', host, 'bash -s'], input=''.join(script).encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    if result.returncode == 0 or (not apply and result.returncode == 2):
        return result.returncode
    return 1


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, f'{self.prog}: error: {message}\n')


def main():
    parser = ArgumentParser(description='Check or apply the Unraid boot and SSH configuration')
    parser.add_argument('action', nargs='?', choices=('check', 'apply'), default='check')
    parser.add_argument('--host', default='unraid')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'config.yaml')
    args = parser.parse_args()
    if args.host.startswith('-'):
        print('configure: invalid SSH host', file=sys.stderr)
        return 1
    try:
        files = load_configuration(args.manifest)
        return reconcile(files, args.host, args.action == 'apply')
    except (OSError, ValueError) as exc:
        print(f'configure: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
PY
