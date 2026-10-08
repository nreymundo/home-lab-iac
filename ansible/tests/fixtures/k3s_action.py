"""Test-only K3s/systemd boundary; real Ansible tasks drive the state machine."""

import json
from pathlib import Path
import shlex

from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        root = Path(task_vars['fixture_dir'])
        state_path = root / 'cluster.json'
        state = json.loads(state_path.read_text())
        host = self._task.delegate_to or task_vars['inventory_hostname']
        args = self._task.args
        kind = self._task.action
        result = {'changed': False, 'rc': 0, 'stdout': '', 'stderr': ''}
        argv = args.get('argv', shlex.split(args.get('_raw_params', '')))
        event = {'kind': kind, 'host': host, 'target': task_vars['inventory_hostname'], 'argv': argv}
        state['events'].append(event)
        if kind == 'fixture_download':
            destination = Path(args['dest'])
            assert destination.is_relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text('fixture binary\n')
            state['hosts'][host]['version'] = task_vars['k3s_version']
            result['changed'] = True
        elif kind == 'fixture_systemd':
            event['state'] = args['state']
            if state.get('fail_restart') == host:
                result.update(rc=1, stderr='injected service failure')
            else:
                state['hosts'][host]['registered'] = True
                state['hosts'][host]['ready'] = True
                state['hosts'][host]['running_version'] = state['hosts'][host]['version']
                state['hosts'][host]['registration_delay'] = state.get('registration_delay', 0)
                (root / host / 'var/lib/rancher/k3s/server/db/etcd').mkdir(parents=True, exist_ok=True)
                token = root / host / 'var/lib/rancher/k3s/server/token'
                token.write_text('fixture-server-secret\n')
                result['changed'] = args['state'] == 'restarted'
        elif argv[0] == 'stat':
            result['stdout'] = 'cgroup2fs'
        elif argv[0] == 'grep':
            result['rc'] = 1
        elif argv[0] == 'sysctl':
            result['stdout'] = '1\n1\n1'
        elif argv[0] == 'swapon':
            pass
        elif argv[0] == 'enrollment-prerequisites':
            assert not state['hosts'][host]['registered'], 'Existing server was reprovisioned'
        elif '--version' in argv:
            result['stdout'] = 'k3s version ' + state['hosts'][host]['version'] + ' (fixture)'
        elif any(arg.startswith('--raw=') for arg in argv):
            result['stdout'] = 'ok'
            if state.get('fail_api') == host:
                result.update(rc=1, stderr='injected unavailable API')
        elif 'namespace' in argv:
            result['stdout'] = 'original-cluster-uid'
        elif 'nodes' in argv:
            result['stdout'] = json.dumps({'items': [self.node(name, data) for name, data in state['hosts'].items() if data['registered']]})
        elif 'get' in argv and 'node' in argv:
            name = argv[argv.index('node') + 1]
            data = state['hosts'][name]
            if data['registered'] and data.get('registration_delay', 0) and '--ignore-not-found' not in argv:
                data['registration_delay'] -= 1
                result.update(rc=1, stderr='node not registered yet')
            elif data['registered']:
                result['stdout'] = json.dumps(self.node(name, data))
            elif '--ignore-not-found' not in argv:
                result.update(rc=1, stderr='node not found')
        elif 'drain' in argv:
            name = argv[argv.index('drain') + 1]
            state['hosts'][name]['cordoned'] = True
            result['changed'] = True
            if state.get('fail_drain') == name:
                result.update(rc=1, stderr='injected drain failure')
        elif 'uncordon' in argv:
            name = argv[argv.index('uncordon') + 1]
            state['hosts'][name]['cordoned'] = False
            result['changed'] = True
        elif 'label' in argv:
            index = argv.index('node')
            name, label = argv[index + 1:index + 3]
            key, value = label.split('=', 1)
            state['hosts'][name]['labels'][key] = value
            result['changed'] = True
        elif 'taint' in argv:
            index = argv.index('node')
            name, taint = argv[index + 1:index + 3]
            state['hosts'][name]['taints'] = [] if taint.endswith('-') else [{'key': 'workloads', 'value': 'disabled', 'effect': 'NoSchedule'}]
            result['changed'] = True
        elif 'wait' in argv:
            pass
        else:
            raise AssertionError(f'Unexpected fixture command: {argv}')
        state_path.write_text(json.dumps(state))
        result['failed'] = result['rc'] != 0
        result['stdout_lines'] = result['stdout'].splitlines()
        return result

    @staticmethod
    def node(name, data):
        return {
            'metadata': {'name': name, 'labels': {'node-role.kubernetes.io/control-plane': 'true', **data['labels']}},
            'spec': {'unschedulable': data['cordoned'], 'taints': data['taints']},
            'status': {
                'conditions': [{'type': 'Ready', 'status': 'True' if data['ready'] else 'False'}],
                'nodeInfo': {'kubeletVersion': data.get('running_version', data['version'])},
            },
        }
