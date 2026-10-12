"""Run real POSIX shell code against isolated network-manager fixtures.

No host DNS/network configuration or network access is used by these tests.
"""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
TEMP_BASE = REPO / '.test-tmp'
SHELL = r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else '/bin/sh'

def posix(path):
    value = str(Path(path).resolve()).replace('\\', '/')
    return '/' + value[0].lower() + value[2:] if os.name == 'nt' else value

CONTROLLER = r'''
import json, os, pathlib, re, sys
sys.stdout.reconfigure(newline='\n')
root=pathlib.Path(os.environ['DNS_FIXTURE'])
path=root/'state.json'
state=json.loads(path.read_text())
name=pathlib.PurePosixPath(sys.argv[1]).name
args=sys.argv[2:]
state['calls'].append([name]+args)
def done(code=0,text=''):
    path.write_text(json.dumps(state))
    if text: print(text)
    sys.exit(code)
backend=state['backend']
if name=='id': done(text=str(state.get('uid',0)))
if name=='ip': done(text='default via 192.0.2.1 dev '+state.get('route_iface','eth0'))
if name=='pgrep': done(1)
if name=='readlink': done(text=os.environ['DNS_FIXTURE_POSIX']+'/run/systemd/resolve/stub-resolv.conf')
if name=='getent': done(1 if state.get('health_failure') else 0,'192.0.2.100 example.org' if not state.get('health_failure') else '')
if name=='nmcli':
    if args==['general','status']: done(0 if backend=='nm' else 1)
    if args[:4]==['-t','-e','no','-f']:
        profiles=['11111111-1111-1111-1111-111111111111:eth0:802-3-ethernet']
        if state.get('multiple'): profiles.append('22222222-2222-2222-2222-222222222222:wlan0:802-11-wireless')
        if state.get('vpn'): profiles.append('33333333-3333-3333-3333-333333333333:tun0:vpn')
        done(text='\n'.join(profiles))
    if args[0]=='-g': done(text=state['nm'][args[1]])
    if args[:2]==['connection','modify']:
        if state.get('modify_failure'):
            state['modify_failure']=False
            done(1)
        for i in range(4,len(args),2): state['nm'][args[i]]=args[i+1]
        done()
    if args[:2]==['device','reapply']:
        if state.get('reapply_failure'):
            state['reapply_failure']=False
            done(1)
        done()
if name=='systemctl':
    if args[:2]==['is-active','--quiet']:
        service=args[2]
        ok=(service=='systemd-resolved' and backend in ['networkd','resolved']) or (service=='systemd-networkd' and backend=='networkd')
        done(0 if ok else 3)
    if args==['restart','systemd-resolved']: done()
if name=='networkctl':
    if args[0]=='status': done(text='  Network File: '+os.environ['DNS_FIXTURE_POSIX']+'/run/systemd/network/10-uplink.network')
    if args==['reload']: done()
if name=='resolvectl':
    if args==['status']: done(text='Global DNS Servers: '+state['link']['dns'])
    if args[0] in ['dns','domain','default-route']:
        if len(args)==2: done(text='Link 2 (eth0): '+state['link'][args[0]])
        values=args[2:]
        if '' in values and values!=['']: done(1)
        state['link'][args[0]]=' '.join(values)
        done()
if name=='resolvconf' and args==['-u']:
    if backend=='debian':
        text=(root/'etc/resolvconf/resolv.conf.d/head').read_text()+'nameserver 192.0.2.53\n'
    else:
        text=(root/'etc/resolvconf.conf').read_text()
        matches=re.findall("name_servers=['\"]([^'\"]*)['\"]",text)
        text=''.join('nameserver '+ip+'\n' for ip in matches[-1].split()) if matches else 'nameserver 192.0.2.53\n'
    (root/'etc/resolv.conf').write_text(text)
    done()
done(66,'Unexpected mock invocation: '+name+' '+repr(args))
'''

class DNSHelpers(unittest.TestCase):
    def setUp(self):
        TEMP_BASE.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='dns-case-', dir=TEMP_BASE)).resolve()
        self.assertTrue(self.root.is_relative_to(TEMP_BASE.resolve()))
        self.shim = self.root / 'bin'
        self.shim.mkdir()
        self.env = os.environ.copy()
        self.env.update(DNS_FIXTURE=str(self.root), DNS_FIXTURE_POSIX=posix(self.root), DNS_FIXTURE_CONTROLLER=str(self.root / 'controller.py'), DNS_FIXTURE_PYTHON=posix(sys.executable), MSYS2_ARG_CONV_EXCL='*', MSYS2_ENV_CONV_EXCL='DNS_FIXTURE_POSIX;DNS_FIXTURE_PYTHON')
        (self.root / 'controller.py').write_text(CONTROLLER, encoding='utf-8')
        commands = ['id', 'ip', 'pgrep', 'getent', 'nmcli', 'systemctl', 'networkctl', 'resolvectl', 'resolvconf']
        if os.name == 'nt': commands.append('readlink')  # MSYS ln -s emulates links by copying.
        for name in commands:
            wrapper = self.shim / name
            wrapper.write_text('#!/bin/sh\nexec "$DNS_FIXTURE_PYTHON" "$DNS_FIXTURE_CONTROLLER" "$0" "$@"\n', encoding='utf-8')
            wrapper.chmod(0o755)
        text = (REPO / 'linux/dns.sh').read_text(encoding='utf-8')
        for prefix in ['/etc/', '/run/', '/var/lib/']:
            text = text.replace(prefix, posix(self.root) + prefix)
        self.script = self.root / 'dns.sh'
        self.script.write_bytes(text.encode('utf-8'))
        (self.root / 'etc').mkdir()
        (self.root / 'etc/resolv.conf').write_text('search lan\nnameserver 192.0.2.53\noptions timeout:2\n')
        self.configure('file')

    def tearDown(self):
        # The only recursive deletion is the verified fixture inside this repo.
        if self.root.is_relative_to(TEMP_BASE.resolve()):
            shutil.rmtree(self.root)

    def configure(self, backend, **kwargs):
        state = {'backend': backend, 'calls': [], 'nm': {'ipv4.dns': '192.0.2.53', 'ipv6.dns': '2001:db8::53', 'ipv4.ignore-auto-dns': 'no', 'ipv6.ignore-auto-dns': 'no'}, 'link': {'dns': '192.0.2.53', 'domain': 'lan ~corp.test', 'default-route': 'no'}}
        state.update(kwargs)
        self.original = json.loads(json.dumps(state))
        (self.root / 'state.json').write_text(json.dumps(state))
        if backend in ['networkd', 'resolved']:
            target = self.root / 'run/systemd/resolve/stub-resolv.conf'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('nameserver 127.0.0.53\n')
            (self.root / 'etc/resolv.conf').unlink()
            self.shell('ln -s ' + shlex.quote(posix(target)) + ' ' + shlex.quote(posix(self.root / 'etc/resolv.conf')), shim=False)
        if backend == 'networkd':
            base = self.root / 'run/systemd/network/10-uplink.network'
            base.parent.mkdir(parents=True, exist_ok=True)
            base.write_text('[Match]\nName=eth0\n[Network]\nDHCP=yes\n')
        if backend == 'debian':
            head = self.root / 'etc/resolvconf/resolv.conf.d/head'
            head.parent.mkdir(parents=True, exist_ok=True)
            head.write_text('# retained comment\noptions timeout:2\n')
        if backend == 'openresolv':
            (self.root / 'etc/resolvconf.conf').write_text("# existing config\nname_servers='192.0.2.53'\n")

    def shell(self, command, shim=True):
        if shim:
            command = 'PATH=' + shlex.quote(posix(self.shim) + ':/usr/bin:/bin') + '; export PATH; ' + command
        return subprocess.run([SHELL, '-c', command], env=self.env, capture_output=True, text=True)

    def run_helper(self, *args, success=True):
        result = self.shell('sh ' + shlex.quote(posix(self.script)) + ' ' + ' '.join(map(shlex.quote, args)))
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def state(self):
        return json.loads((self.root / 'state.json').read_text())

    def test_nm_apply_restore_and_ipv6(self):
        self.configure('nm')
        self.run_helper('1.1.1.1', '2606:4700:4700::1111')
        self.assertEqual(self.state()['nm']['ipv4.dns'], '1.1.1.1')
        self.assertEqual(self.state()['nm']['ipv6.dns'], '2606:4700:4700::1111')
        self.run_helper('--restore')
        self.assertEqual(self.state()['nm'], self.original['nm'])
        self.assertFalse(any(c[:3] in [['nmcli', 'connection', 'up'], ['nmcli', 'connection', 'down']] for c in self.state()['calls']))

    def test_nm_reapply_failure_rolls_back(self):
        self.configure('nm', reapply_failure=True)
        result = self.run_helper('1.1.1.1', success=False)
        self.assertIn('DNS change failed', result.stderr)
        self.assertEqual(self.state()['nm'], self.original['nm'])

    def test_nm_health_failure_rolls_back(self):
        self.configure('nm', health_failure=True)
        result = self.run_helper('1.1.1.1', success=False)
        self.assertIn('DNS change failed', result.stderr)
        self.assertEqual(self.state()['nm'], self.original['nm'])
        self.assertFalse((self.root / 'var/lib/system-toolbox/dns/last').exists())

    def test_nm_ignores_vpn_when_choosing_uplink(self):
        self.configure('nm', vpn=True, route_iface='tun0')
        self.run_helper('1.1.1.1')
        calls = self.state()['calls']
        self.assertIn(['nmcli', 'device', 'reapply', 'eth0'], calls)

    def test_ambiguous_interfaces_require_selection(self):
        self.configure('nm', multiple=True, route_iface='')
        self.run_helper('1.1.1.1', success=False)
        self.assertEqual(self.state()['nm'], self.original['nm'])
        self.run_helper('--interface', 'wlan0', '1.1.1.1')

    def test_networkd_persistence_and_runtime_restore(self):
        self.configure('networkd')
        target = self.root / 'etc/systemd/network/10-uplink.network.d/99-system-toolbox-dns.conf'
        self.run_helper('1.1.1.1', '8.8.8.8')
        self.assertIn('UseDNS=no', target.read_text())
        self.assertEqual(self.state()['link']['domain'], 'lan ~corp.test ~.')
        self.run_helper('--restore')
        self.assertEqual(self.state()['link'], self.original['link'])
        self.assertFalse(target.exists())

    def test_networkd_empty_domains_restore(self):
        self.configure('networkd')
        state = self.state(); state['link']['domain'] = ''
        (self.root / 'state.json').write_text(json.dumps(state))
        self.run_helper('1.1.1.1')
        self.run_helper('--restore')
        self.assertEqual(self.state()['link']['domain'], '')

    def test_resolved_dropin_restore(self):
        self.configure('resolved')
        target = self.root / 'etc/systemd/resolved.conf.d/99-system-toolbox-dns.conf'
        target.parent.mkdir(parents=True)
        original = '[Resolve]\nDNS=192.0.2.53\n'
        target.write_text(original)
        self.run_helper('1.1.1.1')
        self.assertIn('DNS=1.1.1.1', target.read_text())
        self.run_helper('--restore')
        self.assertEqual(target.read_text(), original)

    def test_resolved_health_failure_removes_new_dropin(self):
        self.configure('resolved', health_failure=True)
        result = self.run_helper('1.1.1.1', success=False)
        self.assertIn('DNS change failed', result.stderr)
        self.assertFalse((self.root / 'etc/systemd/resolved.conf.d/99-system-toolbox-dns.conf').exists())

    def test_resolvconf_variants_restore(self):
        for backend in ['debian', 'openresolv']:
            with self.subTest(backend=backend):
                self.configure(backend)
                target = self.root / ('etc/resolvconf/resolv.conf.d/head' if backend == 'debian' else 'etc/resolvconf.conf')
                original = target.read_text()
                # Explicit backend avoids the other fixture's configuration directory.
                if backend == 'openresolv':
                    old_dir = self.root / 'etc/resolvconf'
                    if old_dir.exists(): shutil.rmtree(old_dir)
                self.run_helper('--backend', 'resolvconf', '1.1.1.1', '8.8.8.8')
                self.assertIn('nameserver 1.1.1.1', (self.root / 'etc/resolv.conf').read_text())
                self.run_helper('--restore')
                self.assertEqual(target.read_text(), original)

    def test_static_file_preserves_other_options_and_restores(self):
        target = self.root / 'etc/resolv.conf'
        original = target.read_bytes()
        self.run_helper('1.1.1.1', '8.8.8.8')
        self.assertIn('search lan', target.read_text())
        self.assertIn('options timeout:2', target.read_text())
        self.run_helper('--restore')
        self.assertEqual(target.read_bytes(), original)

    def test_static_file_health_failure_rolls_back(self):
        self.configure('file', health_failure=True)
        target = self.root / 'etc/resolv.conf'; original = target.read_bytes()
        result = self.run_helper('1.1.1.1', success=False)
        self.assertIn('DNS change failed', result.stderr)
        self.assertEqual(target.read_bytes(), original)

    def test_generated_file_refused(self):
        target = self.root / 'etc/resolv.conf'; target.write_text('# Generated by dhcpcd\nnameserver 192.0.2.53\n')
        original = target.read_bytes()
        self.run_helper('1.1.1.1', success=False)
        self.assertEqual(target.read_bytes(), original)

    def test_invalid_inputs_do_not_mutate(self):
        target = self.root / 'etc/resolv.conf'; original = target.read_bytes()
        for address in ['999.1.1.1', '01.1.1.1', 'https://1.1.1.1/dns-query', '1.1.1.1#53', '1::2::3', '::1:2:3:4:5:6:7:8', '1:2:3:4:5:6:7', '1.1.1.1;touch /tmp/bad']:
            with self.subTest(address=address):
                self.run_helper(address, success=False)
                self.assertEqual(target.read_bytes(), original)

    def test_show_does_not_create_backup(self):
        self.run_helper('--show')
        self.assertFalse((self.root / 'var/lib/system-toolbox/dns').exists())

    def test_repeated_apply_restores_previous_success(self):
        self.run_helper('1.1.1.1')
        previous = (self.root / 'etc/resolv.conf').read_bytes()
        self.run_helper('9.9.9.9')
        self.run_helper('--restore')
        self.assertEqual((self.root / 'etc/resolv.conf').read_bytes(), previous)

if __name__ == '__main__':
    unittest.main()
