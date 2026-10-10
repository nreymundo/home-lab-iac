"""Execute K3s orchestration with isolated files and simulated external APIs.

Only the OS/storage provisioning imports and external command/service/download
boundaries are substituted. Conditions, delegation, serial plays, file planning,
templates, assertions, token handling and metadata tasks run through Ansible.
This is not an embedded-etcd or Longhorn integration test.
"""

import copy
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

import yaml
from ansible.template import Templar, trust_as_template


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / 'roles/k3s'


class K3sWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.roles = self.root / 'roles'
        shutil.copytree(ROLE, self.roles / 'k3s')
        self.actions = self.root / 'actions'
        self.actions.mkdir()
        for name in ['fixture_command', 'fixture_systemd', 'fixture_download']:
            shutil.copy(ROOT / 'tests/fixtures/k3s_action.py', self.actions / f'{name}.py')
        for path in (self.roles / 'k3s/tasks').glob('*.yml'):
            tasks = yaml.safe_load(path.read_text())
            path.write_text(yaml.safe_dump(self.adapt(tasks)))
        defaults = self.roles / 'k3s/defaults/main.yml'
        defaults.write_text(yaml.safe_dump(self.relocate(yaml.safe_load(defaults.read_text()), 'inventory_hostname')))
        self.state = {'hosts': {}, 'events': []}
        for name in ['admin', 'node-a', 'node-b']:
            self.add_host(name, registered=name == 'admin')
        self.variables = {
            'fixture_dir': str(self.root), 'ansible_connection': 'local',
            'ansible_python_interpreter': shutil.which('python3'),
            'ansible_distribution': 'Ubuntu', 'ansible_distribution_release': 'noble',
            'ansible_architecture': 'x86_64', 'ansible_os_family': 'Debian',
            'ansible_host': '192.0.2.10', 'k3s_iface': 'eth0',
            'k3s_storage_mode': 'managed',
            'k3s_admin_host': 'admin', 'k3s_bootstrap_host': 'admin',
            'k3s_ready_retries': 1, 'k3s_ready_delay': 0,
        }

    def add_host(self, name, registered=False, cordoned=False, version='v1.36.4+k3s1'):
        self.state['hosts'][name] = {'registered': registered, 'cordoned': cordoned,
                                     'ready': True, 'version': version, 'labels': {}, 'taints': []}
        (self.root / name / 'etc/systemd/system').mkdir(parents=True, exist_ok=True)
        if registered:
            for directory in ['usr/local/bin', 'etc/rancher/k3s', 'var/lib/rancher/k3s/server/db/etcd']:
                (self.root / name / directory).mkdir(parents=True, exist_ok=True)
            (self.root / name / 'usr/local/bin/k3s').write_text('fixture binary\n')
            (self.root / name / 'etc/systemd/system/k3s.service').write_text('ExecStart=/usr/local/bin/k3s server\n')
            (self.root / name / 'var/lib/rancher/k3s/server/token').write_text('fixture-server-secret\n')

    @staticmethod
    def relocate(value, host):
        if isinstance(value, str):
            for prefix in ['/etc/rancher', '/etc/systemd/system', '/usr/local/bin', '/var/lib/rancher']:
                value = value.replace(prefix, '{{ fixture_dir }}/{{ ' + host + ' }}' + prefix)
            return value
        if isinstance(value, list):
            return [K3sWorkflowTests.relocate(item, host) for item in value]
        if isinstance(value, dict):
            return {key: K3sWorkflowTests.relocate(item, host) for key, item in value.items()}
        return value

    def adapt(self, tasks):
        result = []
        for original in tasks:
            task = copy.deepcopy(original)
            if task.get('ansible.builtin.import_tasks') in ['prerequisites.yml', 'storage.yml']:
                boundary = task.pop('ansible.builtin.import_tasks')
                if boundary == 'prerequisites.yml':
                    task['fixture_command'] = {'argv': ['enrollment-prerequisites']}
                else:
                    task['ansible.builtin.debug'] = {'msg': 'Storage tested separately'}
                result.append(task)
                continue
            for block in ['block', 'rescue', 'always']:
                if block in task:
                    task[block] = self.adapt(task[block])
            # Redirect actual filesystem operations, including delegated token reads.
            host = 'k3s_control_host' if 'delegate_to' in task else 'inventory_hostname'
            for module in ['stat', 'slurp', 'copy', 'file', 'set_fact']:
                key = 'ansible.builtin.' + module
                if key in task:
                    task[key] = self.relocate(task[key], host)
                    if 'loop' in task:
                        task['loop'] = self.relocate(task['loop'], host)
                    if module in ['copy', 'file']:
                        task[key].pop('owner', None)
                        task[key].pop('group', None)
            for module, replacement in [('command', 'fixture_command'), ('systemd_service', 'fixture_systemd'), ('get_url', 'fixture_download')]:
                key = 'ansible.builtin.' + module
                if key in task:
                    args = task.pop(key)
                    if isinstance(args, str):
                        args = {'argv': shlex.split(args)}
                    if module == 'get_url':
                        args = self.relocate(args, host)
                    task[replacement] = args
            result.append(task)
        return result

    def run_play(self, limit='node-a', operation='reconcile', check=False, bootstrap=False):
        state_file = self.root / 'cluster.json'
        state_file.write_text(json.dumps(self.state))
        inventory = {'all': {'vars': self.variables, 'children': {'k3s_server': {'hosts': {name: {} for name in self.state['hosts']}}}}}
        inventory_path = self.root / 'inventory.yml'
        inventory_path.write_text(yaml.safe_dump(inventory))
        entrypoint = 'k3s_bootstrap.yml' if bootstrap else 'k3s_upgrade.yml' if operation == 'upgrade' else 'k3s_cluster.yml'
        source = ROOT / 'playbooks' / entrypoint
        plays = yaml.safe_load(source.read_text())
        for play in plays:
            play['gather_facts'] = False
            play['become'] = False
            if not bootstrap:
                play['vars'] = {'k3s_operation': operation}
        play_path = self.root / 'play.yml'
        play_path.write_text(yaml.safe_dump(plays))
        env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
               'ANSIBLE_ROLES_PATH': str(self.roles), 'ANSIBLE_ACTION_PLUGINS': str(self.actions),
               'ANSIBLE_NOCOLOR': '1'}
        command = ['ansible-playbook', '-i', str(inventory_path), str(play_path), '--limit', limit]
        if check:
            command.append('--check')
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.state = json.loads(state_file.read_text())
        self.assertNotIn('fixture-server-secret', result.stdout + result.stderr)
        return result

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def events(self, verb):
        return [event for event in self.state['events'] if verb in event.get('argv', [])]

    def seed_original_role(self, initial=False):
        self.add_host('node-a', registered=True)
        values = {
            'k3s_node_ip': '192.0.2.10', 'k3s_iface': 'eth0',
            'k3s_api_vip': '192.168.10.10', 'k3s_embedded_registry_enabled': True,
            'k3s_cluster_token': 'fixture-server-secret',
            'k3s_node_labels': {'homelab.lan/runtime': 'vm', 'topology.kubernetes.io/zone': 'pve1'},
        }
        self.variables['k3s_node_labels'] = values['k3s_node_labels']
        self.state['hosts']['node-a']['labels'] = values['k3s_node_labels'].copy()
        frozen = yaml.safe_load((ROOT / 'tests/fixtures/k3s_original.yml').read_text())
        def render(text):
            return Templar(variables=values).template(trust_as_template(text))
        values['k3s_node_label_args'] = render(frozen['labels'])
        values['k3s_exec_args'] = render(frozen['initial' if initial else 'joining'])
        service = self.root / 'node-a/etc/systemd/system/k3s.service'
        service.write_text(render((ROOT / 'tests/fixtures/k3s_original.service.j2').read_text()))
        registry = self.root / 'node-a/etc/rancher/k3s/registries.yaml'
        registry.parent.mkdir(parents=True, exist_ok=True)
        registry.write_text('mirrors:\n  "*":\n    {}\n')
        tuning = self.root / 'node-a/etc/sysctl.d/99-zzz-k3s-inotify.conf'
        tuning.parent.mkdir(parents=True)
        tuning.write_text('fs.inotify.max_user_watches=1048576\nfs.inotify.max_user_instances=1024\nfs.inotify.max_queued_events=32768\n')

    def existing_files(self):
        return {str(path.relative_to(self.root)): path.read_bytes()
                for path in (self.root / 'node-a').rglob('*') if path.is_file()}

    def test_original_initial_server_to_new_role_is_noop(self):
        self.seed_original_role(initial=True)
        before = self.existing_files()
        result = self.run_play()
        self.assert_success(result)
        self.assertIn('changed=0', result.stdout)
        self.assertEqual(self.existing_files(), before)
        self.assertEqual(self.events('drain'), [])
        self.assertFalse(any(event['kind'] in ['fixture_systemd', 'fixture_download'] for event in self.state['events']))

    def test_original_joining_server_to_new_role_is_noop(self):
        self.seed_original_role()
        before = self.existing_files()
        result = self.run_play()
        self.assert_success(result)
        self.assertIn('changed=0', result.stdout)
        self.assertEqual(self.existing_files(), before)
        self.assertEqual(self.events('drain'), [])
        self.assertFalse(any(event['kind'] in ['fixture_systemd', 'fixture_download'] for event in self.state['events']))

    def test_original_server_configuration_change_retains_token_layout(self):
        self.seed_original_role()
        self.variables['k3s_embedded_registry_enabled'] = False
        self.assert_success(self.run_play())
        service = (self.root / 'node-a/etc/systemd/system/k3s.service').read_text()
        self.assertIn('--token fixture-server-secret', service)
        self.assertNotIn('--token-file', service)
        self.assertNotIn('--embedded-registry', service)
        self.assertEqual(len(self.events('drain')), 1)

    def test_original_server_check_mode_reports_no_changes(self):
        self.seed_original_role()
        before = self.existing_files()
        result = self.run_play(check=True)
        self.assert_success(result)
        self.assertIn('changed=0', result.stdout)
        self.assertIn('"restart_required": false', result.stdout)
        self.assertEqual(self.existing_files(), before)
        self.assertEqual(self.events('drain'), [])

    def test_existing_metadata_check_mode_reports_drift_without_applying(self):
        self.seed_original_role()
        self.state['hosts']['node-a']['labels'] = {}
        self.variables['k3s_allow_workloads'] = False
        before = self.existing_files()
        result = self.run_play(check=True)
        self.assert_success(result)
        self.assertIn('Would set homelab.lan/runtime=vm', result.stdout)
        self.assertIn('Would reconcile workloads:NoSchedule', result.stdout)
        self.assertIn('"restart_required": false', result.stdout)
        self.assertEqual(self.existing_files(), before)
        self.assertEqual(self.state['hosts']['node-a']['labels'], {})
        self.assertEqual(self.state['hosts']['node-a']['taints'], [])
        self.assertEqual(self.events('label') + self.events('taint') + self.events('drain'), [])

    def test_binary_upgrade_preserves_original_configuration_and_metadata(self):
        self.seed_original_role()
        self.state['hosts']['node-a']['version'] = 'v1.36.3+k3s1'
        self.variables['k3s_embedded_registry_enabled'] = False
        self.variables['k3s_allow_workloads'] = False
        before = self.existing_files()
        self.assert_success(self.run_play(operation='upgrade'))
        self.assertEqual(self.existing_files(), before)
        self.assertEqual(len(self.events('drain')), 1)
        self.assertEqual(self.events('taint'), [])

    def test_limited_join_delegates_outside_limit_and_noop_rerun(self):
        self.assert_success(self.run_play())
        self.assertTrue(self.state['hosts']['node-a']['registered'])
        self.assertFalse(self.state['hosts']['node-b']['registered'])
        self.assertTrue(any(event['host'] == 'admin' for event in self.events('nodes')))
        self.assertEqual(self.events('drain'), [])
        token = self.root / 'node-a/etc/rancher/k3s/server-token'
        self.assertEqual(token.stat().st_mode & 0o777, 0o600)
        self.state['events'] = []
        self.assert_success(self.run_play())
        self.assertEqual(self.events('drain'), [])
        self.assertFalse(any(event.get('state') == 'restarted' for event in self.state['events']))

    def test_join_waits_for_delayed_node_registration(self):
        self.state['registration_delay'] = 2
        self.variables['k3s_ready_retries'] = 3
        self.assert_success(self.run_play())
        registration = [event for event in self.events('get') if event['argv'][-2:] == ['-o', 'name']]
        self.assertEqual(len(registration), 3)

    def test_selected_administrator_can_reconcile_through_the_vip(self):
        self.assert_success(self.run_play(limit='admin'))
        self.assertEqual(len(self.events('drain')), 1)
        self.assertEqual(len(self.events('uncordon')), 1)
        self.assertTrue(all('--server=https://192.168.10.10:6443' in event['argv'] for event in self.events('drain')))

    def test_configuration_change_preserves_existing_cordon(self):
        self.add_host('node-a', registered=True, cordoned=True)
        self.assert_success(self.run_play())
        self.assertEqual(len(self.events('drain')), 1)
        self.assertTrue(self.state['hosts']['node-a']['cordoned'])
        self.assertEqual(self.events('uncordon'), [])

    def test_successful_configuration_change_uncordons(self):
        self.add_host('node-a', registered=True)
        self.assert_success(self.run_play())
        self.assertEqual(len(self.events('uncordon')), 1)
        self.assertFalse(self.state['hosts']['node-a']['cordoned'])

    def test_failed_drain_stops_later_targets_and_leaves_cordon(self):
        self.add_host('node-a', registered=True)
        self.add_host('node-b', registered=True)
        self.state['fail_drain'] = 'node-a'
        self.assertNotEqual(self.run_play(limit='node-a,node-b').returncode, 0)
        self.assertTrue(self.state['hosts']['node-a']['cordoned'])
        self.assertFalse(any(event['target'] == 'node-b' for event in self.state['events']))
        self.assertEqual(self.events('uncordon'), [])

    def test_failed_restart_stops_later_targets_and_leaves_cordon(self):
        self.add_host('node-a', registered=True)
        self.add_host('node-b', registered=True)
        self.state['fail_restart'] = 'node-a'
        self.assertNotEqual(self.run_play(limit='node-a,node-b').returncode, 0)
        self.assertTrue(self.state['hosts']['node-a']['cordoned'])
        self.assertFalse(any(event['target'] == 'node-b' for event in self.state['events']))
        self.assertEqual(self.events('uncordon'), [])

    def test_reconcile_rejects_incidental_upgrade(self):
        self.add_host('node-a', registered=True, version='v1.36.3+k3s1')
        result = self.run_play()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Use k3s_upgrade.yml', result.stdout)
        self.assertEqual(self.events('drain'), [])
        self.assertEqual(self.state['hosts']['node-a']['version'], 'v1.36.3+k3s1')

    def test_explicit_upgrade_uses_same_rolling_sequence(self):
        self.add_host('node-a', registered=True, version='v1.36.3+k3s1')
        self.assert_success(self.run_play(operation='upgrade'))
        self.assertEqual(self.state['hosts']['node-a']['version'], 'v1.36.4+k3s1')
        self.assertEqual(len(self.events('drain')), 1)
        self.assertEqual(len(self.events('uncordon')), 1)

    def test_upgrade_restarts_when_binary_is_current_but_running_service_is_old(self):
        self.assert_success(self.run_play())
        self.state['hosts']['node-a']['running_version'] = 'v1.36.3+k3s1'
        self.state['events'] = []
        result = self.run_play()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Use k3s_upgrade.yml', result.stdout)
        self.assertEqual(self.events('drain'), [])
        self.assert_success(self.run_play(operation='upgrade'))
        self.assertEqual(len(self.events('drain')), 1)
        self.assertEqual(self.state['hosts']['node-a']['running_version'], 'v1.36.4+k3s1')

    def test_check_mode_does_not_enroll_or_write_configuration(self):
        self.assert_success(self.run_play(check=True))
        self.assertFalse(self.state['hosts']['node-a']['registered'])
        self.assertFalse((self.root / 'node-a/etc/rancher/k3s').exists())
        self.assertEqual(self.events('drain'), [])

    def test_unavailable_admin_never_falls_back_to_bootstrap(self):
        self.variables['k3s_admin_host'] = 'missing'
        result = self.run_play()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Set k3s_admin_host', result.stdout)
        self.assertFalse((self.root / 'node-a/etc/rancher/k3s').exists())

    def test_failed_api_does_not_provision_or_bootstrap(self):
        self.state['fail_api'] = 'admin'
        result = self.run_play()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('injected unavailable API', result.stdout)
        self.assertFalse((self.root / 'node-a/etc/rancher/k3s').exists())

    def test_bootstrap_requires_fresh_datastore(self):
        result = self.run_play(limit='admin,node-a,node-b', bootstrap=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Bootstrap requires a fresh datastore', result.stdout)
        self.assertFalse(self.state['hosts']['node-a']['registered'])

    def test_bootstrap_three_servers_then_unchanged_reconcile(self):
        shutil.rmtree(self.root / 'admin')
        (self.root / 'admin/etc/systemd/system').mkdir(parents=True)
        self.state['hosts']['admin']['registered'] = False
        self.assert_success(self.run_play(limit='admin,node-a,node-b', bootstrap=True))
        self.assertTrue(all(host['registered'] for host in self.state['hosts'].values()))
        self.state['events'] = []
        self.assert_success(self.run_play(limit='admin,node-a,node-b'))
        self.assertEqual(self.events('drain'), [])

    def test_registry_auth_and_unmanaged_metadata_are_preserved(self):
        self.add_host('node-a', registered=True)
        self.state['hosts']['node-a']['labels'] = {'outside.example/owner': 'other'}
        self.variables['k3s_node_labels'] = {'homelab.lan/runtime': 'baremetal'}
        self.variables['k3s_allow_workloads'] = False
        path = self.root / 'node-a/etc/rancher/k3s/registries.yaml'
        path.parent.mkdir(parents=True, exist_ok=True)
        credentials = {'docker.io': {'auth': {'username': 'fixture', 'password': 'fixture-server-secret'}}}
        path.write_text(yaml.safe_dump({'configs': credentials, 'mirrors': {'old.invalid': {}}}))
        self.assert_success(self.run_play())
        self.assertEqual(yaml.safe_load(path.read_text())['configs'], credentials)
        self.assertEqual(self.state['hosts']['node-a']['labels'], {
            'outside.example/owner': 'other', 'homelab.lan/runtime': 'baremetal'})
        self.assertEqual(self.state['hosts']['node-a']['taints'][0]['value'], 'disabled')
        self.assertEqual(self.state['hosts']['admin']['labels'], {})

    def test_malformed_registry_file_fails_before_drain(self):
        self.add_host('node-a', registered=True)
        path = self.root / 'node-a/etc/rancher/k3s/registries.yaml'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('configs: [broken\n')
        self.assertNotEqual(self.run_play().returncode, 0)
        self.assertEqual(path.read_text(), 'configs: [broken\n')
        self.assertEqual(self.events('drain'), [])

    def test_upgrade_rejects_downgrade_and_minor_skip(self):
        self.add_host('node-a', registered=True, version='v1.36.4+k3s2')
        result = self.run_play(operation='upgrade')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Use k3s_upgrade.yml', result.stdout)
        self.add_host('node-a', registered=True, version='v1.34.9+k3s1')
        result = self.run_play(operation='upgrade')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Use k3s_upgrade.yml', result.stdout)
        self.assertEqual(self.events('drain'), [])

    def test_upgrade_cannot_leave_unselected_servers_two_minors_behind(self):
        self.add_host('node-a', registered=True)
        self.add_host('node-b', registered=True, version='v1.35.9+k3s1')
        self.variables['k3s_version'] = 'v1.37.0+k3s1'
        result = self.run_play(operation='upgrade')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Complete the current server-fleet minor upgrade', result.stdout)
        self.assertEqual(self.events('drain'), [])

    def test_swap_host_override_blocks_enrollment(self):
        self.variables['swapfile_enabled'] = True
        result = self.run_play()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('host-level swapfile_enabled=false', result.stdout)
        self.assertEqual(self.state['events'], [])


class K3sStorageTests(unittest.TestCase):
    def test_swap_fstab_changes_preserve_other_mounts_and_converge(self):
        tasks = yaml.safe_load((ROLE / 'tasks/prerequisites.yml').read_text())
        task = next(task for task in tasks if task['name'] == 'Disable persistent fstab swap entries')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fstab = root / 'fstab'
            original = '# existing comment\nUUID=root / ext4 defaults 0 1\n\n/swapfile none swap sw 0 0\n\tUUID=swap none swap defaults 0 0\nUUID=data /var/lib/longhorn ext4 defaults 0 2\n'
            fstab.write_text(original)
            task['ansible.builtin.replace']['path'] = str(fstab)
            play = root / 'swap.yml'
            play.write_text(yaml.safe_dump([{'hosts': 'localhost', 'gather_facts': False, 'connection': 'local', 'tasks': [task]}]))
            for attempt in range(2):
                result = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(play)],
                                        env={**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg')},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if attempt:
                    self.assertIn('changed=0', result.stdout)
            self.assertEqual(fstab.read_text(), original.replace('/swapfile none', '# K3s disables swap: /swapfile none')
                             .replace('\tUUID=swap', '# K3s disables swap: \tUUID=swap'))

    def test_manual_mount_assertions_reject_wrong_storage(self):
        tasks = yaml.safe_load((ROLE / 'tasks/storage.yml').read_text())
        task = next(task for task in tasks if task['name'] == 'Validate Longhorn mount properties')
        good = {'target': '/var/lib/longhorn', 'source': '/dev/sdb1', 'fstype': 'ext4', 'options': 'rw,noatime', 'uuid': 'intended'}
        for override, expected in [({}, True), ({'target': '/'}, False), ({'fstype': 'btrfs'}, False), ({'options': 'ro'}, False), ({'uuid': 'other'}, False)]:
            values = {'mount': {**good, **override}, 'k3s_storage_path': '/var/lib/longhorn',
                      'k3s_storage_expected_uuid': 'intended', 'k3s_storage_expected_source': '/dev/sdb1'}
            templar = Templar(variables=values)
            passed = all(templar.evaluate_conditional(trust_as_template(condition)) for condition in task['ansible.builtin.assert']['that'])
            self.assertEqual(passed, expected, override)

    def test_managed_disk_rejects_unknown_filesystem_and_probe_errors(self):
        tasks = yaml.safe_load((ROOT / 'roles/vms/secondary_disk/tasks/main.yml').read_text())[-1]['block']
        assertion = next(task for task in tasks if task['name'] == 'Preserve existing filesystems')
        for rc, filesystem, expected in [(0, 'ext4', True), (0, 'xfs', False), (2, '', True), (4, '', False)]:
            templar = Templar(variables={'secondary_disk_current_fs': {'rc': rc, 'stdout': filesystem}, 'secondary_disk_fstype': 'ext4'})
            passed = all(templar.evaluate_conditional(trust_as_template(condition)) for condition in assertion['ansible.builtin.assert']['that'])
            self.assertEqual(passed, expected)


if __name__ == '__main__':
    unittest.main()
