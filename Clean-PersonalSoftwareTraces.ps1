#requires -version 5.1
<#
Portable cleaner for local personal traces of selected Windows apps.

Default mode is Discover and deletes nothing. Clean mode requires typing CLEAN.
Copy this file together with Run-Clean-As-Admin.bat to the target computer.
#>

[CmdletBinding()]
param(
  [ValidateSet("Discover","Clean")]
  [string]$Mode = "Discover",
  [string[]]$Drives = @("C","D"),
  [switch]$KillProcesses,
  [switch]$NoPrompt
)

$ErrorActionPreference = "Continue"

function Say($Text, $Color = "Gray") { Write-Host $Text -ForegroundColor $Color }
function Info($Text) { Say "[INFO] $Text" "Cyan" }
function Warn($Text) { Say "[WARN] $Text" "Yellow" }
function Xp($Path) { [Environment]::ExpandEnvironmentVariables($Path) }

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function T {
  param(
    [string]$App,
    [string]$Path,
    [ValidateSet("File","Directory","RegistryKey","RegistryValue")]
    [string]$Type = "Directory",
    [string]$ValueName = ""
  )
  [pscustomobject]@{
    App = $App
    Type = $Type
    Path = (Xp $Path)
    ValueName = $ValueName
  }
}

function Stop-Apps {
  $names = @(
    "acad","AcLauncher","3dsmax","SketchUp","Rhino","Photoshop",
    "Creative Cloud","SunloginClient","SunloginRemote","AweSun",
    "WeChat","Weixin","QQ","TIM","BaiduNetdisk","Feishu","Lark",
    "LarkShell","D5 Render","D5Render","MindMaster","EdrawMind",
    "WPS","wps","et","wpp","WINWORD","EXCEL","POWERPNT","OUTLOOK",
    "ONENOTE","JianyingPro","CapCut","chrome","msedge","wemeetapp",
    "TencentMeeting","Eagle","KuJiaLe","Coohom"
  ) | Select-Object -Unique

  foreach ($name in $names) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
      Warn "Closing process: $($_.ProcessName) ($($_.Id))"
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

function Resolve-Target {
  param([object]$Target)
  if ($Target.Path.Contains("*")) {
    Get-ChildItem -Path $Target.Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.PSProvider.Name -eq "Registry") {
        T $Target.App $_.PSPath "RegistryKey"
      } else {
        $kind = if ($_.PSIsContainer) { "Directory" } else { "File" }
        T $Target.App $_.FullName $kind
      }
    }
  } else {
    $Target
  }
}

function Exists {
  param([object]$Target)
  if ($Target.Type -eq "RegistryValue") {
    if (-not (Test-Path -LiteralPath $Target.Path)) { return $false }
    return $null -ne (Get-ItemProperty -LiteralPath $Target.Path -Name $Target.ValueName -ErrorAction SilentlyContinue)
  }
  Test-Path -LiteralPath $Target.Path
}

function Is-ProtectedTarget {
  param([object]$Target)

  if ($Target.Type -eq "RegistryKey" -or $Target.Type -eq "RegistryValue") {
    $p = $Target.Path
    if ($p -like "Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\*") { return $true }
    if ($p -like "HKLM:\*") { return $true }
    return $false
  }

  try {
    $full = [IO.Path]::GetFullPath($Target.Path).TrimEnd("\")
  } catch {
    return $true
  }

  $windows = [IO.Path]::GetFullPath($env:WINDIR).TrimEnd("\")
  $pf = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd("\")
  $pf86Raw = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  $pf86 = if ($pf86Raw) { [IO.Path]::GetFullPath($pf86Raw).TrimEnd("\") } else { "" }
  $programData = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd("\")

  $blockedRoots = @($windows, $pf, $pf86) | Where-Object { $_ }
  foreach ($root in $blockedRoots) {
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($root + "\", [StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  if ($full.Equals($programData, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  if ($full.StartsWith($programData + "\", [StringComparison]::OrdinalIgnoreCase)) {
    $allowedProgramData = @(
      (Join-Path $programData "Oray"),
      (Join-Path $programData "AweSun"),
      (Join-Path $programData "Autodesk\CLM\LGS"),
      (Join-Path $programData "Autodesk\Adlm")
    ) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd("\") }

    foreach ($allowed in $allowedProgramData) {
      if ($full.Equals($allowed, [StringComparison]::OrdinalIgnoreCase) -or
          $full.StartsWith($allowed + "\", [StringComparison]::OrdinalIgnoreCase)) {
        return $false
      }
    }
    return $true
  }

  $installLikeNames = @(
    "Software","Soft","Apps","App","Applications","Tools","DesignTools",
    "Program","Programs","Program Files","Program Files (x86)"
  )
  $parts = $full -split "[\\/]"
  foreach ($part in $parts) {
    if ($installLikeNames -contains $part) { return $true }
  }

  return $false
}

function Delete-Target {
  param([object]$Target)
  if (Is-ProtectedTarget $Target) {
    Warn "Protected path skipped: $($Target.Path)"
    return
  }
  try {
    switch ($Target.Type) {
      "File" {
        if (Test-Path -LiteralPath $Target.Path -PathType Leaf) {
          Remove-Item -LiteralPath $Target.Path -Force -ErrorAction Stop
        }
      }
      "Directory" {
        if (Test-Path -LiteralPath $Target.Path -PathType Container) {
          Remove-Item -LiteralPath $Target.Path -Recurse -Force -ErrorAction Stop
        }
      }
      "RegistryKey" {
        if (Test-Path -LiteralPath $Target.Path) {
          Remove-Item -LiteralPath $Target.Path -Recurse -Force -ErrorAction Stop
        }
      }
      "RegistryValue" {
        if (Test-Path -LiteralPath $Target.Path) {
          Remove-ItemProperty -LiteralPath $Target.Path -Name $Target.ValueName -Force -ErrorAction Stop
        }
      }
    }
  } catch {
    Warn "Failed: $($Target.Path) - $($_.Exception.Message)"
    $script:DeleteFailures += [pscustomobject]@{
      App = $Target.App
      Type = $Target.Type
      Path = $Target.Path
      Reason = $_.Exception.Message
    }
  }
}

function Is-DiscoveredPathAllowed {
  param([string]$Path)

  $leaf = Split-Path -Leaf $Path
  $allowedLeaves = @(
    "WeChat Files","Tencent Files","QQ Files","BaiduNetdiskDownload",
    "com.lveditor.draft","Cache","User Data","Projects","Project",
    "D5 Render","D5Render","d5_immerse","SunloginClient","AweSun",
    "Oray","LarkShell","Feishu","Lark","Kingsoft","WPS Cloud Files"
  )

  foreach ($allowed in $allowedLeaves) {
    if ($leaf -ieq $allowed -or $leaf -like $allowed) { return $true }
  }

  if ($Path -like "*\AppData\Roaming\*" -or $Path -like "*\AppData\Local\*") { return $true }
  return $false
}

function Find-NamedDirs {
  param([string[]]$Roots, [string[]]$Names, [int]$MaxDepth = 7)

  $skip = @(
    "Windows","Users","Program Files","Program Files (x86)","ProgramData",
    "System Volume Information","`$Recycle.Bin","Recovery","PerfLogs",
    "WindowsApps","MSOCache"
  )

  $q = New-Object System.Collections.Queue
  foreach ($root in $Roots) {
    if (Test-Path -LiteralPath $root -PathType Container) {
      $q.Enqueue([pscustomobject]@{ Path = (Resolve-Path -LiteralPath $root).Path; Depth = 0 })
    }
  }

  while ($q.Count -gt 0) {
    $cur = $q.Dequeue()
    if ($cur.Depth -ge $MaxDepth) { continue }

    Get-ChildItem -LiteralPath $cur.Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
      if ($skip -contains $_.Name) { return }

      foreach ($name in $Names) {
        if ($_.Name -ieq $name -or $_.Name -like $name) {
          $_.FullName
          break
        }
      }

      $q.Enqueue([pscustomobject]@{ Path = $_.FullName; Depth = $cur.Depth + 1 })
    }
  }
}

function App-FromLeaf {
  param([string]$Leaf)
  switch -Wildcard ($Leaf) {
    "WeChat Files" { "WeChat"; break }
    "Tencent Files" { "QQ"; break }
    "QQ Files" { "QQ"; break }
    "Baidu*" { "BaiduNetdisk"; break }
    "D5*" { "D5 Render"; break }
    "Jianying*" { "Jianying"; break }
    "com.lveditor.draft" { "Jianying"; break }
    "CapCut" { "CapCut"; break }
    "Autodesk" { "Autodesk"; break }
    "AutoCAD" { "Autodesk"; break }
    "3dsMax" { "Autodesk"; break }
    "SketchUp" { "SketchUp"; break }
    "Kujiale" { "Kujiale"; break }
    "Coohom" { "Kujiale"; break }
    "Rhino" { "Rhino"; break }
    "McNeel" { "Rhino"; break }
    "Feishu" { "Feishu"; break }
    "Lark*" { "Feishu"; break }
    "Kingsoft" { "WPS"; break }
    "WPS*" { "WPS"; break }
    "EdrawMind" { "EdrawMind"; break }
    "MindMaster" { "EdrawMind"; break }
    "Sunlogin*" { "Sunlogin"; break }
    "AweSun" { "Sunlogin"; break }
    "Oray" { "Sunlogin"; break }
    default { $Leaf }
  }
}

function Installed-Hints {
  $patterns = @(
    "Autodesk","AutoCAD","3ds Max","3dsMax","SketchUp","Rhino",
    "Photoshop","Adobe","D5","Sunlogin","AweSun","WeChat","QQ",
    "BaiduNetdisk","Feishu","Lark","WPS","Office","Microsoft 365",
    "Jianying","CapCut","Eagle","EdrawMind","MindMaster","Kujiale",
    "Coohom"
  )
  $keys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  foreach ($key in $keys) {
    Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | ForEach-Object {
      if ([string]::IsNullOrWhiteSpace($_.DisplayName)) { return }
      foreach ($p in $patterns) {
        if ($_.DisplayName -like "*$p*") {
          [pscustomobject]@{ Name = $_.DisplayName; InstallLocation = $_.InstallLocation }
          break
        }
      }
    }
  }
}

function Standard-Targets {
  $tgt = @()
  $kujialeCn = -join ([char[]](0x9177,0x5BB6,0x4E50))
  $jianyingCn = -join ([char[]](0x526A,0x6620,0x4E13,0x4E1A,0x7248))
  $banjiajiaCn = -join ([char[]](0x626E,0x5BB6,0x5BB6))
  $liuyunkuCn = -join ([char[]](0x6E9C,0x4E91,0x5E93))

  $tgt += T "Autodesk" "%APPDATA%\Autodesk"
  $tgt += T "Autodesk" "%LOCALAPPDATA%\Autodesk"
  $tgt += T "Autodesk" "%PROGRAMDATA%\Autodesk\CLM\LGS"
  $tgt += T "Autodesk" "%PROGRAMDATA%\Autodesk\Adlm"
  $tgt += T "Autodesk" "HKCU:\Software\Autodesk\AutoCAD\Recent File List" "RegistryKey"
  $tgt += T "Autodesk" "HKCU:\Software\Autodesk\3dsMax" "RegistryKey"

  $tgt += T "SketchUp" "%APPDATA%\SketchUp"
  $tgt += T "SketchUp" "%LOCALAPPDATA%\SketchUp"
  $tgt += T "SketchUp" "HKCU:\Software\SketchUp" "RegistryKey"
  $tgt += T "Rhino" "%APPDATA%\McNeel"
  $tgt += T "Rhino" "%LOCALAPPDATA%\McNeel"
  $tgt += T "Rhino" "HKCU:\Software\McNeel" "RegistryKey"

  $tgt += T "Photoshop" "%APPDATA%\Adobe\Adobe Photoshop*"
  $tgt += T "Photoshop" "%APPDATA%\Adobe\Common\Media Cache"
  $tgt += T "Photoshop" "%LOCALAPPDATA%\Adobe\CameraRaw\Cache"
  $tgt += T "Photoshop" "%LOCALAPPDATA%\Adobe\Creative Cloud Libraries"
  $tgt += T "Photoshop" "%LOCALAPPDATA%\Adobe\OOBE"
  $tgt += T "Photoshop" "%APPDATA%\Adobe\OOBE"

  foreach ($n in @("Kujiale","Coohom","D5 Render","D5Render","Banjiajia","Liuyunku",$kujialeCn,$banjiajiaCn,$liuyunkuCn)) {
    $app = if ($n -like "D5*") { "D5 Render" } elseif ($n -in @("Kujiale","Coohom",$kujialeCn)) { "Kujiale" } elseif ($n -in @("Banjiajia",$banjiajiaCn)) { "Banjiajia" } elseif ($n -in @("Liuyunku",$liuyunkuCn)) { "Liuyunku" } else { $n }
    $tgt += T $app "%APPDATA%\$n"
    $tgt += T $app "%LOCALAPPDATA%\$n"
  }
  $tgt += T "D5 Render" "%APPDATA%\temp\D5"
  $tgt += T "D5 Render" "%LOCALAPPDATA%\d5_immerse"

  $tgt += T "Sunlogin" "%APPDATA%\SunloginClient"
  $tgt += T "Sunlogin" "%LOCALAPPDATA%\SunloginClient"
  $tgt += T "Sunlogin" "%PROGRAMDATA%\Oray"
  $tgt += T "Sunlogin" "%PROGRAMDATA%\AweSun"

  $tgt += T "WeChat" "%APPDATA%\Tencent\WeChat"
  $tgt += T "WeChat" "%LOCALAPPDATA%\Tencent\WeChat"
  $tgt += T "WeChat" "%USERPROFILE%\Documents\WeChat Files"
  $tgt += T "QQ" "%APPDATA%\Tencent\QQ"
  $tgt += T "QQ" "%LOCALAPPDATA%\Tencent\QQ"
  $tgt += T "QQ" "%USERPROFILE%\Documents\Tencent Files"

  $tgt += T "BaiduNetdisk" "%APPDATA%\Baidu\BaiduNetdisk"
  $tgt += T "BaiduNetdisk" "%LOCALAPPDATA%\Baidu\BaiduNetdisk"
  $tgt += T "BaiduNetdisk" "%USERPROFILE%\BaiduNetdiskDownload"

  foreach ($n in @("LarkShell","Feishu","Lark")) {
    $tgt += T "Feishu" "%APPDATA%\$n"
    $tgt += T "Feishu" "%LOCALAPPDATA%\$n"
  }

  $tgt += T "TencentMeeting" "%APPDATA%\Tencent\WeMeet"
  $tgt += T "TencentMeeting" "%LOCALAPPDATA%\Tencent\WeMeet"

  $tgt += T "WPS" "%APPDATA%\Kingsoft"
  $tgt += T "WPS" "%LOCALAPPDATA%\Kingsoft"
  $tgt += T "WPS" "HKCU:\Software\Kingsoft\Office" "RegistryKey"
  $tgt += T "Office" "%APPDATA%\Microsoft\Office\Recent"
  $tgt += T "Office" "%APPDATA%\Microsoft\Office\UnsavedFiles"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\Office\16.0\OfficeFileCache"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\Office\15.0\OfficeFileCache"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\Office\16.0\Licensing"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\Office\15.0\Licensing"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\OneAuth"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\IdentityCache"
  $tgt += T "Office" "%LOCALAPPDATA%\Microsoft\TokenBroker"
  $tgt += T "Office" "HKCU:\Software\Microsoft\Office\*\*\File MRU" "RegistryKey"
  $tgt += T "Office" "HKCU:\Software\Microsoft\Office\*\*\Place MRU" "RegistryKey"
  $tgt += T "Office" "HKCU:\Software\Microsoft\Office\16.0\Common\Identity" "RegistryKey"
  $tgt += T "Office" "HKCU:\Software\Microsoft\Office\15.0\Common\Identity" "RegistryKey"

  foreach ($n in @("JianyingPro",$jianyingCn,"CapCut","EdrawMind","MindMaster","Eagle")) {
    $app = if ($n -eq "JianyingPro" -or $n -eq $jianyingCn) { "Jianying" } elseif ($n -eq "MindMaster") { "EdrawMind" } else { $n }
    $tgt += T $app "%APPDATA%\$n"
    $tgt += T $app "%LOCALAPPDATA%\$n"
  }
  $tgt += T "Jianying" "%LOCALAPPDATA%\JianyingPro\User Data\Projects\com.lveditor.draft"
  $tgt += T "Jianying" "%LOCALAPPDATA%\JianyingPro\User Data\Cache"

  $tgt += T "Chrome" "%LOCALAPPDATA%\Google\Chrome\User Data"
  $tgt += T "Edge" "%LOCALAPPDATA%\Microsoft\Edge\User Data"
  $tgt
}

function Discovered-Targets {
  $roots = @()
  if (Test-Path -LiteralPath $env:USERPROFILE) { $roots += $env:USERPROFILE }
  foreach ($d in $Drives) {
    $r = "$($d.TrimEnd(':')):\"
    if (Test-Path -LiteralPath $r) { $roots += $r }
  }
  $roots = $roots | Select-Object -Unique

  $names = @(
    "WeChat Files","Tencent Files","QQ Files","BaiduNetdiskDownload",
    "BaiduNetdisk","D5 Render","D5Render",
    "JianyingPro","com.lveditor.draft","CapCut",
    "Kujiale","Coohom","Photoshop","Rhino","McNeel","Feishu","Lark",
    "LarkShell","WPS Cloud Files","Kingsoft","EdrawMind","MindMaster",
    "SunloginClient","AweSun","Oray","Liuyunku","Banjiajia"
  )

  Find-NamedDirs -Roots $roots -Names $names -MaxDepth 7 |
    Select-Object -Unique |
    Where-Object { Is-DiscoveredPathAllowed $_ } |
    ForEach-Object { T (App-FromLeaf (Split-Path -Leaf $_)) $_ "Directory" }
}

$admin = Is-Admin
Say ""
Say "Portable personal software trace cleaner" "Green"
Say "Mode: $Mode"
Say "User: $env:USERNAME"
Say "Profile: $env:USERPROFILE"
Say "Drives scanned for data folders: $($Drives -join ', ')"
Say "Administrator: $admin"
Say ""

if (-not $admin) {
  Warn "Not running as administrator. ProgramData and system-level traces may remain."
}

if ($Mode -eq "Clean" -and $KillProcesses) {
  Stop-Apps
} elseif ($Mode -eq "Clean") {
  Warn "Target applications should be closed. Use -KillProcesses for stronger cleanup."
}

$script:DeleteFailures = @()
$all = @()
$all += Standard-Targets
$all += Discovered-Targets
$resolved = foreach ($x in $all) { Resolve-Target $x }
$existing = $resolved |
  Where-Object { $_ -and (Exists $_) } |
  Sort-Object App, Type, Path, ValueName -Unique
$blocked = $existing | Where-Object { Is-ProtectedTarget $_ }
$cleanable = $existing | Where-Object { -not (Is-ProtectedTarget $_) }

$hints = Installed-Hints | Sort-Object Name -Unique
if ($hints) {
  Say ""
  Say "Installed app hints found:" "DarkCyan"
  foreach ($h in $hints) {
    $loc = if ($h.InstallLocation) { $h.InstallLocation } else { "(no install path)" }
    Say ("  - {0} :: {1}" -f $h.Name, $loc)
  }
}

Say ""
Say "Matched cleanup targets:" "DarkCyan"
if (-not $cleanable) {
  Warn "No cleanable traces were found."
  if ($blocked) {
    Say ""
    Say "Protected targets skipped:" "Yellow"
    foreach ($x in $blocked) {
      Say ("  [{0}] {1} {2}" -f $x.App, $x.Type, $x.Path)
    }
  }
  exit 0
}

foreach ($x in $cleanable) {
  $label = if ($x.Type -eq "RegistryValue") { "$($x.Path) :: $($x.ValueName)" } else { $x.Path }
  Say ("  [{0}] {1} {2}" -f $x.App, $x.Type, $label)
}
Say ""
Say ("Total cleanable targets: {0}" -f $cleanable.Count)

if ($blocked) {
  Say ""
  Say "Protected targets skipped:" "Yellow"
  foreach ($x in $blocked) {
    Say ("  [{0}] {1} {2}" -f $x.App, $x.Type, $x.Path)
  }
  Say ("Total protected targets skipped: {0}" -f $blocked.Count)
}

if ($Mode -eq "Discover") {
  Info "Discover mode only. Nothing was deleted. Run Run-Clean-As-Admin.bat to clean."
  exit 0
}

if (-not $NoPrompt) {
  Say ""
  Warn "Clean mode will permanently delete all matched targets above. No backup and no log will be created."
  $answer = Read-Host "Type CLEAN to continue"
  if ($answer -cne "CLEAN") {
    Warn "Cancelled. Nothing was deleted."
    exit 1
  }
}

foreach ($x in $cleanable) {
  Say ("Deleting [{0}] {1}" -f $x.App, $x.Path)
  Delete-Target $x
}

$failed = $cleanable | Where-Object { Exists $_ }
$allFailureApps = @()
if ($script:DeleteFailures) {
  $allFailureApps += $script:DeleteFailures | Select-Object -ExpandProperty App
}
if ($failed) {
  $allFailureApps += $failed | Select-Object -ExpandProperty App
}

if ($allFailureApps) {
  Say ""
  Warn "Some apps were not fully cleaned."
  Say "Apps with remaining traces:" "Yellow"
  $failedApps = $allFailureApps | Sort-Object -Unique
  foreach ($app in $failedApps) {
    Say ("  - {0}" -f $app) "Yellow"
  }

  if ($script:DeleteFailures) {
    Say ""
    Say "Delete errors:" "Yellow"
    foreach ($x in $script:DeleteFailures) {
      Say ("  [{0}] {1} {2} :: {3}" -f $x.App, $x.Type, $x.Path, $x.Reason) "Yellow"
    }
  }

  Say ""
  if ($failed) {
    Say "Remaining targets still found after deletion:" "Yellow"
    foreach ($x in $failed) {
      Say ("  [{0}] {1} {2}" -f $x.App, $x.Type, $x.Path) "Yellow"
    }
  }
} else {
  Say ""
  Info "All matched cleanable targets were removed."
}

Say ""
Info "Done. Restart Windows before opening the cleaned applications."
