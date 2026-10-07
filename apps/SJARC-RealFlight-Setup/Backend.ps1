#requires -Version 5.1
param([string]$RequestFile, [switch]$LibraryOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'SignalCore.ps1')
. (Join-Path $PSScriptRoot 'Troubleshoot.ps1')
. (Join-Path $PSScriptRoot 'SitlParams.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'models.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Utf8 = [Text.UTF8Encoding]::new($false)
$Version = '0.2.2'
# Absolute root baked into all four PR 158 archives by the vendor's RealFlight 8 PC.
$VendorPrefix = 'C:\Users\Administrator\Documents\RealFlight 8\'
# RF 8/9 store the FlightAxis switch as FlightAxisLinkEnabled; Evolution as RealFlightLinkEnabled. Whichever exists is set.
$LinkKeys = @('FlightAxisLinkEnabled','RealFlightLinkEnabled')
$IniKeys = @(@('FlightAxisLinkEnabled','BOOL:Yes'), @('RealFlightLinkEnabled','BOOL:Yes'), @('PauseSimWhenFocusLost','BOOL:No'), @('PauseSimWhileInMenus','BOOL:No'), @('PhysicsResetDelay2','FLOAT:2.'))

function Full([string]$p) { return [IO.Path]::GetFullPath($p).TrimEnd('\') }
function Inside([string]$base, [string]$relative) {
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe relative path.' }
    $p = Full (Join-Path $base $relative)
    if (-not $p.StartsWith((Full $base) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped its root.' }
    return $p
}
function No-Links([string]$p) {
    $p = Full $p
    while ($p) {
        if (Test-Path -LiteralPath $p) { Assert-NoLink $p }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ($parent -eq $p) { break }
        $p = $parent
    }
}
function Clean-Location([string]$p) {
    # Registry and Steam entries can be quoted, stale or point at unplugged drives; never let one abort discovery.
    if (-not $p) { return '' }
    $p = $p.Trim().Trim('"').Trim()
    if (-not $p) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return '' }
}
function Executable([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'RealFlight executable not found.' }
    $path = Full $path
    $leaf = [IO.Path]::GetFileName($path)
    if ($leaf -notin @('RealFlight.exe', 'RealFlight64.exe')) { throw 'Select RealFlight.exe or RealFlight64.exe, not the launcher.' }
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    if ($v.ProductName -notmatch 'RealFlight' -or $path -match '(?i)Trainer|RealFlight[- _]X([\\/]|$)' -or $v.FileMajorPart -lt 8) { throw 'Supported target: full RealFlight 8/9.5/9.5S/Evolution. Trainer and RealFlight-X are excluded.' }
    if ($v.FileMajorPart -gt 10) { throw 'Unreviewed future RealFlight version. Inspect before supporting it.' }
    $edition = if ($path -match '(?i)Evolution' -or $v.FileMajorPart -eq 10) { 'Evolution' } elseif ($v.FileMajorPart -eq 8) { '8' } else { '9 / 9.5 / 9.5S' }
    return [pscustomobject]@{ Path = $path; Version = $v.FileVersion; Major = $v.FileMajorPart; Edition = $edition; Label = "RealFlight $edition ($($v.FileVersion))" }
}
function Find-Installations($locations) {
    $found = @(); $seen = @{}
    foreach ($location in $locations) {
        $dir = Clean-Location $location
        if (-not $dir) { continue }
        foreach ($name in @('RealFlight64.exe','RealFlight.exe')) {
            try {
                $path = [IO.Path]::Combine($dir, $name)
                if ([IO.File]::Exists($path)) { $item = Executable $path; if (-not $seen.ContainsKey($item.Path)) { $found += $item; $seen[$item.Path] = $true } }
            } catch { }
        }
    }
    return $found | Sort-Object Edition,Path
}
function Detect {
    $locations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $steamRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($base in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        [void]$steamRoots.Add([IO.Path]::Combine($base, 'Steam'))
        foreach ($name in @('RealFlight8','RealFlight 8','RealFlight9','RealFlight 9','RealFlight9.5','RealFlight 9.5','RealFlight 9.5S','RealFlight Evolution')) { [void]$locations.Add([IO.Path]::Combine($base, $name)) }
    }
    foreach ($hive in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $hive)) { continue }
        foreach ($key in Get-ChildItem $hive -ErrorAction SilentlyContinue) {
            $entry = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($entry -and $entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -match 'RealFlight' -and $entry.PSObject.Properties['InstallLocation']) {
                $location = Clean-Location ([string]$entry.InstallLocation)
                if ($location) { [void]$locations.Add($location) }
            }
        }
    }
    if (Test-Path 'HKCU:\Software\Valve\Steam') {
        $steam = Get-ItemProperty 'HKCU:\Software\Valve\Steam'
        if ($steam.PSObject.Properties['SteamPath']) { $location = Clean-Location ([string]$steam.SteamPath).Replace('/','\'); if ($location) { [void]$steamRoots.Add($location) } }
    }
    foreach ($steam in @($steamRoots)) {
        try {
            $vdf = [IO.Path]::Combine($steam, 'steamapps\libraryfolders.vdf')
            if ([IO.File]::Exists($vdf)) {
                foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $location = Clean-Location $m.Groups[1].Value.Replace('\\','\'); if ($location) { [void]$steamRoots.Add($location) } }
            }
        } catch { }
    }
    foreach ($steam in @($steamRoots)) {
        try {
            $common = [IO.Path]::Combine($steam, 'steamapps\common')
            if ([IO.Directory]::Exists($common)) { foreach ($dir in [IO.Directory]::GetDirectories($common, 'RealFlight*')) { [void]$locations.Add($dir) } }
        } catch { }
    }
    $found = @(Find-Installations $locations)
    $roots = @(); $docs = [Environment]::GetFolderPath('MyDocuments')
    foreach ($name in @('RealFlight 8','RealFlight 9','RealFlight 9.5','RealFlight 9.5S','RealFlight Evolution')) {
        $p = [IO.Path]::Combine($docs, $name)
        if ([IO.File]::Exists([IO.Path]::Combine($p, 'RealFlight.ini')) -or [IO.File]::Exists([IO.Path]::Combine($p, 'RealFlight64.ini'))) { $roots += $p }
    }
    return @{ Success = $true; Installations = @($found); Roots = @($roots); Models = @($Catalog | Select-Object Key,Title,Vehicle) }
}
function Root-Info([string]$root, $exe) {
    $root = Full $root
    No-Links $root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Run RealFlight once, exit it, then select its Documents user-data folder.' }
    $ini = @('RealFlight64.ini','RealFlight.ini' | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf })
    # A folder used by both 32- and 64-bit builds keeps two INIs; edit the one belonging to the selected executable.
    if ($ini.Count -eq 2 -and $exe) { $ini = @($ini | Where-Object { $_ -ieq ([IO.Path]::GetFileNameWithoutExtension($exe.Path) + '.ini') }) }
    if ($ini.Count -ne 1) { throw 'Select the exact USER DATA folder containing RealFlight.ini or RealFlight64.ini, not its program folder.' }
    if ([IO.Path]::GetFileName($root) -match '(?i)Trainer|RealFlight[- _]X$') { throw 'Unsupported RealFlight edition.' }
    return @{ Root = $root; Ini = $ini[0] }
}
function Assert-EditionMatch($exe, [string]$root) {
    $leaf = [IO.Path]::GetFileName($root)
    $known = @('RealFlight 8','RealFlight 9','RealFlight 9.5','RealFlight 9.5S','RealFlight Evolution')
    $expected = switch ($exe.Edition) {
        'Evolution' { @('RealFlight Evolution') }
        '8' { @('RealFlight 8') }
        '9 / 9.5 / 9.5S' { @('RealFlight 9','RealFlight 9.5','RealFlight 9.5S') }
        default { throw 'Unknown executable edition.' }
    }
    if ($leaf -in $known -and $leaf -notin @($expected)) {
        throw "Executable edition and user-data folder do not match. Selected: $($exe.Label); folder: $root"
    }
}
function Get-Models($keys) {
    $result = @()
    foreach ($key in $keys) {
        $m = @($Catalog | Where-Object Key -CEQ $key)
        if ($m.Count -ne 1) { throw "Unknown model: $key" }
        if (@($result | Where-Object Key -CEQ $key).Count) { throw 'Duplicate model selection.' }
        $result += $m[0]
    }
    if (-not $result.Count) { throw 'Select at least one model.' }
    return $result
}
function Assets-Root([string]$root, [string]$base) {
    if (-not $base) { $base = Join-Path $env:PUBLIC 'Documents\SJARC\RF' }
    $id = (Hash-Bytes ($Utf8.GetBytes((Full $root).ToLowerInvariant()))).Substring(0,8)
    $p = Join-Path (Full $base) $id
    if ($p -match '[^\x20-\x7e]' -or $p.Length -gt 65) { throw 'Shared asset path must be short ASCII (normally Public\Documents\SJARC\RF). Non-ASCII KEX paths are not safe.' }
    No-Links $p
    return $p
}
function Read-Text([string]$p) { return $ByteEncoding.GetString([IO.File]::ReadAllBytes($p)) }
function Set-Key([string]$text, [string]$key, [string]$value) {
    $re = [regex]::new('(?m)^' + [regex]::Escape($key) + '=[^\r\n]*')
    if ($re.Matches($text).Count -ne 1) { throw "Missing/duplicate key: $key" }
    return $re.Replace($text, [Text.RegularExpressions.MatchEvaluator]{ param($m) return "$key=$value" })
}
function Key-Value([string]$text, [string]$key) {
    $found = [regex]::Matches($text, '(?m)^' + [regex]::Escape($key) + '=([^\r\n]*)')
    if ($found.Count -ne 1) { throw "Missing/duplicate key: $key" }
    return $found[0].Groups[1].Value
}
function Try-KeyValue([string]$text, [string]$key) {
    $found = [regex]::Matches($text, '(?m)^' + [regex]::Escape($key) + '=([^\r\n]*)')
    if ($found.Count -ne 1) { return $null }
    return $found[0].Groups[1].Value
}
function Path-Value($typed) { if ($null -eq $typed) { return '' }; return ([string]$typed -replace '^STRING:', '') }
function Is-Ascii([string]$p) { return ($p -notmatch '[^\x20-\x7e]') }
function Path-Exists([string]$carrier) {
    # Values are held as Latin-1 byte carriers. Evolution stores non-ASCII paths as UTF-8; older builds may use ANSI.
    $bytes = $ByteEncoding.GetBytes($carrier)
    foreach ($encoding in @($Utf8, [Text.Encoding]::Default)) { if ([IO.File]::Exists($encoding.GetString($bytes))) { return $true } }
    return $false
}
function Flat-Tga([int]$width, [int]$height, [byte]$r, [byte]$g, [byte]$b) {
    if ($width -lt 1 -or $height -lt 1 -or $width -gt 8192 -or $height -gt 8192) { throw 'Invalid texture dimensions.' }
    $bytes = New-Object byte[] (18 + $width * $height * 4)
    $bytes[2] = 2; $bytes[12] = $width -band 255; $bytes[13] = $width -shr 8
    $bytes[14] = $height -band 255; $bytes[15] = $height -shr 8; $bytes[16] = 32; $bytes[17] = 8
    $row = New-Object byte[] ($width*4)
    for ($n = 0; $n -lt $row.Length; $n += 4) { $row[$n] = $b; $row[$n+1] = $g; $row[$n+2] = $r; $row[$n+3] = 255 }
    for ($y = 0; $y -lt $height; $y++) { [Array]::Copy($row,0,$bytes,18+$y*$row.Length,$row.Length) }
    return ,$bytes
}
function Brake([string]$text) {
    $tree = Parse-Rf $text
    $props = @(Walk (Child $tree 'RootComponent') | Where-Object { $_.Values['ComponentType'] -ceq 'STRING:PropellerComponent' -and $_.Values['EngineTorusFrame'] -ceq 'STRING:~CS_ENGINE_P' })
    if ($props.Count -ne 1) { throw 'Forward propeller was not identified.' }
    $n = $props[0]
    $part = $text.Substring($n.Start, $n.End - $n.Start)
    $part = [regex]::Replace($part, '(?m)^(\s*HasSpeedControlBrake=BOOL:)(No|Yes)(\r?)$', '${1}Yes${3}')
    return $text.Remove($n.Start, $n.End - $n.Start).Insert($n.Start, $part)
}
function Retry-IO([scriptblock]$action) {
    # Real-time antivirus/indexer scans briefly hold freshly written files ("Unable to remove the file to be replaced").
    # A failed Replace/Move/Copy leaves both files as they were, so retrying is safe.
    for ($attempt = 1; ; $attempt++) {
        try { & $action; return } catch { if ($attempt -ge 8) { throw }; Start-Sleep -Milliseconds (150 * $attempt) }
    }
}
function Atomic-Write([string]$path, [byte[]]$bytes) {
    No-Links $path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    $stamp = [Guid]::NewGuid().ToString('N')
    $temp = $path + '.sjarc-' + $stamp + '.tmp'
    # With a backup name, a failed ReplaceFile never deletes the original (without one, ERROR_UNABLE_TO_MOVE_REPLACEMENT can).
    $old = $path + '.sjarc-' + $stamp + '.old'
    try {
        [IO.File]::WriteAllBytes($temp, $bytes)
        Retry-IO { if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, $old) } else { [IO.File]::Move($temp, $path) } }
    } catch {
        if (-not [IO.File]::Exists($path) -and [IO.File]::Exists($old)) { [IO.File]::Move($old, $path) }
        throw
    } finally {
        foreach ($leftover in @($temp, $old)) { if ([IO.File]::Exists($leftover)) { try { Retry-IO { [IO.File]::Delete($leftover) } } catch { } } }
    }
}
function Download-Pinned($m, [string]$cache, [string]$sourceFolder) {
    [void][IO.Directory]::CreateDirectory($cache)
    $origins = @(); $notes = @()
    foreach ($spec in @(@{Name=$m.Rfx; Hash=$m.RfxSha256}, @{Name=$m.Param; Hash=$m.ParamSha256})) {
        $dest = Inside $cache ($m.Key + '-' + $spec.Name)
        No-Links $dest
        if ([IO.File]::Exists($dest)) {
            if ((Hash-Bytes ([IO.File]::ReadAllBytes($dest))) -ceq $spec.Hash) { $origins += 'cache'; continue }
            # A damaged cache entry is kept for inspection and replaced by a freshly verified copy.
            $quarantine = Inside $cache ('quarantine\' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '-' + $m.Key + '-' + $spec.Name)
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($quarantine))
            Retry-IO { [IO.File]::Move($dest, $quarantine) }
            $notes += "Damaged cached source moved aside: $quarantine"
        }
        $data = $null
        if ($sourceFolder) {
            $local = ''
            try { $local = [IO.Path]::Combine($sourceFolder, $spec.Name) } catch { $local = '' }
            if ($local -and [IO.File]::Exists($local)) {
                $bytes = [IO.File]::ReadAllBytes($local)
                if ((Hash-Bytes $bytes) -ceq $spec.Hash) { $data = $bytes; $origins += 'local' }
                else { $notes += "Ignored local file with a different hash: $local" }
            }
        }
        if ($null -eq $data) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $client = [Net.WebClient]::new()
            $client.Headers.Add('User-Agent', "SJARC-RealFlight-Setup/$Version")
            try { $data = $client.DownloadData($m.BaseUrl + [Uri]::EscapeDataString($spec.Name)) } finally { $client.Dispose() }
            if ((Hash-Bytes $data) -cne $spec.Hash) { throw "Downloaded source hash mismatch: $($spec.Name)" }
            $origins += 'download'
        }
        Atomic-Write $dest $data
    }
    return @{ Rfx = (Inside $cache ($m.Key + '-' + $m.Rfx)); Param = (Inside $cache ($m.Key + '-' + $m.Param)); Origins = $origins; Notes = $notes }
}
function Archive-Data([string]$path, $m) {
    $zip = [IO.Compression.ZipFile]::OpenRead($path); $files = @{}
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '[\\/]' -or $entry.FullName -in @('.','..') -or $entry.Length -gt 90000000 -or $files.ContainsKey($entry.FullName)) { throw 'Unexpected archive entry.' }
            $spec = @($m.Entries | Where-Object Name -CEQ $entry.FullName)
            if ($spec.Count -ne 1) { throw 'Archive entry is not in the pinned allowlist.' }
            $stream = $entry.Open(); $mem = [IO.MemoryStream]::new()
            try { $stream.CopyTo($mem); $data = $mem.ToArray() } finally { $stream.Dispose(); $mem.Dispose() }
            if ((Hash-Bytes $data) -cne $spec[0].Sha256) { throw 'Archive entry hash mismatch.' }
            $files[$entry.FullName] = $data
        }
        if ($files.Count -ne $m.Entries.Count) { throw 'Archive is incomplete.' }
    } finally { $zip.Dispose() }
    return $files
}
function Add-Plan($plans, [string]$kind, [string]$relative, [byte[]]$bytes) {
    $plans.Add([pscustomobject]@{ Kind=$kind; Relative=$relative; Data=$bytes })
}
function Find-ImportedKex($m, [string]$root, [string]$assets, [string]$vendorDir) {
    # RealFlight converts the KEX on Import (Evolution adds 4 bytes per material) but leaves the vendor texture path inside.
    # Its converted copy is what RealFlight loads at runtime, so it is preferred over the vendor archive's RF 8 copy.
    $models = Inside $root 'Vehicles\CustomModels'
    if (-not [IO.Directory]::Exists($models)) { return '' }
    $found = @([IO.Directory]::GetFiles($models, $m.Kex, [IO.SearchOption]::AllDirectories) | Where-Object { -not $_.StartsWith($assets + '\', [StringComparison]::OrdinalIgnoreCase) })
    $preferred = @($found | Where-Object { [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($_)) -ieq $vendorDir })
    if ($preferred.Count) { return $preferred[0] }
    if ($found.Count) { return $found[0] }
    return ''
}
function Plan-Assets($m, $files, [string]$root, [string]$assets, $plans) {
    # Short ASCII copies: RealFlight cannot load KEX textures from non-ASCII (e.g. Korean profile) paths.
    $folder = [IO.Path]::Combine($assets, $m.Key)
    $stem = [IO.Path]::GetFileNameWithoutExtension($m.Texture)
    $shared = @{ Folder = $folder; Kex = [IO.Path]::Combine($folder, $m.Kex); Tga = [IO.Path]::Combine($folder, $m.Texture)
                 Dds = [IO.Path]::Combine($folder, $stem + '.dds'); Normal = [IO.Path]::Combine($folder, $stem + '_n.tga'); Specular = [IO.Path]::Combine($folder, $stem + '_s.tga'); Origin = 'vendor archive' }
    $oldTexture = Path-Value (Key-Value ($ByteEncoding.GetString($files[$m.Color])) 'TGAFileName')
    if ($shared.Tga.Length -gt $oldTexture.Length) { throw 'KEX replacement path exceeds its fixed storage length.' }
    $kexText = $ByteEncoding.GetString($files[$m.Kex])
    $vendorKex = Path-Value (Key-Value ($ByteEncoding.GetString($files[$m.Bse])) 'XK_FileName')
    $imported = Find-ImportedKex $m $root $assets ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($vendorKex)))
    if ($imported) {
        No-Links $imported
        $importedText = Read-Text $imported
        if ($importedText.Contains($oldTexture)) { $kexText = $importedText; $shared.Origin = "RealFlight import ($imported)" }
    }
    if (-not $kexText.Contains($oldTexture)) { throw 'Pinned KEX texture path was not found.' }
    Add-Plan $plans 'Assets' ($m.Key + '\' + $m.Kex) ($ByteEncoding.GetBytes($kexText.Replace($oldTexture, $shared.Tga.PadRight($oldTexture.Length, [char]0))))
    $tga = $files[$m.Texture]
    Add-Plan $plans 'Assets' ($m.Key + '\' + $m.Texture) $tga
    $width = [int]$tga[12] + 256*[int]$tga[13]; $height = [int]$tga[14] + 256*[int]$tga[15]
    Add-Plan $plans 'Assets' ($m.Key + '\' + $stem + '_n.tga') (Flat-Tga $width $height 128 128 255)
    Add-Plan $plans 'Assets' ($m.Key + '\' + $stem + '_s.tga') (Flat-Tga $width $height 0 0 0)
    return $shared
}
function Add-AssetProblems([string]$bse, [string]$color, $problems) {
    # RealFlight re-roots every path on Import (Evolution writes C:\Users\<name>\Documents\...), so the
    # vendor prefix alone is not a reliable signal. Keep only references that are ASCII and present.
    if ($bse.Contains($VendorPrefix) -or $color.Contains($VendorPrefix)) { $problems.Add('vendor PC path') }
    $kex = Path-Value (Try-KeyValue $bse 'XK_FileName')
    if (-not $kex) { $problems.Add('XK_FileName missing') }
    elseif (-not (Is-Ascii $kex)) { $problems.Add('non-ASCII model path') }
    elseif (-not [IO.File]::Exists($kex)) { $problems.Add('model file missing') }
    elseif ((Read-Text $kex).Contains($VendorPrefix)) { $problems.Add('model file points at vendor texture') }
    foreach ($key in @('TGAFileName','NormalMap','SpecularMap')) {
        $p = Path-Value (Try-KeyValue $color $key)
        if (-not $p) { $problems.Add("$key missing") }
        elseif (-not (Is-Ascii $p)) { $problems.Add("non-ASCII $key") }
        elseif (-not [IO.File]::Exists($p)) { $problems.Add("$key file missing") }
    }
    $folder = Path-Value (Try-KeyValue $color 'TexturePath')
    if (-not $folder) { $problems.Add('TexturePath missing') }
    elseif (-not (Is-Ascii $folder)) { $problems.Add('non-ASCII TexturePath') }
    elseif (-not [IO.Directory]::Exists($folder)) { $problems.Add('TexturePath folder missing') }
}
function Carrier-Path([string]$path) {
    # RF 8/9 are ANSI programs, so their Import writes paths in the system code page; UTF-8 is used only for a path
    # that code page cannot hold. Returned as a Latin-1 byte carrier like every other edited text.
    foreach ($encoding in @([Text.Encoding]::Default, $Utf8)) {
        $bytes = $encoding.GetBytes($path)
        if ($encoding.GetString($bytes) -ceq $path) { return $ByteEncoding.GetString($bytes) }
    }
    throw "Path cannot be encoded for RealFlight: $path"
}
function Uses-SharedAssets([string]$text, [string]$sharedBase) {
    return $text.IndexOf($sharedBase + '\', [StringComparison]::OrdinalIgnoreCase) -ge 0
}
function Plan-ImportPaths($m, $files, [string]$root, [string]$assets, [string]$bse, [string]$color, $notes, $warnings) {
    # Undo the shared-asset path repair of v0.1.2/v0.1.3: point BSE and colorscheme back at the files RealFlight's own
    # Import left in Vehicles\CustomModels\<model>\ (the state Pioneer was flown in on RF 9.5).
    $vendorKex = Path-Value (Key-Value ($ByteEncoding.GetString($files[$m.Bse])) 'XK_FileName')
    $kex = Find-ImportedKex $m $root $assets ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($vendorKex)))
    if (-not $kex) {
        $warnings.Add("$($m.Title): still points at the shared asset copy (RF 9 crashed on FLY with it) and RealFlight's imported model file was not found. Re-import the original RFX (overwrite), close RF, then run step 3 again.")
        return $null
    }
    No-Links $kex
    $dir = [IO.Path]::GetDirectoryName($kex)
    $stem = [IO.Path]::GetFileNameWithoutExtension($m.Texture)
    $bse = Set-Key $bse 'XK_FileName' ('STRING:' + (Carrier-Path $kex))
    # Same values RealFlight writes on Import, including the _n/_s maps it references but never creates.
    foreach ($pair in @(@('TGAFileName', $m.Texture), @('DDSFileName', ($stem + '.dds')), @('NormalMap', ($stem + '_n.tga')), @('SpecularMap', ($stem + '_s.tga')))) {
        if ($null -ne (Try-KeyValue $color $pair[0])) { $color = Set-Key $color $pair[0] ('STRING:' + (Carrier-Path ([IO.Path]::Combine($dir, $pair[1])))) }
    }
    # RealFlight's Import names TexturePath after BaseVehicle (FIGHTERVTOL for folder fighterVTOL): same folder on NTFS.
    $texturePath = $dir
    $baseVehicle = Path-Value (Try-KeyValue $color 'BaseVehicle')
    if ($baseVehicle -and (Is-Ascii $baseVehicle) -and $baseVehicle.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0) {
        $candidate = [IO.Path]::Combine([IO.Path]::GetDirectoryName($dir), $baseVehicle)
        if ($candidate -ieq $dir) { $texturePath = $candidate }
    }
    if ($null -ne (Try-KeyValue $color 'TexturePath')) { $color = Set-Key $color 'TexturePath' ('STRING:' + (Carrier-Path $texturePath)) }
    if (-not [IO.File]::Exists([IO.Path]::Combine($dir, $m.Texture))) { $warnings.Add("$($m.Title): $($m.Texture) is missing next to the imported model; RealFlight may show it untextured.") }
    $notes.Add("$($m.Title): RF 8/9 - shared asset paths from v0.1.2/v0.1.3 (RF 9 FLY crash) replaced with RealFlight's import paths ($dir).")
    return @{ Bse = $bse; Color = $color }
}
function Plan-Installed($m, $files, [string]$root, [string]$assets, $plans, [bool]$brake, [bool]$repairPaths, [string]$edition, $notes, $warnings) {
    $vp = Inside $root ('Vehicles\CustomVehicles\' + $m.Vehicle)
    $v = Patched-Text (Read-Text $vp)
    if ($brake) { $v = Brake $v }
    $bsePath = Inside $root ('Vehicles\CustomModels\' + $m.Bse)
    $colorPath = Inside $root ('Vehicles\ColorSchemes\' + $m.Color)
    if (-not [IO.File]::Exists($bsePath) -or -not [IO.File]::Exists($colorPath)) { throw "Incomplete Import: $($m.Title) BSE/colorscheme missing." }
    No-Links $bsePath; No-Links $colorPath
    $bse = Read-Text $bsePath; $color = Read-Text $colorPath
    $folder = [IO.Path]::Combine($assets, $m.Key)
    if ($edition -cne 'Evolution') {
        # RF 8/9 load the paths their own Import wrote (the manufacturer built these models in RF 8). On 2026-09-29 the
        # shared-asset copies made RF 9.5 crash on FLY while the same model with import paths flew, so RF 8/9 are
        # always signals-only here and an earlier shared-asset repair is undone.
        $sharedBase = [IO.Path]::GetDirectoryName($assets)
        if ((Uses-SharedAssets $bse $sharedBase) -or (Uses-SharedAssets $color $sharedBase)) {
            $restored = Plan-ImportPaths $m $files $root $assets $bse $color $notes $warnings
            if ($restored) {
                Add-Plan $plans 'Root' ('Vehicles\CustomModels\' + $m.Bse) ($ByteEncoding.GetBytes($restored.Bse))
                Add-Plan $plans 'Root' ('Vehicles\ColorSchemes\' + $m.Color) ($ByteEncoding.GetBytes($restored.Color))
            }
        } else {
            $notes.Add("$($m.Title): RF 8/9 - model/texture paths left as RealFlight imported them (signals only).")
        }
        if (Uses-SharedAssets (Path-Value (Key-Value $v 'BasedOn')) $sharedBase) {
            $v = Set-Key $v 'BasedOn' (Key-Value ($ByteEncoding.GetString($files[$m.Vehicle])) 'BasedOn')
            $notes.Add("$($m.Title): BasedOn pointed at the shared asset folder; restored to the manufacturer value.")
        }
        Add-Plan $plans 'Root' ('Vehicles\CustomVehicles\' + $m.Vehicle) ($ByteEncoding.GetBytes($v))
        return
    }
    $problems = [Collections.Generic.List[string]]::new()
    Add-AssetProblems $bse $color $problems
    $usesShared = $bse.Contains($folder + '\') -or $color.Contains($folder + '\')
    if (-not $repairPaths) {
        $notes.Add("$($m.Title): path repair turned off; model/texture paths and BasedOn left as they are (signals only).")
    } elseif ($problems.Count -or $usesShared) {
        $shared = Plan-Assets $m $files $root $assets $plans
        $bse = Set-Key $bse 'XK_FileName' ('STRING:' + $shared.Kex)
        foreach ($pair in @(@('TGAFileName','Tga'), @('DDSFileName','Dds'), @('NormalMap','Normal'), @('SpecularMap','Specular'), @('TexturePath','Folder'))) {
            $color = Set-Key $color $pair[0] ('STRING:' + $shared[$pair[1]])
        }
        Add-Plan $plans 'Root' ('Vehicles\CustomModels\' + $m.Bse) ($ByteEncoding.GetBytes($bse))
        Add-Plan $plans 'Root' ('Vehicles\ColorSchemes\' + $m.Color) ($ByteEncoding.GetBytes($color))
        $why = if ($problems.Count) { " ($($problems -join '; '))" } else { '' }
        $notes.Add("$($m.Title): model/texture paths set to $folder$why; model file from $($shared.Origin).")
    } else {
        $notes.Add("$($m.Title): existing model/texture paths are ASCII and present; kept.")
    }
    # BasedOn may be a bare model name (RF 8 style) or an absolute path (Evolution style); only a dead path is replaced,
    # and with an ASCII copy of the base model so no non-ASCII bytes are ever written into the vehicle.
    $basedOn = Path-Value (Key-Value $v 'BasedOn')
    $deadBasedOn = $basedOn -match '[\\/:]' -and -not (Path-Exists $basedOn)
    if ($repairPaths -and ($deadBasedOn -or $basedOn.StartsWith($folder + '\', [StringComparison]::OrdinalIgnoreCase))) {
        $sharedBse = [IO.Path]::Combine($folder, $m.Bse)
        Add-Plan $plans 'Assets' ($m.Key + '\' + $m.Bse) ($ByteEncoding.GetBytes($bse))
        $v = Set-Key $v 'BasedOn' ('STRING:' + $sharedBse)
        if ($deadBasedOn) { $notes.Add("$($m.Title): BasedOn '$basedOn' did not exist; pointed to $sharedBse.") }
    }
    Add-Plan $plans 'Root' ('Vehicles\CustomVehicles\' + $m.Vehicle) ($ByteEncoding.GetBytes($v))
}
function Commit-Plan($plans, [string]$root, [string]$assets, [string]$phase) {
    Assert-Closed
    $items = @(); $seen = @{}
    foreach ($p in $plans) {
        $base = if ($p.Kind -ceq 'Root') { $root } elseif ($p.Kind -ceq 'Assets') { $assets } else { throw 'Unknown plan kind.' }
        $target = Inside $base $p.Relative
        No-Links $target
        if ($seen.ContainsKey($target)) { throw 'Duplicate file target.' }; $seen[$target] = $true
        # Plain assignment: an if-expression would unroll byte[] into Object[] (~57x memory) and turn 0-byte files into $null.
        $before = $null
        if ([IO.File]::Exists($target)) { $before = [IO.File]::ReadAllBytes($target) }
        $oldHash = if ($null -ne $before) { Hash-Bytes $before } else { '' }
        $newHash = Hash-Bytes $p.Data
        if ($oldHash -ceq $newHash) { continue }
        if ($null -ne $before -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReadOnly)) { throw "Read-only target: $target" }
        $items += [pscustomobject]@{ Target=$target; Kind=$p.Kind; Relative=$p.Relative; Before=$before; After=$p.Data; BeforeSha256=$oldHash; AfterSha256=$newHash; Backup=('{0:D4}.bin' -f $items.Count) }
    }
    if (-not $items.Count) { return @{ Changed=0; Manifest=''; State='Unchanged' } }
    $run = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $backup = Inside $root ('.SJARC\Backups\' + $run)
    No-Links $backup; [void][IO.Directory]::CreateDirectory($backup)
    foreach ($item in $items) {
        if ($null -ne $item.Before) {
            $dest = Inside $backup $item.Backup
            [IO.File]::WriteAllBytes($dest, $item.Before)
            if ((Hash-Bytes ([IO.File]::ReadAllBytes($dest))) -cne $item.BeforeSha256) { throw 'Backup readback failed.' }
        }
    }
    $manifest = [ordered]@{ Package='SJARC-RealFlight-Setup'; Version=$Version; Root=$root; Assets=$assets; Phase=$phase; State='BackedUp'; Entries=@($items | Select-Object Kind,Relative,Backup,BeforeSha256,AfterSha256) }
    $mp = Inside $backup 'manifest.json'; Save-Json $manifest $mp
    $written = @()
    try {
        Assert-Closed
        foreach ($item in $items) {
            $now = if ([IO.File]::Exists($item.Target)) { Hash-Bytes ([IO.File]::ReadAllBytes($item.Target)) } else { '' }
            if ($now -cne $item.BeforeSha256) { throw 'Target changed while preparing; refusing overwrite.' }
            Atomic-Write $item.Target $item.After; $written += $item
            if ((Hash-Bytes ([IO.File]::ReadAllBytes($item.Target))) -cne $item.AfterSha256) { throw 'File readback verification failed.' }
        }
        $manifest.State = 'Applied'; Save-Json $manifest $mp
    } catch {
        $failure = $_.Exception.Message; $rollbackErrors = @()
        foreach ($item in $written) {
            try {
                if ($null -ne $item.Before) { Atomic-Write $item.Target $item.Before }
                else { $quarantine = Inside $backup ('rolled-back\' + $item.Backup); [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($quarantine)); Retry-IO { [IO.File]::Move($item.Target, $quarantine) } }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        $manifest.State = if ($rollbackErrors.Count) { 'RollbackNeedsReview' } else { 'RolledBack' }; Save-Json $manifest $mp
        throw "$failure`nBackup: $mp`n$($rollbackErrors -join '; ')"
    }
    return @{ Changed=$items.Count; Manifest=$mp; State='Applied' }
}
function Controller-Warnings([string]$root, [string]$ini) {
    # Read-only: report when the controller profile RealFlight last used still shapes channels with the software
    # radio's dual rates/expo. Controller profiles are never edited by this tool.
    $out = @()
    try {
        $selected = Path-Value (Try-KeyValue $ini 'CurrentControllerSelection')
        if (-not $selected) { return $out }
        $section = [regex]::Match($ini, '(?ms)^\[Control\|[^\]\r\n]*\|' + [regex]::Escape($selected) + '\]\r?\n(.*?)(?=^\[|\z)')
        if (-not $section.Success) { return $out }
        $name = Path-Value (Try-KeyValue $section.Groups[1].Value 'ChannelMapName')
        if (-not $name -or -not (Is-Ascii $name) -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $out }
        $radioProfile = [IO.Path]::Combine($root, 'Radio Profiles', $name + '.radioprofile')
        if (-not [IO.File]::Exists($radioProfile)) { return $out }
        if ((Try-KeyValue (Read-Text $radioProfile) 'EnableSoftwareRadioDualRatesAndExpo') -ceq 'BOOL:Yes') {
            $out += "Controller profile '$name': Software Radio Dual Rates and Expo is on. Turn it off in RealFlight's controller settings (this tool does not edit controller profiles)."
        }
    } catch { }
    return $out
}
function Restore-IniKeys([string]$current, [string]$before) {
    # RealFlight rewrites its INI on exit. Undo only this tool's FlightAxis keys, and only if they still hold our values.
    foreach ($kv in $IniKeys) {
        $now = Try-KeyValue $current $kv[0]
        $old = Try-KeyValue $before $kv[0]
        if ($null -ne $now -and $null -ne $old -and $now -ceq $kv[1]) { $current = Set-Key $current $kv[0] $old }
    }
    return $current
}
function Restore-Run([string]$path, [string]$root, [string]$assets) {
    Assert-Closed; $path = Full $path
    $backup = [IO.Path]::GetDirectoryName($path)
    if ([IO.Path]::GetDirectoryName($backup) -ine (Inside $root '.SJARC\Backups') -or [IO.Path]::GetFileName($path) -cne 'manifest.json') { throw 'Select a manifest under this RF user-data .SJARC\Backups folder.' }
    No-Links $path
    $m = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.Package -cne 'SJARC-RealFlight-Setup' -or $m.Root -ine $root -or $m.Assets -ine $assets -or $m.State -cne 'Applied') { throw 'Restore manifest root/state mismatch.' }
    $items = @(); $seen = @{}; $notes = [Collections.Generic.List[string]]::new()
    foreach ($e in $m.Entries) {
        $base = if ($e.Kind -ceq 'Root') { $root } elseif ($e.Kind -ceq 'Assets') { $assets } else { throw 'Unknown restore kind.' }
        $target = Inside $base $e.Relative
        if ($e.Kind -ceq 'Root' -and $e.Relative -notmatch '^(RealFlight(64)?\.ini|RFX\\SJARC\\[^\\]+|\.SJARC\\Parameters\\[^\\]+|Vehicles\\(CustomVehicles|CustomModels|ColorSchemes)\\[^\\]+)$') { throw 'Restore target outside installer scope.' }
        if ($e.Kind -ceq 'Assets' -and $e.Relative -notmatch '^[A-Z]\\[^\\]+$') { throw 'Invalid shared asset target.' }
        if ($e.Backup -notmatch '^\d{4}\.bin$' -or $seen.ContainsKey($target)) { throw 'Invalid/duplicate backup entry.' }
        $seen[$target] = $true; No-Links $target
        if (-not [IO.File]::Exists($target)) { throw "File removed since setup; manual review required: $target" }
        if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReadOnly) { throw "Read-only restore target: $target" }
        $before = $null
        if ($e.BeforeSha256) {
            $bp = Inside $backup $e.Backup; No-Links $bp; $before = [IO.File]::ReadAllBytes($bp)
            if ((Hash-Bytes $before) -cne $e.BeforeSha256) { throw 'Damaged backup.' }
        }
        $restore = $before
        $current = [IO.File]::ReadAllBytes($target)
        if ((Hash-Bytes $current) -cne $e.AfterSha256) {
            if (-not ($e.Kind -ceq 'Root' -and $e.Relative -match '^RealFlight(64)?\.ini$' -and $null -ne $before)) { throw "File changed since setup; manual review required: $target" }
            $restore = $ByteEncoding.GetBytes((Restore-IniKeys ($ByteEncoding.GetString($current)) ($ByteEncoding.GetString($before))))
            $notes.Add('RealFlight rewrote its INI after setup; only the FlightAxis keys still holding this tool''s values were restored.')
        }
        $items += [pscustomobject]@{ Target=$target; Restore=$restore; Backup=$e.Backup }
    }
    if (-not $items.Count) { throw 'Empty restore manifest.' }
    # Refuse to move shared assets away while any model file would still reference that model's asset folder.
    $removedKeys = @($m.Entries | Where-Object { $_.Kind -ceq 'Assets' -and -not $_.BeforeSha256 } | ForEach-Object { ($_.Relative -split '\\')[0] } | Sort-Object -Unique)
    if ($removedKeys.Count) {
        $planned = @{}; foreach ($i in $items) { $planned[$i.Target] = $i }
        foreach ($sub in @('Vehicles\CustomVehicles','Vehicles\CustomModels','Vehicles\ColorSchemes')) {
            $dir = Inside $root $sub
            if (-not [IO.Directory]::Exists($dir)) { continue }
            foreach ($file in [IO.Directory]::GetFiles($dir)) {
                if ($file -notmatch '(?i)\.(rfvehicle|bse|colorscheme)$') { continue }
                $full = Full $file; $text = $null
                if ($planned.ContainsKey($full)) { if ($null -ne $planned[$full].Restore) { $text = $ByteEncoding.GetString($planned[$full].Restore) } }
                else { $text = Read-Text $full }
                if ($null -eq $text) { continue }
                foreach ($key in $removedKeys) {
                    if ($text.IndexOf(([IO.Path]::Combine($assets, $key) + '\'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "A model file would still use the shared $key assets after this restore: $full. Restore the later setup run first, or remove that model in RealFlight." }
                }
            }
        }
    }
    # Retain pre-restore bytes too. No model/asset is permanently deleted.
    $recovery = Inside $backup ('pre-restore-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($recovery)
    foreach ($i in $items) { $copy = Inside $recovery $i.Backup; Retry-IO { [IO.File]::Copy($i.Target, $copy) } }
    $written = @()
    try {
        Assert-Closed
        foreach ($i in $items) {
            $written += $i
            if ($null -eq $i.Restore) { $moved = Inside $recovery ($i.Backup + '.new-file'); Retry-IO { [IO.File]::Move($i.Target, $moved) } }
            else { Atomic-Write $i.Target $i.Restore }
        }
    } catch {
        $failure = $_.Exception.Message; $rollbackErrors = @()
        foreach ($i in $written) {
            try { Atomic-Write $i.Target ([IO.File]::ReadAllBytes((Inside $recovery $i.Backup))) } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) { $m.State = 'RestoreRollbackNeedsReview'; Save-Json $m $path }
        throw "$failure`nPre-restore copies: $recovery`n$($rollbackErrors -join '; ')"
    }
    $m.State = 'Restored'; Save-Json $m $path
    return @{ Success=$true; State='Restored'; Message='Installer-managed files restored; recovery copies retained. RF Import itself and ArduPilot parameters are not undone.'; Recovery=$recovery; Notes=@($notes) }
}
function Setup($request) {
    if ($request.Action -ceq 'Detect') { return Detect }
    if ($request.Action -ceq 'InspectExecutable') { return @{ Success=$true; Installation=(Executable $request.Executable) } }
    if ($request.Action -ceq 'Probe') {
        $ports = @()
        $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        foreach ($port in @(18083,5760)) {
            $open = @($listeners | Where-Object Port -EQ $port).Count -gt 0
            $ports += @{Port=$port; Open=$open}
        }
        return @{Success=$true; Ports=$ports; Message='Local TCP listener inventory only. No connection or packet sent; process identity, reachability, MAVLink and flight readiness are not checked.'}
    }
    # Connection troubleshooting (Troubleshoot.ps1): Diagnose only reads; every reset moves files aside and has a restore.
    if ($request.Action -ceq 'Status') { return Quick-Status $request }
    if ($request.Action -ceq 'StartSitl') { return Start-FlightAxisSitl $request }
    if ($request.Action -ceq 'Diagnose') { return Diagnose $request }
    if ($request.Action -ceq 'StopSitl') { return Stop-SitlProcesses $request }
    if ($request.Action -ceq 'ResetSitl') { return Reset-SitlStore $request }
    if ($request.Action -ceq 'RestoreSitl') { return Restore-SitlStore $request }
    if ($request.Action -ceq 'ResetRfIni') { return Reset-RfIni $request }
    if ($request.Action -ceq 'RestoreRfIni') { return Restore-RfIni $request }
    if ($request.Action -cnotin @('Prepare','Finalize','Restore')) { throw 'Unknown action.' }
    $exe = Executable $request.Executable
    $rootInfo = Root-Info $request.Root $exe; $root = $rootInfo.Root
    Assert-EditionMatch $exe $root
    $assetBase = if ($request.PSObject.Properties['AssetBase']) { $request.AssetBase } else { '' }
    $assets = Assets-Root $root $assetBase
    if ($request.Action -ceq 'Restore') { return Restore-Run $request.Manifest $root $assets }
    Assert-Closed
    $models = @(Get-Models @($request.Models))
    $plans = [Collections.Generic.List[object]]::new(); $statuses = @()
    $warnings = [Collections.Generic.List[string]]::new(); $notes = [Collections.Generic.List[string]]::new()
    $cache = Full $request.Cache
    No-Links $cache
    $source = if ($request.PSObject.Properties['SourceFolder'] -and $request.SourceFolder) { [string]$request.SourceFolder } else { '' }
    $brake = [bool]$request.Brake
    $repairPaths = if ($request.PSObject.Properties['RepairPaths']) { [bool]$request.RepairPaths } else { $true }
    # Preflight every existing model before downloads or application writes.
    foreach ($m in $models) {
        $vp = Inside $root ('Vehicles\CustomVehicles\' + $m.Vehicle)
        if ([IO.File]::Exists($vp)) { No-Links $vp; [void](Patched-Text (Read-Text $vp)) }
        elseif ($request.Action -ceq 'Finalize') { throw "Import missing model first: $($m.Title). Nothing patched." }
    }
    foreach ($m in $models) {
        $src = Download-Pinned $m $cache $source
        foreach ($n in $src.Notes) { $warnings.Add($n) }
        if ($src.Origins -contains 'local') { $notes.Add("$($m.Title): source files taken from $source (hash verified).") }
        $files = Archive-Data $src.Rfx $m
        if ([IO.File]::Exists((Inside $root ('Vehicles\CustomVehicles\' + $m.Vehicle)))) {
            Plan-Installed $m $files $root $assets $plans $brake $repairPaths $exe.Edition $notes $warnings
            $statuses += @{Model=$m.Title; State='SIGNALS_PATCHED'; Rfx=''}
        } else {
            # RealFlight imports the vendor archive unmodified (the path this workflow was proven with); all edits happen after Import.
            Add-Plan $plans 'Root' ('RFX\SJARC\' + $m.Rfx) ([IO.File]::ReadAllBytes($src.Rfx))
            $statuses += @{Model=$m.Title; State='IMPORT_REQUIRED'; Rfx=(Inside $root ('RFX\SJARC\' + $m.Rfx))}
        }
        $vendorParam = [IO.File]::ReadAllBytes($src.Param)
        Add-Plan $plans 'Root' ('.SJARC\Parameters\' + $m.Param) $vendorParam
        # Pioneer and Striver also get a RealFlight SITL file made from the verified original (SitlParams.ps1).
        $rfSitl = New-RfSitlParam $m.Param $vendorParam
        if ($rfSitl) { Add-Plan $plans 'Root' ('.SJARC\Parameters\' + $rfSitl.Name) $rfSitl.Bytes }
    }
    Add-Plan $plans 'Root' '.SJARC\Parameters\MFE_MotorMap_ONLY.param' ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'MotorMap.param')))
    $ini = Read-Text (Inside $root $rootInfo.Ini)
    foreach ($kv in $IniKeys) {
        if ([regex]::Matches($ini, '(?m)^' + [regex]::Escape($kv[0]) + '=').Count -eq 1) { $ini = Set-Key $ini $kv[0] $kv[1] }
        elseif ($LinkKeys -notcontains $kv[0]) { $warnings.Add('Set manually in RealFlight Physics: ' + $kv[0] + '=' + $kv[1]) }
    }
    if (-not @($LinkKeys | Where-Object { [regex]::Matches($ini, '(?m)^' + [regex]::Escape($_) + '=').Count -eq 1 }).Count) {
        $warnings.Add('Set manually in RealFlight Physics: RealFlight Link (FlightAxis) = Yes')
    }
    foreach ($w in @(Controller-Warnings $root $ini)) { $warnings.Add($w) }
    Add-Plan $plans 'Root' $rootInfo.Ini ($ByteEncoding.GetBytes($ini))
    $transaction = Commit-Plan $plans $root $assets $request.Action
    $pending = @($statuses | Where-Object State -EQ 'IMPORT_REQUIRED').Count
    return @{Success=$true; Version=$Version; State=$(if ($pending) {'IMPORT_REQUIRED'} else {'FILES_VERIFIED'}); Edition=$exe.Edition; Root=$root; Assets=$assets; Models=@($statuses); Warnings=@($warnings); Notes=@($notes); Transaction=$transaction; ImportFolder=(Inside $root 'RFX\SJARC'); ParamFolder=(Inside $root '.SJARC\Parameters'); Message='File preparation/patch only. Import clicks, controller calibration and SITL parameter loading remain manual. No ARM or flight test performed.'}
}

if (-not $LibraryOnly) {
    try { $req = Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json; $result = Setup $req; $result | ConvertTo-Json -Depth 10; exit 0 }
    catch { @{Success=$false; Error=$_.Exception.Message; Location=$_.InvocationInfo.PositionMessage} | ConvertTo-Json -Depth 5; exit 1 }
}
