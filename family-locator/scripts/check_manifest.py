#!/usr/bin/env python3
"""Fails the release build if the merged Android manifest picks up anything
Google Play restricts or that this app must keep (plugins can add
permissions silently on upgrade). Run after `flutter build appbundle`."""
import pathlib
import sys
import xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}'
MANIFEST = pathlib.Path(__file__).resolve().parent.parent / (
    'build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml')

# Each of these needs a Play declaration this app can't justify, or is
# something a monitoring app must never have (microphone, contacts, SMS...).
FORBIDDEN = {
    'android.permission.USE_FULL_SCREEN_INTENT',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.USE_EXACT_ALARM',
    'android.permission.QUERY_ALL_PACKAGES',
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android.permission.MANAGE_EXTERNAL_STORAGE',
    'android.permission.SYSTEM_ALERT_WINDOW',
    'android.permission.RECORD_AUDIO',
    'android.permission.CAMERA',
    'android.permission.READ_CONTACTS',
    'android.permission.READ_SMS',
    'android.permission.RECEIVE_SMS',
    'android.permission.READ_CALL_LOG',
    'android.permission.READ_PHONE_STATE',
    'android.permission.PACKAGE_USAGE_STATS',
    'android.permission.BIND_ACCESSIBILITY_SERVICE',
    'com.google.android.gms.permission.AD_ID',
}


def main() -> int:
    if not MANIFEST.exists():
        print(f'Merged manifest not found; build the release first:\n  {MANIFEST}')
        return 1
    root = ET.parse(MANIFEST).getroot()
    app = root.find('application')
    problems = []

    perms = {p.get(A + 'name') for p in root.findall('uses-permission')}
    problems += [f'restricted permission added: {p}' for p in sorted(perms & FORBIDDEN)]

    meta = {m.get(A + 'name'): m.get(A + 'value') for m in app.findall('meta-data')}
    if meta.get('isMonitoringTool') != 'child_monitoring':
        problems.append('isMonitoringTool=child_monitoring meta-data is missing (Play stalkerware policy)')
    if app.get(A + 'debuggable') == 'true':
        problems.append('release build is debuggable')
    if app.get(A + 'allowBackup') != 'false':
        problems.append('android:allowBackup must be false (family session must not leave the device)')
    location_fgs = [s for s in app.findall('service') if 'location' in (s.get(A + 'foregroundServiceType') or '')]
    if not location_fgs:
        problems.append('no foreground service of type "location" (background sharing would stop)')

    if problems:
        print('Manifest check FAILED:')
        for p in problems:
            print(f'  - {p}')
        return 1
    print(f'Manifest check passed ({len(perms)} permissions, monitoring flag present, backups off).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
