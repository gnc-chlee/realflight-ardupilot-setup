#requires -Version 5.1
# Draws the SJ-ARC helper icon (quadplane VTOL, top view) and writes a multi-size Windows .ico:
# 16-64 px as 32-bit BMP frames (every Windows/.NET icon reader handles them) and 256 px as PNG.
param(
    [string] $Out = (Join-Path (Split-Path $PSScriptRoot -Parent) 'apps\SJARC-RealFlight-Setup\app.ico'),
    [string] $PreviewDir = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Round-Rect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Min($r * 2, [Math]::Min($w, $h))
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-Icon([int]$size) {
    $bmp = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([Drawing.Color]::Transparent)
    $k = $size / 256.0
    # Thin parts get a 1 px floor so the airframe still reads at 16 px.
    function S([double]$v) { return [single]($v * $k) }
    function W([double]$v) { return [single][Math]::Max(1.0, $v * $k) }
    $blue = [Drawing.Color]::FromArgb(255, 35, 79, 132)
    $g.FillPath((New-Object Drawing.SolidBrush $blue), (Round-Rect 0 0 $size $size (S 56)))
    $white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $mint = [Drawing.Color]::FromArgb(255, 159, 225, 203)
    $disc = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 159, 225, 203))
    if ($size -lt 32) {
        # Small sizes: cross-shaped airframe and four solid rotors; booms and tail would only blur into a grid.
        $g.FillPath($white, (Round-Rect (S 40) (S 110) (S 176) (S 36) (S 18)))
        $g.FillPath($white, (Round-Rect (S 110) (S 40) (S 36) (S 176) (S 18)))
        $solid = New-Object Drawing.SolidBrush $mint
        foreach ($c in @(@(66, 66), @(190, 66), @(66, 190), @(190, 190))) { $g.FillEllipse($solid, (S ($c[0] - 36)), (S ($c[1] - 36)), (S 72), (S 72)) }
    } else {
        # wing, fuselage, two booms, tailplane (top view, nose up) and four lift-rotor discs at the boom ends
        $g.FillPath($white, (Round-Rect (S 26) (S 106) (S 204) (W 26) (S 13)))
        $g.FillPath($white, (Round-Rect (S 113) (S 36) (W 30) (S 180) (S 15)))
        $g.FillPath($white, (Round-Rect (S 68) (S 60) (W 11) (S 138) (S 5)))
        $g.FillPath($white, (Round-Rect (S 177) (S 60) (W 11) (S 138) (S 5)))
        $g.FillPath($white, (Round-Rect (S 94) (S 196) (S 68) (W 16) (S 8)))
        $pen = New-Object Drawing.Pen $mint, (W 9)
        foreach ($c in @(@(73, 58), @(73, 200), @(183, 58), @(183, 200))) {
            $g.FillEllipse($disc, (S ($c[0] - 30)), (S ($c[1] - 30)), (S 60), (S 60))
            $g.DrawEllipse($pen, (S ($c[0] - 30)), (S ($c[1] - 30)), (S 60), (S 60))
        }
    }
    $g.Dispose()
    return $bmp
}

function Bmp-Frame([Drawing.Bitmap]$bmp) {
    $s = $bmp.Width
    $rect = New-Object Drawing.Rectangle 0, 0, $s, $s
    $data = $bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $raw = New-Object byte[] ($data.Stride * $s)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
    $bmp.UnlockBits($data)
    $maskRow = [int]([Math]::Floor(($s + 31) / 32) * 4)
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $ms
    $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]0); $w.Write([int]($s * $s * 4 + $maskRow * $s)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
    for ($y = $s - 1; $y -ge 0; $y--) { $w.Write($raw, $y * $data.Stride, $s * 4) }   # DIB rows are bottom-up
    for ($y = $s - 1; $y -ge 0; $y--) {
        $row = New-Object byte[] $maskRow
        for ($x = 0; $x -lt $s; $x++) { if ($raw[$y * $data.Stride + $x * 4 + 3] -eq 0) { $row[$x -shr 3] = $row[$x -shr 3] -bor (0x80 -shr ($x -band 7)) } }
        $w.Write($row)
    }
    $w.Flush()
    return , $ms.ToArray()
}

$frames = @()
foreach ($size in 16, 20, 24, 32, 40, 48, 64, 256) {
    $bmp = Draw-Icon $size
    if ($PreviewDir) { [void][IO.Directory]::CreateDirectory($PreviewDir); $bmp.Save((Join-Path $PreviewDir "icon-$size.png"), [Drawing.Imaging.ImageFormat]::Png) }
    if ($size -eq 256) { $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bytes = $ms.ToArray() } else { $bytes = Bmp-Frame $bmp }
    $bmp.Dispose()
    $frames += , @($size, $bytes)
}
$ico = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $ico
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $dim = if ($f[0] -ge 256) { 0 } else { $f[0] }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$f[1].Length); $w.Write([int]$offset)
    $offset += $f[1].Length
}
foreach ($f in $frames) { $w.Write($f[1]) }
$w.Flush()
[IO.File]::WriteAllBytes($Out, $ico.ToArray())
"wrote $Out ($($ico.Length) bytes, $($frames.Count) sizes)"
