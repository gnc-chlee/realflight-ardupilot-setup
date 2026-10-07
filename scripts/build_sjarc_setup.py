"""Build the single-file .NET Framework WinForms setup assistant, no runtime downloads of code."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps/SJARC-RealFlight-Setup'
BUILD = ROOT / 'artifacts/sjarc-setup/build'
BUILD.mkdir(parents=True, exist_ok=True)
COMMIT = 'e93e185d4e22df48d6791fe45103b593f168946a'
VERSION = '0.2.1'
# MakeFlyEasy's original files (ArduPilot/SITL_Models PR #158) are not kept in this repository.
# The build downloads them once into UPSTREAM and checks SHA-256, as the helper itself does at run time.
UPSTREAM = ROOT / 'artifacts/mfe-four-models/upstream'
RAW_BASE = 'https://raw.githubusercontent.com/ArduPilot/SITL_Models/' + COMMIT + '/RealFlight/Released_Models/QuadPlanes/'
MODELS = [('S', 'MFE Striver mini VTOL', 'MFE_Striver_mini_VTOL',
           ('STRIVERminiVTOL_EA.RFX', 'b13c2b33de646083a672e723f4ff9f3a85d097d339c821c161086cd23f56395d'),
           ('Striver_VTOL_V4.4.4.param', '24818e383baba6a06352e3b93d19f7732ecb8c6e68a405daab97eba99fba8230')),
          ('P', 'MFE Pioneer VTOL', 'MFE_Pioneer_VTOL',
           ('Pioneer_EA.RFX', 'b6fcb848e7d58bcda30beed7e8e773398fc31d57a561c41d97535eb2ccc7e649'),
           ('Pioneer_VTOL_V4.4.4.param', 'c031190cdb40fd1719cd1c83142eed12df396d467a40e1a2dd8f0e05d938f828')),
          ('F', 'MFE Fighter VTOL', 'MFE_Fighter_VTOL',
           ('fighterVTOL_EA.RFX', '9b0804ec1c4432de3965f005f341f44a1f1a4e3c4ded38f7bc8cb2385d5dd313'),
           ('Fighter_VTOL_V4.4.4.param', 'bc938fea362067ccdfd86b55d31f4b03c8ef266678f20974e4600116c288e49f')),
          ('H', 'MFE Hero VTOL', 'MFE_Hero_VTOL',
           ('HERO_EA.RFX', '77b92dc9b6c2b3755fdbc2d9783c7950915891c92ee135ad2fd856051ead22ff'),
           ('Hero_VTOL_V4.4.4.param', 'dd7c7405275548cb80e3755ef94c0589b6a57d923e3068fcb1c8ce4b1189a887'))]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fetch(directory, name, digest):
    path = UPSTREAM / directory / name
    if path.exists():
        assert sha(path.read_bytes()) == digest, 'Local copy differs from the pinned original, move it aside: ' + str(path)
        return path
    data = urllib.request.urlopen(RAW_BASE + directory + '/' + urllib.parse.quote(name), timeout=60).read()
    assert sha(data) == digest, 'Downloaded file does not match the pinned SHA-256: ' + name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def payload():
    models = []
    for key, title, directory, rfx_pin, param_pin in MODELS:
        rfx = fetch(directory, *rfx_pin)
        param = fetch(directory, *param_pin)
        with zipfile.ZipFile(str(rfx)) as z:
            entries = [{'Name': n, 'Sha256': sha(z.read(n))} for n in z.namelist()]
            names = z.namelist()
            def name(ext):
                found = [n for n in names if n.lower().endswith(ext)]
                assert len(found) == 1, (directory, ext, found)
                return found[0]
            m = dict(Key=key, Title=title, Directory=directory, Rfx=rfx.name,
                     RfxSha256=sha(rfx.read_bytes()), Param=param.name, ParamSha256=sha(param.read_bytes()),
                     Vehicle=name('.rfvehicle'), Bse=name('.bse'), Kex=name('.kex'),
                     Color=name('.colorscheme'), Texture=name('.tga'), Entries=entries,
                     BaseUrl='https://raw.githubusercontent.com/ArduPilot/SITL_Models/' + COMMIT + '/RealFlight/Released_Models/QuadPlanes/' + directory + '/')
            models.append(m)
    old = (ROOT / 'patches/MFE-FlightAxis-Signal-Patch-v1.0.0/Patch-MFE-Signals.ps1').read_text('utf-8')
    core = old[old.index('$Names = '):old.index('\ntry {\n    if (-not $RealFlightRoot')]
    entries = {'Backend.ps1': (APP / 'Backend.ps1').read_bytes(), 'Troubleshoot.ps1': (APP / 'Troubleshoot.ps1').read_bytes(),
               'SignalCore.ps1': core.encode('utf-8'),
               'models.json': json.dumps(models, indent=2).encode('utf-8'),
               'MotorMap.param': (ROOT / 'patches/MFE-FlightAxis-Signal-Patch-v1.0.0/MFE_PR158_QuadX_Servo_Map_ONLY.param').read_bytes()}
    for name in ['GUIDE_KO.txt', 'README_KO.md', 'TROUBLESHOOT_KO.txt']:
        if (APP / name).exists():
            entries[name] = (APP / name).read_bytes()
    for name, data in entries.items():
        (BUILD / name).write_bytes(data)
    raw = io.BytesIO()
    with zipfile.ZipFile(raw, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(entries.items()):
            z.writestr(name, data)
    (BUILD / 'payload.zip').write_bytes(raw.getvalue())
    return entries


def main():
    entries = payload()
    if not (APP / 'Program.cs').exists():
        print('Backend payload prepared: ' + str(BUILD))
        return
    out = ROOT / ('dist/SJARC-RealFlight-Setup-v' + VERSION)
    out.mkdir(parents=True, exist_ok=True)
    exe = out / 'SJARC-RealFlight-Setup.exe'
    command = [r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe', '/nologo', '/target:winexe',
               '/platform:anycpu', '/optimize+', '/utf8output', '/out:' + str(exe),
               '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
               '/reference:System.Web.Extensions.dll', '/reference:System.IO.Compression.dll',
               '/reference:System.IO.Compression.FileSystem.dll',
               '/resource:' + str(BUILD / 'payload.zip') + ',payload.zip', str(APP / 'Program.cs'), str(APP / 'TargetSelection.cs')]
    if (APP / 'app.ico').exists():
        command.insert(-2, '/win32icon:' + str(APP / 'app.ico'))  # EXE icon; drawn by scripts/make_icon.ps1
    subprocess.run(command, check=True)
    verification = {'release': VERSION + ' test release', 'exe_sha256': sha(exe.read_bytes()),
                    'source_commit': COMMIT,
                    'live_import_tested': False, 'live_flight_tested': False,
                    'ui_checks': 'v0.1.2 window launch smoke test (payload extraction + read-only detection). Target-selection rules covered by a headless C# harness; no multi-version native UI or live Import test.',
                    'network_checks': 'Pinned raw.githubusercontent.com URL re-fetched and SHA-256 checked; offline source folder (EXE folder) path covered by tests',
                    'changes_in_0_2_1': ['SITL step: Start SITL button runs Mission Planner\'s own flightaxis command line (same sitl\\flightaxis store, never --wipe) plus a UDP 14550 output that Mission Planner auto-connects to; refuses a second SITL and asks for RealFlight first',
                                         'SITL step: connection diagram (controller -> RealFlight <-> FlightAxis TCP 18083 <-> ArduPilot SITL <-> MAVLink TCP 5760 / UDP 14550 <-> Mission Planner)',
                                         'Log area collapses on the SITL, troubleshooting and help pages'],
                    'changes_in_0_2_0': ['Step layout: left rail (1 target, 2 models, 3 RF import, 4 check and patch, 5 SITL, troubleshooting, help) with done/current/attention marks, one action card per step',
                                         'Bottom status strip from a new read-only Status action: RealFlight Link, pause settings, controller selection, SITL started with flightaxis',
                                         'Header shows the target and whether RealFlight/Mission Planner/SITL are running; results shown as lists instead of raw log lines',
                                         'Setup, patch, restore and troubleshooting behaviour unchanged'],
                    'changes_in_0_1_6': ['App icon (quadplane) on the EXE and window, drawn by scripts/make_icon.ps1',
                                         'Common backend errors shown in Korean with the original text kept',
                                         'Diagnosis flags SITL started without flightaxis, RealFlight not listening on 18083 and newer non-flightaxis SITL stores (2026-09-30 field case)',
                                         'Stronger reminders to pick Model = flightaxis in Mission Planner'],
                    'changes_in_0_1_5': ['New tab: connection troubleshooting for RealFlight hanging (Not Responding) when SITL flightaxis connects after the first session',
                                         'Read-only diagnosis report + zip (processes and responsiveness, 18083/5760 listeners and TIME_WAIT, RF INI link/pause/physics/controller keys, radio-profile Reset mapping, MFE model state, Mission Planner SITL stores, Windows hang/crash events); LicenseInfo profile values removed from the INI copy',
                                         'Stop leftover SITL processes started from Mission Planner sitl folder only',
                                         'Reset Mission Planner sitl\\flightaxis store by renaming it (nothing deleted) and restore it',
                                         'Reset the selected RealFlight INI by moving it under .SJARC\\IniReset (hash-checked) and restore it; RealFlight-created INI is kept as a copy'],
                    'changes_in_0_1_4': ['Field fix from the 2026-09-29 Icheon RF 9.5 visit (built in another session, merged here)',
                                         'RF 8/9: signals only; model/texture paths an earlier helper moved to the shared asset folder are restored to RealFlight import paths; BasedOn restored',
                                         'INI: FlightAxisLinkEnabled (RF 8/9) or RealFlightLinkEnabled (Evolution), whichever exists; read-only controller profile dual-rates warning',
                                         'GUI: path-repair checkbox enabled for Evolution only'],
                    'changes_in_0_1_3': ['Shared KEX is built from RealFlight\'s own imported (converted) KEX instead of the vendor RF 8 copy; RF 9 field test on 2026-09-29 could not load aircraft with the vendor-derived KEX',
                                         'New option (checkbox) to turn path repair off and patch CH8-12 signals only'],
                    'changes_from_0_1_1': ['RealFlight imports the unmodified vendor RFX; all edits happen after Import (no repacked archive, g3x.enc untouched)',
                                           'Asset paths repaired when non-ASCII, missing or vendor-rooted, matching how RF Evolution re-roots paths on Import',
                                           'Dead BasedOn paths repointed to an ASCII copy of the imported base model',
                                           'Commit-Plan no longer unrolls byte[] (4-model Finalize 29 s/2.9 GB -> ~2 s/0.6 GB); 0-byte targets handled',
                                           'Discovery tolerates unplugged Steam library drives and quoted registry paths',
                                           'Restore undoes only the FlightAxis INI keys after RealFlight rewrites its INI; per-model asset guard incl. colour schemes',
                                           'Offline: pinned source files next to the EXE are used after hash check; damaged cache entries are quarantined',
                                           'Case-sensitive actions, -Force on hidden targets, quoted-path UI crash fixed, atomic payload extraction, restore rollback state recorded',
                                           'Tests clean up their own folders']}
    testfile = ROOT / 'artifacts/sjarc-setup/test-results.json'
    assert testfile.exists(), 'Run installer tests before packaging'
    tests = json.loads(testfile.read_text('utf-8'))
    assert tests['success'] and tests['backend_sha256'] == sha(entries['Backend.ps1']), 'Rerun installer tests before packaging'
    assert tests.get('troubleshoot_sha256') == sha(entries['Troubleshoot.ps1']), 'Rerun installer tests before packaging'
    assert tests['program_sha256'] == sha((APP/'Program.cs').read_bytes()) and tests['selection_sha256'] == sha((APP/'TargetSelection.cs').read_bytes()), 'Rerun selection regression tests before packaging'
    verification['offline_tests'] = tests
    archive = ROOT / ('dist/SJARC-RealFlight-Setup-v' + VERSION + '.zip')
    with zipfile.ZipFile(str(archive), 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(str(exe), 'SJARC-RealFlight-Setup.exe')
        for name in ('README_KO.md',):
            z.writestr(name, entries[name])
        z.writestr('SHA256SUMS.txt', sha(exe.read_bytes()) + '  SJARC-RealFlight-Setup.exe\n')
        z.writestr('VERIFICATION.json', json.dumps(verification, indent=2))
    (out / 'README_KO.md').write_bytes(entries['README_KO.md'])
    (out / 'VERIFICATION.json').write_text(json.dumps(verification, indent=2), encoding='utf-8')
    checksum = archive.with_suffix(archive.suffix + '.sha256')
    checksum.write_text(sha(archive.read_bytes()) + '  ' + archive.name + '\n', encoding='ascii')
    print(json.dumps({'exe': str(exe), 'exe_bytes': exe.stat().st_size, 'exe_sha256': sha(exe.read_bytes()),
                      'zip': str(archive), 'zip_bytes': archive.stat().st_size, 'checksum': str(checksum)}, indent=2))


if __name__ == '__main__':
    main()
