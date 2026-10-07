#requires -Version 5.1
# Screenshots for the user guide (run with powershell -STA). Shows the built form off-screen and stages each step with
# example data for an RF 9 target, so no real RealFlight folder is read or written and no personal path appears.
# Only display code runs: no Prepare/Finalize/Restore/reset is invoked.
param(
    [string] $Exe = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'dist\SJARC-RealFlight-Setup-v0.2.1\SJARC-RealFlight-Setup.exe'),
    [string] $OutDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'docs\guide\img')
)
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with powershell -STA.' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class GuideCapture { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags); }
"@
[void][IO.Directory]::CreateDirectory($OutDir)
$work = Join-Path $env:TEMP ('sjarc-guide-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$asm = [Reflection.Assembly]::LoadFile($Exe)
$flags = [Reflection.BindingFlags]'NonPublic,Public,Instance'
$t = $asm.GetType('SJARC.SetupForm')
$form = $t.GetConstructor([Type[]]@([string])).Invoke([object[]]@([string]$work))
function Field($n) { $t.GetField($n, $flags).GetValue($form) }
function Invoke-Form($n, [object[]]$a) { $t.GetMethod($n, $flags).Invoke($form, $a) }
function Settle([int]$ms) { $end = [DateTime]::Now.AddMilliseconds($ms); while ([DateTime]::Now -lt $end) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
function Controls-Of($c) { foreach ($x in $c.Controls) { $x; Controls-Of $x } }
function Shot([string]$name, $crop = $null) {
    Settle 350
    $bmp = New-Object Drawing.Bitmap $form.Width, $form.Height; $g = [Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [void][GuideCapture]::PrintWindow($form.Handle, $hdc, 0); $g.ReleaseHdc($hdc); $g.Dispose()
    if ($crop) { $part = $bmp.Clone($crop, $bmp.PixelFormat); $bmp.Dispose(); $bmp = $part }
    $bmp.Save((Join-Path $OutDir $name), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "saved $name"
}
function Rows([object[]]$items) { $list = New-Object 'System.Collections.Generic.List[string[]]'; foreach ($r in $items) { $list.Add([string[]]$r) }; return , $list }
function Fill-List($view, $rows) { [void]$t.GetMethod('Fill', $flags).Invoke($form, [object[]]@($view.PSObject.BaseObject, $rows.PSObject.BaseObject)) }
function Status([string]$badge, [bool]$good, [object[]]$items) {
    $b = Field 'badge'; $b.Text = $badge
    $b.BackColor = if ($good) { [Drawing.Color]::FromArgb(226, 243, 234) } else { [Drawing.Color]::FromArgb(252, 242, 222) }
    $b.ForeColor = if ($good) { [Drawing.Color]::FromArgb(36, 121, 83) } else { [Drawing.Color]::FromArgb(166, 104, 0) }
    $names = 'stLink', 'stPause', 'stController', 'stSitl'
    for ($i = 0; $i -lt 4; $i++) { (Field $names[$i]).Set($items[$i][0], [string]$items[$i][1]) }
}
$green = [Drawing.Color]::FromArgb(36, 121, 83); $red = [Drawing.Color]::FromArgb(176, 42, 42); $amber = [Drawing.Color]::FromArgb(166, 104, 0); $gray = [Drawing.Color]::FromArgb(160, 168, 178)

$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point -4000, -4000; $form.ShowInTaskbar = $false
$form.Size = New-Object Drawing.Size 1136, 880
$form.Show()
$deadline = [DateTime]::Now.AddSeconds(90)
do { Settle 250 } while (((Field 'busy') -or (Field 'statusBusy') -or (Field 'badge').Text -eq '상태 확인 중') -and [DateTime]::Now -lt $deadline)
# The form was loaded from PowerShell, so take the icon from the built EXE for the title bar and header.
$icon = [Drawing.Icon]::ExtractAssociatedIcon($Exe); $form.Icon = $icon
foreach ($p in @(Controls-Of $form | Where-Object { $_ -is [Windows.Forms.PictureBox] })) { $p.Image = $icon.ToBitmap() }

# Example RF 9 target (display only; the status refresh is stopped so nothing is read from this path).
$install = [Activator]::CreateInstance($asm.GetType('SJARC.Install'))
$installType = $asm.GetType('SJARC.Install')
$installType.GetField('Path').SetValue($install, 'C:\Program Files (x86)\RealFlight9\RealFlight.exe')
$installType.GetField('Label').SetValue($install, 'RealFlight 9 / 9.5 / 9.5S (9.50.015)')
$installType.GetField('Edition').SetValue($install, '9 / 9.5 / 9.5S')
$installs = Field 'installs'; $installs.Items.Clear(); [void]$installs.Items.Add($install); $installs.SelectedIndex = 0
(Field 'roots').Text = 'C:\Users\사용자\Documents\RealFlight 9'
(Field 'statusTimer').Stop(); Settle 300; (Field 'statusTimer').Stop()
$log = Field 'log'; $log.Clear()
$stamp = '09:10:0'
$log.AppendText("${stamp}2  RealFlight 실행 파일 1개, 사용자 폴더 1개 발견. Trainer / RealFlight-X 제외.`r`n")
Status 'RF·MP 꺼짐 · 파일 작업 가능' $true @(@($green, 'RealFlight Link 켜짐'), @($green, '일시정지 꺼짐'), @($green, '조종기 선택됨'), @($gray, 'SITL 꺼짐 · 켜면 flightaxis 확인'))
(Field 'state').Text = '설치 확인 완료 · 대상과 모델을 확인한 뒤 진행하세요.'
$steps = Field 'steps'
[void](Invoke-Form 'ShowStep' @([int]0)); Shot '01-target.png'
[void](Invoke-Form 'ShowStep' @([int]1)); Shot '02-models.png'

# After "모델 준비": two models still need Import (example).
$root = 'C:\Users\사용자\Documents\RealFlight 9'
Fill-List (Field 'prepareList') (Rows @(@('MFE Striver mini VTOL', '보정 완료', ''), @('MFE Pioneer VTOL', 'Import 필요', 'Pioneer_EA.RFX'), @('MFE Fighter VTOL', '보정 완료', ''), @('MFE Hero VTOL', 'Import 필요', 'HERO_EA.RFX')))
$pending = New-Object 'System.Collections.Generic.List[string]'; $pending.Add("$root\RFX\SJARC\Pioneer_EA.RFX"); $pending.Add("$root\RFX\SJARC\HERO_EA.RFX")
[void]$t.GetMethod('ShowImport', $flags).Invoke($form, [object[]]@(, $pending.PSObject.BaseObject))
$log.Clear(); $log.AppendText("09:10:02  RealFlight 실행 파일 1개, 사용자 폴더 1개 발견. Trainer / RealFlight-X 제외.`r`n09:12:41  MFE Pioneer VTOL : IMPORT_REQUIRED`r`n09:12:41  MFE Hero VTOL : IMPORT_REQUIRED`r`n09:12:41  Import할 파일: $root\RFX\SJARC\Pioneer_EA.RFX`r`n09:12:41  Import할 파일: $root\RFX\SJARC\HERO_EA.RFX`r`n")
$steps[0].Mark = 2; $steps[1].Mark = 2; $steps[2].Mark = 3
(Field 'state').Text = '모델 파일 준비 완료 · RealFlight에서 Import가 필요합니다.'
[void](Invoke-Form 'ShowStep' @([int]2)); Shot '03-import.png'

# After "Import 후 검사·패치": all four patched and hash-checked (example).
Fill-List (Field 'finalizeList') (Rows @(@('MFE Striver mini VTOL', '보정 완료', ''), @('MFE Pioneer VTOL', '보정 완료', ''), @('MFE Fighter VTOL', '보정 완료', ''), @('MFE Hero VTOL', '보정 완료', '')))
(Field 'tip').Text = '선택 기종의 신호 파일 보정을 마쳤습니다. RF 기체 선택에서 원래 이름(STRIVERminiVTOL · Pioneer · fighterVTOL · HERO2180)을 골라 정상 로드를 확인하세요. 다른 이름으로 저장한 사본은 패치되지 않습니다. 비행 검증 완료가 아닙니다.'
(Field 'nextFromFinalize').Visible = $true
$steps[2].Mark = 2; $steps[3].Mark = 2; $steps[4].Mark = 1
$log.AppendText("09:18:05  백업: $root\.SJARC\Backups\20261001-091805-3f2a9c1d\manifest.json`r`n09:18:05  MFE Pioneer VTOL : SIGNALS_PATCHED`r`n09:18:05  MFE Hero VTOL : SIGNALS_PATCHED`r`n")
(Field 'state').Text = '파일 적용·해시 검사 완료 · SITL 파라미터 적용과 DISARM 검증은 별도입니다.'
[void](Invoke-Form 'ShowStep' @([int]3)); Shot '04-finalize.png'

# SITL step while Mission Planner runs SITL with flightaxis (example status).
Status 'RF·MP 실행 중 · 파일 작업은 종료 후' $false @(@($green, 'RealFlight Link 켜짐'), @($green, '일시정지 꺼짐'), @($green, '조종기 선택됨'), @($green, 'SITL flightaxis로 실행 중'))
$t.GetField('statusBusy', $flags).SetValue($form, $true)   # keep ShowStep from refreshing over the example status
(Field 'state').Text = 'SITL 연결 중 · 아래 상태 줄에서 flightaxis 여부를 확인하세요.'
[void](Invoke-Form 'ShowStep' @([int]4)); Shot '05-sitl.png'

# Troubleshooting page with an example diagnosis summary.
$tlog = Field 'tlog'; $tlog.Clear()
$tlog.AppendText("10:02:11  [문제] SITL(PID 8124)이 RealFlight 연결 모델(flightaxis)이 아니라 `"plane`" 모델로 실행 중입니다. MP와 SITL을 닫고 Simulation에서 Model = flightaxis를 고른 뒤 다시 시작하세요.`r`n")
$tlog.AppendText("10:02:11  [확인] RealFlight 9: 조종기 입력 #17이(가) RF의 Reset 기능에 지정되어 있습니다. 연결 전에 해당 스위치 위치를 확인하세요.`r`n")
$tlog.AppendText("10:02:11  진단 보고서: ...\reports\diagnose-20261001-100211.txt`r`n10:02:11  보낼 파일(zip): ...\reports\SJARC-diagnose-20261001-100211.zip`r`n")
Status 'RF·MP 실행 중 · 파일 작업은 종료 후' $false @(@($green, 'RealFlight Link 켜짐'), @($green, '일시정지 꺼짐'), @($green, '조종기 선택됨'), @($red, 'SITL이 flightaxis 아님 → Model 다시 선택'))
(Field 'state').Text = '진단 완료 · 파일과 설정은 바꾸지 않았습니다.'
[void](Invoke-Form 'ShowStep' @([int]5)); Shot '06-trouble.png'

# Status strip close-ups: all good, and the usual problems.
$strip = (Field 'stLink').Parent
$screen = $strip.RectangleToScreen($strip.ClientRectangle)
$crop = New-Object Drawing.Rectangle ($screen.X - $form.Left), ($screen.Y - $form.Top), $screen.Width, $screen.Height
Status 'RF·MP 꺼짐 · 파일 작업 가능' $true @(@($green, 'RealFlight Link 켜짐'), @($green, '일시정지 꺼짐'), @($green, '조종기 선택됨'), @($green, 'SITL flightaxis로 실행 중'))
Shot '07-status-good.png' $crop
Status 'RF·MP 실행 중 · 파일 작업은 종료 후' $false @(@($red, 'RealFlight Link 꺼짐'), @($red, '일시정지 켜짐 (꺼야 함)'), @($amber, '조종기 선택 기록 없음'), @($red, 'SITL이 flightaxis 아님 → Model 다시 선택'))
Shot '08-status-bad.png' $crop
# Connection diagram on its own at twice the design size, for the printed guide.
$diagram = [Activator]::CreateInstance($asm.GetType('SJARC.ConnectionDiagram'))
$diagram.Font = $form.Font; $diagram.Size = New-Object Drawing.Size 1560, 316
$bmp = New-Object Drawing.Bitmap 1560, 316
$diagram.DrawToBitmap($bmp, (New-Object Drawing.Rectangle 0, 0, 1560, 316))
$bmp.Save((Join-Path $OutDir '09-diagram.png'), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $diagram.Dispose()
"saved 09-diagram.png"
$form.Close(); $form.Dispose()
