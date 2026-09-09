#!/usr/bin/env python3
"""Mandatory pre-install/RC gate: inspect signed app and EVERY embedded appex."""
import argparse, datetime, fnmatch, json, plistlib, subprocess, tempfile
from pathlib import Path
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('app', type=Path)
p.add_argument('--build', required=True)
p.add_argument('--bundle-id', default='com.lafayette.tastemap')
p.add_argument('--team', default='7G5J9MJX88')
p.add_argument('--device-udid')
a = p.parse_args()
errors, records = [], []
def check(ok, message):
    if not ok: errors.append(message)
def run(*args):
    r = subprocess.run(args, capture_output=True)
    if r.returncode: raise ValueError('command failed: ' + args[0])
    return r.stdout
try:
    main = plistlib.loads((a.app / 'Info.plist').read_bytes())
    extensions = sorted(a.app.rglob('*.appex'))
    check(bool(extensions), 'Share Extension missing')
    for bundle in [a.app] + extensions:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        bid = info.get('CFBundleIdentifier', '')
        label = bundle.name
        for key in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundlePackageType', 'CFBundleVersion', 'CFBundleShortVersionString']:
            check(bool(info.get(key)) and '$(' not in str(info.get(key)), label + ': missing/unexpanded ' + key)
        check(info.get('CFBundleVersion') == a.build, label + ': wrong build')
        check(info.get('CFBundleShortVersionString') == main.get('CFBundleShortVersionString'), label + ': version mismatch')
        check((bundle / info.get('CFBundleExecutable', '__missing__')).is_file(), label + ': executable missing')
        if bundle == a.app:
            check(bid == a.bundle_id, label + ': wrong bundle identifier')
            check(info.get('CFBundlePackageType') == 'APPL', label + ': wrong package type')
        else:
            check(bundle.parent == a.app / 'PlugIns', label + ': unexpected embedding location')
            check(bid == a.bundle_id + '.ShareExtension', label + ': unknown extension identifier; audit before allowlisting')
            check(info.get('CFBundlePackageType') == 'XPC!', label + ': wrong package type')
            ext = info.get('NSExtension', {})
            check(ext.get('NSExtensionPointIdentifier') == 'com.apple.share-services', label + ': wrong extension point')
            check(bool(ext.get('NSExtensionPrincipalClass')), label + ': missing principal class')
        run('codesign', '--verify', '--deep', '--strict', str(bundle))
        ent = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', str(bundle)))
        profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(bundle / 'embedded.mobileprovision')))
        pe = profile['Entitlements']
        with tempfile.TemporaryDirectory() as cert_dir:
            prefix = str(Path(cert_dir) / 'signer')
            run('codesign', '-d', '--extract-certificates=' + prefix, str(bundle))
            check(Path(prefix + '0').read_bytes() in profile.get('DeveloperCertificates', []), label + ': signing certificate absent from profile')
        check(a.team in profile.get('ApplicationIdentifierPrefix', []), label + ': wrong application prefix')
        check(ent.get('com.apple.developer.team-identifier') == a.team, label + ': wrong signing team')
        check(a.team in profile.get('TeamIdentifier', []), label + ': wrong provisioning team')
        check(ent.get('application-identifier') == a.team + '.' + bid, label + ': wrong application entitlement')
        check(profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), label + ': expired profile')
        if a.device_udid: check(a.device_udid in profile.get('ProvisionedDevices', []) or profile.get('ProvisionsAllDevices'), label + ': device not provisioned')
        for key, value in ent.items():
            allowed = pe.get(key)
            values = value if isinstance(value, list) else [value]
            allowed = allowed if isinstance(allowed, list) else [allowed]
            check(all(any(fnmatch.fnmatchcase(str(v), str(x)) for x in allowed) for v in values), label + ': entitlement not provisioned: ' + key)
        check(ent.get('com.apple.security.application-groups') == ['group.' + a.bundle_id], label + ': shared container mismatch')
        if bundle != a.app:
            check(not ent.get('com.apple.developer.applesignin') and not ent.get('com.apple.developer.associated-domains'), label + ': unrelated extension entitlements')
        records.append({'bundle': label, 'identifier': bid, 'build': info.get('CFBundleVersion'), 'version': info.get('CFBundleShortVersionString'), 'executable': info.get('CFBundleExecutable'), 'entitlements': ent, 'codesign': 'PASS'})
except Exception as e:
    errors.append(str(e))
print(json.dumps({'status': 'FAIL' if errors else 'PASS', 'bundles': records, 'errors': errors}, indent=2))
raise SystemExit(bool(errors))
