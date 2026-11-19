param(
    [string]$InstallDir,
    # Internal: used by the detached background run that fills in EstimatedSize.
    [switch]$UpdateSizeOnly
)

$AppName = "OsdagBridge"
$Version = "1.0.0"
$AppExe = Join-Path $InstallDir "Scripts\osdagbridge.exe"
$Launcher = Join-Path $InstallDir "launch_osdagbridge.vbs"
$UninstallExe = Join-Path $InstallDir "Uninstall-$AppName.exe"
$IconFile = Join-Path $InstallDir "icon.ico"

# Is the current user an administrator (all-users install) ?
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $StartMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$AppName"
    $DesktopPath = Join-Path $env:Public "Desktop"
} else {
    $StartMenuDir = Join-Path $env:AppData "Microsoft\Windows\Start Menu\Programs\$AppName"
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
}

# ---- Background mode: compute the real install size for "Installed apps" ----
if ($UpdateSizeOnly) {
    # Skip pkgs\: the package cache still exists while post_install runs and is
    # deleted by the installer right afterwards, so it must not be counted.
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $root = $fso.GetFolder($InstallDir)
    $bytes = 0
    foreach ($f in $root.Files) { $bytes += $f.Size }
    foreach ($d in $root.SubFolders) {
        if ($d.Name -ne "pkgs") { $bytes += $d.Size }
    }
    $realKB = [int][math]::Round($bytes / 1KB)

    if ($isAdmin) {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $subKey = $baseKey.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppName", $true)
        if ($subKey) {
            $subKey.SetValue("EstimatedSize", $realKB, [Microsoft.Win32.RegistryValueKind]::DWord)
            $subKey.Close()
        }
        $baseKey.Close()
    } else {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
        if (Test-Path $key) {
            New-ItemProperty -Path $key -Name "EstimatedSize" -Value $realKB -PropertyType DWord -Force | Out-Null
        }
    }
    exit 0
}

if (!(Test-Path $StartMenuDir)) {
    New-Item -ItemType Directory -Path $StartMenuDir | Out-Null
}
if (!(Test-Path $DesktopPath)) {
    New-Item -ItemType Directory -Path $DesktopPath | Out-Null
}

$Shell = New-Object -ComObject WScript.Shell

# ---- Desktop Shortcut ----
$Shortcut = $Shell.CreateShortcut("$DesktopPath\$AppName.lnk")
$Shortcut.TargetPath = $Launcher
$Shortcut.WorkingDirectory = "$InstallDir"
$Shortcut.IconLocation = "$IconFile,0"
$Shortcut.Save()

# ---- Start Menu Shortcut ----
$Shortcut = $Shell.CreateShortcut("$StartMenuDir\$AppName.lnk")
$Shortcut.TargetPath = $Launcher
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.IconLocation = "$IconFile,0"
$Shortcut.Save()

# ---- Registry Entry for Add/Remove Programs ----
# EstimatedSize is only shown in "Installed apps". Walking the tens of thousands
# of files in the environment (previously Get-ChildItem -Recurse) blocked the
# installer for minutes, so write a placeholder now and let a hidden background
# process replace it with the real size (see the end of this script).
$SizeKB = 4500000  # ~4.5 GB placeholder

if ($isAdmin) {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $subKey = $baseKey.CreateSubKey(
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
    )
    $subKey.SetValue("DisplayName", $AppName)
    $subKey.SetValue("UninstallString", "`"$UninstallExe`"")
    $subKey.SetValue("DisplayIcon", $IconFile)
    $subKey.SetValue("Publisher", "Osdag, FOSSEE")
    $subKey.SetValue("DisplayVersion", $Version)
    $subKey.SetValue("InstallLocation", $InstallDir)
    $subKey.SetValue("HelpLink", "https://osdag.fossee.in/")
    $subKey.SetValue("EstimatedSize", $SizeKB, [Microsoft.Win32.RegistryValueKind]::DWord)
    $subKey.Close()
    $baseKey.Close()
} else {
    $UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
    New-Item -Path $UninstallKey -Force | Out-Null
    Set-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value $AppName
    Set-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "`"$UninstallExe`""
    Set-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value $IconFile
    Set-ItemProperty -Path $UninstallKey -Name "Publisher" -Value "Osdag, FOSSEE"
    Set-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value $Version
    Set-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir
    Set-ItemProperty -Path $UninstallKey -Name "HelpLink" -Value "https://osdag.fossee.in/"
    New-ItemProperty -Path $UninstallKey -Name "EstimatedSize" -Value $SizeKB -PropertyType DWord -Force | Out-Null
}

# ---- Accurate EstimatedSize, computed without blocking the installer ----
try {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -WindowStyle Hidden `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", "`"$PSCommandPath`"",
                        "-InstallDir", "`"$InstallDir`"",
                        "-UpdateSizeOnly")
} catch {
    # Cosmetic only; keep the placeholder size.
}
