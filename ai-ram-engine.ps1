# =================================================================
# AI RAM Engine - APEX OPTIMIZED v4.6.3 Compact Format
# =================================================================

$apiCode = @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("kernel32.dll")] public static extern bool SetPriorityClass(IntPtr h, uint p);
    [DllImport("kernel32.dll")] public static extern bool SetProcessInformation(IntPtr h, int c, ref PROCESS_POWER_THROTTLING_STATE i, uint s);
    [DllImport("kernel32.dll")] public static extern bool SetProcessInformation(IntPtr h, int c, ref MEMORY_PRIORITY_INFORMATION i, uint s);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    public struct PROCESS_POWER_THROTTLING_STATE { public uint V, CM, SM; }
    public struct MEMORY_PRIORITY_INFORMATION { public uint MP; }

    public static void Optimize(IntPtr h, bool eco) {
        if (h == IntPtr.Zero) return;
        try {
            SetPriorityClass(h, eco ? 0x40u : 0x20u);
            var m = new MEMORY_PRIORITY_INFORMATION { MP = eco ? 1u : 5u };
            SetProcessInformation(h, 5, ref m, (uint)Marshal.SizeOf(m));
            var t = new PROCESS_POWER_THROTTLING_STATE { V = 1, CM = 5, SM = eco ? 5u : 0u };
            SetProcessInformation(h, 4, ref t, (uint)Marshal.SizeOf(t));
        } catch {}
    }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) { Add-Type -TypeDefinition $apiCode }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$conf = Join-Path $PSScriptRoot "config.txt"
$global:vault = [System.Collections.Generic.HashSet[string]]::new()
if (Test-Path $conf) { Get-Content $conf | Where-Object { $_ } | ForEach-Object { [void]$global:vault.Add($_) } }

$global:ecoMode = $true; $global:allowClose = $false
$global:lastProcHash = ""; $global:tickCount = $global:lastThreadsCount = 0
$cEco = [Drawing.ColorTranslator]::FromHtml("#004000")
$cNorm = [Drawing.ColorTranslator]::FromHtml("#2F4F4F")
$cOff = [Drawing.Color]::Firebrick
$exclude = [regex]"explorer"

# --- GUI ---
$form = New-Object Windows.Forms.Form -Property @{
    Text = "AI RAM Engine v4.6.3"
    Size = "320,550"
    Topmost = $true
    StartPosition = "CenterScreen"
    BackColor = [Drawing.Color]::White
}
$list = New-Object Windows.Forms.CheckedListBox -Property @{
    Dock = "Fill"
    CheckOnClick = $true
    BorderStyle = 0
    Font = [Drawing.Font]::new("Segoe UI", 9)
}
$stats = New-Object Windows.Forms.Label -Property @{
    Text = "Optimized: 0 procs / 0 MB / 0 thrs"
    Dock = "Bottom"
    Height = 30
    TextAlign = "MiddleCenter"
    Font = [Drawing.Font]::new("Segoe UI", 9, [Drawing.FontStyle]::Bold)
    ForeColor = [Drawing.Color]::DimGray
    BackColor = [Drawing.Color]::White
}
$toggle = New-Object Windows.Forms.Button -Property @{
    Text = "MODE: ECO (Active)"
    Dock = "Bottom"
    Height = 45
    FlatStyle = "Flat"
    BackColor = $cEco
    ForeColor = [Drawing.Color]::White
    Font = [Drawing.Font]::new("Segoe UI", 9, [Drawing.FontStyle]::Bold)
}
$toggle.FlatAppearance.BorderSize = 0

$strip = New-Object Windows.Forms.StatusStrip
$lRTitle = New-Object Windows.Forms.ToolStripStatusLabel -Property @{ Text = " RAM Comp: " }
$lRStat = New-Object Windows.Forms.ToolStripStatusLabel
$lOTitle = New-Object Windows.Forms.ToolStripStatusLabel -Property @{ Text = "Optimizer: "; Spring = $true; TextAlign = "MiddleRight" }
$lOStat = New-Object Windows.Forms.ToolStripStatusLabel -Property @{ Text = "ACTIVE "; ForeColor = $cEco }
[void]$strip.Items.AddRange(@($lRTitle, $lRStat, $lOTitle, $lOStat))
$form.Controls.AddRange(@($list, $stats, $toggle, $strip))

function Show-UI { $form.Show(); $form.WindowState = 0; $form.Activate() }

function Invoke-Engine {
    $global:tickCount++
    try { [WinAPI]::SetPriorityClass([System.Diagnostics.Process]::GetCurrentProcess().Handle, 0x40) } catch {}

    try {
        $mm = Get-MMAgent
        $lRStat.Text = if ($mm.MemoryCompression) { "ON" } else { "OFF" }
        $lRStat.ForeColor = if ($mm.MemoryCompression) { $cEco } else { $cOff }
    } catch { $lRStat.Text = "?" }

    for ($i = 0; $i -lt $list.Items.Count; $i++) {
        $n = $list.Items[$i].ToString()
        if ($list.GetItemChecked($i)) { [void]$global:vault.Add($n) } else { [void]$global:vault.Remove($n) }
    }

    $optCount = $optRam = $curThreads = 0
    $vNames = [System.Collections.Generic.HashSet[string]]::new()
    $calcThrs = ($global:tickCount % 5 -eq 0 -or $global:lastThreadsCount -eq 0)

    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $n = $p.ProcessName
            if ($global:vault.Contains($n)) {
                try { [WinAPI]::Optimize($p.Handle, $global:ecoMode) } catch {}
                $optCount++; $optRam += $p.WorkingSet64
                if ($calcThrs) { try { $curThreads += $p.Threads.Count } catch {} }
            }
            if (($p.MainWindowHandle -ne 0 -or $n -match "WINWORD|EXCEL|OUTLOOK") -and -not $exclude.IsMatch($n)) {
                [void]$vNames.Add($n)
            }
        } finally { try { $p.Dispose() } catch {} }
    }

    if ($calcThrs) { $global:lastThreadsCount = $curThreads }
    $stats.Text = "Optimized: $optCount procs / $([math]::Round($optRam / 1MB, 0)) MB / $($global:lastThreadsCount) thrs"

    $hash = ($vNames | Sort-Object) -join ","
    if ($hash -ne $global:lastProcHash) {
        $global:lastProcHash = $hash
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($n in ($vNames | Sort-Object)) { [void]$list.Items.Add($n, $global:vault.Contains($n)) }
        $list.EndUpdate()
    }

    if ($global:tickCount % 10 -eq 0) { [System.GC]::Collect() }
}

# --- Tray ---
$tray = New-Object Windows.Forms.NotifyIcon -Property @{
    Icon = [Drawing.SystemIcons]::Application
    Visible = $true
    Text = "AI RAM Engine"
}
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Open", $null, { Show-UI })
[void]$menu.Items.Add("Exit", $null, { $global:allowClose = $true; $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Add_MouseDoubleClick({ Show-UI })

# --- Safe shutdown with process restore ---
$form.Add_FormClosing({
    $global:vault | Sort-Object | Out-File $conf -Force
    if (-not $global:allowClose -and $_.CloseReason -eq "UserClosing" -and $tray.Visible) {
        $_.Cancel = $true; $form.Hide(); return
    }

    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            if ($global:vault.Contains($p.ProcessName)) { [WinAPI]::Optimize($p.Handle, $false) }
        } catch {} finally { try { $p.Dispose() } catch {} }
    }
    $tray.Visible = $false
})

$toggle.Add_Click({
    $global:ecoMode = -not $global:ecoMode
    $toggle.Text = if ($global:ecoMode) { "MODE: ECO (Active)" } else { "MODE: NORMAL (Full Speed)" }
    $toggle.BackColor = if ($global:ecoMode) { $cEco } else { $cNorm }
})

# --- Start ---
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 6000 }
$timer.Add_Tick({ Invoke-Engine })
$timer.Start(); Invoke-Engine

$h = [WinAPI]::GetConsoleWindow()
if ($h -ne 0) { [WinAPI]::ShowWindow($h, 0) }
[Windows.Forms.Application]::Run($form)