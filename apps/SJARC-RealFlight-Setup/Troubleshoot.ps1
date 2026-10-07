# Connection troubleshooting for RealFlight FlightAxis <-> ArduPilot SITL (Mission Planner). Dot-sourced by Backend.ps1.
# This file is saved as UTF-8 with BOM (Korean report text); Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# Diagnose only reads. Resets move the file/folder aside (nothing is deleted) and each has a matching restore.
Add-Type -AssemblyName System.IO.Compression

$SitlNamePattern = '^(ArduPlane|ArduCopter|ArduHeli|ArduRover|ArduSub|AntennaTracker|Blimp)$'
$SitlModelFolder = 'flightaxis'
$IniResetFolder = '.SJARC\IniReset'

function Mp-Root($request) {
    if ($request -and $request.PSObject.Properties['MissionPlannerRoot'] -and $request.MissionPlannerRoot) { return Full ([string]$request.MissionPlannerRoot) }
    return Full ([IO.Path]::Combine([Environment]::GetFolderPath('MyDocuments'), 'Mission Planner'))
}
function Request-Text($request, [string]$name) {
    if ($request -and $request.PSObject.Properties[$name] -and $request.$name) { return ([string]$request.$name).Trim().Trim('"').Trim() }
    return ''
}
function Stamp { return (Get-Date).ToString('yyyyMMdd-HHmmss') }
function Free-Name([string]$path) {
    # Never overwrite an earlier backup made in the same second.
    $candidate = $path; $n = 2
    while ([IO.Directory]::Exists($candidate) -or [IO.File]::Exists($candidate)) { $candidate = $path + '-' + $n; $n++ }
    return $candidate
}
function Sitl-Running {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $SitlNamePattern -or $_.ProcessName -match '^MissionPlanner' })
}
function Assert-SimClosed {
    Assert-Closed
    $busy = @(Sitl-Running)
    if ($busy.Count) { throw ('Close Mission Planner and every SITL window first: ' + (@($busy | ForEach-Object { $_.ProcessName }) -join ', ')) }
}

# ---------------------------------------------------------------- report helpers
function Diag-Line([string]$line) { $script:DiagReport.Add($line) }
function Diag-Find([string]$level, [string]$text) {
    $script:DiagFindings.Add([pscustomobject]@{ Level = $level; Text = $text })
}
function Diag-Try([string]$diagWhat, [scriptblock]$diagBlock) {
    # Unusual parameter names: the block runs in this function's child scope and must still see the caller's $label etc.
    try { & $diagBlock } catch { Diag-Line ('  (' + $diagWhat + ' 확인 실패: ' + $_.Exception.Message + ')') }
}
function Show-Value($typed) { if ($null -eq $typed) { return '(없음)' }; return (Decode-Carrier ([string]$typed)) }
function Decode-Carrier([string]$carrier) {
    # INI/model text is read as Latin-1 byte carriers; show non-ASCII values the way they were written (UTF-8, else GBK/ANSI).
    $bytes = $ByteEncoding.GetBytes($carrier)
    try { return ([Text.UTF8Encoding]::new($false, $true)).GetString($bytes) } catch { }
    foreach ($cp in 936, 949) { try { return [Text.Encoding]::GetEncoding($cp).GetString($bytes) } catch { } }
    return $carrier
}
function Section-Text([string]$ini, [string]$name) {
    $m = [regex]::Match($ini, '(?ms)^\[' + [regex]::Escape($name) + '\]\r?\n(.*?)(?=^\[|\z)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}
function File-Line([string]$path) {
    $f = [IO.FileInfo]$path
    return ('{0}  ({1:N0} bytes, {2})' -f $path, $f.Length, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
}

# ---------------------------------------------------------------- diagnose sections
function Diag-System {
    Diag-Line '[PC]'
    Diag-Try 'Windows' {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Diag-Line ('  Windows: ' + $os.Caption + ' ' + $os.Version + ' (build ' + $os.BuildNumber + '), 메모리 ' + [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) + ' GB')
        Diag-Line ('  마지막 부팅: ' + $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))
    }
    Diag-Try 'CPU' { foreach ($c in @(Get-CimInstance Win32_Processor -ErrorAction Stop)) { Diag-Line ('  CPU: ' + ([string]$c.Name).Trim()) } }
    Diag-Try 'GPU' {
        foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            $mode = if ($g.CurrentHorizontalResolution) { ' / ' + $g.CurrentHorizontalResolution + 'x' + $g.CurrentVerticalResolution + ' ' + $g.CurrentRefreshRate + 'Hz' } else { ' / 화면 연결 없음' }
            Diag-Line ('  GPU: ' + $g.Name + ' / 드라이버 ' + $g.DriverVersion + $mode)
            if ([string]$g.Name -match '(?i)Basic Display|기본 디스플레이') { Diag-Find '문제' ('그래픽 드라이버가 설치되지 않았습니다(' + $g.Name + '). RealFlight가 느려지거나 멈출 수 있습니다. 그래픽카드 제조사 드라이버를 설치하세요.') }
        }
    }
    Diag-Try 'controller' {
        $hid = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='HIDClass'" -ErrorAction Stop | Where-Object { [string]$_.Name -match '(?i)game|joystick|컨트롤러' -or [string]$_.DeviceID -match 'VID_1209&PID_4F54' })
        if (-not $hid.Count) { Diag-Line '  조종기(HID 게임 컨트롤러): 연결된 장치 없음' }
        foreach ($h in $hid) { Diag-Line ('  조종기(HID): ' + $h.Name + ' [' + $h.DeviceID + '] 상태 ' + $h.Status) }
    }
    Diag-Line ''
}
function Diag-Processes {
    Diag-Line '[실행 중인 관련 프로그램]'
    $all = @(Get-Process -ErrorAction SilentlyContinue)
    $rf = @($all | Where-Object { $_.ProcessName -match '^RealFlight' })
    $mp = @($all | Where-Object { $_.ProcessName -match '^MissionPlanner' })
    $sitl = @($all | Where-Object { $_.ProcessName -match $SitlNamePattern })
    $steam = @($all | Where-Object { $_.ProcessName -match '^steam$' })
    $commandLines = @{}
    try {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Ardu%' OR Name LIKE 'AntennaTracker%' OR Name LIKE 'Blimp%'" -ErrorAction Stop)) { $commandLines[[int]$c.ProcessId] = [string]$c.CommandLine }
    } catch { }
    $hung = @()
    foreach ($p in @($rf + $mp + $sitl + $steam)) {
        $path = ''; try { $path = [string]$p.Path } catch { }
        $start = ''; try { $start = $p.StartTime.ToString('MM-dd HH:mm:ss') } catch { }
        $state = ''
        try {
            if ($p.MainWindowHandle -eq [IntPtr]::Zero) { $state = '창 없음' }
            elseif ($p.Responding) { $state = '정상 응답' }
            else { $state = '응답 없음'; $hung += $p }
        } catch { }
        Diag-Line ('  ' + $p.ProcessName + ' (PID ' + $p.Id + ', 시작 ' + $start + ', ' + $state + ') ' + $path)
        if ($commandLines.ContainsKey([int]$p.Id)) { Diag-Line ('      명령줄: ' + $commandLines[[int]$p.Id]) }
    }
    if (-not @($rf + $mp + $sitl).Count) { Diag-Line '  RealFlight / Mission Planner / SITL 모두 실행 중이 아님' }
    foreach ($p in $hung) { Diag-Find '문제' ($p.ProcessName + '(PID ' + $p.Id + ')가 지금 "응답 없음" 상태입니다. 이 보고서를 저장한 뒤 작업 관리자에서 끝내세요.') }
    if ($rf.Count -gt 1) { Diag-Find '문제' ('RealFlight가 ' + $rf.Count + '개 실행 중입니다. RF 9와 Evolution은 같은 FlightAxis 포트(18083)를 쓰므로 하나만 켜세요.') }
    if ($sitl.Count -gt 1) { Diag-Find '문제' ('SITL(ArduPlane 등)이 ' + $sitl.Count + '개 실행 중입니다. 여러 SITL이 한 RealFlight에 동시에 붙으면 RF가 멈출 수 있습니다. "남은 SITL 창 종료"를 누르세요.') }
    elseif ($sitl.Count -eq 1 -and -not $mp.Count) { Diag-Find '확인' 'Mission Planner 없이 SITL 창만 남아 있습니다. 다음 연결 전에 "남은 SITL 창 종료"로 닫으세요.' }
    # A SITL started with a built-in physics model (e.g. -Mplane) never talks to RealFlight: Mission Planner shows a
    # vehicle that stays still (SITL default battery 12.60 V) while the RF aircraft tumbles. Seen at Icheon 2026-09-30.
    $script:DiagRfRunning = [bool]$rf.Count
    foreach ($p in $sitl) {
        if (-not $commandLines.ContainsKey([int]$p.Id)) { continue }
        $line = $commandLines[[int]$p.Id]
        if ($line -match '(?i)flightaxis') { $script:DiagFlightAxisSitl = $true; continue }
        $model = [regex]::Match($line, '(?:^|\s)(?:-M|--model[= ])\s*"?([^\s"]+)')
        $name = if ($model.Success) { $model.Groups[1].Value } else { '알 수 없음' }
        Diag-Find '문제' ('SITL(PID ' + $p.Id + ')이 RealFlight 연결 모델(flightaxis)이 아니라 "' + $name + '" 모델로 실행 중입니다. 이 상태에서는 RF와 연결되지 않고 SITL 자체 물리로만 돌아서, RF 기체가 넘어져도 Mission Planner 화면은 그대로입니다(배터리 12.60V 고정이 대표적인 표시). MP와 SITL을 닫고 Simulation에서 Model = flightaxis를 고른 뒤 다시 시작하세요.')
    }
    Diag-Line ''
}
function Diag-Network {
    Diag-Line '[로컬 포트 - 읽기만 함, 접속 시도 없음]'
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        foreach ($port in 18083, 5760) { Diag-Line ('  ' + $port + ': ' + $(if (@($listeners | Where-Object Port -EQ $port).Count) { '수신 대기 있음' } else { '수신 대기 없음' })) }
        Diag-Line ''
        return
    }
    $conns = @(Get-NetTCPConnection -ErrorAction SilentlyContinue)
    foreach ($port in 18083, 5760, 5762, 5763) {
        $listen = @($conns | Where-Object { [string]$_.State -eq 'Listen' -and $_.LocalPort -eq $port })
        if (-not $listen.Count) { Diag-Line ('  ' + $port + ': 수신 대기 없음'); continue }
        foreach ($l in $listen) {
            $owner = '?'; try { $owner = (Get-Process -Id $l.OwningProcess -ErrorAction Stop).ProcessName } catch { }
            Diag-Line ('  ' + $port + ': 수신 대기 ' + $l.LocalAddress + ' - ' + $owner + ' (PID ' + $l.OwningProcess + ')')
            if ($port -eq 18083 -and $owner -notmatch '^RealFlight') { Diag-Find '문제' ('FlightAxis 포트 18083을 RealFlight가 아닌 ' + $owner + '가 쓰고 있습니다.') }
        }
        if ($port -eq 18083 -and @($listen | Select-Object -ExpandProperty OwningProcess -Unique).Count -gt 1) { Diag-Find '문제' '18083 포트를 여러 프로그램이 동시에 열고 있습니다(RealFlight 중복 실행 등).' }
    }
    $fa = @($conns | Where-Object { $_.LocalPort -eq 18083 -or $_.RemotePort -eq 18083 } | Where-Object { [string]$_.State -ne 'Listen' })
    $byState = @($fa | Group-Object { [string]$_.State } | ForEach-Object { $_.Name + ' ' + $_.Count })
    Diag-Line ('  18083 연결 상태: ' + $(if ($byState.Count) { $byState -join ', ' } else { '없음' }))
    $faListen = @($conns | Where-Object { [string]$_.State -eq 'Listen' -and $_.LocalPort -eq 18083 })
    if ($script:DiagRfRunning -and -not $faListen.Count) { Diag-Find '확인' 'RealFlight가 실행 중인데 FlightAxis 포트 18083에서 대기하지 않습니다. RealFlight Link가 꺼져 있을 수 있습니다. RF의 Settings -> Physics에서 RealFlight Link = Yes를 확인하세요(바꿨다면 RF 재시작).' }
    elseif ($script:DiagRfRunning -and $script:DiagFlightAxisSitl -and -not $fa.Count) { Diag-Find '확인' 'RealFlight와 SITL(flightaxis)이 모두 켜져 있는데 둘 사이의 18083 연결 흔적이 없습니다. SITL 검은 창에 "connect failed"가 반복되는지 확인하세요.' }
    $timeWait = @($conns | Where-Object { [string]$_.State -eq 'TimeWait' }).Count
    Diag-Line ('  전체 TIME_WAIT: ' + $timeWait)
    $faWait = @($fa | Where-Object { [string]$_.State -eq 'TimeWait' }).Count
    if ($faWait -gt 2000) { Diag-Find '확인' ('RealFlight(18083)와 짧은 연결이 ' + $faWait + '개 쌓여 있습니다. SITL이 연결을 계속 다시 맺고 있다는 뜻입니다. 이 보고서와 SITL 검은 창 사진을 함께 보관하세요.') }
    Diag-Try 'dynamic ports' {
        # netsh labels are localized (OEM code page); keep only the numbers: start port, number of ports.
        $numbers = @(& netsh.exe int ipv4 show dynamicport tcp 2>$null | ForEach-Object { [regex]::Match([string]$_, '(\d+)\s*$').Groups[1].Value } | Where-Object { $_ })
        if ($numbers.Count -ge 2) { Diag-Line ('  TCP 동적 포트: ' + $numbers[0] + '부터 ' + $numbers[1] + '개') }
    }
    Diag-Line ''
}
function Diag-RfRoot([string]$root, [bool]$selected) {
    Diag-Line ('[RealFlight 사용자 폴더] ' + $root + $(if ($selected) { '   <- 도우미에서 선택한 대상' } else { '' }))
    $inis = @('RealFlight.ini', 'RealFlight64.ini' | Where-Object { [IO.File]::Exists([IO.Path]::Combine($root, $_)) })
    if (-not $inis.Count) {
        Diag-Line '  INI 없음 (RealFlight를 한 번 실행·종료하면 새로 만들어짐)'
        if ([IO.Directory]::Exists([IO.Path]::Combine($root, $IniResetFolder))) { Diag-Line ('  도우미 INI 초기화 백업 있음: ' + [IO.Path]::Combine($root, $IniResetFolder)) }
    }
    $label = Split-Path $root -Leaf
    foreach ($name in $inis) {
        $path = [IO.Path]::Combine($root, $name)
        Diag-Line ('  ' + (File-Line $path))
        $ini = Read-Text $path
        $keys = @('FlightAxisLinkEnabled', 'RealFlightLinkEnabled', 'PauseSimWhenFocusLost', 'PauseSimWhileInMenus', 'PhysicsResetDelay2', 'PhysicsTimeScale',
            'PhysicsQuality2', 'FlightModelRealism', 'AutopilotAssistLevel', 'SetupFailureProbability', 'CurrentVehicle', 'CurrentAirportBaseName',
            'CurrentControllerSelection', 'HasFinishedCalibratingAControllerOfSomeKind', 'HIDControllerDeadband', 'GraphicsQuality', 'CurrentRefresh',
            'LockToMonitorFrequency', 'WindowState', 'WindowLocation', 'ResetOnReset', 'DoPhysicsCheck')
        foreach ($k in $keys) { Diag-Line ('    ' + $k + ' = ' + (Show-Value (Try-KeyValue $ini $k))) }
        foreach ($m in [regex]::Matches($ini, '(?mi)^([^\[=\r\n]*(FlightAxis|RealFlightLink)[^=\r\n]*)=([^\r\n]*)')) {
            if ($keys -notcontains $m.Groups[1].Value) { Diag-Line ('    ' + $m.Groups[1].Value + ' = ' + $m.Groups[3].Value) }
        }
        $link = @('FlightAxisLinkEnabled', 'RealFlightLinkEnabled' | Where-Object { $null -ne (Try-KeyValue $ini $_) })
        if (-not $link.Count) { Diag-Find '문제' ($label + ': INI에 RealFlight Link 설정이 없습니다. RF 화면(Settings -> Physics)에서 RealFlight Link = Yes로 켜세요.') }
        foreach ($k in $link) { if ((Try-KeyValue $ini $k) -cne 'BOOL:Yes') { Diag-Find '문제' ($label + ': RealFlight Link(' + $k + ')가 꺼져 있습니다. 도우미 3번 또는 RF 화면에서 켜세요.') } }
        foreach ($k in 'PauseSimWhenFocusLost', 'PauseSimWhileInMenus') { if ((Try-KeyValue $ini $k) -ceq 'BOOL:Yes') { Diag-Find '확인' ($label + ': ' + $k + ' = Yes. Mission Planner를 클릭하면 RF가 멈춰 SITL 연결이 끊깁니다. No로 바꾸세요(도우미 3번).') } }
        $scale = Try-KeyValue $ini 'PhysicsTimeScale'
        if ($null -ne $scale -and $scale -notmatch '^FLOAT:1\.?0*$') { Diag-Find '확인' ($label + ': RF 시뮬레이션 속도 배율(PhysicsTimeScale)이 ' + $scale + '입니다. SITL은 1배속 기준입니다.') }
        $failure = Try-KeyValue $ini 'SetupFailureProbability'
        if ($null -ne $failure -and $failure -notmatch '^INT:0$') { Diag-Find '문제' ($label + ': RF 고장 훈련(Setup Failures) 확률이 ' + $failure + '입니다. 채널이 무작위로 바뀔 수 있으니 0으로 끄세요.') }
        $selection = Path-Value (Try-KeyValue $ini 'CurrentControllerSelection')
        $sections = @([regex]::Matches($ini, '(?m)^\[(Control\|[^\]\r\n]+)\]') | ForEach-Object { $_.Groups[1].Value })
        foreach ($s in $sections) {
            $body = Section-Text $ini $s
            $map = Path-Value (Try-KeyValue $body 'ChannelMapName')
            Diag-Line ('    [' + $s + '] ChannelMapName=' + (Decode-Carrier $map) + ' ManualCalibration=' + (Show-Value (Try-KeyValue $body 'ManualCalibration')) + $(if ($selection -and $s.EndsWith('|' + $selection)) { '   <- 현재 선택' } else { '' }))
        }
        if (-not $selection) { Diag-Find '확인' ($label + ': RF에 선택된 조종기 기록(CurrentControllerSelection)이 없습니다. RF에서 조종기를 선택·보정했는지 확인하세요.') }
        elseif (-not @($sections | Where-Object { $_.EndsWith('|' + $selection) }).Count) { Diag-Find '확인' ($label + ': 현재 선택 조종기(' + $selection + ')의 보정 정보가 INI에 없습니다. RF에서 조종기를 다시 선택·보정하세요.') }
        else {
            $body = Section-Text $ini (@($sections | Where-Object { $_.EndsWith('|' + $selection) })[0])
            $map = Path-Value (Try-KeyValue $body 'ChannelMapName')
            $profile = [IO.Path]::Combine($root, 'Radio Profiles', $map + '.radioprofile')
            if ($map -and (Is-Ascii $map) -and $map.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0 -and [IO.File]::Exists($profile)) { Diag-RadioProfile $profile $label }
            elseif ($map) { Diag-Line ('    조종기 프로필 파일 없음: ' + $profile) }
        }
    }
    Diag-Models $root $label
    Diag-Try 'RF logs' {
        $logs = [IO.Path]::Combine($root, 'Logs')
        if ([IO.Directory]::Exists($logs)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $logs -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 8)) {
                Diag-Line ('  로그: ' + (File-Line $f.FullName))
                if ($f.Length -gt 0 -and $f.Length -lt 200KB -and $f.LastWriteTime -gt (Get-Date).AddDays(-30)) {
                    foreach ($l in @([IO.File]::ReadAllLines($f.FullName) | Select-Object -Last 15)) { Diag-Line ('      | ' + $l) }
                }
            }
        }
    }
    Diag-Try 'helper backups' {
        $runs = [IO.Path]::Combine($root, '.SJARC', 'Backups')
        if ([IO.Directory]::Exists($runs)) { Diag-Line ('  도우미 작업 기록(최근): ' + (@(Get-ChildItem -LiteralPath $runs -Directory | Sort-Object Name -Descending | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', ')) }
        $resets = [IO.Path]::Combine($root, $IniResetFolder)
        if ([IO.Directory]::Exists($resets)) { Diag-Line ('  도우미 INI 초기화 기록: ' + (@(Get-ChildItem -LiteralPath $resets -Directory | Sort-Object Name -Descending | ForEach-Object { $_.Name }) -join ', ')) }
    }
    Diag-Line ''
}
function Diag-RadioProfile([string]$profile, [string]$label) {
    Diag-Line ('    조종기 프로필: ' + (File-Line $profile))
    $text = Read-Text $profile
    $main = Section-Text $text 'Main'
    if ($null -ne $main) {
        Diag-Line ('      EnableSoftwareRadioDualRatesAndExpo=' + (Show-Value (Try-KeyValue $main 'EnableSoftwareRadioDualRatesAndExpo')) + '  EnableSoftwareRadioMixes=' + (Show-Value (Try-KeyValue $main 'EnableSoftwareRadioMixes')))
        if ((Try-KeyValue $main 'EnableSoftwareRadioDualRatesAndExpo') -ceq 'BOOL:Yes') { Diag-Find '확인' ($label + ': 조종기 프로필의 Software Radio Dual Rates and Expo가 켜져 있습니다. RF 조종기 설정에서 끄세요.') }
    }
    foreach ($name in 'Reset', 'Cancel', 'Select', 'Mode', 'Up', 'Down') {
        $body = Section-Text $text $name
        if ($null -eq $body) { continue }
        $primary = Path-Value (Try-KeyValue $body 'InputPrimary'); $secondary = Path-Value (Try-KeyValue $body 'InputSecondary')
        Diag-Line ('      [' + $name + '] InputPrimary=' + $primary + ' InputSecondary=' + $secondary)
        $inputs = @(@($primary, $secondary) | ForEach-Object { $_ -replace '^INT:', '' } | Where-Object { $_ -match '^\d+$' })
        if ($name -eq 'Reset' -and $inputs.Count) { Diag-Find '확인' ($label + ': 조종기 입력 #' + ($inputs -join ', #') + '이(가) RF의 Reset 기능에 지정되어 있습니다. 이 스위치를 켠 채로 두면 RF가 기체를 반복 리셋하고, SITL도 리셋 때마다 다시 연결합니다. 연결 전에 해당 스위치 위치를 확인하세요.') }
    }
}
function Diag-Models([string]$root, [string]$label) {
    foreach ($m in $Catalog) {
        $vp = [IO.Path]::Combine($root, 'Vehicles', 'CustomVehicles', $m.Vehicle)
        if (-not [IO.File]::Exists($vp)) { Diag-Line ('  ' + $m.Title + ': 설치 안 됨'); continue }
        Diag-Try $m.Title {
            $text = Read-Text $vp
            $state = '검사 불가'
            try { $state = if ((Patched-Text $text) -ceq $text) { 'CH8~12 보정됨' } else { 'CH8~12 보정 필요(도우미 3번)' } } catch { $state = '보정 검사 불가: ' + $_.Exception.Message }
            $based = Path-Value (Try-KeyValue $text 'BasedOn')
            $basedState = if (-not $based) { '없음' } elseif ($based -notmatch '[\\/:]') { '이름만 있음' } elseif (Path-Exists $based) { '파일 있음' } else { '파일 없음' }
            $launch = @([regex]::Matches($text, '(?m)^\s*LaunchMethod=([^\r\n]*)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            $odd = @([regex]::Matches($text, '(?m)^\s*(\w*Frame\w*)=STRING:(<[^\r\n<>]*[^\x00-\x7f][^\r\n<>]*>)') | ForEach-Object { $_.Groups[1].Value + '=' + (Decode-Carrier $_.Groups[2].Value) } | Select-Object -Unique)
            Diag-Line ('  ' + $m.Title + ': ' + (File-Line $vp))
            Diag-Line ('      ' + $state + ' / BasedOn ' + $basedState + ' / LaunchMethod ' + $(if ($launch.Count) { $launch -join ',' } else { '(없음)' }))
            if ($odd.Count) {
                Diag-Line ('      비영문 프레임 이름: ' + ($odd -join '; '))
                Diag-Find '정보' ($label + ' / ' + $m.Title + ': 프레임 이름 ' + @($odd).Count + '종이 영문판의 <None>이 아니라 제작사 중국어판 RF의 표기(' + (($odd | ForEach-Object { ($_ -split '=', 2)[1] } | Select-Object -Unique) -join ', ') + ')입니다. RF 9에서 "Landing Gear Child Component has no Frame" 경고가 날 수 있습니다. 도우미는 이 값을 바꾸지 않습니다.')
            }
        }
    }
}
function Diag-MissionPlanner($request) {
    $mp = Mp-Root $request
    Diag-Line ('[Mission Planner / SITL] ' + $mp)
    if (-not [IO.Directory]::Exists($mp)) { Diag-Line '  Mission Planner 사용자 폴더 없음'; Diag-Line ''; return }
    $config = [IO.Path]::Combine($mp, 'config.xml')
    if ([IO.File]::Exists($config)) { Diag-Line ('  ' + (File-Line $config)) }
    $sitl = [IO.Path]::Combine($mp, 'sitl')
    if (-not [IO.Directory]::Exists($sitl)) { Diag-Line '  sitl 폴더 없음 (Mission Planner에서 SITL을 아직 실행하지 않음)'; Diag-Line ''; return }
    foreach ($exe in @(Get-ChildItem -LiteralPath $sitl -File -Filter '*.exe' -ErrorAction SilentlyContinue)) { Diag-Line ('  ' + (File-Line $exe.FullName)) }
    foreach ($git in @(Get-ChildItem -LiteralPath $sitl -File -Filter '*-git.txt' -ErrorAction SilentlyContinue)) {
        $lines = @([IO.File]::ReadAllLines($git.FullName) | Where-Object { $_.Trim() })
        Diag-Line ('  ' + $git.Name + ': ' + (@($lines | Where-Object { $_ -match '^commit ' } | Select-Object -First 1) -join '') + ' / ' + (@($lines | Select-Object -Last 1) -join '').Trim() + ' / ' + $git.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    }
    $faTime = $null; $other = $null
    foreach ($d in @(Get-ChildItem -LiteralPath $sitl -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $eeprom = [IO.Path]::Combine($d.FullName, 'eeprom.bin')
        if (-not [IO.File]::Exists($eeprom)) { continue }
        $logDir = [IO.Path]::Combine($d.FullName, 'logs')
        $logs = @(); if ([IO.Directory]::Exists($logDir)) { $logs = @(Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) }
        $newest = if ($logs.Count) { ', 최근 로그 ' + $logs[0].Name + ' ' + $logs[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
        $mark = if ($d.Name -ceq $SitlModelFolder) { '   <- Mission Planner flightaxis SITL이 쓰는 저장소' } else { '' }
        $changed = ([IO.FileInfo]$eeprom).LastWriteTime
        if ($d.Name -ceq $SitlModelFolder) { $faTime = $changed }
        elseif ($d.Name -notmatch '^flightaxis' -and ($null -eq $other -or $changed -gt $other.Time)) { $other = [pscustomobject]@{ Name = $d.Name; Time = $changed } }
        Diag-Line ('  ' + $d.Name + '\eeprom.bin (파라미터 저장) ' + ([IO.FileInfo]$eeprom).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + ', 로그 ' + $logs.Count + '개' + $newest + $mark)
    }
    if ($other -and ($null -eq $faTime -or $other.Time -gt $faTime)) { Diag-Find '확인' ('flightaxis가 아닌 SITL 저장소 "' + $other.Name + '"가 flightaxis 저장소보다 최근에 바뀌었습니다(' + $other.Time.ToString('MM-dd HH:mm') + '). 최근에 SITL을 다른 모델로 실행했을 수 있습니다. RealFlight와 연결하려면 Simulation에서 Model = flightaxis를 고르세요.') }
    if (-not [IO.File]::Exists([IO.Path]::Combine($sitl, $SitlModelFolder, 'eeprom.bin'))) { Diag-Line ('  ' + $SitlModelFolder + ' 저장소 없음: 다음 SITL 시작 때 기본 파라미터로 새로 만들어짐') }
    Diag-Line ''
}
function Diag-Events {
    Diag-Line '[Windows 기록 - 최근 30일 멈춤(1002)·비정상 종료(1000)]'
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 400 -ErrorAction Stop |
            Where-Object { $_.Message -match '(?i)RealFlight|ArduPlane|MissionPlanner' } | Select-Object -First 15)
        if (-not $events.Count) { Diag-Line '  관련 기록 없음' }
        foreach ($e in $events) {
            $msg = (($e.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' | ')
            if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + '...' }
            Diag-Line ('  ' + $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') + ' [' + $e.Id + '] ' + $msg)
        }
        $hangs = @($events | Where-Object { $_.Id -eq 1002 -and $_.Message -match '(?i)RealFlight' }).Count
        if ($hangs) { Diag-Find '정보' ('최근 30일 동안 Windows가 기록한 RealFlight 멈춤(응답 없음) ' + $hangs + '건이 보고서에 있습니다.') }
    } catch {
        if ([string]$_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { Diag-Line '  관련 기록 없음' } else { Diag-Line ('  (읽기 실패: ' + $_.Exception.Message + ')') }
    }
    Diag-Try 'crash dumps' {
        $dumps = [IO.Path]::Combine($env:LOCALAPPDATA, 'CrashDumps')
        if ([IO.Directory]::Exists($dumps)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dumps -File -ErrorAction Stop | Where-Object { $_.Name -match '(?i)RealFlight|ArduPlane|MissionPlanner' } | Sort-Object LastWriteTime -Descending | Select-Object -First 5)) { Diag-Line ('  덤프: ' + (File-Line $f.FullName)) }
        }
    }
    Diag-Line ''
}
function Report-Folder($request) {
    $folder = Request-Text $request 'ReportFolder'
    if (-not $folder) { $folder = [IO.Path]::Combine($env:LOCALAPPDATA, 'SJARC', 'RealFlightSetup', '0.1.0', 'reports') }
    $folder = Full $folder
    [void][IO.Directory]::CreateDirectory($folder)
    No-Links $folder
    return $folder
}
function Redacted-Ini([string]$text) {
    # The profile block holds the user's avatar/bio/location; everything else is simulator settings.
    return [regex]::Replace($text, '(?ms)^(\[LicenseInfo\]\r?\n)(.*?)(?=^\[|\z)', [Text.RegularExpressions.MatchEvaluator]{ param($m) return $m.Groups[1].Value + ([regex]::Replace($m.Groups[2].Value, '(?m)^([^=\r\n]+)=[^\r\n]*', '$1=(removed)')) })
}
function Quick-Status($request) {
    # Read-only snapshot for the GUI status strip: running programs, the SITL model, and the selected RF INI's
    # FlightAxis link / pause / controller keys. Null means "could not tell".
    $all = @(Get-Process -ErrorAction SilentlyContinue)
    $sitl = @($all | Where-Object { $_.ProcessName -match $SitlNamePattern })
    $flightAxis = $null
    if ($sitl.Count) {
        try {
            $lines = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Ardu%' OR Name LIKE 'AntennaTracker%' OR Name LIKE 'Blimp%'" -ErrorAction Stop | ForEach-Object { [string]$_.CommandLine } | Where-Object { $_ })
            if ($lines.Count) { $flightAxis = (@($lines | Where-Object { $_ -match '(?i)flightaxis' }).Count -gt 0) }
        } catch { }
    }
    $link = $null; $pause = $null; $controller = $null; $iniName = ''
    $root = Request-Text $request 'Root'
    if ($root) {
        try {
            $full = Full $root
            $names = @('RealFlight64.ini', 'RealFlight.ini' | Where-Object { [IO.File]::Exists([IO.Path]::Combine($full, $_)) })
            $exePath = Request-Text $request 'Executable'
            if ($names.Count -eq 2 -and $exePath) { $names = @($names | Where-Object { $_ -ieq ([IO.Path]::GetFileNameWithoutExtension($exePath) + '.ini') }) }
            if ($names.Count -ge 1) {
                $iniName = $names[0]
                $text = Read-Text ([IO.Path]::Combine($full, $iniName))
                $keys = @('FlightAxisLinkEnabled', 'RealFlightLinkEnabled' | Where-Object { $null -ne (Try-KeyValue $text $_) })
                if ($keys.Count) { $link = (@($keys | Where-Object { (Try-KeyValue $text $_) -ceq 'BOOL:Yes' }).Count -gt 0) }
                $pauses = @('PauseSimWhenFocusLost', 'PauseSimWhileInMenus' | Where-Object { $null -ne (Try-KeyValue $text $_) })
                if ($pauses.Count) { $pause = (@($pauses | Where-Object { (Try-KeyValue $text $_) -ceq 'BOOL:Yes' }).Count -gt 0) }
                $selection = Path-Value (Try-KeyValue $text 'CurrentControllerSelection')
                $controller = [bool]($selection -and [regex]::IsMatch($text, '(?m)^\[Control\|[^\]\r\n]*\|' + [regex]::Escape($selection) + '\]'))
            }
        } catch { }
    }
    return @{ Success = $true; Version = $Version; State = 'STATUS'; Ini = $iniName
        RfRunning = (@($all | Where-Object { $_.ProcessName -match '^RealFlight' }).Count -gt 0)
        MpRunning = (@($all | Where-Object { $_.ProcessName -match '^MissionPlanner' }).Count -gt 0)
        SitlRunning = ($sitl.Count -gt 0); SitlFlightAxis = $flightAxis
        LinkEnabled = $link; PauseOn = $pause; ControllerSelected = $controller }
}
function Diagnose($request) {
    $script:DiagReport = [Collections.Generic.List[string]]::new()
    $script:DiagFindings = [Collections.Generic.List[object]]::new()
    $script:DiagRfRunning = $false; $script:DiagFlightAxisSitl = $false
    $now = Get-Date
    Diag-Line ('SJ-ARC 설치 도우미 v' + $Version + ' - RealFlight/SITL 연결 진단 보고서')
    Diag-Line ('작성: ' + $now.ToString('yyyy-MM-dd HH:mm:ss') + '   (읽기 전용: 이 진단은 어떤 파일·설정도 바꾸지 않습니다)')
    Diag-Line ''
    $exePath = Request-Text $request 'Executable'
    $selectedRoot = Request-Text $request 'Root'
    Diag-System
    Diag-Processes
    Diag-Network
    Diag-Line '[RealFlight 설치]'
    Diag-Try 'installations' {
        foreach ($i in @((Detect).Installations)) { Diag-Line ('  ' + $i.Label + ' - ' + $i.Path) }
        if ($exePath) { $e = Executable $exePath; Diag-Line ('  도우미에서 선택: ' + $e.Label + ' - ' + $e.Path) }
    }
    Diag-Line ''
    $roots = [Collections.Generic.List[string]]::new()
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($selectedRoot) { try { $roots.Add((Full $selectedRoot)) } catch { Diag-Line ('선택한 문서 폴더 경로 오류: ' + $selectedRoot) } }
    foreach ($name in 'RealFlight 8', 'RealFlight 9', 'RealFlight 9.5', 'RealFlight 9.5S', 'RealFlight Evolution') {
        $p = Full ([IO.Path]::Combine($docs, $name))
        if ([IO.Directory]::Exists($p) -and -not @($roots | Where-Object { $_ -ieq $p }).Count) { $roots.Add($p) }
    }
    foreach ($r in $roots) {
        if (-not [IO.Directory]::Exists($r)) { Diag-Line ('[RealFlight 사용자 폴더] ' + $r + ' - 폴더 없음'); Diag-Line ''; continue }
        Diag-Try $r { Diag-RfRoot $r ($selectedRoot -and $r -ieq (Full $selectedRoot)) }
    }
    Diag-MissionPlanner $request
    Diag-Events
    $order = @{ '문제' = 0; '확인' = 1; '정보' = 2 }
    $findings = @($script:DiagFindings | Sort-Object { $order[$_.Level] })
    $summary = @($findings | ForEach-Object { '[' + $_.Level + '] ' + $_.Text })
    if (-not $summary.Count) { $summary = @('[정보] 자동 검사에서 눈에 띄는 설정 문제는 찾지 못했습니다. 아래 "다음 순서"대로 하나씩 확인하세요.') }
    $body = $script:DiagReport.ToArray()
    $script:DiagReport.Clear()
    Diag-Line '================ 요약 ================'
    foreach ($s in $summary) { Diag-Line $s }
    Diag-Line ''
    Diag-Line '================ 다음 순서 (위에서부터 하나씩) ================'
    Diag-Line '1. RealFlight가 "응답 없음"이면: 창을 닫기 전에 이 진단을 먼저 만들고, SITL 검은 창(ArduPlane)을 사진으로 찍어 두세요.'
    Diag-Line '   "Starting controller" 줄이 계속 반복되면 RF가 리셋될 때마다 SITL이 다시 연결하고 있다는 뜻입니다.'
    Diag-Line '2. 모두 종료 -> "남은 SITL 창 종료" -> 켜는 순서: RealFlight(기체 선택까지) -> Mission Planner -> Simulation 연결.'
    Diag-Line '   끌 때는 Mission Planner(SITL)를 먼저 끄고 RealFlight를 마지막에 끄세요.'
    Diag-Line '3. 그래도 멈추면 "SITL 저장 설정 초기화". 파라미터를 넣기 전에 먼저 연결만 확인합니다.'
    Diag-Line '   - 초기화 직후에도 멈춤: SITL 파라미터 문제가 아닙니다 -> 4번으로.'
    Diag-Line '   - 초기화 직후엔 되고, 기종 param 적용 후 SITL을 재시작하면 멈춤: 파라미터가 원인입니다 -> 이 보고서와 함께 알려 주세요.'
    Diag-Line '4. 그래도 멈추면 "RealFlight 설정 초기화"(최후 수단). 조종기 선택·보정과 Physics 설정을 다시 해야 합니다.'
    Diag-Line '5. 해결되지 않으면 두 초기화를 되돌리고, 이 보고서 zip과 사진을 보내 주세요.'
    Diag-Line ''
    foreach ($line in $body) { Diag-Line $line }
    $folder = Report-Folder $request
    $stamp = $now.ToString('yyyyMMdd-HHmmss')
    $reportPath = [IO.Path]::Combine($folder, 'diagnose-' + $stamp + '.txt')
    [IO.File]::WriteAllLines($reportPath, $script:DiagReport.ToArray(), [Text.UTF8Encoding]::new($true))
    $zipPath = [IO.Path]::Combine($folder, 'SJARC-diagnose-' + $stamp + '.zip')
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $reportPath, 'diagnose.txt')
        $n = 0
        foreach ($r in $roots) {
            $n++
            foreach ($name in 'RealFlight.ini', 'RealFlight64.ini') {
                $p = [IO.Path]::Combine($r, $name)
                if (-not [IO.File]::Exists($p)) { continue }
                $entry = $zip.CreateEntry(('rf' + $n + '-' + ([IO.Path]::GetFileName($r) -replace '[^\w.-]', '_') + '/' + $name))
                $s = $entry.Open(); try { $b = $ByteEncoding.GetBytes((Redacted-Ini (Read-Text $p))); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
            }
            $profiles = [IO.Path]::Combine($r, 'Radio Profiles')
            if ([IO.Directory]::Exists($profiles)) {
                foreach ($f in @(Get-ChildItem -LiteralPath $profiles -File -Filter '*.radioprofile' -ErrorAction SilentlyContinue)) {
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, ('rf' + $n + '-' + ([IO.Path]::GetFileName($r) -replace '[^\w.-]', '_') + '/Radio Profiles/' + ($f.Name -replace '[^\w. -]', '_')))
                }
            }
        }
        $sitl = [IO.Path]::Combine((Mp-Root $request), 'sitl')
        if ([IO.Directory]::Exists($sitl)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $sitl -File -Filter '*-git.txt' -ErrorAction SilentlyContinue)) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, 'sitl/' + $f.Name) }
        }
    } finally { $zip.Dispose() }
    $problems = @($findings | Where-Object { $_.Level -eq '문제' }).Count
    return @{ Success = $true; Version = $Version; State = 'DIAGNOSED'; ReportFile = $reportPath; Bundle = $zipPath; Problems = $problems; Summary = @($summary)
        Message = 'Read-only diagnosis. No file or setting was changed.' }
}

# ---------------------------------------------------------------- SITL launcher
function Planner-Exe {
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($entry in @(Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and [string]$_.DisplayName -match '^Mission Planner' })) {
            if ($entry.PSObject.Properties['InstallLocation'] -and $entry.InstallLocation) {
                $candidate = [IO.Path]::Combine(([string]$entry.InstallLocation).Trim().Trim('"'), 'MissionPlanner.exe')
                if ([IO.File]::Exists($candidate)) { return $candidate }
            }
        }
    }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $base) { continue }
        $candidate = [IO.Path]::Combine($base, 'Mission Planner', 'MissionPlanner.exe')
        if ([IO.File]::Exists($candidate)) { return $candidate }
    }
    return ''
}
function Planner-Setting([string]$xml, [string]$name) {
    $m = [regex]::Match($xml, '<' + [regex]::Escape($name) + '>([^<]*)</' + [regex]::Escape($name) + '>')
    if ($m.Success) { return [Net.WebUtility]::HtmlDecode($m.Groups[1].Value) }
    return $null
}
function Planner-AutoConnect([string]$xml) {
    # Mission Planner 1.3.8x listens for MAVLink on UDP 14550 ("Mavlink default port", on by default) and connects by
    # itself. $null = no saved list (default applies), $false = the user turned that entry off.
    $saved = Planner-Setting $xml 'AutoConnect'
    if (-not $saved) { return $null }
    # Windows PowerShell's ConvertFrom-Json emits a JSON array as one object; unroll it before filtering.
    try { $parsed = $saved | ConvertFrom-Json } catch { return $null }
    $entry = @(@($parsed) | ForEach-Object { $_ } | Where-Object { $_.Port -eq 14550 -and $_.Protocol -eq 1 -and $_.Direction -eq 0 })
    if (-not $entry.Count) { return $false }
    return [bool]$entry[0].Enabled
}
function Sitl-Home([string]$xml) {
    # Same "-O lat,lng,alt,heading" form Mission Planner builds from its map; its last map position is reused when saved.
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $lat = -35.363261; $lng = 149.165230; $alt = 584
    $savedLat = Planner-Setting $xml 'maplast_lat'; $savedLng = Planner-Setting $xml 'maplast_lng'
    $a = 0.0; $b = 0.0
    if ($savedLat -and $savedLng -and [double]::TryParse($savedLat, [Globalization.NumberStyles]::Float, $invariant, [ref]$a) -and [double]::TryParse($savedLng, [Globalization.NumberStyles]::Float, $invariant, [ref]$b) -and [Math]::Abs($a) -le 90 -and [Math]::Abs($b) -le 180 -and ($a -ne 0 -or $b -ne 0)) {
        if ([Math]::Abs($a - $lat) -gt 0.01 -or [Math]::Abs($b - $lng) -gt 0.01) { $alt = 0 }
        $lat = $a; $lng = $b
    }
    return [string]::Format($invariant, '{0:0.0######},{1:0.0######},{2},0', $lat, $lng, $alt)
}
function Start-FlightAxisSitl($request) {
    $mp = Mp-Root $request
    $sitlDir = [IO.Path]::Combine($mp, 'sitl')
    $exe = [IO.Path]::Combine($sitlDir, 'ArduPlane.exe')
    if (-not [IO.File]::Exists($exe)) { throw ('No ArduPlane SITL in ' + $sitlDir + '. Run Simulation > Plane once in Mission Planner to download it.') }
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $SitlNamePattern })
    if ($running.Count) { throw ('A SITL is already running: ' + (@($running | ForEach-Object { $_.ProcessName + ' (PID ' + $_.Id + ')' }) -join ', ') + '. Stop it before starting another one.') }
    $rf = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^RealFlight' })
    $allowWithout = $request.PSObject.Properties['AllowWithoutRealFlight'] -and [bool]$request.AllowWithoutRealFlight
    if (-not $rf.Count -and -not $allowWithout) { throw 'Start RealFlight and select the aircraft first: the flightaxis SITL drives the aircraft RealFlight is showing.' }
    $store = [IO.Path]::Combine($sitlDir, $SitlModelFolder)
    [void][IO.Directory]::CreateDirectory($store)
    No-Links $store
    $config = [IO.Path]::Combine($mp, 'config.xml')
    $xml = if ([IO.File]::Exists($config)) { [IO.File]::ReadAllText($config) } else { '' }
    # Mission Planner's own command line for flightaxis (GCSViews/SITL.cs) plus one extra MAVLink output on UDP 14550,
    # which Mission Planner's auto-connect picks up. Never --wipe: the stored parameters are the point of this button.
    $arguments = '-Mflightaxis -O' + (Sitl-Home $xml) + ' -s1 --serial0 tcp:0 --serial1 udpclient:127.0.0.1:14550'
    $window = if ($request.PSObject.Properties['HideWindow'] -and [bool]$request.HideWindow) { 'Hidden' } else { 'Minimized' }
    # Start-Process goes through ShellExecute: the SITL gets its own console and does not inherit this script's output pipe.
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $store -WindowStyle $window -PassThru
    Start-Sleep -Milliseconds 1500
    if ($process.HasExited) { throw ('SITL exited immediately (exit code ' + $process.ExitCode + '). Command: ArduPlane.exe ' + $arguments) }
    $notes = [Collections.Generic.List[string]]::new(); $warnings = [Collections.Generic.List[string]]::new()
    $notes.Add('SITL started (PID ' + $process.Id + '): ArduPlane.exe ' + $arguments + '  in ' + $store)
    $planner = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^MissionPlanner' })
    $plannerStarted = $false
    $startPlanner = -not ($request.PSObject.Properties['StartPlanner'] -and -not [bool]$request.StartPlanner)
    if (-not $planner.Count -and $startPlanner) {
        $plannerExe = Planner-Exe
        if ($plannerExe) { [void](Start-Process -FilePath $plannerExe -WorkingDirectory ([IO.Path]::GetDirectoryName($plannerExe))); $plannerStarted = $true; $notes.Add('Mission Planner started: ' + $plannerExe) }
        else { $warnings.Add('Mission Planner was not found; start it yourself.') }
    }
    $auto = Planner-AutoConnect $xml
    if ($auto -eq $false) { $warnings.Add('Mission Planner auto-connect on UDP 14550 is turned off: connect with TCP 127.0.0.1:5760.') }
    if ($rf.Count) {
        $listening = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq 18083 })
        if (-not $listening.Count) { $warnings.Add('RealFlight is not listening on 18083: check RealFlight Link = Yes in Settings > Physics.') }
    }
    return @{ Success = $true; Version = $Version; State = 'SITL_STARTED'; Pid = $process.Id; Arguments = $arguments; Store = $store
        PlannerStarted = $plannerStarted; AutoConnect = $auto; Notes = @($notes); Warnings = @($warnings) }
}

# ---------------------------------------------------------------- actions (reversible)
function Stop-SitlProcesses($request) {
    # Only simulator processes started from Mission Planner's sitl folder; Mission Planner and RealFlight are left to the user.
    $sitlDir = [IO.Path]::Combine((Mp-Root $request), 'sitl') + '\'
    $stopped = @(); $skipped = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $SitlNamePattern })) {
        $path = ''; try { $path = [string]$p.Path } catch { }
        if (-not $path -or -not $path.StartsWith($sitlDir, [StringComparison]::OrdinalIgnoreCase)) { $skipped += ($p.ProcessName + ' (PID ' + $p.Id + ') ' + $path); continue }
        try { $p.Kill(); [void]$p.WaitForExit(5000); $stopped += ($p.ProcessName + ' (PID ' + $p.Id + ')') } catch { $skipped += ($p.ProcessName + ' (PID ' + $p.Id + '): ' + $_.Exception.Message) }
    }
    return @{ Success = $true; Version = $Version; State = 'SITL_STOPPED'; Stopped = @($stopped); Skipped = @($skipped)
        Message = 'Stopped SITL processes started from ' + $sitlDir + '. Mission Planner and RealFlight were not touched.' }
}
function Reset-SitlStore($request) {
    Assert-SimClosed
    $sitl = [IO.Path]::Combine((Mp-Root $request), 'sitl')
    $model = [IO.Path]::Combine($sitl, $SitlModelFolder)
    if (-not [IO.Directory]::Exists($model)) { return @{ Success = $true; Version = $Version; State = 'NOTHING_TO_RESET'; Message = 'No ' + $model + ' folder. The next SITL start already begins with default parameters.' } }
    No-Links $model
    $backup = Free-Name ([IO.Path]::Combine($sitl, $SitlModelFolder + '_SJARC-backup-' + (Stamp)))
    # A plain rename: the folder name carries the time, and a restore puts the store back byte for byte.
    Retry-IO { [IO.Directory]::Move($model, $backup) }
    return @{ Success = $true; Version = $Version; State = 'SITL_RESET'; Backup = $backup
        Message = 'Moved ' + $model + ' (eeprom.bin parameters, logs) to ' + $backup + '. Nothing deleted. The next SITL start creates default parameters.' }
}
function Restore-SitlStore($request) {
    Assert-SimClosed
    $sitl = [IO.Path]::Combine((Mp-Root $request), 'sitl')
    $model = [IO.Path]::Combine($sitl, $SitlModelFolder)
    $latest = @()
    if ([IO.Directory]::Exists($sitl)) { $latest = @(Get-ChildItem -LiteralPath $sitl -Directory -Filter ($SitlModelFolder + '_SJARC-backup-*') | Sort-Object LastWriteTime, Name -Descending) }
    if (-not $latest.Count) { throw 'No SITL backup made by this helper was found (' + $SitlModelFolder + '_SJARC-backup-*).' }
    $source = $latest[0].FullName
    No-Links $source
    $aside = ''
    if ([IO.Directory]::Exists($model)) {
        No-Links $model
        $aside = Free-Name ([IO.Path]::Combine($sitl, $SitlModelFolder + '_SJARC-replaced-' + (Stamp)))
        Retry-IO { [IO.Directory]::Move($model, $aside) }
    }
    try { Retry-IO { [IO.Directory]::Move($source, $model) } }
    catch { if ($aside -and -not [IO.Directory]::Exists($model)) { [IO.Directory]::Move($aside, $model) }; throw }
    $msg = 'Restored ' + $model + ' from ' + $source + '.'
    if ($aside) { $msg += ' The store created after the reset was kept at ' + $aside + '.' }
    return @{ Success = $true; Version = $Version; State = 'SITL_RESTORED'; Restored = $source; Kept = $aside; Message = $msg }
}
function Reset-RfIni($request) {
    Assert-SimClosed
    $exe = Executable $request.Executable
    $info = Root-Info $request.Root $exe; $root = $info.Root
    Assert-EditionMatch $exe $root
    $ini = Inside $root $info.Ini
    No-Links $ini
    $bytes = [IO.File]::ReadAllBytes($ini)
    $folder = Free-Name (Inside $root ($IniResetFolder + '\' + (Stamp)))
    [void][IO.Directory]::CreateDirectory($folder)
    $saved = [IO.Path]::Combine($folder, $info.Ini)
    Retry-IO { [IO.File]::Move($ini, $saved) }
    if ((Hash-Bytes ([IO.File]::ReadAllBytes($saved))) -cne (Hash-Bytes $bytes)) { throw 'Moved INI does not match the original: ' + $saved }
    $meta = @{ Package = 'SJARC-RealFlight-Setup'; Version = $Version; Kind = 'RfIni'; Root = $root; Ini = $info.Ini; Sha256 = (Hash-Bytes $bytes); State = 'Reset'; Time = (Get-Date).ToString('o') }
    [IO.File]::WriteAllText([IO.Path]::Combine($folder, 'reset.json'), ($meta | ConvertTo-Json), $Utf8)
    return @{ Success = $true; Version = $Version; State = 'RF_INI_RESET'; Backup = $saved
        Message = 'Moved ' + $ini + ' to ' + $saved + '. RealFlight creates a default INI on its next start. Nothing deleted.' }
}
function Restore-RfIni($request) {
    Assert-SimClosed
    $exe = Executable $request.Executable
    $root = Full ([string]$request.Root)
    No-Links $root
    Assert-EditionMatch $exe $root
    $base = Inside $root $IniResetFolder
    $sets = @()
    if ([IO.Directory]::Exists($base)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name -Descending)) {
            $metaPath = [IO.Path]::Combine($d.FullName, 'reset.json')
            if (-not [IO.File]::Exists($metaPath)) { continue }
            $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($meta.Package -ceq 'SJARC-RealFlight-Setup' -and $meta.State -ceq 'Reset') { $sets += [pscustomobject]@{ Dir = $d.FullName; Meta = $meta; MetaPath = $metaPath } }
        }
    }
    if (-not $sets.Count) { throw 'No RealFlight INI reset made by this helper was found under ' + $base + '.' }
    $set = $sets[0]
    if ($set.Meta.Ini -cnotin @('RealFlight.ini', 'RealFlight64.ini') -or $set.Meta.Root -ine $root) { throw 'INI reset record does not belong to this folder.' }
    $saved = [IO.Path]::Combine($set.Dir, $set.Meta.Ini)
    No-Links $saved
    $bytes = [IO.File]::ReadAllBytes($saved)
    if ((Hash-Bytes $bytes) -cne $set.Meta.Sha256) { throw 'Saved INI changed since the reset; not restoring it: ' + $saved }
    $target = Inside $root $set.Meta.Ini
    $kept = ''
    if ([IO.File]::Exists($target)) {
        No-Links $target
        $kept = [IO.Path]::Combine($set.Dir, $set.Meta.Ini + '.after-reset-' + (Stamp))
        [IO.File]::Copy($target, $kept)
    }
    Atomic-Write $target $bytes
    $set.Meta.State = 'Restored'
    $set.Meta | Add-Member -NotePropertyName RestoredAt -NotePropertyValue (Get-Date).ToString('o') -Force
    [IO.File]::WriteAllText($set.MetaPath, ($set.Meta | ConvertTo-Json), $Utf8)
    $msg = 'Restored ' + $target + ' from ' + $saved + ' (the saved copy is kept).'
    if ($kept) { $msg += ' The INI RealFlight created after the reset was copied to ' + $kept + '.' }
    return @{ Success = $true; Version = $Version; State = 'RF_INI_RESTORED'; Restored = $target; Kept = $kept; Message = $msg }
}
