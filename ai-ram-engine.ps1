# =================================================================
# AI RAM Engine - APEX OPTIMIZED (v4.5.7 - Clean Exit Cleanup Fix)
# =================================================================
# 1. HIGH-PERFORMANCE API
$apiCode = @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
 [DllImport("kernel32.dll")] public static extern bool SetPriorityClass(IntPtr h, uint p);
 [DllImport("kernel32.dll")] public static extern bool SetProcessInformation(IntPtr h, int infoClass, ref PROCESS_POWER_THROTTLING_STATE info, uint size);
 [DllImport("kernel32.dll", EntryPoint = "SetProcessInformation")] public static extern bool SetProcessMemoryInformation(IntPtr h, int infoClass, ref long priority, uint size);
 [DllImport("kernel32.dll")] public static extern bool SetProcessAffinityMask(IntPtr h, IntPtr mask);
 [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
 [StructLayout(LayoutKind.Sequential)]
 public struct PROCESS_POWER_THROTTLING_STATE {
 public uint Version;
 public uint ControlMask;
 public uint StateMask;
 }
 public static void Optimize(IntPtr h, bool eco) {
 if (h == IntPtr.Zero) return;
 try {
 // 1. CPU Priorita: ECO = Idle (0x40) | Normal = Normal (0x20)
 SetPriorityClass(h, eco ? (uint)0x40 : (uint)0x20);
 
 // 2. Memory Priorita: ECO = 1 | Full Speed = 5
 long memPriority = eco ? 1 : 5;
 SetProcessMemoryInformation(h, 5, ref memPriority, (uint)sizeof(long));
 
 // 3. SKUTEČNÝ REŽIM EFEKTIVITY (Sloučené masky pro Win 11)
 PROCESS_POWER_THROTTLING_STATE throttlingState = new PROCESS_POWER_THROTTLING_STATE();
 throttlingState.Version = 1;
 throttlingState.ControlMask = 0x1 | 0x4; 
 throttlingState.StateMask = eco ? (uint)(0x1 | 0x4) : (uint)0x0;
 SetProcessInformation(h, 4, ref throttlingState, (uint)Marshal.SizeOf(throttlingState));
 
 // POZNÁMKA: Omezení CPU Afinity bylo odstraněno pro plné využití všech vláken procesoru.
 } catch {}
 }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) { 
 Add-Type -TypeDefinition $apiCode 
}
# 2. CORE SETUP
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$conf = "$PSScriptRoot\config.txt"
$global:vault = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $conf) { Get-Content $conf | ForEach-Object { [void]$global:vault.Add($_) } }
$global:colorEco = [System.Drawing.ColorTranslator]::FromHtml("#004000")
$global:colorNormal = [System.Drawing.ColorTranslator]::FromHtml("#2F4F4F")
$global:colorOff = [System.Drawing.Color]::Firebrick
# 3. GUI CONSTRUCTION
$form = New-Object Windows.Forms.Form
$form.Text = "AI RAM Engine v4.5.7"
$form.Size = "320, 550"
$form.Topmost = $true
$form.StartPosition = "CenterScreen"
$form.BackColor = "White"
$list = New-Object Windows.Forms.CheckedListBox
$list.Dock = "Fill"
$list.CheckOnClick = $true
$list.BorderStyle = 0
$list.Font = "Segoe UI, 9"
# PASSIVE STATS LABEL (DimGray English text)
$optStatsLabel = New-Object Windows.Forms.Label
$optStatsLabel.Text = "Optimized: 0 processes (0 MB RAM)"
$optStatsLabel.Dock = "Bottom"
$optStatsLabel.Height = 30
$optStatsLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$optStatsLabel.Font = "Segoe UI, 9, Italic"
$optStatsLabel.ForeColor = [System.Drawing.Color]::DimGray
$optStatsLabel.BackColor = [System.Drawing.Color]::White
$global:ecoMode = $true
$toggleBtn = New-Object Windows.Forms.Button
$toggleBtn.Text = "MODE: ECO (Active)"
$toggleBtn.Dock = "Bottom"
$toggleBtn.Height = 45
$toggleBtn.FlatStyle = "Flat"
$toggleBtn.BackColor = $global:colorEco
$toggleBtn.ForeColor = "White"
$toggleBtn.Font = "Segoe UI, 9, Bold"
$toggleBtn.FlatAppearance.BorderSize = 0
$strip = New-Object Windows.Forms.StatusStrip
$lblRamTitle = New-Object Windows.Forms.ToolStripStatusLabel
$lblRamTitle.Text = " RAM Comp: "
$lblRamStatus = New-Object Windows.Forms.ToolStripStatusLabel
$lblOptTitle = New-Object Windows.Forms.ToolStripStatusLabel
$lblOptTitle.Text = "Optimizer: "
$lblOptTitle.Spring = $true
$lblOptTitle.TextAlign = [Drawing.ContentAlignment]::MiddleRight
$lblOptStatus = New-Object Windows.Forms.ToolStripStatusLabel
$lblOptStatus.Text = "ACTIVE "
$lblOptStatus.ForeColor = $global:colorEco
[void]$strip.Items.AddRange(@($lblRamTitle, $lblRamStatus, $lblOptTitle, $lblOptStatus))
$form.Controls.AddRange(@($list, $optStatsLabel, $toggleBtn, $strip))
# 4. ENGINE LOGIC
$global:lastProcHash = ""
# NOVÁ FUNKCE: Obnoví u všech sledovaných procesů plnou rychlost
function Reset-AllProcesses {
 $allProcs = Get-Process -ErrorAction SilentlyContinue
 foreach ($p in $allProcs) {
 if ($global:vault.Contains($p.ProcessName)) { 
 [WinAPI]::Optimize($p.Handle, $false) # Vynucení režimu NORMAL (eco = false)
 }
 }
}
function Invoke-Engine {
 try {
 [WinAPI]::SetPriorityClass([System.Diagnostics.Process]::GetCurrentProcess().Handle, 0x40)
 } catch {}
 try {
 $mm = Get-MMAgent
 $lblRamStatus.Text = if ($mm.MemoryCompression) { "ON" } else { "OFF" }
 $lblRamStatus.ForeColor = if ($mm.MemoryCompression) { $global:colorEco } else { $global:colorOff }
 } catch { $lblRamStatus.Text = "?" }
 for ($i=0; $i -lt $list.Items.Count; $i++) {
 $name = $list.Items[$i].ToString()
 if ($list.GetItemChecked($i)) { [void]$global:vault.Add($name) } else { [void]$global:vault.Remove($name) }
 }
 $allProcs = Get-Process -ErrorAction SilentlyContinue
 
 $optimizedCount = 0
 $totalOptimizedRam = 0
 foreach ($p in $allProcs) {
 if ($global:vault.Contains($p.ProcessName)) { 
 [WinAPI]::Optimize($p.Handle, $global:ecoMode)
 $optimizedCount++
 $totalOptimizedRam += $p.WorkingSet64
 }
 }
 $ramMb = [Math]::Round($totalOptimizedRam / 1MB, 0)
 $optStatsLabel.Text = "Optimized: $optimizedCount processes ($ramMb MB RAM)"
 $visibleProcs = $allProcs | Where-Object { 
 ($_.MainWindowHandle -ne 0 -or $_.ProcessName -match "WINWORD|EXCEL|OUTLOOK") -and 
 $_.Name -notmatch "explorer|taskmgr|pwsh|powershell" 
 }
 
 $currentHash = ($visibleProcs.Name -join ",")
 if ($currentHash -ne $global:lastProcHash) {
 $global:lastProcHash = $currentHash
 $list.BeginUpdate()
 $list.Items.Clear()
 $visibleProcs.Name | Select-Object -Unique | Sort-Object | ForEach-Object {
 [void]$list.Items.Add($_, $global:vault.Contains($_))
 }
 $list.EndUpdate()
 }
}
# 5. TRAY & EVENTS
$tray = New-Object Windows.Forms.NotifyIcon -Property @{ Icon=[System.Drawing.SystemIcons]::Application; Visible=$true; Text="AI RAM Engine" }
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Open", $null, { $form.Show(); $form.WindowState = 0; $form.Activate() })
# ZMĚNA: Tlačítko Exit vyvolá návrat procesů do plné rychlosti
[void]$menu.Items.Add("Exit", $null, { 
 $global:vault | Out-File $conf -Force
 Reset-AllProcesses
 $tray.Visible=$false
 [Windows.Forms.Application]::Exit() 
})
$tray.ContextMenuStrip = $menu
$tray.Add_MouseDoubleClick({ $form.Show(); $form.WindowState = 0; $form.Activate() })
$form.Add_FormClosing({ if ($tray.Visible) { $_.Cancel = $true; $form.Hide() }; $global:vault | Out-File $conf -Force })
$toggleBtn.Add_Click({
 $global:ecoMode = -not $global:ecoMode
 $toggleBtn.Text = if ($global:ecoMode) { "MODE: ECO (Active)" } else { "MODE: NORMAL (Full Speed)" }
 $toggleBtn.BackColor = if ($global:ecoMode) { $global:colorEco } else { $global:colorNormal } 
 Invoke-Engine
})
# ZMĚNA: Registrace čištění pro případ tvrdého ukončení procesu PowerShellu na pozadí
[AppDomain]::CurrentDomain.add_ProcessExit({
 $global:vault | Out-File $conf -Force
 Reset-AllProcesses
})
# 6. RUN
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 5000 }
$timer.Add_Tick({ Invoke-Engine })
$timer.Start()
Invoke-Engine
$h = [WinAPI]::GetConsoleWindow(); if ($h -ne 0) { [WinAPI]::ShowWindow($h, 0) }
[Windows.Forms.Application]::Run($form)
