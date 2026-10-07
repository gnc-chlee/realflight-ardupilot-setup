#requires -Version 5.1
<# Offline patch for the four MFE models in SITL_Models PR 158, commit e93e185.
   Default: inspect only. Never connects to MAVLink or starts a simulator. #>
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [string]$RealFlightRoot,
    [ValidateSet('All', 'Striver', 'Pioneer', 'Fighter', 'Hero')][string]$Model = 'All',
    [Parameter(ParameterSetName = 'Apply')][switch]$Apply,
    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')][string]$RestoreManifest,
    [switch]$Interactive
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Names = [ordered]@{
    Striver = 'STRIVERminiVTOL.rfvehicle'
    Pioneer = 'Pioneer.rfvehicle'
    Fighter = 'fighterVTOL.rfvehicle'
    Hero = 'HERO2180.rfvehicle'
}
# Latin-1 is a reversible byte container here, NOT an encoding conversion.
# Only ASCII signal fields are edited; original UTF-8/ANSI bytes stay intact.
$ByteEncoding = [Text.Encoding]::GetEncoding(28591)

function Assert-Closed {
    $busy = @(Get-Process | Where-Object { $_.ProcessName -match '^(RealFlight.*|MissionPlanner.*|ArduPlane.*)$' })
    if ($busy.Count) { throw ('Close RealFlight, Mission Planner and SITL first: ' + ($busy.ProcessName -join ', ')) }
}
function Assert-NoLink([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked/cloud-placeholder path refused: $Path. Use a local, fully available folder." }
}
function Hash-Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function New-Node([string]$Name, [int]$Start) {
    return [pscustomobject]@{ Name = $Name; Start = $Start; End = -1; Values = @{}; Children = [Collections.Generic.List[object]]::new() }
}
function Parse-Rf([string]$Text) {
    if ($Text.Contains([string][char]0)) { throw 'UTF-16/binary vehicle files are not supported.' }
    $rootNode = New-Node 'ROOT' 0
    $stack = [Collections.Generic.List[object]]::new()
    $stack.Add($rootNode)
    foreach ($line in [regex]::Matches($Text, '[^\n]*\n|[^\n]+$')) {
        $s = $line.Value.Trim()
        if ($line.Index -eq 0) { $s = $s.TrimStart([char[]]@([char]239, [char]187, [char]191)) }
        if ($s -match '^ENDGROUP\[([^\]]+)\]$') {
            if ($stack.Count -lt 3 -or $stack[$stack.Count - 1].Name -cne $Matches[1]) { throw 'Unbalanced rfvehicle subgroup.' }
            $stack[$stack.Count - 1].End = $line.Index + $line.Length
            $stack.RemoveAt($stack.Count - 1)
        } elseif ($s -match '^SUBGROUP\[([^\]]+)\]$') {
            if ($stack.Count -lt 2) { throw 'Subgroup outside section.' }
            $node = New-Node $Matches[1] $line.Index
            $stack[$stack.Count - 1].Children.Add($node)
            $stack.Add($node)
        } elseif ($s -match '^\[([^\]]+)\]$') {
            if ($stack.Count -gt 2) { throw 'Unclosed subgroup before section.' }
            if ($stack.Count -eq 2) { $stack[1].End = $line.Index; $stack.RemoveAt(1) }
            $node = New-Node $Matches[1] $line.Index
            $rootNode.Children.Add($node)
            $stack.Add($node)
        } elseif ($s.Contains('=')) {
            $pair = $s -split '=', 2
            $v = $stack[$stack.Count - 1].Values
            if ($v.ContainsKey($pair[0])) { throw "Duplicate key: $($pair[0])" }
            $v[$pair[0]] = $pair[1]
        } elseif ($s -and -not $s.StartsWith(';') -and -not $s.StartsWith('//')) {
            throw "Unknown rfvehicle syntax at byte $($line.Index)."
        }
    }
    if ($stack.Count -ne 2) { throw 'Truncated rfvehicle.' }
    $stack[1].End = $Text.Length
    return $rootNode
}
function Child($Node, [string]$Name) {
    $found = @($Node.Children | Where-Object Name -CEQ $Name)
    if ($found.Count -ne 1) { throw "Expected one $Name under $($Node.Name); found $($found.Count)." }
    return $found[0]
}
function Walk($Node) {
    $Node
    foreach ($c in $Node.Children) { Walk $c }
}
function Expect($Node, [string]$Key, [string]$Value) {
    if ($Node.Values[$Key] -cne $Value) { throw "Unsupported wiring/settings: $($Node.Name) $Key=$($Node.Values[$Key]); expected $Value. Nothing should be forced." }
}
function Number($Node, [string]$Key) {
    $value = $Node.Values[$Key]
    if ($null -eq $value -or $value -notmatch '^FLOAT:(.*)$') { throw "Missing numeric field $Key." }
    return [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
}
function Validate-Wiring($Tree) {
    $e = Child $Tree 'VehicleElectronics'
    Expect $e 'NumReceiverChannels' 'INT:12'
    $expected = @(
        @{ Frame = '~CS_ENGINE_FR'; Signal = 122; Rx = 9; CW = 'Yes' },
        @{ Frame = '~CS_ENGINE_RL'; Signal = 121; Rx = 10; CW = 'Yes' },
        @{ Frame = '~CS_ENGINE_RR'; Signal = 123; Rx = 11; CW = 'No' },
        @{ Frame = '~CS_ENGINE_FL'; Signal = 119; Rx = 12; CW = 'No' },
        @{ Frame = '~CS_ENGINE_P'; Signal = 104; Rx = 3; CW = 'Yes' }
    )
    $props = @(Walk (Child $Tree 'RootComponent') | Where-Object { $_.Values['ComponentType'] -ceq 'STRING:PropellerComponent' })
    if ($props.Count -ne 5) { throw 'Expected exactly five propeller components.' }
    foreach ($m in $expected) {
        $p = @($props | Where-Object { $_.Values['EngineTorusFrame'] -ceq ('STRING:' + $m.Frame) })
        if ($p.Count -ne 1) { throw "Unrecognised motor frame $($m.Frame)." }
        Expect $p[0] 'ServoThrottle' "INT:$($m.Signal)"
        Expect $p[0] 'ServoThrottleRev' 'BOOL:No'
        Expect $p[0] 'ClockSpinsClockwiseFromRear' "BOOL:$($m.CW)"
        $servo = Child $e "#$($m.Signal)"
        Expect $servo 'Type' 'STRING:PhysicalServo'
        Expect $servo 'ConnectTo_InternalName' "INT:$($m.Rx)"
    }
    $radio = Child $Tree 'AirplaneSoftwareRadio'
    Expect $radio 'OutputChannelsArray' 'INTARRAY:1~2~3~4~5~6~7~8~9~10~11~12~'
    $outputs = Child $radio 'OutputChannelsArray'
    if ($outputs.Children.Count -ne 12) { throw 'Expected 12 software-radio channels.' }
    return $outputs
}
function Validate-EditableChannel($Node, [int]$Channel) {
    # Refuse user-added mixes/curves/reversals instead of silently erasing them.
    $keys = @('Expo', 'ExpoLowRates', 'InputFeedsArray', 'LowRates', 'Trim')
    if ($Node.Values.Count -ne 5 -or @($Node.Values.Keys | Where-Object { $_ -notin $keys }).Count) { throw "Custom fields in CH$Channel." }
    if ((Number $Node 'Expo') -ne 0 -or (Number $Node 'ExpoLowRates') -ne 0 -or (Number $Node 'LowRates') -notin @(0, 1) -or (Number $Node 'Trim') -notin @(0, 1)) { throw "Custom rate/trim settings in CH$Channel." }
    if ($Node.Children.Count -ne 3) { throw "Custom groups in CH$Channel." }
    foreach ($name in @('ExpoWhen', 'LowRatesActivatedWhen')) {
        $condition = Child $Node $name
        if ($condition.Values.Count -ne 4 -or $condition.Children.Count -ne 0) { throw "Custom condition in CH$Channel." }
        if ((Number $condition 'Value1') -ne 0 -or (Number $condition 'Value2') -ne 0) { throw "Custom condition in CH$Channel." }
        Expect $condition 'WhenInput' 'INT:100'
        Expect $condition 'WhenLogic' 'INT:0'
    }
    $feeds = Child $Node 'InputFeedsArray'
    if ($feeds.Values.Count) { throw "Custom feed metadata in CH$Channel." }
    if ($feeds.Children.Count -eq 0) { Expect $Node 'InputFeedsArray' 'INTARRAY:'; return }
    Expect $Node 'InputFeedsArray' 'INTARRAY:1~'
    if ($feeds.Children.Count -ne 1) { throw "Custom mixed inputs in CH$Channel." }
    $feed = Child $feeds '#1'
    if ($feed.Values.Count -ne 8 -or $feed.Children.Count -ne 1) { throw "Custom input in CH$Channel." }
    Expect $feed 'InputChannel' "INT:$($Channel + 99)"
    Expect $feed 'InputFeedType' 'INT:1'
    Expect $feed 'CurveInputValues' 'FLOATARRAY:'
    Expect $feed 'CurveOutputValues' 'FLOATARRAY:'
    Expect $feed 'Logic' 'INT:0'
    Expect $feed 'SimpleReversed' 'BOOL:No'
    if (-not $feed.Values.ContainsKey('InputName') -or (Number $feed 'SimpleMaxPercent') -ne 1) { throw "Custom gain in CH$Channel." }
    $when = Child $feed 'InputActivatedWhen'
    if ($when.Values.Count -ne 4 -or $when.Children.Count) { throw "Custom input condition in CH$Channel." }
    Expect $when 'WhenInput' 'INT:100'
    Expect $when 'WhenLogic' 'INT:1'
    if ((Number $when 'Value1') -ne 0 -or (Number $when 'Value2') -ne 0) { throw "Custom activation in CH$Channel." }
}
function New-ChannelText([int]$Channel, [string]$Eol) {
    $lines = @(
        "      SUBGROUP[#$Channel]", '         Expo=FLOAT:0.', '         ExpoLowRates=FLOAT:0.',
        '         InputFeedsArray=INTARRAY:1~', '         LowRates=FLOAT:1.', '         Trim=FLOAT:0.', '',
        '         SUBGROUP[ExpoWhen]', '            Value1=FLOAT:0.', '            Value2=FLOAT:0.',
        '            WhenInput=INT:100', '            WhenLogic=INT:0', '         ENDGROUP[ExpoWhen]', '',
        '         SUBGROUP[LowRatesActivatedWhen]', '            Value1=FLOAT:0.', '            Value2=FLOAT:0.',
        '            WhenInput=INT:100', '            WhenLogic=INT:0', '         ENDGROUP[LowRatesActivatedWhen]', '',
        '         SUBGROUP[InputFeedsArray]', '            SUBGROUP[#1]',
        '               CurveInputValues=FLOATARRAY:', '               CurveOutputValues=FLOATARRAY:',
        "               InputChannel=INT:$($Channel + 99)", '               InputFeedType=INT:1',
        '               InputName=STRING:Input', '               Logic=INT:0',
        '               SimpleMaxPercent=FLOAT:1.', '               SimpleReversed=BOOL:No', '',
        '               SUBGROUP[InputActivatedWhen]', '                  Value1=FLOAT:0.', '                  Value2=FLOAT:0.',
        '                  WhenInput=INT:100', '                  WhenLogic=INT:1', '               ENDGROUP[InputActivatedWhen]',
        '            ENDGROUP[#1]', '         ENDGROUP[InputFeedsArray]', "      ENDGROUP[#$Channel]", ''
    )
    return $lines -join $Eol
}
function Patched-Text([string]$Text) {
    $tree = Parse-Rf $Text
    $outputs = Validate-Wiring $tree
    $eol = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $edits = @()
    foreach ($ch in 8..12) {
        $node = Child $outputs "#$ch"
        Validate-EditableChannel $node $ch
        $edits += [pscustomobject]@{ Start = $node.Start; Length = $node.End - $node.Start; Text = (New-ChannelText $ch $eol) }
    }
    foreach ($edit in ($edits | Sort-Object Start -Descending)) {
        $Text = $Text.Remove($edit.Start, $edit.Length).Insert($edit.Start, $edit.Text)
    }
    $check = Validate-Wiring (Parse-Rf $Text)
    foreach ($ch in 8..12) {
        $node = Child $check "#$ch"
        Validate-EditableChannel $node $ch
        if ((Number $node 'Trim') -ne 0 -or (Number $node 'LowRates') -ne 1) { throw 'Post-patch verification failed.' }
        Expect $node 'InputFeedsArray' 'INTARRAY:1~'
    }
    return $Text
}
function Save-Json($Object, [string]$Path) {
    [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

try {
    if (-not $RealFlightRoot -and $Interactive) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $candidates = @(foreach ($leaf in @('RealFlight 9', 'RealFlight 9.5', 'RealFlight 9.5S', 'RealFlight Evolution')) {
            $p = Join-Path $docs $leaf
            if (Test-Path -LiteralPath (Join-Path $p 'Vehicles\CustomVehicles') -PathType Container) { $p }
        })
        Write-Host 'Select the USER DATA folder for your 9.5/9.5S or Evolution installation (not the Steam folder).'
        for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host "[$($i + 1)] $($candidates[$i])" }
        $choice = Read-Host 'Enter a listed number OR the full folder path; blank cancels'
        if (-not $choice) { throw 'Cancelled.' }
        $index = 0
        if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $candidates.Count) { $RealFlightRoot = $candidates[$index - 1] }
        else { $RealFlightRoot = $choice.Trim('"') }
    }
    if (-not $RealFlightRoot) { throw 'Specify -RealFlightRoot with the exact RealFlight user data folder, or use -Interactive.' }
    $rfRoot = (Resolve-Path -LiteralPath $RealFlightRoot).ProviderPath.TrimEnd('\')
    if ([IO.Path]::GetFileName($rfRoot) -match '(?i)RealFlight[ -]?X$') { throw 'RealFlight-X is not supported.' }
    $vehicles = Join-Path $rfRoot 'Vehicles'
    $custom = Join-Path $vehicles 'CustomVehicles'
    foreach ($p in @($rfRoot, $vehicles, $custom)) { Assert-NoLink $p }
    Write-Host "Target USER DATA: $rfRoot"
    Write-Host 'Exact product version must be confirmed in RealFlight About; folder names alone are not proof.'
    $backupBase = Join-Path $rfRoot 'MFE-Signal-Backups'
    if (Test-Path -LiteralPath $backupBase) { Assert-NoLink $backupBase }

    if ($RestoreManifest) {
        Assert-Closed
        $manifestPath = (Resolve-Path -LiteralPath $RestoreManifest).ProviderPath
        $backupDir = Split-Path -Parent $manifestPath
        if ((Split-Path -Parent $backupDir) -ine $backupBase -or [IO.Path]::GetFileName($manifestPath) -cne 'manifest.json') { throw 'Restore manifest must be under the selected root\MFE-Signal-Backups\<run>\manifest.json.' }
        Assert-NoLink $backupDir
        Assert-NoLink $manifestPath
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.Package -cne 'MFE-FlightAxis-Signal-Patch-v1.0.0' -or $manifest.Root -ine $rfRoot) { throw 'Manifest package/root mismatch.' }
        $restoreItems = @()
        $seen = @{}
        foreach ($entry in $manifest.Files) {
            if ($entry.File -cnotin $Names.Values -or $seen.ContainsKey($entry.File)) { throw 'Unknown or duplicate restore target.' }
            $seen[$entry.File] = $true
            $target = Join-Path $custom $entry.File
            $backup = Join-Path $backupDir $entry.File
            Assert-NoLink $target
            Assert-NoLink $backup
            $original = [IO.File]::ReadAllBytes($backup)
            $current = [IO.File]::ReadAllBytes($target)
            if ((Hash-Bytes $original) -cne $entry.BeforeSha256 -or (Hash-Bytes $current) -cne $entry.AfterSha256) { throw "Restore refused: backup damaged or vehicle changed after patch: $($entry.File). Keep both files and review manually." }
            $restoreItems += [pscustomobject]@{ Path = $target; Original = $original; Current = $current }
        }
        if (-not $restoreItems.Count) { throw 'Empty restore manifest.' }
        Assert-Closed
        $written = @()
        try {
            foreach ($item in $restoreItems) {
                $written += $item
                [IO.File]::WriteAllBytes($item.Path, $item.Original)
                if ((Hash-Bytes ([IO.File]::ReadAllBytes($item.Path))) -cne (Hash-Bytes $item.Original)) { throw 'Restore readback mismatch.' }
            }
        } catch {
            foreach ($item in $written) { [IO.File]::WriteAllBytes($item.Path, $item.Current) }
            throw
        }
        Write-Host 'RESTORED RF model files. Backups retained. ArduPilot parameters were NOT restored; use your saved .param export.'
        exit 0
    }

    if ($Apply) { Assert-Closed }
    $plans = @()
    foreach ($key in $Names.Keys) {
        if ($Model -ne 'All' -and $Model -ne $key) { continue }
        $path = Join-Path $custom $Names[$key]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            if ($Model -ne 'All') { throw "Model not imported or renamed: $path" }
            Write-Host "SKIP (not installed): $key"
            continue
        }
        Assert-NoLink $path
        $before = [IO.File]::ReadAllBytes($path)
        $after = $ByteEncoding.GetBytes((Patched-Text ($ByteEncoding.GetString($before))))
        $oldHash = Hash-Bytes $before
        $newHash = Hash-Bytes $after
        $plans += [pscustomobject]@{ Model = $key; File = $Names[$key]; Path = $path; Before = $before; After = $after; BeforeSha256 = $oldHash; AfterSha256 = $newHash }
        $status = if ($oldHash -ceq $newHash) { 'ALREADY PATCHED' } else { 'RF CH8-12 patch planned' }
        Write-Host "$key : compatible motor wiring; $status"
    }
    if (-not $plans.Count) { throw 'No supported imported .rfvehicle found. Import the original RFX first; model must load without asset errors.' }
    Write-Host 'Required SITL overlay: SERVO9_FUNCTION=33, SERVO10_FUNCTION=34, SERVO11_FUNCTION=36, SERVO12_FUNCTION=35.'
    Write-Host 'Requires Q_FRAME_CLASS=1 and Q_FRAME_TYPE=1. Live SITL parameters are NOT checked or written.'
    if (-not $Apply) { Write-Host 'CHECK ONLY: no files changed. No claim of flight readiness.'; exit 0 }
    $changed = @($plans | Where-Object { $_.BeforeSha256 -cne $_.AfterSha256 })
    if (-not $changed.Count) { Write-Host 'No RF changes needed. Still verify the separate ArduPilot overlay and RC inputs.'; exit 0 }
    if ($Interactive) {
        $answer = Read-Host 'Type APPLY to back up and patch these installed RF model files; anything else cancels'
        if ($answer -cne 'APPLY') { throw 'Cancelled before writes.' }
    }
    Assert-Closed
    foreach ($p in $changed) {
        if ((Hash-Bytes ([IO.File]::ReadAllBytes($p.Path))) -cne $p.BeforeSha256) { throw "File changed during preflight: $($p.Path)" }
    }
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $backupDir = Join-Path $backupBase $stamp
    [void][IO.Directory]::CreateDirectory($backupDir)
    $manifestPath = Join-Path $backupDir 'manifest.json'
    $manifest = [ordered]@{
        Package = 'MFE-FlightAxis-Signal-Patch-v1.0.0'; Root = $rfRoot; State = 'BackedUp'
        SourceCommit = 'e93e185d4e22df48d6791fe45103b593f168946a'; CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Files = @($changed | Select-Object Model, File, BeforeSha256, AfterSha256)
    }
    foreach ($p in $changed) {
        $dest = Join-Path $backupDir $p.File
        [IO.File]::WriteAllBytes($dest, $p.Before)
        if ((Hash-Bytes ([IO.File]::ReadAllBytes($dest))) -cne $p.BeforeSha256) { throw "Backup verification failed: $dest" }
    }
    Save-Json $manifest $manifestPath
    $written = @()
    try {
        Assert-Closed
        foreach ($p in $changed) {
            $written += $p
            [IO.File]::WriteAllBytes($p.Path, $p.After)
            if ((Hash-Bytes ([IO.File]::ReadAllBytes($p.Path))) -cne $p.AfterSha256) { throw "Write verification failed: $($p.File)" }
        }
        $manifest.State = 'Applied'
        Save-Json $manifest $manifestPath
    } catch {
        foreach ($p in $written) { [IO.File]::WriteAllBytes($p.Path, $p.Before) }
        $manifest.State = 'RolledBack'
        Save-Json $manifest $manifestPath
        throw
    }
    Write-Host 'RF SIGNAL PATCH APPLIED AND FILE HASHES VERIFIED. This is NOT a flight test.'
    Write-Host "Backup/restore manifest: $manifestPath"
    Write-Host 'NEXT: manually back up SITL parameters, apply the 4-line .param overlay, restart SITL, verify while DISARMED.'
    exit 0
} catch {
    [Console]::Error.WriteLine('STOP: ' + $_.Exception.Message)
    [Console]::Error.WriteLine('Do not apply the parameter overlay after a failed RF compatibility check. See README_FIRST_KO.md.')
    exit 1
}
