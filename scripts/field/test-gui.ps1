#requires -Version 5.1
# GUI check for the step layout (run with powershell -STA). Shows the form off-screen, runs the read-only Detect scan and
# the Status refresh, then captures every step page with PrintWindow (native controls included) into PNGs.
# Never clicks Prepare/Finalize/Restore or a reset. -Diagnose also runs the read-only diagnosis (opens Notepad).
param(
    [string] $Exe = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'dist\SJARC-RealFlight-Setup-v0.2.0\SJARC-RealFlight-Setup.exe'),
    [string] $OutDir = (Join-Path $env:TEMP 'sjarc-gui-test'),
    [switch] $Diagnose
)
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with powershell -STA.' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class GuiCapture { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags); }
"@
[void][IO.Directory]::CreateDirectory($OutDir)
$asm = [Reflection.Assembly]::LoadFile($Exe)
$flags = [Reflection.BindingFlags]'NonPublic,Public,Instance'
$formType = $asm.GetType('SJARC.SetupForm')
$form = $formType.GetConstructor([Type[]]@([string])).Invoke([object[]]@([string](Join-Path $OutDir 'work')))
function Field($name) { return $formType.GetField($name, $flags).GetValue($form) }
function Call($name, $arguments) { return $formType.GetMethod($name, $flags).Invoke($form, $arguments) }
function Pump($task) { while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }; if ($task.IsFaulted) { throw $task.Exception } }
function Settle([int]$ms) { $end = [DateTime]::Now.AddMilliseconds($ms); while ([DateTime]::Now -lt $end) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point -4000, -4000; $form.ShowInTaskbar = $false
$form.Show(); Settle 400
"Title: $($form.Text)"
# Shown already starts the scan and the status refresh; wait for both instead of starting a second scan.
$deadline = [DateTime]::Now.AddSeconds(90)
do { Settle 250 } while (((Field 'busy') -or (Field 'statusBusy') -or (Field 'badge').Text -eq '상태 확인 중') -and [DateTime]::Now -lt $deadline)
"installs: $(@((Field 'installs').Items | ForEach-Object { $_.ToString() }) -join ' | ')"
"roots: $((Field 'roots').Text)"
"header: $((Field 'headerTarget').Text) | badge: $((Field 'badge').Text)"
"status: $(@('stLink','stPause','stController','stSitl' | ForEach-Object { (Field $_).Text }) -join ' | ')"
"steps: $(@((Field 'steps') | ForEach-Object { $_.Text + '=' + $_.Mark }) -join ', ')"
"paths enabled: $((Field 'paths').Enabled)  request RepairPaths: $((Call 'Basic' @('Finalize'))['RepairPaths'])"
$pages = Field 'pages'
for ($i = 0; $i -lt $pages.Count; $i++) {
    [void](Call 'ShowStep' @([int]$i)); Settle 350
    $bmp = New-Object Drawing.Bitmap $form.Width, $form.Height
    $g = [Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [void][GuiCapture]::PrintWindow($form.Handle, $hdc, 0)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $png = Join-Path $OutDir ("step$i.png"); $bmp.Save($png, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "rendered $png"
}
if ($Diagnose) {
    [void](Call 'ShowStep' @([int]5))
    Pump (Call 'Diagnose' @())
    "trouble log:`n$((Field 'tlog').Text)"
}
$form.Close(); $form.Dispose()
