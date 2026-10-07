"""Installer regression tests use isolated mock RF data; they never import into a running RealFlight."""
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest
import urllib.request
import zipfile
from datetime import datetime
from audit_mfe_signal_maps import audit

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'artifacts/sjarc-setup/build'
BASE = ROOT / 'artifacts/sjarc-setup/tests'
BASE.mkdir(parents=True, exist_ok=True)
PS = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
EXE = Path(r'C:\Program Files (x86)\Steam\steamapps\common\RealFlight Evolution\RealFlight64.exe')
CATALOG = json.loads((BUILD / 'models.json').read_text('utf-8'))
UPSTREAM = ROOT / 'artifacts/mfe-four-models/upstream'
# SitlParams.ps1 output for the pinned originals (same recipe as the field kit since v0.1.4, plus the load-twice header)
RF_SITL_SHA256 = {'Pioneer_VTOL_RF_SITL.param': '2e7c50d0f77f99196b7d627130ff866393353fee3969c9636a222c6fefb48f6d',
                  'Striver_VTOL_RF_SITL.param': '3dab6d4e7cf0411b6eaddd6b359d7bda2b2f25e4a81cb8f434aa35702ee84574'}
ASSETS = Path(r'C:\Users\Public\Documents\SJARC-Setup-Test')
# Fixed, isolated test assets only; never the production Public\Documents\SJARC\RF tree.
ASSETS.mkdir(exist_ok=True)
CSC = Path(os.environ['SystemRoot']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
VENDOR = 'C:\\Users\\Administrator\\Documents\\RealFlight 8\\'
INI = (b'[Physics]\r\nRealFlightLinkEnabled=BOOL:No\r\nPauseSimWhenFocusLost=BOOL:Yes\r\nPauseSimWhileInMenus=BOOL:Yes\r\n'
       b'PhysicsResetDelay2=FLOAT:0.\r\n\r\n[Other]\r\nUserKeep=INT:42\r\n')

# RealFlight 9.5-style INI/profile (key names as seen on the 2026-09-29 Icheon PC) for the troubleshooting tests.
RF9_INI = (b'[Main]\r\nFlightAxisLinkEnabled=BOOL:No\r\nPauseSimWhenFocusLost=BOOL:Yes\r\nPauseSimWhileInMenus=BOOL:No\r\n'
           b'PhysicsResetDelay2=FLOAT:2.\r\nPhysicsTimeScale=FLOAT:1.\r\nSetupFailureProbability=INT:5\r\n\r\n'
           b'[Controller]\r\nCurrentControllerSelection=STRING:4F541209-0000-0000-0000-504944564944\r\n\r\n'
           b'[Control|HIDController|4F541209-0000-0000-0000-504944564944]\r\nChannelMapName=STRING:TX16S\r\nManualCalibration=BOOL:Yes\r\n\r\n'
           b'[LicenseInfo]\r\nBio=STRING:private bio\r\nLocation=STRING:Icheon\r\n')
PROFILE = (b'[Main]\r\nEnableSoftwareRadioDualRatesAndExpo=BOOL:Yes\r\nEnableSoftwareRadioMixes=BOOL:Yes\r\n\r\n'
           b'[Reset]\r\nAction=INT:0\r\nInputPrimary=INT:17\r\nInputSecondary=INT:-1\r\nReverse=BOOL:No\r\n')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def model(key):
    return next(m for m in CATALOG if m['Key'] == key)


def asset_dir(root):
    """Same id as Backend.ps1 Assets-Root, so each test removes exactly what it created."""
    return ASSETS / sha(str(root).lower().encode('utf-8'))[:8]


def free_drive():
    return next(c for c in 'RQSTUVWXYZMNOP' if not os.path.exists(c + ':\\'))


def invoke(request, work):
    file = work / ('request-' + str(len(list(work.glob('request-*')))) + '.json')
    file.write_text(json.dumps(request), encoding='utf-8')
    p = subprocess.run([str(PS), '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                        '-File', str(BUILD / 'Backend.ps1'), '-RequestFile', str(file)],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    output = p.stdout.decode('utf-8-sig')
    try:
        result = json.loads(output)
    except Exception:
        raise AssertionError(output + '\n' + p.stderr.decode('utf-8', 'replace'))
    return p.returncode, result


def simulate_import(root, rfx):
    """Verbatim extraction: an RF build that keeps the archive's vendor paths."""
    with zipfile.ZipFile(str(rfx)) as z:
        for name in z.namelist():
            ext = Path(name).suffix.lower()
            group = {'.rfvehicle': 'CustomVehicles', '.bse': 'CustomModels', '.colorscheme': 'ColorSchemes',
                     '.electrictorque': 'Engines', '.battery': 'Batteries'}.get(ext)
            if group:
                p = root / 'Vehicles' / group / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(z.read(name))


RF_CONVERTED = b'<converted by RealFlight import>'


def simulate_rf_import(root, rfx):
    """Mimic RealFlight Evolution's Import as observed on 2026-08-02 (artifacts/path-repair/*.original,
    artifacts/kex-repair/*.kex.original): text-file paths are re-rooted to the user's RF folder (UTF-8),
    BasedOn becomes an absolute CustomModels path, and KEX/TGA land in CustomModels/<model>/. The KEX is
    converted (+4 bytes per material) but keeps the vendor texture path inside. Normal/specular maps are not shipped."""
    new_root = str(root) + '\\'
    with zipfile.ZipFile(str(rfx)) as z:
        names = z.namelist()
        bse_name = next(n for n in names if n.lower().endswith('.bse'))
        kex_ref = re.search(r'XK_FileName=STRING:([^\r\n]+)', z.read(bse_name).decode('latin-1')).group(1)
        model_dir = root / 'Vehicles/CustomModels' / kex_ref.split('\\')[-2]
        for name in names:
            ext = Path(name).suffix.lower()
            data = z.read(name)
            if ext == '.kex':
                data += RF_CONVERTED
            elif ext != '.tga':
                data = data.replace(VENDOR.encode('latin-1'), new_root.encode('utf-8'))
            if ext == '.rfvehicle':
                based_on = ('BasedOn=STRING:' + new_root + 'Vehicles\\CustomModels\\' + bse_name).encode('utf-8')
                data = re.sub(rb'(?m)^BasedOn=STRING:[^\r\n]*', lambda _: based_on, data)
                target = root / 'Vehicles/CustomVehicles' / name
            elif ext == '.bse':
                target = root / 'Vehicles/CustomModels' / name
            elif ext == '.colorscheme':
                target = root / 'Vehicles/ColorSchemes' / name
            elif ext in ('.kex', '.tga'):
                target = model_dir / name
            else:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


def set_line(data, key, value):
    line = (key + '=STRING:' + value).encode('utf-8')
    return re.sub(('(?m)^' + key + '=STRING:[^\\r\\n]*').encode(), lambda _: line, data)


class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata_dir = Path(tempfile.mkdtemp(prefix='rf9-metadata-', dir=str(BASE)))
        cls.rf9_exe = cls.metadata_dir / 'RealFlight.exe'
        subprocess.run([str(CSC), '/nologo', '/target:exe', '/out:' + str(cls.rf9_exe),
                        str(ROOT / 'scripts/fixtures/RealFlight9Metadata.cs')], check=True)
        cls.fake_sitl_exe = cls.metadata_dir / 'FakeSitl.exe'
        subprocess.run([str(CSC), '/nologo', '/target:exe', '/out:' + str(cls.fake_sitl_exe),
                        str(ROOT / 'scripts/fixtures/FakeSitl.cs')], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(str(cls.metadata_dir), ignore_errors=True)

    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='case-', dir=str(BASE)))
        self.cleanup = [self.work]
        self.ini = INI
        self.rf = self.make_root(self.work)
        self.cache = self.work / 'cache'
        self.cache.mkdir()
        for m in CATALOG:
            for name in (m['Rfx'], m['Param']):
                shutil.copyfile(str(UPSTREAM / m['Directory'] / name), str(self.cache / (m['Key'] + '-' + name)))

    def tearDown(self):
        for p in self.cleanup:
            if p.exists():
                subprocess.run(['attrib', '-h', '-r', str(p / '*'), '/s', '/d'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.rmtree(str(p), ignore_errors=True)

    def make_root(self, parent, name='RealFlight Evolution', ini_name='RealFlight64.ini'):
        root = Path(parent) / name
        root.mkdir(parents=True)
        (root / ini_name).write_bytes(INI)
        self.cleanup.append(asset_dir(root))
        return root

    def req(self, action='Prepare', keys=('S', 'P', 'F', 'H'), **extra):
        request = dict(Action=action, Executable=str(EXE), Root=str(self.rf), Models=list(keys),
                       Cache=str(self.cache), Brake=True, AssetBase=str(ASSETS))
        request.update(extra)
        return request

    def run_request(self, req=None, success=True):
        code, report = invoke(req or self.req(), self.work)
        self.assertEqual(code, 0 if success else 1, report)
        self.assertEqual(report['Success'], success, report)
        return report

    def check_patched(self, m, assets, brake=True):
        report = audit(self.rf / 'Vehicles/CustomVehicles' / m['Vehicle'])
        self.assertEqual([x['inputs'][0] for x in report['radio'][7:]], ['INT:107', 'INT:108', 'INT:109', 'INT:110', 'INT:111'])
        self.assertTrue(all(x['trim'] == 'FLOAT:0.' for x in report['radio'][7:]))
        forward = [x for x in report['motors'] if x['frame'] == 'STRING:~CS_ENGINE_P']
        self.assertEqual(forward[0]['brake'], 'BOOL:Yes' if brake else 'BOOL:No')
        folder = assets / m['Key']
        self.assertTrue(all(ord(c) < 128 for c in str(folder)))
        bse = (self.rf / 'Vehicles/CustomModels' / m['Bse']).read_bytes()
        color = (self.rf / 'Vehicles/ColorSchemes' / m['Color']).read_bytes()
        self.assertIn(('XK_FileName=STRING:' + str(folder / m['Kex'])).encode(), bse)
        stem = Path(m['Texture']).stem
        for key, name in (('TGAFileName', m['Texture']), ('NormalMap', stem + '_n.tga'), ('SpecularMap', stem + '_s.tga')):
            self.assertIn((key + '=STRING:' + str(folder / name)).encode(), color)
            self.assertTrue((folder / name).exists(), name)
        self.assertNotIn(VENDOR.encode(), (folder / m['Kex']).read_bytes())
        # The shared KEX must be RealFlight's own imported (converted) copy when one exists, else the vendor copy,
        # with only the fixed-length texture path buffer rewritten.
        with zipfile.ZipFile(str(UPSTREAM / m['Directory'] / m['Rfx'])) as z:
            vendor_kex = z.read(m['Kex'])
            old = re.search(rb'(?m)^TGAFileName=STRING:([^\r\n]+)', z.read(m['Color'])).group(1)
        imported = [p for p in (self.rf / 'Vehicles/CustomModels').rglob(m['Kex'])]
        base = imported[0].read_bytes() if imported else vendor_kex
        new = str(folder / m['Texture']).encode('latin-1')
        self.assertEqual((folder / m['Kex']).read_bytes(), base.replace(old, new + b'\0' * (len(old) - len(new))))
        self.assertEqual((self.rf / '.SJARC/Parameters' / m['Param']).read_bytes(),
                         (UPSTREAM / m['Directory'] / m['Param']).read_bytes())

    def test_detects_real_install_not_trainer_or_workspace(self):
        r = self.run_request(dict(Action='Detect'))
        self.assertTrue(any(x['Path'] == str(EXE) for x in r['Installations']))
        self.assertTrue(all('Trainer' not in x['Path'] for x in r['Installations']))
        self.assertTrue(all(Path(x).name != ROOT.name for x in r['Roots']))

    def test_manual_executable_selection_is_validated_read_only(self):
        r = self.run_request(dict(Action='InspectExecutable', Executable=str(EXE)))
        self.assertEqual(r['Installation']['Edition'], 'Evolution')
        self.assertEqual((self.rf / 'RealFlight64.ini').read_bytes(), self.ini)
        self.assertFalse((self.rf / '.SJARC').exists())
        r = self.run_request(dict(Action='InspectExecutable', Executable=str(self.rf9_exe)))
        self.assertEqual(r['Installation']['Edition'], '9 / 9.5 / 9.5S')
        self.assertIn('Select RealFlight.exe', self.run_request(dict(Action='InspectExecutable', Executable=str(PS)), success=False)['Error'])

    def discover(self, locations):
        def quote(path):
            return "'" + str(path).replace("'", "''") + "'"
        command = ("$ErrorActionPreference='Stop'; . " + quote(BUILD / 'Backend.ps1') + ' -LibraryOnly; @(Find-Installations @('
                   + ','.join(quote(x) for x in locations) + ')) | ConvertTo-Json -Depth 5')
        result = subprocess.run([str(PS), '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', command],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', 'replace'))
        found = json.loads(result.stdout.decode('utf-8-sig'))
        return found if isinstance(found, list) else [found]

    def test_coexisting_installation_discovery_does_not_collapse_versions(self):
        found = self.discover([self.metadata_dir, EXE.parent, self.metadata_dir])
        self.assertEqual(len(found), 2)
        self.assertEqual({x['Edition'] for x in found}, {'9 / 9.5 / 9.5S', 'Evolution'})
        self.assertEqual({x['Path'] for x in found}, {str(EXE), str(self.rf9_exe)})

    def test_discovery_survives_unplugged_drive_and_quoted_registry_paths(self):
        found = self.discover([free_drive() + ':\\SteamLibrary\\steamapps\\common\\RealFlight 9.5',
                               '"' + str(self.metadata_dir) + '"', ' '])
        self.assertEqual([x['Path'] for x in found], [str(self.rf9_exe)])

    def test_evolution_cannot_patch_rf9_data(self):
        root = self.make_root(self.work, 'RealFlight 9', 'RealFlight.ini')
        req = self.req(); req['Root'] = str(root)
        self.assertIn('do not match', self.run_request(req, success=False)['Error'])
        self.assertEqual((root / 'RealFlight.ini').read_bytes(), self.ini)
        self.assertFalse((root / '.SJARC').exists())

    def test_rf9_cannot_patch_evolution_data(self):
        req = self.req(); req['Executable'] = str(self.rf9_exe)
        self.assertIn('do not match', self.run_request(req, success=False)['Error'])
        self.assertEqual((self.rf / 'RealFlight64.ini').read_bytes(), self.ini)
        self.assertFalse((self.rf / '.SJARC').exists())

    def test_coexisting_user_data_and_backups_stay_separate(self):
        root9 = self.make_root(self.work, 'RealFlight 9', 'RealFlight.ini')
        r = self.run_request(self.req(keys=('H',)))
        self.assertEqual((root9 / 'RealFlight.ini').read_bytes(), self.ini)
        self.assertFalse((root9 / '.SJARC').exists())
        snapshot = lambda: {str(p.relative_to(self.rf)): sha(p.read_bytes()) for p in self.rf.rglob('*') if p.is_file()}
        evo_snapshot = snapshot()
        req9 = self.req(keys=('H',)); req9['Root'] = str(root9); req9['Executable'] = str(self.rf9_exe)
        r9 = self.run_request(req9)
        self.assertNotEqual(r['Assets'], r9['Assets'])
        self.assertTrue(r9['Transaction']['Manifest'].startswith(str(root9)))
        self.assertEqual(evo_snapshot, snapshot())
        restore9 = dict(req9, Action='Restore', Manifest=r['Transaction']['Manifest'])
        self.assertIn('under this RF', self.run_request(restore9, success=False)['Error'])
        restore9['Manifest'] = r9['Transaction']['Manifest']; self.run_request(restore9)
        self.assertEqual((root9 / 'RealFlight.ini').read_bytes(), self.ini)
        self.assertEqual(evo_snapshot, snapshot())

    def test_form_target_selection_policy(self):
        exe = self.work / 'TargetSelectionTests.exe'
        subprocess.run([str(CSC), '/nologo', '/target:exe', '/out:' + str(exe),
                        str(ROOT / 'apps/SJARC-RealFlight-Setup/TargetSelection.cs'),
                        str(ROOT / 'scripts/fixtures/TargetSelectionTests.cs')], check=True)
        result = subprocess.run([str(exe)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        self.assertIn('Target selection checks passed: 19', result.stdout.decode('utf-8'))

    def test_new_four_models_import_original_archive_then_finalize(self):
        r = self.run_request()
        self.assertEqual(r['State'], 'IMPORT_REQUIRED')
        self.assertEqual(len(r['Models']), 4)
        for entry in r['Models']:
            rfx = Path(entry['Rfx'])
            spec = next(m for m in CATALOG if m['Rfx'] == rfx.name)
            self.assertEqual(sha(rfx.read_bytes()), spec['RfxSha256'])  # unmodified vendor archive, g3x.enc intact
            simulate_rf_import(self.rf, rfx)
        final = self.run_request(self.req('Finalize'))
        self.assertEqual(final['State'], 'FILES_VERIFIED')
        for m in CATALOG:
            self.check_patched(m, Path(final['Assets']))
            vehicle = (self.rf / 'Vehicles/CustomVehicles' / m['Vehicle']).read_bytes()
            # RealFlight's own (existing) BasedOn reference is kept.
            self.assertIn(('BasedOn=STRING:' + str(self.rf) + '\\Vehicles\\CustomModels\\' + m['Bse']).encode('utf-8'), vehicle)
        self.assertEqual(self.run_request(self.req('Finalize'))['Transaction']['Changed'], 0)

    def test_ascii_profile_rf_import_gets_missing_maps(self):
        parent = Path(tempfile.mkdtemp(prefix='rf-', dir=str(ASSETS)))
        self.cleanup.append(parent)
        self.rf = self.make_root(parent)
        h = model('H')
        r = self.run_request(self.req(keys=('H',)))
        simulate_rf_import(self.rf, Path(r['Models'][0]['Rfx']))
        final = self.run_request(self.req('Finalize', keys=('H',)))
        self.assertTrue(any('NormalMap file missing' in n for n in final['Notes']), final['Notes'])
        self.check_patched(h, Path(final['Assets']))

    def test_known_good_assets_kept_and_dead_basedon_repointed(self):
        s = model('S')
        rfx = self.cache / ('S-' + s['Rfx'])
        simulate_import(self.rf, rfx)
        custom = Path(tempfile.mkdtemp(prefix='custom-', dir=str(ASSETS)))
        self.cleanup.append(custom)
        with zipfile.ZipFile(str(rfx)) as z:
            (custom / s['Kex']).write_bytes(z.read(s['Kex']).replace(VENDOR.encode(), b'X' * len(VENDOR)))
            (custom / s['Texture']).write_bytes(z.read(s['Texture']))
        stem = Path(s['Texture']).stem
        for suffix in ('_n.tga', '_s.tga'):
            (custom / (stem + suffix)).write_bytes(b'x')
        bse_path = self.rf / 'Vehicles/CustomModels' / s['Bse']
        bse = set_line(bse_path.read_bytes(), 'XK_FileName', str(custom / s['Kex']))
        bse_path.write_bytes(bse)
        color_path = self.rf / 'Vehicles/ColorSchemes' / s['Color']
        color = color_path.read_bytes()
        for key, name in (('TGAFileName', s['Texture']), ('NormalMap', stem + '_n.tga'), ('SpecularMap', stem + '_s.tga'), ('DDSFileName', stem + '.dds')):
            color = set_line(color, key, str(custom / name))
        color = set_line(color, 'TexturePath', str(custom))
        color_path.write_bytes(color)
        vp = self.rf / 'Vehicles/CustomVehicles' / s['Vehicle']
        vp.write_bytes(set_line(vp.read_bytes(), 'BasedOn', free_drive() + ':\\Vehicles\\CustomModels\\' + s['Bse']))
        r = self.run_request(self.req(keys=('S',)))
        self.assertEqual(r['State'], 'FILES_VERIFIED')
        self.assertEqual(bse_path.read_bytes(), bse)
        self.assertEqual(color_path.read_bytes(), color)
        shared_bse = Path(r['Assets']) / 'S' / s['Bse']
        self.assertIn(('BasedOn=STRING:' + str(shared_bse)).encode(), vp.read_bytes())
        self.assertEqual(shared_bse.read_bytes(), bse)
        self.assertTrue(any('kept' in n for n in r['Notes']), r['Notes'])
        self.assertEqual(audit(vp)['radio'][8]['inputs'], ['INT:108'])

    def test_existing_vehicle_preserves_custom_physics_and_roll(self):
        m = CATALOG[0]
        simulate_import(self.rf, self.cache / (m['Key'] + '-' + m['Rfx']))
        p = self.rf / 'Vehicles/CustomVehicles' / m['Vehicle']
        data = p.read_bytes().replace(b'RollIntertia=FLOAT:100.', b'RollIntertia=FLOAT:111.')
        p.write_bytes(data)
        r = self.run_request(self.req(keys=('S',)))
        self.assertEqual(r['State'], 'FILES_VERIFIED')
        self.assertFalse((self.rf / 'RFX/SJARC' / m['Rfx']).exists())
        self.check_patched(m, Path(r['Assets']))
        after = p.read_bytes()
        for key in (b'RollIntertia=', b'PitchIntertia=', b'CGAdjustmentMTR='):
            self.assertEqual([line for line in after.splitlines() if line.startswith(key)], [line for line in data.splitlines() if line.startswith(key)])
        again = self.run_request(self.req(keys=('S',)))
        self.assertEqual(again['Transaction']['Changed'], 0)
        restore = self.req('Restore', keys=('S',)); restore['Manifest'] = r['Transaction']['Manifest']
        self.run_request(restore)
        self.assertEqual(p.read_bytes(), data)

    def test_incompatible_motor_map_stops_all_writes(self):
        m = CATALOG[1]
        simulate_import(self.rf, self.cache / (m['Key'] + '-' + m['Rfx']))
        p = self.rf / 'Vehicles/CustomVehicles' / m['Vehicle']
        p.write_bytes(p.read_bytes().replace(b'ConnectTo_InternalName=INT:11', b'ConnectTo_InternalName=INT:12'))
        r = self.run_request(success=False)
        self.assertIn('Unsupported wiring', r['Error'])
        self.assertEqual((self.rf / 'RealFlight64.ini').read_bytes(), self.ini)
        self.assertFalse((self.rf / '.SJARC/Backups').exists())

    def test_damaged_cache_is_quarantined_and_replaced_from_local_source(self):
        m = CATALOG[0]
        (self.cache / (m['Key'] + '-' + m['Rfx'])).write_bytes(b'wrong hash')
        r = self.run_request(self.req(keys=('S',), SourceFolder=str(UPSTREAM / m['Directory'])))
        self.assertTrue(any('Damaged cached source' in w for w in r['Warnings']), r['Warnings'])
        self.assertEqual(sha((self.cache / (m['Key'] + '-' + m['Rfx'])).read_bytes()), m['RfxSha256'])
        self.assertEqual(len(list((self.cache / 'quarantine').glob('*' + m['Rfx']))), 1)

    def test_offline_source_folder_is_used_after_hash_check(self):
        cache = self.work / 'empty-cache'; cache.mkdir()
        usb = self.work / 'usb'; usb.mkdir()
        h = model('H')
        for name in (h['Rfx'], h['Param']):
            shutil.copyfile(str(UPSTREAM / h['Directory'] / name), str(usb / name))
        r = self.run_request(self.req(keys=('H',), Cache=str(cache), SourceFolder=str(usb)))
        self.assertTrue(any('source files taken from' in n for n in r['Notes']), r['Notes'])
        self.assertEqual(sha((cache / ('H-' + h['Rfx'])).read_bytes()), h['RfxSha256'])

    def test_wrong_hash_local_file_is_never_used(self):
        try:
            urllib.request.urlopen(model('H')['BaseUrl'] + model('H')['Param'], timeout=10).read()
        except Exception:
            self.skipTest('GitHub not reachable')
        h = model('H')
        (self.cache / ('H-' + h['Param'])).unlink()
        usb = self.work / 'usb'; usb.mkdir()
        (usb / h['Param']).write_bytes(b'SERVO9_FUNCTION,0\r\n')
        r = self.run_request(self.req(keys=('H',), SourceFolder=str(usb)))
        self.assertTrue(any('Ignored local file' in w for w in r['Warnings']), r['Warnings'])
        self.assertEqual(sha((self.rf / '.SJARC/Parameters' / h['Param']).read_bytes()), h['ParamSha256'])

    def test_wrong_user_data_edition_refused(self):
        root = self.make_root(self.work, 'RealFlight 8', 'RealFlight.ini')
        req = self.req(); req['Root'] = str(root)
        self.assertIn('do not match', self.run_request(req, success=False)['Error'])

    def test_missing_import_refused(self):
        r = self.run_request(self.req('Finalize'), success=False)
        self.assertIn('Import missing', r['Error'])
        self.assertFalse((self.rf / '.SJARC/Backups').exists())

    def test_non_realflight_executable_refused(self):
        req = self.req(); req['Executable'] = str(PS)
        self.assertIn('Select RealFlight.exe', self.run_request(req, success=False)['Error'])

    def test_action_names_are_case_sensitive(self):
        self.assertIn('Unknown action', self.run_request(self.req('restore'), success=False)['Error'])
        self.assertEqual((self.rf / 'RealFlight64.ini').read_bytes(), self.ini)
        self.assertFalse((self.rf / '.SJARC').exists())

    def test_two_inis_only_the_selected_executables_is_edited(self):
        (self.rf / 'RealFlight.ini').write_bytes(self.ini)
        self.run_request(self.req(keys=('H',)))
        self.assertEqual((self.rf / 'RealFlight.ini').read_bytes(), self.ini)
        self.assertIn(b'RealFlightLinkEnabled=BOOL:Yes', (self.rf / 'RealFlight64.ini').read_bytes())

    def test_report_port_inventory_without_connection(self):
        report = self.run_request(dict(Action='Probe'))
        self.assertEqual([p['Port'] for p in report['Ports']], [18083, 5760])
        self.assertIn('No connection', report['Message'])

    def test_prepare_restore_is_exact_before_import(self):
        r = self.run_request(self.req(keys=('H',)))
        req = self.req('Restore', keys=('H',)); req['Manifest'] = r['Transaction']['Manifest']
        restored = self.run_request(req)
        self.assertEqual(restored['State'], 'Restored')
        self.assertEqual((self.rf / 'RealFlight64.ini').read_bytes(), self.ini)
        self.assertFalse((self.rf / 'RFX/SJARC/HERO_EA.RFX').exists())
        self.assertTrue(list(Path(restored['Recovery']).glob('*.new-file')))

    def test_additional_edit_blocks_restore(self):
        r = self.run_request(self.req(keys=('H',)))
        (self.rf / 'RFX/SJARC/HERO_EA.RFX').write_bytes(b'user changed')
        req = self.req('Restore', keys=('H',)); req['Manifest'] = r['Transaction']['Manifest']
        self.assertIn('changed since setup', self.run_request(req, success=False)['Error'])

    def test_ini_rewritten_by_realflight_restores_only_tool_keys(self):
        r = self.run_request(self.req(keys=('H',)))
        ini = self.rf / 'RealFlight64.ini'
        ini.write_bytes(ini.read_bytes() + b'LastAircraft=STRING:HERO2180\r\n')  # RF saves its INI on exit
        req = self.req('Restore', keys=('H',)); req['Manifest'] = r['Transaction']['Manifest']
        restored = self.run_request(req)
        self.assertEqual(ini.read_bytes(), self.ini + b'LastAircraft=STRING:HERO2180\r\n')
        self.assertTrue(restored['Notes'])

    def test_restore_guard_is_per_model_and_scans_colour_schemes(self):
        prepared = self.run_request(self.req(keys=('S', 'H')))
        for entry in prepared['Models']:
            simulate_rf_import(self.rf, Path(entry['Rfx']))
        fh = self.run_request(self.req('Finalize', keys=('H',)))
        fs = self.run_request(self.req('Finalize', keys=('S',)))
        s = model('S')
        copy = self.rf / 'Vehicles/ColorSchemes' / ('copy-' + s['Color'])
        shutil.copyfile(str(self.rf / 'Vehicles/ColorSchemes' / s['Color']), str(copy))  # a saved paint variant
        req = self.req('Restore', keys=('S',)); req['Manifest'] = fs['Transaction']['Manifest']
        self.assertIn('still use the shared S assets', self.run_request(req, success=False)['Error'])
        copy.unlink()
        self.run_request(req)  # Hero's shared assets do not block undoing Striver
        self.assertTrue((Path(fh['Assets']) / 'H' / model('H')['Kex']).exists())
        self.assertFalse((Path(fs['Assets']) / 'S' / s['Kex']).exists())

    def test_rf_sitl_parameter_files_are_made_from_the_verified_originals(self):
        r = self.run_request(self.req(keys=('S', 'P', 'H')))
        params = self.rf / '.SJARC/Parameters'
        # Pioneer and Striver get a RealFlight SITL file; Fighter and Hero keep using the original + MotorMap.
        self.assertEqual(sorted(p.name for p in params.glob('*_RF_SITL.param')), sorted(RF_SITL_SHA256))
        for name, digest in RF_SITL_SHA256.items():
            data = (params / name).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), digest, name)
            text = data.decode('utf-8')
            for needle in ('SERVO11_FUNCTION,36', 'SERVO12_FUNCTION,35', 'Q_ENABLE,1', 'Q_ASSIST_SPEED,14', 'AIRSPEED_MIN,',
                           'load and write this file once more'):
                self.assertIn(needle, text, name)
            self.assertNotIn('\nFLTMODE_CH,', text)
        for key in ('S', 'P', 'H'):
            m = model(key)
            self.assertEqual((params / m['Param']).read_bytes(), (UPSTREAM / m['Directory'] / m['Param']).read_bytes())
        req = self.req('Restore', keys=('S', 'P', 'H')); req['Manifest'] = r['Transaction']['Manifest']
        self.run_request(req)
        self.assertEqual(list(params.glob('*_RF_SITL.param')), [])

    def test_zero_byte_and_hidden_targets_do_not_abort(self):
        params = self.rf / '.SJARC/Parameters'; params.mkdir(parents=True)
        h = model('H')
        (params / h['Param']).write_bytes(b'')
        hidden = params / 'MFE_MotorMap_ONLY.param'; hidden.write_bytes(b'old')
        subprocess.run(['attrib', '+h', str(hidden)], check=True)
        r = self.run_request(self.req(keys=('H',)))
        self.assertEqual((params / h['Param']).read_bytes(), (UPSTREAM / h['Directory'] / h['Param']).read_bytes())
        self.assertEqual(hidden.read_bytes(), (BUILD / 'MotorMap.param').read_bytes())
        req = self.req('Restore', keys=('H',)); req['Manifest'] = r['Transaction']['Manifest']
        self.run_request(req)
        self.assertEqual((params / h['Param']).read_bytes(), b'')
        self.assertEqual(hidden.read_bytes(), b'old')

    def test_running_rf_guard_blocks_before_any_changes(self):
        helper = self.work / 'RealFlightWizardGuard.exe'
        shutil.copyfile(str(Path(os.environ['SystemRoot']) / 'System32/cmd.exe'), str(helper))
        p = subprocess.Popen([str(helper), '/D', '/C', 'set /p SJARC_TEST='], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            self.assertIsNone(p.poll())
            self.assertIn('Close RealFlight', self.run_request(success=False)['Error'])
            self.assertFalse((self.rf / '.SJARC/Backups').exists())
        finally:
            p.communicate(b'done\r\n', timeout=10)

    def test_brake_option_applies_after_import(self):
        h = model('H')
        r = self.run_request(self.req(keys=('H',), Brake=False))
        simulate_rf_import(self.rf, Path(r['Models'][0]['Rfx']))
        final = self.run_request(self.req('Finalize', keys=('H',), Brake=False))
        self.check_patched(h, Path(final['Assets']), brake=False)
        final = self.run_request(self.req('Finalize', keys=('H',), Brake=True))
        self.check_patched(h, Path(final['Assets']), brake=True)

    def test_path_repair_off_patches_signals_only(self):
        s = model('S')
        r = self.run_request(self.req(keys=('S',)))
        simulate_rf_import(self.rf, Path(r['Models'][0]['Rfx']))
        bse = (self.rf / 'Vehicles/CustomModels' / s['Bse']).read_bytes()
        color = (self.rf / 'Vehicles/ColorSchemes' / s['Color']).read_bytes()
        final = self.run_request(self.req('Finalize', keys=('S',), RepairPaths=False))
        self.assertTrue(any('path repair turned off' in n for n in final['Notes']), final['Notes'])
        self.assertEqual((self.rf / 'Vehicles/CustomModels' / s['Bse']).read_bytes(), bse)
        self.assertEqual((self.rf / 'Vehicles/ColorSchemes' / s['Color']).read_bytes(), color)
        self.assertFalse((Path(final['Assets']) / 'S').exists())
        report = audit(self.rf / 'Vehicles/CustomVehicles' / s['Vehicle'])
        self.assertEqual([x['inputs'][0] for x in report['radio'][7:]], ['INT:107', 'INT:108', 'INT:109', 'INT:110', 'INT:111'])

    def test_v012_vendor_kex_is_rebuilt_from_realflight_import(self):
        # Field state from 2026-09-29 (RF 9, v0.1.2): shared KEX made from the vendor copy. v0.1.3 must rebuild it
        # from RealFlight's own converted copy on the next run.
        h = model('H')
        r = self.run_request(self.req(keys=('H',)))
        simulate_rf_import(self.rf, Path(r['Models'][0]['Rfx']))
        imported = next((self.rf / 'Vehicles/CustomModels').rglob(h['Kex']))
        hidden = imported.with_name(imported.name + '.away')
        imported.rename(hidden)
        first = self.run_request(self.req('Finalize', keys=('H',)))
        self.assertTrue(any('model file from vendor archive' in n for n in first['Notes']), first['Notes'])
        shared = Path(first['Assets']) / 'H' / h['Kex']
        self.assertFalse(shared.read_bytes().endswith(RF_CONVERTED))
        hidden.rename(imported)
        second = self.run_request(self.req('Finalize', keys=('H',)))
        self.assertTrue(any('model file from RealFlight import' in n for n in second['Notes']), second['Notes'])
        self.assertGreater(second['Transaction']['Changed'], 0)
        self.assertTrue(shared.read_bytes().endswith(RF_CONVERTED))
        self.check_patched(h, Path(second['Assets']))

    def test_manifest_traversal_refused(self):
        r = self.run_request(self.req(keys=('H',)))
        path = Path(r['Transaction']['Manifest']); manifest = json.loads(path.read_text('utf-8'))
        manifest['Entries'][0]['Relative'] = '..\\outside.txt'
        path.write_text(json.dumps(manifest), encoding='utf-8')
        req = self.req('Restore', keys=('H',)); req['Manifest'] = str(path)
        self.assertIn('Unsafe relative path', self.run_request(req, success=False)['Error'])

    # ---- v0.1.4: RF 8/9 signals only ----
    def test_rf9_finalize_patches_signals_only_and_keeps_import_paths(self):
        s = model('S')
        self.rf = self.make_root(self.work / 'rf9', 'RealFlight 9', 'RealFlight.ini')
        (self.rf / 'RealFlight.ini').write_bytes(self.ini.replace(b'RealFlightLinkEnabled', b'FlightAxisLinkEnabled'))
        r = self.run_request(self.req(keys=('S',), Executable=str(self.rf9_exe)))
        simulate_rf_import(self.rf, Path(r['Models'][0]['Rfx']))
        bse = (self.rf / 'Vehicles/CustomModels' / s['Bse']).read_bytes()
        color = (self.rf / 'Vehicles/ColorSchemes' / s['Color']).read_bytes()
        final = self.run_request(self.req('Finalize', keys=('S',), Executable=str(self.rf9_exe), RepairPaths=True))
        self.assertTrue(any('left as RealFlight imported them' in n for n in final['Notes']), final['Notes'])
        self.assertEqual((self.rf / 'Vehicles/CustomModels' / s['Bse']).read_bytes(), bse)
        self.assertEqual((self.rf / 'Vehicles/ColorSchemes' / s['Color']).read_bytes(), color)
        self.assertFalse((Path(final['Assets']) / 'S').exists())
        report = audit(self.rf / 'Vehicles/CustomVehicles' / s['Vehicle'])
        self.assertEqual([x['inputs'][0] for x in report['radio'][7:]], ['INT:107', 'INT:108', 'INT:109', 'INT:110', 'INT:111'])
        self.assertIn(b'FlightAxisLinkEnabled=BOOL:Yes', (self.rf / 'RealFlight.ini').read_bytes())
        self.assertFalse(any('Set manually' in w and 'Link' in w for w in final['Warnings']), final['Warnings'])

    # ---- v0.1.5: connection troubleshooting ----
    def make_mp(self):
        mp = self.work / 'Mission Planner'
        store = mp / 'sitl' / 'flightaxis'
        (store / 'logs').mkdir(parents=True)
        (store / 'eeprom.bin').write_bytes(bytes(range(256)) * 64)
        (store / 'logs' / '00000001.BIN').write_bytes(b'log')
        (mp / 'sitl' / 'PlaneStable-git.txt').write_bytes(b'commit 1511f27\nAuthor: x\n\n    Plane: version to 4.7.0\n')
        return mp

    def snapshot(self, *folders):
        return {str(p.relative_to(f)): sha(p.read_bytes()) for f in folders for p in sorted(Path(f).rglob('*')) if p.is_file()}

    def rf9_root(self):
        root = self.make_root(self.work / 'rf9', 'RealFlight 9', 'RealFlight.ini')
        (root / 'RealFlight.ini').write_bytes(RF9_INI)
        (root / 'Radio Profiles').mkdir()
        (root / 'Radio Profiles' / 'TX16S.radioprofile').write_bytes(PROFILE)
        return root

    def fake_sitl(self, exe, *args):
        # cmd.exe copy that waits on stdin; extra arguments only show up in its command line (like SITL's -M model).
        exe.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(Path(os.environ['SystemRoot']) / 'System32/cmd.exe'), str(exe))
        return subprocess.Popen([str(exe), '/D', '/C', 'set /p SJARC_TEST='] + list(args), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)

    def test_diagnose_is_read_only_and_reports_link_controller_and_sitl(self):
        root = self.rf9_root()
        mp = self.make_mp()
        before = (self.snapshot(root), self.snapshot(mp))
        r = self.run_request(dict(Action='Diagnose', Executable=str(self.rf9_exe), Root=str(root),
                                  MissionPlannerRoot=str(mp), ReportFolder=str(self.work / 'reports')))
        self.assertEqual((self.snapshot(root), self.snapshot(mp)), before)
        text = Path(r['ReportFile']).read_text('utf-8-sig')
        for needle in ('FlightAxisLinkEnabled = BOOL:No', 'CurrentControllerSelection = STRING:4F541209',
                       '[Reset] InputPrimary=INT:17', 'flightaxis\\eeprom.bin', 'Plane: version to 4.7.0', '<- 현재 선택'):
            self.assertIn(needle, text)
        summary = '\n'.join(r['Summary'])
        for needle in ('FlightAxisLinkEnabled', 'Setup Failures', '#17', 'PauseSimWhenFocusLost', 'Dual Rates'):
            self.assertIn(needle, summary)
        self.assertGreaterEqual(r['Problems'], 2)
        with zipfile.ZipFile(r['Bundle']) as z:
            names = z.namelist()
            ini = z.read(next(n for n in names if n.endswith('RealFlight_9/RealFlight.ini')))
        self.assertIn('diagnose.txt', names)
        self.assertTrue(any(n.endswith('/Radio Profiles/TX16S.radioprofile') for n in names), names)
        self.assertIn(b'Bio=(removed)', ini)
        self.assertNotIn(b'private bio', ini)
        self.assertNotIn(b'Icheon', ini)
        self.assertIn(b'CurrentControllerSelection=STRING:4F541209', ini)

    def test_diagnose_flags_sitl_started_without_flightaxis(self):
        # 2026-09-30 Icheon video: RF aircraft tumbling while Mission Planner showed a still vehicle at 12.60 V.
        mp = self.make_mp()
        (mp / 'sitl' / 'plane').mkdir()
        (mp / 'sitl' / 'plane' / 'eeprom.bin').write_bytes(b'\0' * 16)
        old = mp / 'sitl' / 'flightaxis' / 'eeprom.bin'
        os.utime(str(old), (old.stat().st_atime, old.stat().st_mtime - 3600))
        sitl = self.fake_sitl(mp / 'sitl' / 'ArduPlane.exe', '-Mplane', '-O-35.363,149.165,584,0')
        rf = self.fake_sitl(self.work / 'rf' / 'RealFlightStandIn.exe')
        try:
            r = self.run_request(dict(Action='Diagnose', MissionPlannerRoot=str(mp), ReportFolder=str(self.work / 'reports')))
        finally:
            for p in (sitl, rf):
                p.communicate(b'done\r\n', timeout=10)
        summary = '\n'.join(r['Summary'])
        self.assertIn('"plane" 모델로 실행 중', summary)
        self.assertIn('flightaxis 저장소보다 최근', summary)
        self.assertIn('18083에서 대기하지 않습니다', summary)
        self.assertIn('-Mplane', Path(r['ReportFile']).read_text('utf-8-sig'))

    def test_diagnose_quiet_when_sitl_uses_flightaxis(self):
        mp = self.make_mp()
        sitl = self.fake_sitl(mp / 'sitl' / 'ArduPlane.exe', '-Mflightaxis', '-O-35.363,149.165,584,0')
        try:
            r = self.run_request(dict(Action='Diagnose', MissionPlannerRoot=str(mp), ReportFolder=str(self.work / 'reports')))
        finally:
            sitl.communicate(b'done\r\n', timeout=10)
        summary = '\n'.join(r['Summary'])
        self.assertNotIn('모델로 실행 중', summary)
        self.assertNotIn('저장소보다 최근', summary)

    def test_status_reads_link_pause_controller_and_sitl_model(self):
        root = self.rf9_root()
        mp = self.make_mp()
        before = self.snapshot(root)
        r = self.run_request(dict(Action='Status', Executable=str(self.rf9_exe), Root=str(root)))
        self.assertEqual((r['LinkEnabled'], r['PauseOn'], r['ControllerSelected'], r['Ini']), (False, True, True, 'RealFlight.ini'))
        self.assertEqual(self.snapshot(root), before)
        sitl = self.fake_sitl(mp / 'sitl' / 'ArduPlane.exe', '-Mplane')
        try:
            r = self.run_request(dict(Action='Status', Root=str(root)))
        finally:
            sitl.communicate(b'done\r\n', timeout=10)
        self.assertTrue(r['SitlRunning'])
        self.assertIs(r['SitlFlightAxis'], False)
        (root / 'RealFlight.ini').write_bytes(RF9_INI.replace(b'FlightAxisLinkEnabled=BOOL:No', b'FlightAxisLinkEnabled=BOOL:Yes')
                                              .replace(b'PauseSimWhenFocusLost=BOOL:Yes', b'PauseSimWhenFocusLost=BOOL:No'))
        r = self.run_request(dict(Action='Status', Root=str(root)))
        self.assertEqual((r['LinkEnabled'], r['PauseOn']), (True, False))
        empty = self.run_request(dict(Action='Status', Root=''))
        self.assertIsNone(empty['LinkEnabled'])
        self.assertIsNone(empty['ControllerSelected'])

    def install_fake_sitl(self, mp):
        target = mp / 'sitl' / 'ArduPlane.exe'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(self.fake_sitl_exe), str(target))
        return target

    def sitl_record(self, mp):
        record = mp / 'sitl' / 'flightaxis' / 'fake-sitl.txt'
        for _ in range(100):
            if record.exists() and record.stat().st_size:
                break
            time.sleep(0.1)
        lines = record.read_text('utf-8').splitlines()
        return lines[0], Path(lines[1])

    def start_sitl(self, mp, success=True):
        return self.run_request(dict(Action='StartSitl', MissionPlannerRoot=str(mp), StartPlanner=False, HideWindow=True), success=success)

    def test_start_sitl_runs_flightaxis_in_its_store_with_udp_for_mission_planner(self):
        mp = self.make_mp()
        (mp / 'config.xml').write_text('<?xml version="1.0"?><Config><maplast_lat>37.2</maplast_lat><maplast_lng>127.4</maplast_lng></Config>', encoding='utf-8')
        self.install_fake_sitl(mp)
        rf = self.fake_sitl(self.work / 'rf' / 'RealFlightStandIn.exe')
        try:
            r = self.start_sitl(mp)
            self.assertEqual(r['State'], 'SITL_STARTED')
            line, cwd = self.sitl_record(mp)
            for needle in ('-Mflightaxis', '-O37.2,127.4,0,0', '-s1', '--serial0 tcp:0', '--serial1 udpclient:127.0.0.1:14550'):
                self.assertIn(needle, line)
            self.assertNotIn('--wipe', line)
            self.assertEqual(cwd, mp / 'sitl' / 'flightaxis')
            self.assertTrue((mp / 'sitl' / 'flightaxis' / 'eeprom.bin').exists())
            self.assertIsNone(r['AutoConnect'])  # no saved list: Mission Planner's default (UDP 14550 on) applies
            self.assertIn('already running', self.start_sitl(mp, success=False)['Error'])
            self.assertIs(self.run_request(dict(Action='Status', Root=''))['SitlFlightAxis'], True)
        finally:
            self.run_request(dict(Action='StopSitl', MissionPlannerRoot=str(mp)))
            rf.communicate(b'done\r\n', timeout=10)

    def test_start_sitl_reports_auto_connect_off_and_uses_default_home(self):
        mp = self.make_mp()
        listing = json.dumps([{'Label': 'Mavlink default port', 'Enabled': False, 'Port': 14550, 'Protocol': 1, 'Direction': 0, 'Format': 0}])
        (mp / 'config.xml').write_text('<?xml version="1.0"?><Config><AutoConnect>' + html.escape(listing) + '</AutoConnect></Config>', encoding='utf-8')
        self.install_fake_sitl(mp)
        rf = self.fake_sitl(self.work / 'rf' / 'RealFlightStandIn.exe')
        try:
            r = self.start_sitl(mp)
            self.assertIs(r['AutoConnect'], False)
            self.assertTrue(any('auto-connect' in w for w in r['Warnings']), r['Warnings'])
            self.assertTrue(any('18083' in w for w in r['Warnings']), r['Warnings'])  # the stand-in RealFlight does not listen
            self.assertIn('-O-35.363261,149.16523,584,0', self.sitl_record(mp)[0])
        finally:
            self.run_request(dict(Action='StopSitl', MissionPlannerRoot=str(mp)))
            rf.communicate(b'done\r\n', timeout=10)

    def test_start_sitl_needs_the_downloaded_sitl_and_realflight(self):
        mp = self.make_mp()
        self.assertIn('No ArduPlane SITL', self.start_sitl(mp, success=False)['Error'])
        self.install_fake_sitl(mp)
        running = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq RealFlight*'], stdout=subprocess.PIPE).stdout.decode('mbcs', 'replace')
        if 'RealFlight' in running:
            self.skipTest('a real RealFlight is running on this PC')
        self.assertIn('Start RealFlight', self.start_sitl(mp, success=False)['Error'])
        self.assertFalse((mp / 'sitl' / 'flightaxis' / 'fake-sitl.txt').exists())

    def test_sitl_store_reset_moves_aside_and_restore_brings_it_back(self):
        mp = self.make_mp()
        store = mp / 'sitl' / 'flightaxis'
        original = self.snapshot(store)
        r = self.run_request(dict(Action='ResetSitl', MissionPlannerRoot=str(mp)))
        self.assertEqual(r['State'], 'SITL_RESET')
        backup = Path(r['Backup'])
        self.assertFalse(store.exists())
        self.assertTrue(backup.name.startswith('flightaxis_SJARC-backup-'))
        self.assertEqual(self.snapshot(backup), original)
        store.mkdir()
        (store / 'eeprom.bin').write_bytes(b'fresh')  # Mission Planner makes a new store on the next SITL start
        r = self.run_request(dict(Action='RestoreSitl', MissionPlannerRoot=str(mp)))
        self.assertEqual(r['State'], 'SITL_RESTORED')
        self.assertEqual(self.snapshot(store), original)
        self.assertEqual((Path(r['Kept']) / 'eeprom.bin').read_bytes(), b'fresh')
        self.assertIn('No SITL backup', self.run_request(dict(Action='RestoreSitl', MissionPlannerRoot=str(mp)), success=False)['Error'])

    def test_sitl_reset_without_store_changes_nothing(self):
        mp = self.work / 'Mission Planner'
        (mp / 'sitl').mkdir(parents=True)
        self.assertEqual(self.run_request(dict(Action='ResetSitl', MissionPlannerRoot=str(mp)))['State'], 'NOTHING_TO_RESET')
        self.assertEqual(list((mp / 'sitl').iterdir()), [])

    def test_rf_ini_reset_moves_ini_and_restore_keeps_realflight_copy(self):
        root = self.rf9_root()
        base = dict(Executable=str(self.rf9_exe), Root=str(root))
        r = self.run_request(dict(base, Action='ResetRfIni'))
        saved = Path(r['Backup'])
        self.assertFalse((root / 'RealFlight.ini').exists())
        self.assertEqual(saved.read_bytes(), RF9_INI)
        self.assertEqual(saved.parent.parent, root / '.SJARC' / 'IniReset')
        fresh = b'[Main]\r\nFreshDefaults=BOOL:Yes\r\n'
        (root / 'RealFlight.ini').write_bytes(fresh)  # RealFlight recreates its INI on the next start
        r = self.run_request(dict(base, Action='RestoreRfIni'))
        self.assertEqual((root / 'RealFlight.ini').read_bytes(), RF9_INI)
        self.assertEqual(Path(r['Kept']).read_bytes(), fresh)
        self.assertEqual(saved.read_bytes(), RF9_INI)
        self.assertIn('No RealFlight INI reset', self.run_request(dict(base, Action='RestoreRfIni'), success=False)['Error'])

    def test_rf_ini_restore_before_realflight_ran_again(self):
        root = self.rf9_root()
        base = dict(Executable=str(self.rf9_exe), Root=str(root))
        self.run_request(dict(base, Action='ResetRfIni'))
        r = self.run_request(dict(base, Action='RestoreRfIni'))
        self.assertEqual((root / 'RealFlight.ini').read_bytes(), RF9_INI)
        self.assertEqual(r['Kept'], '')

    def test_rf_ini_reset_refuses_other_edition(self):
        root = self.rf9_root()
        self.assertIn('do not match', self.run_request(dict(Action='ResetRfIni', Executable=str(EXE), Root=str(root)), success=False)['Error'])
        self.assertEqual((root / 'RealFlight.ini').read_bytes(), RF9_INI)

    def test_stop_sitl_only_stops_mission_planner_sitl_processes(self):
        mp = self.make_mp()
        procs = [self.fake_sitl(mp / 'sitl' / 'ArduPlane.exe'), self.fake_sitl(self.work / 'elsewhere' / 'ArduPlane.exe')]
        try:
            self.assertIsNone(procs[0].poll())
            # Stores are never moved while a simulator runs.
            self.assertIn('Close', self.run_request(dict(Action='ResetSitl', MissionPlannerRoot=str(mp)), success=False)['Error'])
            self.assertTrue((mp / 'sitl' / 'flightaxis' / 'eeprom.bin').exists())
            r = self.run_request(dict(Action='StopSitl', MissionPlannerRoot=str(mp)))
            self.assertIsNotNone(procs[0].wait(timeout=10))
            self.assertIsNone(procs[1].poll())
            self.assertEqual(len(r['Stopped']), 1, r)
            self.assertTrue(any(str(self.work / 'elsewhere') in x for x in r['Skipped']), r)
        finally:
            for p in procs:
                if p.poll() is None:
                    p.communicate(b'done\r\n', timeout=10)
                else:
                    p.communicate(timeout=10)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(InstallerTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = dict(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors), skipped=len(result.skipped),
                   success=result.wasSuccessful(), completed_utc=datetime.utcnow().isoformat() + 'Z',
                   scope='Isolated file fixtures incl. RF-Evolution-style import re-rooting (from artifacts/path-repair), RF9 metadata fixture + real Evolution read-only discovery, pure C# target selection rules (19 assertions), connection troubleshooting on sandbox RF 9 / Mission Planner folders with stand-in SITL processes; RF Import UI, live FlightAxis connection and live flights NOT tested',
                   backend_sha256=hashlib.sha256((BUILD / 'Backend.ps1').read_bytes()).hexdigest(),
                   troubleshoot_sha256=hashlib.sha256((BUILD / 'Troubleshoot.ps1').read_bytes()).hexdigest(),
                   sitlparams_sha256=hashlib.sha256((BUILD / 'SitlParams.ps1').read_bytes()).hexdigest(),
                   program_sha256=hashlib.sha256((ROOT / 'apps/SJARC-RealFlight-Setup/Program.cs').read_bytes()).hexdigest(),
                   selection_sha256=hashlib.sha256((ROOT / 'apps/SJARC-RealFlight-Setup/TargetSelection.cs').read_bytes()).hexdigest())
    (ROOT / 'artifacts/sjarc-setup/test-results.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
