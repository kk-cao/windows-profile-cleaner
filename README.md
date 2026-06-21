# Windows Profile Cleaner

Portable Windows 10 cleanup scripts for removing local personal usage traces from selected desktop applications.

## What It Cleans

The cleaner targets local user traces such as:

- AppData configuration and cache folders
- local account and sync state
- browser profiles, history, cookies, saved passwords, bookmarks, and extension local data
- Office/WPS identity cache and recent-file state
- WeChat/QQ local files under common user folders
- common C/D drive data folders for selected apps
- selected ProgramData traces for Oray/AweSun and Autodesk licensing cache

Covered application families include Autodesk AutoCAD, 3ds Max, SketchUp, Rhino, Photoshop, D5 Render, Kujiale/Coohom, Sunlogin/AweSun, WeChat, QQ, Baidu Netdisk, Feishu/Lark, WPS, Microsoft Office, Jianying/CapCut, EdrawMind/MindMaster, Eagle app state, Chrome, Edge, Tencent Meeting, Liuyunku, and Banjiajia.

Eagle user libraries are not automatically deleted. Remove them manually if needed.

## Safety Model

The script is designed to remove traces, not uninstall applications.

It does not call uninstallers and does not delete:

- `C:\Windows`
- `C:\Program Files`
- `C:\Program Files (x86)`
- `WindowsApps`
- `HKLM` registry keys
- non-whitelisted `ProgramData` folders

For Edge, it removes only the user profile folder:

```text
%LOCALAPPDATA%\Microsoft\Edge\User Data
```

It does not remove the Edge application folder.

## Files

- `Clean-PersonalSoftwareTraces.ps1` - main PowerShell cleaner
- `Run-Clean-As-Admin.bat` - administrator launcher for normal use

## Usage

Copy both script files to the target computer in the same folder.

Recommended:

1. Right-click `Run-Clean-As-Admin.bat`.
2. Choose "Run as administrator".
3. Review the matched cleanup targets.
4. Type `CLEAN` to confirm deletion.
5. Restart Windows after cleanup.

Preview only:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Clean-PersonalSoftwareTraces.ps1"
```

Manual clean:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Clean-PersonalSoftwareTraces.ps1" -Mode Clean -KillProcesses
```

## Notes

This tool cleans local traces only. It cannot revoke cloud-side sessions from Google, Microsoft, Adobe, Autodesk, or other providers. Use the provider's account security page if you need to revoke a device remotely.

No backup or log is created by design.
