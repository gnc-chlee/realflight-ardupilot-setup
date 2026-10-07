# MFE FlightAxis signal patch v1.0.0

Unofficial, offline patch for the **Striver mini VTOL, Pioneer, Fighter and Hero** models
in [SITL_Models PR #158](https://github.com/ArduPilot/SITL_Models/pull/158), pinned to
`e93e185d4e22df48d6791fe45103b593f168946a`.
Intended for imported models in RealFlight 9.5/9.5S or Evolution, not RealFlight-X.
These are separate product versions; confirm the actual version in Help/About.

## Findings and scope

All four inspected archives use these motor chains, from the aircraft's perspective:

| RF RX | Electronic signal ID | Propeller frame | AP Quad-X function |
|---|---|---|---|
| 9 | 122 | ENGINE_FR, front-right | Motor1 = 33 |
| 10 | 121 | ENGINE_RL, rear-left | Motor2 = 34 |
| 11 | 123 | ENGINE_RR, rear-right | Motor4 = 36 |
| 12 | 119 | ENGINE_FL, front-left | Motor3 = 35 |

The supplied parameter files assign Motor3 to output 11 and Motor4 to output 12.
The included four-line `.param` overlay corrects this mismatch. **RF motor wiring is not swapped.**
Do not also swap RX11/12 in Aircraft Editor; modified wiring is intentionally rejected.
Requires `Q_FRAME_CLASS=1` and `Q_FRAME_TYPE=1`; verify those before loading the overlay.

The RF patch separately adds direct TX-to-software-radio feeds on CH8..12, sets their
Trim=0, LowRates=1 and Expo=0. Originals have empty feeds on those channels and Trim=1
on CH9..12. CH8 can then convey the user's mode switch to SITL RC8; mode assignment
and controller calibration are still manual. Software-radio outputs become SITL RC inputs,
while SITL SERVO outputs become RF actuator RX inputs: these are distinct paths.
[Official FlightAxis explanation](https://ardupilot.org/dev/docs/flightaxis.html)

No PID, servo reversals, CH1..7, controller GUID/calibration, missions, CG/physics,
asset paths, propeller brakes or RF Link settings are changed. Hero's V-tail
(`SERVO2_FUNCTION=79`, `SERVO4_FUNCTION=80`) must not be replaced by Striver settings.
Pioneer also has a different original elevator reversal: verify direction per model.

## Use

1. Import the original RFX using RealFlight. Ensure the model loads without missing-path errors.
   This package contains neither the original RFX nor a full simulator installation.
2. Disconnect real flight controllers. Close RF, Mission Planner and ArduPlane SITL.
3. Extract the entire ZIP locally. Run `01-Check.cmd` and explicitly select the correct RF
   **user data** folder, usually Documents/RealFlight 9 or Documents/RealFlight Evolution.
   Do not choose the Steam installation folder. Multiple installations are never guessed.
4. On a successful check, run `02-Apply-RF-Patch.cmd`, select the same folder, then type `APPLY`.
   Installed supported models are patched; absent ones are skipped. Custom wiring/CH8..12
   mixes and unknown revisions are refused. Do not force the overlay after a failed check.
5. Start RF and the matching ArduPlane FlightAxis SITL. Do not use Simulation **Wipe**.
   Confirm it is **DISARMED SITL**, not hardware. Export the full current parameters in Mission Planner.
6. Retain the matching model's base parameters. Verify Quad-X class/type. Load
   `MFE_PR158_QuadX_Servo_Map_ONLY.param` in Full Parameter List. Review the diff: only
   SERVO9/10/11/12_FUNCTION may change. Click Write Params, restart SITL while disarmed,
   reconnect and read those four values back. Separate vehicle stores need separate verification.
7. Before any user-initiated flight, check RF Electronics/propeller mapping against the table,
   RC axes/ranges, mode switch, and MANUAL control-surface directions while DISARMED.
   Do not copy controller calibration between PCs. Our controller setup uses Software Radio Mixes On,
   Software Radio Dual Rates and Expo Off. The preserved CH1..7 mixes still need checking.
   Confirm `ch3in` throttle low/high and `ch2in` pitch forward/back are approximately 1000/2000.
   Verify RC8 and FLTMODE_CH/mode assignments separately. Hover testing precedes transitions.

The patch never connects to MAVLink, writes live parameters, arms or takes off. Applying the
RF script alone does **not** apply the AP fix. PID tuning is not included. A visible rotating
forward prop may be windmilling: inspect actual output and brake settings before diagnosing it.
FlightAxis must remain connected; disconnected RF can follow its own radio controls.
Do not treat these patched models as validated standalone RC-flight models.

## Backup and restore

Changed RF files are backed up under `<RF user data>\MFE-Signal-Backups\<run>\`.
`manifest.json` records before/after SHA-256 hashes and status. Preflight validates every selected
model before writes; backups are verified first. On a caught write failure the script attempts
rollback. Keep backups for recovery from interruption or disk failure.

With RF/MP/SITL closed, run (replace placeholder paths):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-MFE-Signals.ps1 -RealFlightRoot "C:\Users\USER\Documents\RealFlight 9" -RestoreManifest "C:\Users\USER\Documents\RealFlight 9\MFE-Signal-Backups\RUN\manifest.json"
```

Restore refuses damaged backups or models edited after patching; inspect them manually instead.
Backups are retained. RF restore does not restore AP parameters: use your own prior `.param` export.
Select just one model with `-Model Striver`, `Pioneer`, `Fighter` or `Hero`. Without `-Apply`,
the script only inspects. PowerShell 5.1 is sufficient; no Python or administrator installation is needed.
Launchers use process-local ExecutionPolicy Bypass, not a global policy change. Respect organizational restrictions.

Renamed variants, custom wiring/mixes, reparse points/cloud placeholders and missing assets require
separate review. This patch does not repair KEX/BSE/texture paths, enable Link or install software.
Include RF version, AP version, model name, console error and rfvehicle when asking for help;
review personal Windows paths in manifests before public sharing. Never send account/license files.

## Evidence and limitations

`SOURCE_AUDIT.json` contains hashes of the pinned RFX/parameter/rfvehicle sources and signal traces.
`TEST_RESULTS.json` records offline tests of all four extracted models in Windows PowerShell 5.1,
including exact preservation of unrelated bytes, repeat application, backup/restore and refusal tests.
A copy of an Evolution-saved Striver was also checked, without modifying the installed model.
**No four-model live flight validation on RF 9.5/9.5S was performed.** Recipient-side verification is required.

Additional references: [motor ordering](https://ardupilot.org/copter/docs/connect-escs-and-motors.html),
[SITL setup](https://ardupilot.org/dev/docs/sitl-with-realflight.html).
