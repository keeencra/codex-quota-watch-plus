"""Renew this user's existing signed apps without changing their identifiers.

Only installation receipts advance the recorded installed expiration dates.
Private configuration and command logs stay outside the public repository.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path.home() / 'Library/Application Support/CodexQuotaWatch'
WINDOW = 48 * 3600


def save(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.renew-')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, indent=2)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def expiry(value):
    return datetime.fromisoformat(value).timestamp()


def due_groups(state, now):
    return [group for group, labels in [('phone', ['phone', 'widget']), ('watch', ['watch'])]
            if min(expiry(state['installed'][label]) for label in labels) - now <= WINDOW]


def is_renewed(state, profiles, labels, now):
    return all(expiry(profiles[label]) > expiry(state['installed'][label]) + 3600
               and expiry(profiles[label]) - now > WINDOW for label in labels)


def run(command, log, timeout):
    with log.open('wb') as f:
        try:
            result = subprocess.run(command, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise RuntimeError('command_timeout') from None
    if result.returncode:
        raise RuntimeError('command_failed')


def read_profiles(products, config):
    profiles = {}
    for label, item in config['apps'].items():
        app = products / item['path']
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != item['bundle_id']:
            raise RuntimeError('unexpected_app_identifier')
        raw = subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')],
                             capture_output=True, check=True).stdout
        profile = plistlib.loads(raw)
        if profile.get('TeamIdentifier') != [config['team_id']]:
            raise RuntimeError('unexpected_signing_team')
        if not profile.get('Entitlements', {}).get('application-identifier', '').endswith('.' + item['bundle_id']):
            raise RuntimeError('unexpected_profile_identifier')
        if item['device_udid'] not in profile.get('ProvisionedDevices', []):
            raise RuntimeError('device_not_provisioned')
        profiles[label] = profile['ExpirationDate'].replace(tzinfo=timezone.utc).isoformat()
    return profiles


def execute(check_only=False):
    os.umask(0o077)
    config = json.loads((ROOT / 'renew-signing-config.json').read_text())
    state_path = ROOT / 'renew-signing-state.json'
    state = json.loads(state_path.read_text())
    now = datetime.now(timezone.utc).timestamp()
    due = due_groups(state, now)
    report = {'status': 'check_only' if check_only else 'not_due',
              'installed_expires': state['installed'], 'due': due}
    if check_only or not due:
        return report
    log_dir = Path(config['derived_data']).parent / 'RenewalLogs'
    log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    report['renewed'] = []
    stage = 'build'
    try:
        if not (Path(config['project']) / 'project.pbxproj').is_file():
            raise RuntimeError('project_missing')
        run(['xcodebuild', '-project', config['project'], '-scheme', 'CodingQuota Watch App',
             '-configuration', 'Debug', '-destination', 'generic/platform=watchOS',
             '-derivedDataPath', config['derived_data'], '-allowProvisioningUpdates',
             '-allowProvisioningDeviceRegistration', 'build'], log_dir / 'build.log', 1200)
        products = Path(config['derived_data']) / 'Build/Products'
        profiles = read_profiles(products, config)
        errors = []
        for group in due:
            labels = ['phone', 'widget'] if group == 'phone' else ['watch']
            if not is_renewed(state, profiles, labels, now):
                errors.append({'group': group, 'reason': 'profile_not_extended'})
                continue
            stage = 'install_' + group
            app = products / config['apps'][group]['path']
            receipt = log_dir / (group + '-install.json')
            if receipt.exists():
                receipt.unlink()
            try:
                run(['codesign', '--verify', '--deep', '--strict', str(app)], log_dir / (group + '-signature.log'), 60)
                run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', config['devices'][group],
                     '--timeout', '60', '--json-output', str(receipt), str(app)], log_dir / (group + '-install.log'), 90)
                result = json.loads(receipt.read_text())
                if result.get('info', {}).get('outcome') != 'success':
                    raise RuntimeError('install_not_confirmed')
            except (RuntimeError, OSError, ValueError):
                errors.append({'group': group, 'reason': 'install_failed_connect_unlock_device'})
                continue
            for label in labels:
                state['installed'][label] = profiles[label]
            state['last_success_at'] = datetime.now(timezone.utc).isoformat()
            save(state_path, state)
            report['renewed'].append(group)
        report['status'] = 'needs_attention' if errors else 'renewed'
        report['errors'] = errors
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError):
        report.update(status='needs_attention', errors=[{'stage': stage, 'reason': 'check_private_renewal_logs'}])
    report['installed_expires'] = state['installed']
    report['checked_at'] = datetime.now(timezone.utc).isoformat()
    save(ROOT / 'renew-signing-last-result.json', report)
    return report


def main():
    global ROOT
    parser = argparse.ArgumentParser(description='Check and renew an existing personal iPhone/Watch installation.')
    parser.add_argument('--check', action='store_true', help='Only inspect the recorded installed expiration dates.')
    parser.add_argument('--state-dir', type=Path, default=ROOT, help='Private configuration and installed-state directory.')
    parser.add_argument('--record-installed-from', type=Path,
                        help='Initialize once from Build/Products of packages you have already successfully installed.')
    args = parser.parse_args()
    os.umask(0o077)
    ROOT = args.state_dir.expanduser().resolve()
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (ROOT / 'renew-signing.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'status': 'already_running'}))
            return
        try:
            if args.record_installed_from:
                if (ROOT / 'renew-signing-state.json').exists():
                    raise RuntimeError('Installed state already exists')
                config = json.loads((ROOT / 'renew-signing-config.json').read_text())
                profiles = read_profiles(args.record_installed_from.expanduser().resolve(), config)
                save(ROOT / 'renew-signing-state.json', {'installed': profiles,
                     'baseline': 'Operator recorded packages already successfully installed on the devices.'})
                result = {'status': 'initialized', 'installed_expires': profiles}
            else:
                result = execute(args.check)
        except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            result = {'status': 'needs_attention', 'errors': [{'reason': 'check_private_configuration_or_initialization'}]}
        print(json.dumps(result, ensure_ascii=False))
        if result.get('status') == 'needs_attention':
            raise SystemExit(2)


if __name__ == '__main__':
    main()
