# =================================================================
# AI RAM Engine v1.0
# Compact Efficiency Mode Manager
# config.txt stays next to PS1/EXE
# + CPU LIMIT button
#   ON  = Min CPU 5 %, Max CPU 66 %
#   OFF = Restore original CPU power values
# =================================================================

$apiCode = @"
using System;
using System.Runtime.InteropServices;

public class AIRAMWinAPI {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetPriorityClass(IntPtr h, uint p);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetProcessInformation(IntPtr h, int c, ref PROCESS_POWER_THROTTLING_STATE i, uint s);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetProcessInformation(IntPtr h, int c, ref MEMORY_PRIORITY_INFORMATION i, uint s);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr h, int n);

    public struct PROCESS_POWER_THROTTLING_STATE {
        public uint V;
        public uint CM;
        public uint SM;
    }

    public struct MEMORY_PRIORITY_INFORMATION {
        public uint MP;
    }

    public static bool Optimize(IntPtr h, bool eco) {
        if (h == IntPtr.Zero) return false;

        bool ok = true;

        try {
            ok &= SetPriorityClass(h, eco ? 0x40u : 0x20u);

            var m = new MEMORY_PRIORITY_INFORMATION {
                MP = eco ? 1u : 5u
            };

            ok &= SetProcessInformation(
                h,
                0,
                ref m,
                (uint)Marshal.SizeOf(typeof(MEMORY_PRIORITY_INFORMATION))
            );

            var t = new PROCESS_POWER_THROTTLING_STATE {
                V  = 1,
                CM = 5,
                SM = eco ? 5u : 0u
            };

            ok &= SetProcessInformation(
                h,
                4,
                ref t,
                (uint)Marshal.SizeOf(typeof(PROCESS_POWER_THROTTLING_STATE))
            );
        }
        catch {
            ok = false;
        }

        return ok;
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]'AIRAMWinAPI').Type) {
    Add-Type -TypeDefinition $apiCode
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# --- HELPERS ---
function N {
    param([string]$Type, [hashtable]$Props)

    $o = New-Object $Type

    foreach ($k in $Props.Keys) {
        $o.$k = $Props[$k]
    }

    $o
}

function Get-AppDirectory {
    try {
        $p = [Diagnostics.Process]::GetCurrentProcess()

        # PS2EXE / EXE: config next to EXE
        if ($p.ProcessName -notmatch '^(powershell|pwsh|powershell_ise)$') {
            $d = Split-Path -Parent $p.MainModule.FileName

            if ($d -and (Test-Path -LiteralPath $d)) {
                return $d
            }
        }
    }
    catch {}

    # PS1: config next to PS1
    if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) {
        return $PSScriptRoot
    }

    if ($MyInvocation.MyCommand.Path) {
        $d = Split-Path -Parent $MyInvocation.MyCommand.Path

        if ($d -and (Test-Path -LiteralPath $d)) {
            return $d
        }
    }

    return (Get-Location).Path
}

# --- PATH / CONFIG ---
$appDir = Get-AppDirectory
$conf   = Join-Path $appDir "config.txt"

$vault = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)

if (Test-Path -LiteralPath $conf) {
    Get-Content -LiteralPath $conf -ErrorAction SilentlyContinue | ForEach-Object {
        $x = $_.Trim()

        if ($x) {
            [void]$vault.Add($x)
        }
    }
}

# --- STATE ---
$global:ecoMode     = $true
$global:cpuCap      = $false
$global:cpuOriginal = $null

$global:allowClose  = $false
$global:lastHash    = ""
$global:tick        = 0
$global:lastThreads = 0
$global:dirty       = $false
$global:lastMemComp = $null

# --- CPU LIMIT CONFIG ---
$cpuMinPercent = 5
$cpuMaxPercent = 66

# Processor power management GUIDs
$cpuSubGuid = "54533251-82be-4824-96c1-47b60b740d00"
$cpuMinGuid = "893dee8e-2bef-41e0-89c6-b55d0929964c"
$cpuMaxGuid = "bc5038f7-23e0-4960-96da-33abaf5935ec"

# --- STYLE ---
$cBg   = [Drawing.Color]::White
$cEco  = [Drawing.ColorTranslator]::FromHtml("#004000")
$cNorm = [Drawing.ColorTranslator]::FromHtml("#2F4F4F")
$cOff  = [Drawing.Color]::Firebrick

$f9  = [Drawing.Font]::new("Segoe UI", 9)
$f9b = [Drawing.Font]::new("Segoe UI", 9, [Drawing.FontStyle]::Bold)

$exclude = [Text.RegularExpressions.Regex]::new(
    '^(explorer|ApplicationFrameHost|ShellExperienceHost|SearchHost|StartMenuExperienceHost)$',
    [Text.RegularExpressions.RegexOptions]'IgnoreCase,Compiled'
)

$office = [Text.RegularExpressions.Regex]::new(
    '^(WINWORD|EXCEL|OUTLOOK|POWERPNT|ONENOTE|MSACCESS|VISIO)$',
    [Text.RegularExpressions.RegexOptions]'IgnoreCase,Compiled'
)

# --- POWERCFG / CPU LIMIT ---
function Invoke-PowerCfg {
    param([string[]]$PowerArgs)

    try {
        $null = & powercfg.exe @PowerArgs 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-PowerCfgOutput {
    param([string[]]$PowerArgs)

    try {
        $out = & powercfg.exe @PowerArgs 2>$null

        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        @($out)
    }
    catch {
        $null
    }
}

function Get-ActivePowerSchemeGuid {
    $out = Get-PowerCfgOutput -PowerArgs @("/getactivescheme")

    if (-not $out) {
        return $null
    }

    $txt = @($out) -join "`n"

    if ($txt -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return $matches[1]
    }

    $null
}

function Get-CpuPowerValue {
    param(
        [string]$SchemeGuid,
        [string]$SettingGuid,
        [int]$FallbackAC,
        [int]$FallbackDC
    )

    $out = Get-PowerCfgOutput -PowerArgs @(
        "/query",
        $SchemeGuid,
        $cpuSubGuid,
        $SettingGuid
    )

    if (-not $out) {
        return [pscustomobject]@{
            AC = $FallbackAC
            DC = $FallbackDC
        }
    }

    $ac = $null
    $dc = $null
    $hexValues = [Collections.Generic.List[int]]::new()

    foreach ($line in $out) {
        if ($line -match '(?i)\bAC\b.*0x([0-9a-fA-F]+)') {
            $ac = [Convert]::ToInt32($matches[1], 16)
        }

        if ($line -match '(?i)\bDC\b.*0x([0-9a-fA-F]+)') {
            $dc = [Convert]::ToInt32($matches[1], 16)
        }

        foreach ($m in [Text.RegularExpressions.Regex]::Matches($line, '0x([0-9a-fA-F]+)')) {
            try {
                [void]$hexValues.Add([Convert]::ToInt32($m.Groups[1].Value, 16))
            }
            catch {}
        }
    }

    # Fallback pro lokalizované Windows:
    # u konkrétního nastavení bývají aktuální AC/DC hodnoty poslední dvě HEX hodnoty.
    if ($null -eq $ac -and $hexValues.Count -ge 2) {
        $ac = $hexValues[$hexValues.Count - 2]
    }

    if ($null -eq $dc -and $hexValues.Count -ge 1) {
        $dc = $hexValues[$hexValues.Count - 1]
    }

    [pscustomobject]@{
        AC = if ($null -ne $ac) { $ac } else { $FallbackAC }
        DC = if ($null -ne $dc) { $dc } else { $FallbackDC }
    }
}

function Get-CpuPowerState {
    param([string]$SchemeGuid)

    $min = Get-CpuPowerValue `
        -SchemeGuid $SchemeGuid `
        -SettingGuid $cpuMinGuid `
        -FallbackAC 5 `
        -FallbackDC 5

    $max = Get-CpuPowerValue `
        -SchemeGuid $SchemeGuid `
        -SettingGuid $cpuMaxGuid `
        -FallbackAC 100 `
        -FallbackDC 100

    [pscustomobject]@{
        MinAC = $min.AC
        MinDC = $min.DC
        MaxAC = $max.AC
        MaxDC = $max.DC
    }
}

function Set-CpuPowerValue {
    param(
        [string]$SchemeGuid,
        [string]$SettingGuid,
        [int]$AC,
        [int]$DC
    )

    $okAC = Invoke-PowerCfg -PowerArgs @(
        "/setacvalueindex",
        $SchemeGuid,
        $cpuSubGuid,
        $SettingGuid,
        "$AC"
    )

    # DC / baterie je best-effort.
    Invoke-PowerCfg -PowerArgs @(
        "/setdcvalueindex",
        $SchemeGuid,
        $cpuSubGuid,
        $SettingGuid,
        "$DC"
    ) | Out-Null

    $okAC
}

function Set-CpuLimit {
    param([bool]$Enabled)

    try {
        $scheme = Get-ActivePowerSchemeGuid

        if (-not $scheme) {
            return $false
        }

        # Best-effort: zobrazit nastavení v Advanced power options, pokud je skryté.
        foreach ($setting in @($cpuMinGuid, $cpuMaxGuid)) {
            Invoke-PowerCfg -PowerArgs @(
                "/attributes",
                $cpuSubGuid,
                $setting,
                "-ATTRIB_HIDE"
            ) | Out-Null
        }

        if ($Enabled) {
            if ($null -eq $global:cpuOriginal) {
                $global:cpuOriginal = Get-CpuPowerState -SchemeGuid $scheme
            }

            $okMin = Set-CpuPowerValue `
                -SchemeGuid $scheme `
                -SettingGuid $cpuMinGuid `
                -AC $cpuMinPercent `
                -DC $cpuMinPercent

            $okMax = Set-CpuPowerValue `
                -SchemeGuid $scheme `
                -SettingGuid $cpuMaxGuid `
                -AC $cpuMaxPercent `
                -DC $cpuMaxPercent
        }
        else {
            $restore = $global:cpuOriginal

            if ($null -eq $restore) {
                $restore = [pscustomobject]@{
                    MinAC = 5
                    MinDC = 5
                    MaxAC = 100
                    MaxDC = 100
                }
            }

            $okMin = Set-CpuPowerValue `
                -SchemeGuid $scheme `
                -SettingGuid $cpuMinGuid `
                -AC $restore.MinAC `
                -DC $restore.MinDC

            $okMax = Set-CpuPowerValue `
                -SchemeGuid $scheme `
                -SettingGuid $cpuMaxGuid `
                -AC $restore.MaxAC `
                -DC $restore.MaxDC

            $global:cpuOriginal = $null
        }

        Invoke-PowerCfg -PowerArgs @("/setactive", $scheme) | Out-Null

        return ($okMin -and $okMax)
    }
    catch {
        return $false
    }
}

# --- GUI ---
$form = N "Windows.Forms.Form" @{
    Text          = "AI RAM Engine v1.0"
    Size          = [Drawing.Size]::new(320, 590)
    Topmost       = $true
    StartPosition = "CenterScreen"
    BackColor     = $cBg
}

$list = N "Windows.Forms.CheckedListBox" @{
    Dock         = "Fill"
    CheckOnClick = $true
    BorderStyle  = 0
    Font         = $f9
}

$stats = N "Windows.Forms.Label" @{
    Text      = "Optimized: 0 procs / 0 MB / 0 thrs"
    Dock      = "Bottom"
    Height    = 30
    TextAlign = "MiddleCenter"
    Font      = $f9b
    ForeColor = [Drawing.Color]::DimGray
    BackColor = $cBg
}

$toggle = N "Windows.Forms.Button" @{
    Text      = "MODE: ECO (Active)"
    Dock      = "Bottom"
    Height    = 45
    FlatStyle = "Flat"
    BackColor = $cEco
    ForeColor = [Drawing.Color]::White
    Font      = $f9b
}
$toggle.FlatAppearance.BorderSize = 0

$cpuBtn = N "Windows.Forms.Button" @{
    Text      = "CPU LIMIT: OFF"
    Dock      = "Bottom"
    Height    = 40
    FlatStyle = "Flat"
    BackColor = $cNorm
    ForeColor = [Drawing.Color]::White
    Font      = $f9b
}
$cpuBtn.FlatAppearance.BorderSize = 0

$strip   = New-Object Windows.Forms.StatusStrip
$lRTitle = N "Windows.Forms.ToolStripStatusLabel" @{ Text = " RAM Comp: " }
$lRStat  = N "Windows.Forms.ToolStripStatusLabel" @{ Text = "?" }
$lOTitle = N "Windows.Forms.ToolStripStatusLabel" @{ Text = "Optimizer: "; Spring = $true; TextAlign = "MiddleRight" }
$lOStat  = N "Windows.Forms.ToolStripStatusLabel" @{ Text = "ACTIVE "; ForeColor = $cEco }

[void]$strip.Items.AddRange(@($lRTitle, $lRStat, $lOTitle, $lOStat))
$form.Controls.AddRange(@($list, $stats, $toggle, $cpuBtn, $strip))

function Set-EcoUi {
    if ($global:ecoMode) {
        $toggle.Text = "MODE: ECO (Active)"
        $toggle.BackColor = $cEco
        $lOStat.Text = "ACTIVE "
        $lOStat.ForeColor = $cEco
    }
    else {
        $toggle.Text = "MODE: NORMAL (Full Speed)"
        $toggle.BackColor = $cNorm
        $lOStat.Text = "NORMAL "
        $lOStat.ForeColor = $cNorm
    }
}

function Set-CpuUi {
    param([string]$State)

    switch ($State) {
        "On" {
            $cpuBtn.Text = "CPU LIMIT: ON (5-66%)"
            $cpuBtn.BackColor = $cEco
        }
        "Failed" {
            $cpuBtn.Text = "CPU LIMIT: FAILED"
            $cpuBtn.BackColor = $cOff
        }
        default {
            $cpuBtn.Text = "CPU LIMIT: OFF"
            $cpuBtn.BackColor = $cNorm
        }
    }
}

function Show-UI {
    [void]$form.Show()
    $form.WindowState = [Windows.Forms.FormWindowState]::Normal
    [void]$form.Activate()
}

# --- CONFIG SAVE ---
function Save-Config {
    if (-not $global:dirty) {
        return
    }

    $tmp = "$conf.tmp"

    try {
        $lines = [string[]]@($vault | Sort-Object)
        $utf8  = [Text.UTF8Encoding]::new($false)

        [IO.File]::WriteAllLines($tmp, $lines, $utf8)
        Move-Item -LiteralPath $tmp -Destination $conf -Force

        $global:dirty = $false
    }
    catch {
        try {
            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Force
            }
        }
        catch {}
    }
}

# --- ENGINE HELPERS ---
function Restore-ProcessName {
    param([string]$Name)

    if (-not $Name) {
        return
    }

    foreach ($p in [Diagnostics.Process]::GetProcessesByName($Name)) {
        try {
            [AIRAMWinAPI]::Optimize($p.Handle, $false) | Out-Null
        }
        catch {}
        finally {
            try {
                $p.Dispose()
            }
            catch {}
        }
    }
}

function Restore-All {
    try {
        if ($global:cpuCap) {
            Set-CpuLimit $false | Out-Null
            $global:cpuCap = $false
        }
    }
    catch {}

    foreach ($name in @($vault)) {
        Restore-ProcessName -Name $name
    }
}

function Sync-ListToVault {
    for ($i = 0; $i -lt $list.Items.Count; $i++) {
        $n = $list.Items[$i].ToString()

        if ($list.GetItemChecked($i)) {
            if ($vault.Add($n)) {
                $global:dirty = $true
            }
        }
        else {
            if ($vault.Remove($n)) {
                $global:dirty = $true
                Restore-ProcessName -Name $n
            }
        }
    }
}

function Update-MemoryCompression {
    if ($global:tick % 10 -eq 1 -or $null -eq $global:lastMemComp) {
        try {
            $global:lastMemComp = (Get-MMAgent).MemoryCompression
        }
        catch {
            $global:lastMemComp = $null
        }
    }

    if ($null -eq $global:lastMemComp) {
        $lRStat.Text = "?"
        $lRStat.ForeColor = [Drawing.Color]::DimGray
    }
    elseif ($global:lastMemComp) {
        $lRStat.Text = "ON"
        $lRStat.ForeColor = $cEco
    }
    else {
        $lRStat.Text = "OFF"
        $lRStat.ForeColor = $cOff
    }
}

function Refresh-List {
    param(
        [Collections.Generic.HashSet[string]]$Visible,
        [Collections.Generic.HashSet[string]]$RunningVault
    )

    $display = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($n in $Visible) {
        [void]$display.Add($n)
    }

    foreach ($n in $RunningVault) {
        [void]$display.Add($n)
    }

    $names = @($display | Sort-Object)
    $hash  = $names -join ","

    if ($hash -eq $global:lastHash) {
        return
    }

    $global:lastHash = $hash

    $list.BeginUpdate()

    try {
        $list.Items.Clear()

        foreach ($n in $names) {
            [void]$list.Items.Add($n, $vault.Contains($n))
        }
    }
    finally {
        $list.EndUpdate()
    }
}

function Invoke-Engine {
    $global:tick++

    Update-MemoryCompression
    Sync-ListToVault

    $optCount = 0
    $optRam   = 0
    $curThrs  = 0

    $calcThreads = ($global:tick % 5 -eq 0 -or $global:lastThreads -eq 0)

    $visible = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    $runningVault = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        try {
            $n = $p.ProcessName

            if ($vault.Contains($n)) {
                [void]$runningVault.Add($n)

                [AIRAMWinAPI]::Optimize($p.Handle, $global:ecoMode) | Out-Null

                $optCount++
                $optRam += $p.WorkingSet64

                if ($calcThreads) {
                    try {
                        $curThrs += $p.Threads.Count
                    }
                    catch {}
                }
            }

            if (($p.MainWindowHandle -ne [IntPtr]::Zero -or $office.IsMatch($n)) -and -not $exclude.IsMatch($n)) {
                [void]$visible.Add($n)
            }
        }
        catch {}
        finally {
            try {
                $p.Dispose()
            }
            catch {}
        }
    }

    if ($calcThreads) {
        $global:lastThreads = $curThrs
    }

    $stats.Text = "Optimized: $optCount procs / $([Math]::Round($optRam / 1MB, 0)) MB / $($global:lastThreads) thrs"

    Refresh-List -Visible $visible -RunningVault $runningVault

    if ($global:tick % 5 -eq 0) {
        Save-Config
    }

    if ($global:tick % 30 -eq 0) {
        [GC]::Collect()
    }
}

# --- TRAY ---
$tray = N "Windows.Forms.NotifyIcon" @{
    Icon    = [Drawing.SystemIcons]::Application
    Visible = $true
    Text    = "AI RAM Engine v1.0"
}

$menu = New-Object Windows.Forms.ContextMenuStrip

[void]$menu.Items.Add("Open", $null, {
    Show-UI
})

[void]$menu.Items.Add("Exit", $null, {
    $global:allowClose = $true
    $form.Close()
})

$tray.ContextMenuStrip = $menu
$tray.Add_MouseDoubleClick({
    Show-UI
})

# --- EVENTS ---
$toggle.Add_Click({
    $global:ecoMode = -not $global:ecoMode

    Set-EcoUi
    Invoke-Engine
})

$cpuBtn.Add_Click({
    if (-not $global:cpuCap) {
        if (Set-CpuLimit $true) {
            $global:cpuCap = $true
            Set-CpuUi -State "On"
        }
        else {
            $global:cpuCap = $false
            Set-CpuUi -State "Failed"

            [Windows.Forms.MessageBox]::Show(
                "CPU limit se nepodařilo nastavit.",
                "AI RAM Engine",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }
    else {
        Set-CpuLimit $false | Out-Null

        $global:cpuCap = $false
        Set-CpuUi -State "Off"
    }
})

$form.Add_FormClosing({
    Save-Config

    if (-not $global:allowClose -and $_.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing -and $tray.Visible) {
        $_.Cancel = $true
        $form.Hide()
        return
    }

    try {
        $timer.Stop()
    }
    catch {}

    Restore-All

    try {
        $tray.Visible = $false
        $tray.Dispose()
    }
    catch {}
})

[Windows.Forms.Application]::add_ApplicationExit({
    try {
        Save-Config
    }
    catch {}

    try {
        if ($global:cpuCap) {
            Set-CpuLimit $false | Out-Null
            $global:cpuCap = $false
        }
    }
    catch {}

    try {
        $tray.Visible = $false
        $tray.Dispose()
    }
    catch {}
})

# --- START ---
try {
    [AIRAMWinAPI]::SetPriorityClass(
        [Diagnostics.Process]::GetCurrentProcess().Handle,
        0x40
    ) | Out-Null
}
catch {}

$timer = N "Windows.Forms.Timer" @{
    Interval = 6000
}

$timer.Add_Tick({
    Invoke-Engine
})

$timer.Start()

Set-EcoUi
Set-CpuUi -State "Off"
Invoke-Engine

$h = [AIRAMWinAPI]::GetConsoleWindow()

if ($h -ne [IntPtr]::Zero) {
    [AIRAMWinAPI]::ShowWindow($h, 0) | Out-Null
}

[Windows.Forms.Application]::Run($form)