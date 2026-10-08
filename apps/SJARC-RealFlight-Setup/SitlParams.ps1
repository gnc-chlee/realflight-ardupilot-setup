# RealFlight SITL parameter files (*_VTOL_RF_SITL.param) made from MakeFlyEasy's untouched ArduPlane 4.4.4 files.
# Used by Backend.ps1 (writes them next to the originals in .SJARC\Parameters) and scripts\make-sitl-params.ps1 (field kit).
# Every change is listed in the file header; the vendor originals stay byte-identical (the helper hash-checks them).

$SitlParamRecipes = [ordered]@{
    'Pioneer_VTOL_V4.4.4.param' = @{
        Out = 'Pioneer_VTOL_RF_SITL.param'; Title = 'MFE Pioneer VTOL'
        Set = [ordered]@{ SERVO11_FUNCTION = '36'; SERVO12_FUNCTION = '35' }
        After = @{}
        Reset = [ordered]@{ MIXING_GAIN = '0.5'; SERVO8_FUNCTION = '0' }
        Notes = @(
            '#   MIXING_GAIN 0.5, SERVO8_FUNCTION 0 : ArduPlane defaults; clear values the Striver file sets')
    }
    'Striver_VTOL_V4.4.4.param' = @{
        Out = 'Striver_VTOL_RF_SITL.param'; Title = 'MFE Striver mini VTOL'
        Set = [ordered]@{ SERVO11_FUNCTION = '36'; SERVO12_FUNCTION = '35'; Q_A_RAT_RLL_P = '0.2' }
        After = @{ SERVO2_FUNCTION = 'SERVO2_REVERSED,1' }
        Reset = [ordered]@{ KFF_RDDRMIX = '0.5'; TRIM_THROTTLE = '45' }
        Notes = @(
            '#   SERVO2_REVERSED 1 : the RealFlight Striver elevator moves opposite (only Pioneer''s RF model reverses it)',
            '#   Q_A_RAT_RLL_P 0.24 -> 0.2 : removed VTOL roll oscillation in RealFlight (simulator tune)',
            '#   KFF_RDDRMIX 0.5, TRIM_THROTTLE 45 : ArduPlane defaults; clear values the Pioneer file sets')
    }
}

# ArduPlane 4.4.4 names renamed in 4.5-4.7, with the unit scale ArduPilot's own upgrade code applies
# (Plane Parameters.cpp, QuadPlane, AC_AttitudeControl, AC_PosControl, AC_WPNav, AC_Loiter, AP_Arming).
$SitlParamRenames = [ordered]@{
    ALT_HOLD_RTL = @('RTL_ALTITUDE', 0.01); ARSPD_FBW_MAX = @('AIRSPEED_MAX', 1); ARSPD_FBW_MIN = @('AIRSPEED_MIN', 1)
    LIM_PITCH_MAX = @('PTCH_LIM_MAX_DEG', 0.01); LIM_PITCH_MIN = @('PTCH_LIM_MIN_DEG', 0.01); LIM_ROLL_CD = @('ROLL_LIMIT_DEG', 0.01)
    TRIM_ARSPD_CM = @('AIRSPEED_CRUISE', 0.01); TRIM_PITCH_CD = @('PTCH_TRIM_DEG', 0.01)
    Q_A_ACCEL_P_MAX = @('Q_A_ACC_P_MAX', 0.01); Q_A_ACCEL_R_MAX = @('Q_A_ACC_R_MAX', 0.01); Q_A_ACCEL_Y_MAX = @('Q_A_ACC_Y_MAX', 0.01)
    Q_A_SLEW_YAW = @('Q_A_RATE_WPY_MAX', 0.01); Q_ANGLE_MAX = @('Q_A_ANGLE_MAX', 0.01)
    Q_ACCEL_Z = @('Q_PILOT_ACCEL_Z', 0.01); Q_LAND_SPEED = @('Q_LAND_FINAL_SPD', 0.01); Q_VELZ_MAX = @('Q_PILOT_SPD_UP', 0.01); Q_VELZ_MAX_DN = @('Q_PILOT_SPD_DN', 0.01)
    Q_LOIT_ACC_MAX = @('Q_LOIT_ACC_MAX_M', 0.01); Q_LOIT_BRK_ACCEL = @('Q_LOIT_BRK_ACC_M', 0.01); Q_LOIT_BRK_JERK = @('Q_LOIT_BRK_JRK_M', 0.01); Q_LOIT_SPEED = @('Q_LOIT_SPEED_MS', 0.01)
    Q_WP_ACCEL = @('Q_WP_ACC', 0.01); Q_WP_ACCEL_C = @('Q_WP_ACC_CNR', 0.01); Q_WP_ACCEL_Z = @('Q_WP_ACC_Z', 0.01); Q_WP_RADIUS = @('Q_WP_RADIUS_M', 0.01)
    Q_WP_SPEED = @('Q_WP_SPD', 0.01); Q_WP_SPEED_DN = @('Q_WP_SPD_DN', 0.01); Q_WP_SPEED_UP = @('Q_WP_SPD_UP', 0.01)
    Q_P_ACCZ_P = @('Q_P_D_ACC_P', 0.1); Q_P_ACCZ_I = @('Q_P_D_ACC_I', 0.1); Q_P_ACCZ_D = @('Q_P_D_ACC_D', 0.1); Q_P_ACCZ_IMAX = @('Q_P_D_ACC_IMAX', 0.001)
    Q_P_ACCZ_FF = @('Q_P_D_ACC_FF', 1); Q_P_ACCZ_FLTD = @('Q_P_D_ACC_FLTD', 1); Q_P_ACCZ_FLTE = @('Q_P_D_ACC_FLTE', 1); Q_P_ACCZ_FLTT = @('Q_P_D_ACC_FLTT', 1); Q_P_ACCZ_SMAX = @('Q_P_D_ACC_SMAX', 1)
    Q_P_JERK_XY = @('Q_P_NE_JERK', 1); Q_P_JERK_Z = @('Q_P_D_JERK', 1); Q_P_POSXY_P = @('Q_P_NE_POS_P', 1); Q_P_POSZ_P = @('Q_P_D_POS_P', 1)
    Q_P_VELXY_P = @('Q_P_NE_VEL_P', 1); Q_P_VELXY_I = @('Q_P_NE_VEL_I', 1); Q_P_VELXY_D = @('Q_P_NE_VEL_D', 1); Q_P_VELXY_FF = @('Q_P_NE_VEL_FF', 1)
    Q_P_VELXY_FLTD = @('Q_P_NE_VEL_FLTD', 1); Q_P_VELXY_FLTE = @('Q_P_NE_VEL_FLTE', 1); Q_P_VELXY_IMAX = @('Q_P_NE_VEL_IMAX', 0.01)
    Q_P_VELZ_P = @('Q_P_D_VEL_P', 1); Q_P_VELZ_I = @('Q_P_D_VEL_I', 1); Q_P_VELZ_D = @('Q_P_D_VEL_D', 1); Q_P_VELZ_FF = @('Q_P_D_VEL_FF', 1)
    Q_P_VELZ_FLTD = @('Q_P_D_VEL_FLTD', 1); Q_P_VELZ_FLTE = @('Q_P_D_VEL_FLTE', 1); Q_P_VELZ_IMAX = @('Q_P_D_VEL_IMAX', 0.01)
}

function Convert-SitlParamName([string]$old, [string]$value) {
    if ($old -ceq 'ARMING_CHECK') {
        # AP_Arming: ARMING_CHECK became ARMING_SKIPCHK (checks to skip). 1 = all checks -> skip none.
        $v = [int]$value
        $skip = if ($v -eq 0) { -1 } elseif ($v -band 1) { 0 } else { (-bnot $v) -band ((1 -shl 21) - 1) -band (-bnot 1) }
        return @('ARMING_SKIPCHK', [string]$skip)
    }
    if (-not $SitlParamRenames.Contains($old)) { return $null }
    $new = $SitlParamRenames[$old][0]; $scale = [double]$SitlParamRenames[$old][1]; $v = [double]::Parse($value, [Globalization.CultureInfo]::InvariantCulture)
    # RTL_ALTITUDE keeps -1 (= hold current altitude) instead of scaling it to -0.01.
    $converted = if ($new -ceq 'RTL_ALTITUDE' -and $v -lt 0) { -1.0 } else { [math]::Round($v * $scale, 6) }
    return @($new, $converted.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture))
}

function Read-SitlParams([string]$text) {
    $h = [ordered]@{}
    foreach ($line in $text -split "`n") { if ($line -match '^\s*([A-Z0-9_]+)\s*,\s*([^\s#]+)') { $h[$Matches[1]] = $Matches[2] } }
    return $h
}

# Returns @{Name; Bytes} for a vendor file that has a RealFlight recipe, otherwise $null.
function New-RfSitlParam([string]$vendorName, [byte[]]$vendorBytes) {
    if (-not $SitlParamRecipes.Contains($vendorName)) { return $null }
    $m = $SitlParamRecipes[$vendorName]
    $utf8 = [Text.UTF8Encoding]::new($false)
    $text = $utf8.GetString($vendorBytes).Replace("`r`n", "`n")
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in $text.TrimEnd("`n") -split "`n") {
        if ($line -match '^\s*([A-Z0-9_]+)\s*,') {
            $key = $Matches[1]
            if ($key -ceq 'FLTMODE_CH') { $lines.Add('# FLTMODE_CH not set here: use your transmitter''s mode-switch channel'); continue }
            if ($m.Set.Contains($key)) { $line = $key + ',' + $m.Set[$key] }
            $lines.Add($line)
            if ($m.After.ContainsKey($key)) { $lines.Add($m.After[$key]) }
        } else { $lines.Add($line) }
    }
    $lines.Add('')
    $lines.Add('#Reset to ArduPlane defaults (values another MFE model file may have left in the same SITL)')
    $lines.Add('')
    foreach ($k in $m.Reset.Keys) { $lines.Add($k + ',' + $m.Reset[$k]) }
    # Same values under the names ArduPlane 4.5-4.7 introduced; each firmware accepts the names it knows.
    $lines.Add('')
    $lines.Add('#Newer ArduPlane names (4.5-4.7 renames, units converted like the firmware upgrade does); 4.4.4 skips these')
    $lines.Add('')
    foreach ($kv in (Read-SitlParams ($lines -join "`n")).GetEnumerator()) {
        $c = Convert-SitlParamName $kv.Key $kv.Value
        if ($c) { $lines.Add($c[0] + ',' + $c[1]) }
    }
    $sha = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($vendorBytes)) -replace '-', '').ToLowerInvariant()
    $header = @(
        "# SJ-ARC RealFlight 9 SITL parameters - $($m.Title)   *** SIMULATOR ONLY - do not load into a real aircraft ***",
        "# Base: $vendorName (MakeFlyEasy, ArduPlane 4.4.4, ArduPilot SITL_Models PR #158) sha256 $sha",
        '# Changed for RealFlight FlightAxis SITL (2026-09-29, Icheon field test):',
        '#   SERVO11_FUNCTION 35 -> 36, SERVO12_FUNCTION 36 -> 35 : RF wiring RX11 = rear-right (Motor4), RX12 = front-left (Motor3)') +
        $m.Notes + @(
        '#   FLTMODE_CH is not set by this file: set it to your transmitter''s mode-switch channel (ArduPlane default 8)',
        '#   Q_ASSIST_SPEED stays at the vendor value; ArduPlane refuses to arm ("Q_ASSIST_SPEED is not set") while it is 0',
        '# Vendor names are ArduPlane 4.4.4. The last section repeats 56 renamed ones under their 4.5-4.7 names',
        '# (e.g. ARSPD_FBW_MIN -> AIRSPEED_MIN); each firmware applies the names it knows and skips the others.',
        '# Mission Planner: CONFIG > Full Parameter List > Load from file > Write Params, restart SITL, Refresh Params,',
        '# then load and write this file once more: Q_ parameters only exist after Q_ENABLE = 1 and a restart.',
        '')
    return @{ Name = $m.Out; Bytes = $utf8.GetBytes((($header + $lines) -join "`n") + "`n") }
}
