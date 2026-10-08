#requires -Version 5.1
# Builds the RealFlight-SITL parameter files (kit\*_VTOL_RF_SITL.param) for the field USB kit from the untouched MFE V4.4.4 files.
# The recipe lives in apps\SJARC-RealFlight-Setup\SitlParams.ps1; the helper writes the same files into .SJARC\Parameters.
# Default input: the originals scripts\build_sjarc_setup.py downloads (one subfolder per model) or a flat USB kit folder.
param(
    [string] $VendorFolder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\mfe-four-models\upstream'),
    [string] $OutFolder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'apps\SJARC-RealFlight-Setup\kit')
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'apps\SJARC-RealFlight-Setup\SitlParams.ps1')
$utf8 = [Text.UTF8Encoding]::new($false)

foreach ($vendorName in $SitlParamRecipes.Keys) {
    $vendorPath = Join-Path $VendorFolder $vendorName
    if (-not [IO.File]::Exists($vendorPath)) { $vendorPath = @(Get-ChildItem -LiteralPath $VendorFolder -Recurse -File -Filter $vendorName)[0].FullName }
    $vendorBytes = [IO.File]::ReadAllBytes($vendorPath)
    $made = New-RfSitlParam $vendorName $vendorBytes
    $out = Join-Path $OutFolder $made.Name
    [IO.File]::WriteAllBytes($out, $made.Bytes)

    # Verify: exactly the intended differences against the vendor file.
    $a = Read-SitlParams ($utf8.GetString($vendorBytes).Replace("`r`n", "`n"))
    $b = Read-SitlParams ($utf8.GetString($made.Bytes))
    "== $($made.Name)"
    foreach ($k in $a.Keys) { if (-not $b.Contains($k)) { "   removed  $k ($($a[$k]))" } elseif ($a[$k] -cne $b[$k]) { "   changed  $k $($a[$k]) -> $($b[$k])" } }
    foreach ($k in $b.Keys) { if (-not $a.Contains($k)) { "   added    $k = $($b[$k])" } }
}
