# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Universal Pre-Wipe Hardware Diagnostic for Windows to Linux Migrations
# Outputs: Human-readable report + Arch/Fedora/NixOS-ready Hardware IDs
# Requires: PowerShell 5.1+ (default on Windows 10/11). Run as Administrator.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$OutputDir = "D:\_BACKUP_BEFORE_CLEAN"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportFile = Join-Path $OutputDir "HardwareReport_$timestamp.txt"
$DxDiagFile = Join-Path $OutputDir "dxdiag_$timestamp.txt"
$BatteryReport = Join-Path $OutputDir "BatteryReport_$timestamp.html"
$ArchIDsFile = Join-Path $OutputDir "Linux_HardwareIDs.txt"
$ArchDrvFile = Join-Path $OutputDir "Linux_Drivers_Firmware.txt"

$script:reportLines = [System.Collections.ArrayList]::new()
function Add-ReportLine($text) {
    [void]$script:reportLines.Add($text)
}

Add-ReportLine "================================================================================"
Add-ReportLine "   HARDWARE DIAGNOSTIC REPORT (Linux Migration)"
Add-ReportLine "   Generated : $(Get-Date)"
Add-ReportLine "   Computer  : $env:COMPUTERNAME"
Add-ReportLine "================================================================================"

Add-ReportLine "`n### 1. SYSTEM OVERVIEW ###"
$cs = Get-CimInstance Win32_ComputerSystem
$baseboard = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
$os = Get-CimInstance Win32_OperatingSystem

Add-ReportLine "Manufacturer : $($cs.Manufacturer)"
Add-ReportLine "Model        : $($cs.Model)"
Add-ReportLine "System Family: $($cs.SystemFamily)"
Add-ReportLine "Motherboard  : $($baseboard.Manufacturer) $($baseboard.Product) ($($baseboard.Version))"
Add-ReportLine "BIOS         : $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion), Date $($bios.ReleaseDate)"
Add-ReportLine "OS           : $($os.Caption) Build $($os.BuildNumber) $($os.OSArchitecture)"

Add-ReportLine "`n### 2. CPU (PROCESSOR) ###"
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Add-ReportLine "Name               : $($cpu.Name)"
Add-ReportLine "Cores / Threads    : $($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
Add-ReportLine "Max Clock Speed    : $($cpu.MaxClockSpeed) MHz"
Add-ReportLine "L2 Cache           : $([math]::Round($cpu.L2CacheSize/1024,1)) MB"
Add-ReportLine "L3 Cache           : $([math]::Round($cpu.L3CacheSize/1024,1)) MB"
Add-ReportLine "Architecture       : $($cpu.Architecture)"
Add-ReportLine "Socket             : $($cpu.SocketDesignation)"
Add-ReportLine "Virtualization     : $($cpu.VirtualizationFirmwareEnabled)"
Add-ReportLine "Processor ID       : $($cpu.ProcessorId)"

Add-ReportLine "`n### 3. MEMORY (RAM) ###"
$modules = Get-CimInstance Win32_PhysicalMemory
$totalRAM = ($modules | Measure-Object Capacity -Sum).Sum / 1GB
Add-ReportLine "Total installed    : $([math]::Round($totalRAM,2)) GB"
Add-ReportLine "Modules:"
if (-not $modules) { Add-ReportLine "  (No WMI data)" } else {
    $memTypeMap = @{20="DDR"; 21="DDR2"; 24="DDR3"; 26="DDR4"; 34="DDR5"; 0="Unknown"}
    foreach ($m in $modules) {
        $type = $memTypeMap[[int]$m.MemoryType]
        if (-not $type) { $type = "TypeCode=$($m.MemoryType)" }
        Add-ReportLine "  [$($m.DeviceLocator)] $($m.Manufacturer) $($m.PartNumber) | $([math]::Round($m.Capacity/1GB,2)) GB $type @ $($m.Speed) MHz, FormFactor=$($m.FormFactor)"
    }
}

Add-ReportLine "`n### 4. GRAPHICS (GPU) ###"
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Microsoft Basic' }
if (-not $gpus) { Add-ReportLine "No dedicated GPU found." } else {
    foreach ($gpu in $gpus) {
        $vram = if ($gpu.AdapterRAM) { [math]::Round($gpu.AdapterRAM/1GB,2) } else { "Unknown" }
        $res = "$($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution) @ $($gpu.CurrentRefreshRate) Hz"
        Add-ReportLine "$($gpu.Name)"
        Add-ReportLine "  VRAM        : $vram GB"
        Add-ReportLine "  Driver      : $($gpu.DriverVersion) ($($gpu.DriverDate))"
        Add-ReportLine "  Current Mode: $res"
        Add-ReportLine "  PNP DeviceID: $($gpu.PNPDeviceID)"
    }
}

Add-ReportLine "`n### 5. STORAGE DRIVES ###"
try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop
    foreach ($disk in $physDisks) {
        $size = [math]::Round($disk.Size/1GB,2)
        Add-ReportLine "$($disk.FriendlyName) | BusType: $($disk.BusType) | MediaType: $($disk.MediaType) | Size: $size GB | Health: $($disk.HealthStatus)"
    }
} catch {
    Add-ReportLine "(Physical disk info via Get-PhysicalDisk failed, using Win32_DiskDrive fallback)"
    $disks = Get-CimInstance Win32_DiskDrive
    foreach ($d in $disks) {
        $size = [math]::Round($d.Size/1GB,2)
        Add-ReportLine "$($d.Model) | Interface: $($d.InterfaceType) | Media: $($d.MediaType) | Size: $size GB"
    }
}
Add-ReportLine "Mounted volumes:"
Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3 | ForEach-Object {
    $free = [math]::Round($_.FreeSpace/1GB,2)
    $total = [math]::Round($_.Size/1GB,2)
    Add-ReportLine "  $($_.DeviceID) $($_.FileSystem) Total: $total GB, Free: $free GB"
}

Add-ReportLine "`n### 6. DISPLAY & MONITOR DETAILS ###"

function Parse-EDID([byte[]]$edidBytes) {
    if ($edidBytes.Count -lt 128) { return $null }
    if ($edidBytes[0..7] -ne [byte[]](0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x00)) { return $null }
    $manuf = [System.Text.Encoding]::ASCII.GetString($edidBytes[8..9])
    $prod  = [BitConverter]::ToUInt16($edidBytes[10..11],0)
    $ser   = [BitConverter]::ToUInt32($edidBytes[12..15],0)
    $week  = $edidBytes[16]
    $year  = 1990 + $edidBytes[17]
    $widthCm  = $edidBytes[21]
    $heightCm = $edidBytes[22]

    $prefRes = $null; $monName = ""
    for ($i=54; $i -le 108; $i+=18) {
        $blk = $edidBytes[$i..($i+17)]
        if ($blk[0..1] -eq 0 -and $blk[2] -eq 0) {
            $tag = $blk[3]
            if ($tag -eq 0xFC) {
                for ($j=5; $j -le 17; $j++) { if ($blk[$j] -eq 0x0A) { break }; $monName += [char]$blk[$j] }
            }
        } else {
            $pxClk = [BitConverter]::ToUInt16($blk[0..1],0) * 10000
            $hAct  = (($blk[4] -band 0xF0) -shl 4) + $blk[2]
            $hBlnk = (($blk[4] -band 0x0F) -shl 8) + $blk[3]
            $vAct  = (($blk[7] -band 0xF0) -shl 4) + $blk[5]
            $vBlnk = (($blk[7] -band 0x0F) -shl 8) + $blk[6]
            $refresh = [math]::Round($pxClk / (($hAct+$hBlnk)*($vAct+$vBlnk)), 1)
            $prefRes = [PSCustomObject]@{Width=$hAct; Height=$vAct; Refresh=$refresh}
        }
    }
    $diag = if ($widthCm -gt 0 -and $heightCm -gt 0) {
        [math]::Round([math]::Sqrt($widthCm*$widthCm + $heightCm*$heightCm) / 2.54, 1)
    } else { $null }

    return [PSCustomObject]@{
        MonitorName         = $monName.Trim()
        Manufacturer        = $manuf
        ProductCode         = "0x{0:X}" -f $prod
        Serial              = $ser
        ManufactureDate     = "$week/$year"
        PhysicalWidthCm     = $widthCm
        PhysicalHeightCm    = $heightCm
        DiagonalInches      = $diag
        PreferredResolution = if ($prefRes) { "$($prefRes.Width)x$($prefRes.Height) @ $($prefRes.Refresh) Hz" } else { "" }
    }
}

$monList = @()
$displayBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY"
if (Test-Path $displayBase) {
    Get-ChildItem $displayBase | Where-Object { $_.PSChildName -ne 'Default_Monitor' } | ForEach-Object {
        $modelPath = $_.PSPath
        Get-ChildItem $modelPath | ForEach-Object {
            $devParams = Join-Path $_.PSPath "Device Parameters"
            if (Test-Path $devParams) {
                $edid = (Get-ItemProperty -Path $devParams -Name "EDID" -ErrorAction SilentlyContinue).EDID
                if ($edid) {
                    $parsed = Parse-EDID -edidBytes $edid
                    if ($parsed) { $monList += $parsed }
                }
            }
        }
    }
}

if ($monList.Count -eq 0) {
    $wmiMonitors = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID
    foreach ($wm in $wmiMonitors) {
        $nameChars = $wm.UserFriendlyName | ForEach-Object { [char]$_ }
        $name = (-join $nameChars).Trim()
        $serialChars = $wm.SerialNumberID | ForEach-Object { [char]$_ }
        $serialNum = if ($wm.SerialNumberID -and $wm.SerialNumberID[0] -ne 0) { (-join $serialChars).Trim() } else { "" }
        $week = $wm.WeekOfManufacture
        $year = $wm.YearOfManufacture

        $diag = $null
        $basicParams = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBasicDisplayParams -Filter "InstanceName='$($wm.InstanceName)'"
        if ($basicParams) {
            $maxH = $basicParams.MaxHorizontalImageSize
            $maxV = $basicParams.MaxVerticalImageSize
            if ($maxH -gt 0 -and $maxV -gt 0) {
                $diag = [math]::Round([math]::Sqrt($maxH*$maxH + $maxV*$maxV) / 2.54, 1)
            }
        }
        $monList += [PSCustomObject]@{
            MonitorName         = $name
            Manufacturer        = -join [char[]]$wm.ManufacturerName
            ProductCode         = -join [char[]]$wm.ProductCodeID
            Serial              = $serialNum
            ManufactureDate     = "$week/$year"
            PhysicalWidthCm     = if ($basicParams) { $basicParams.MaxHorizontalImageSize } else { $null }
            PhysicalHeightCm    = if ($basicParams) { $basicParams.MaxVerticalImageSize } else { $null }
            DiagonalInches      = $diag
            PreferredResolution = ""
        }
    }
}

if ($monList.Count -eq 0) {
    Add-ReportLine "No EDID-capable monitors found."
} else {
    foreach ($m in $monList) {
        Add-ReportLine "Monitor: $($m.MonitorName)"
        Add-ReportLine "  EDID Info: $($m.Manufacturer) $($m.ProductCode), Serial=$($m.Serial), Made $($m.ManufactureDate)"
        Add-ReportLine "  Physical  : $($m.PhysicalWidthCm) x $($m.PhysicalHeightCm) cm  ->  Diagonal $($m.DiagonalInches) inch"
        if ($m.DiagonalInches -and $m.PreferredResolution -match '(\d+)x(\d+)') {
            $w = [int]$Matches[1]; $h = [int]$Matches[2]
            $ppi = [math]::Round([math]::Sqrt($w*$w + $h*$h) / $m.DiagonalInches, 1)
            Add-ReportLine "  Preferred : $($m.PreferredResolution)  |  PPI ~ $ppi"
        } else {
            Add-ReportLine "  Preferred : $($m.PreferredResolution)"
        }
    }
}

Add-ReportLine "`nCurrent Windows screen layout:"
try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
        $prim = if ($_.Primary) { "Primary" } else { "Secondary" }
        Add-ReportLine "  $($_.DeviceName) ($prim) : $($_.Bounds.Width)x$($_.Bounds.Height) at ($($_.Bounds.X),$($_.Bounds.Y))"
    }
} catch {
    Add-ReportLine "  (Unable to query screen info)"
}

Add-ReportLine "`n### 7. INPUT DEVICES ###"
$touchDev = Get-PnpDevice -Class HIDClass -PresentOnly | Where-Object { $_.FriendlyName -match 'touch' }
if ($touchDev) {
    Add-ReportLine "--- Touchscreen ---"
    foreach ($d in $touchDev) {
        $status = if ($d.Status -eq 'OK') { "OK" } else { "[Status: $($d.Status)]" }
        Add-ReportLine "  $($d.FriendlyName) $status  [Instance: $($d.InstanceId)]"
    }
} else { Add-ReportLine "Touchscreen: not detected." }

$touchpad = Get-PnpDevice -PresentOnly | Where-Object { ($_.Class -eq 'Mouse' -or $_.Class -eq 'HIDClass') -and $_.FriendlyName -match '(?i)touchpad|trackpad' }
if ($touchpad) {
    Add-ReportLine "--- Touchpad ---"
    foreach ($d in $touchpad) {
        $status = if ($d.Status -eq 'OK') { "OK" } else { "[Status: $($d.Status)]" }
        Add-ReportLine "  $($d.FriendlyName) $status  [Instance: $($d.InstanceId)]"
    }
} else { Add-ReportLine "Touchpad: not explicitly detected." }

Add-ReportLine "--- Mice & Keyboards ---"
Get-PnpDevice -Class 'Mouse','Keyboard' -PresentOnly | ForEach-Object {
    $status = if ($_.Status -eq 'OK') { "" } else { " [Status: $($_.Status)]" }
    Add-ReportLine "  $($_.Class): $($_.FriendlyName)$status"
}

Add-ReportLine "`n### 8. BIOMETRIC (Windows Hello Fingerprint) ###"
$bio = Get-PnpDevice -Class 'Biometric' -PresentOnly
if ($bio) {
    foreach ($d in $bio) {
        $status = if ($d.Status -eq 'OK') { "OK" } else { "[Status: $($d.Status)]" }
        Add-ReportLine "  $($d.FriendlyName) $status  [ID: $($d.InstanceId)]"
    }
} else { Add-ReportLine "No biometric devices found." }

Add-ReportLine "`n### 9. CAMERAS, IR & LASER DOT PROJECTORS ###"
$camClass = @('Camera','Image')
$cameras = Get-PnpDevice -Class $camClass -PresentOnly -ErrorAction SilentlyContinue
if ($cameras) {
    Add-ReportLine "--- Cameras ---"
    foreach ($c in $cameras) {
        $irTag = if ($c.FriendlyName -match '(?i)IR|Infrared') { " *** IR-CAMERA ***" } else { "" }
        $status = if ($c.Status -eq 'OK') { "" } else { " [Status: $($c.Status)]" }
        Add-ReportLine "  $($c.FriendlyName)$irTag$status  [ID: $($c.InstanceId)]"
    }
} else { Add-ReportLine "No camera/image devices found." }

$projectors = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match '(?i)laser|dot projector|IR projector|structure' }
if ($projectors) {
    Add-ReportLine "--- Laser / IR dot projector candidates ---"
    foreach ($p in $projectors) {
        $status = if ($p.Status -eq 'OK') { "" } else { " [Status: $($p.Status)]" }
        Add-ReportLine "  $($p.FriendlyName)$status  [Class: $($p.Class)]"
    }
} else { Add-ReportLine "Laser/IR projector: not detected separately." }

Add-ReportLine "`n--- Other Sensors ---"
$sensors = Get-PnpDevice -Class 'Sensor' -PresentOnly
if ($sensors) {
    foreach ($s in $sensors) {
        $status = if ($s.Status -eq 'OK') { "" } else { " [Status: $($s.Status)]" }
        Add-ReportLine "  $($s.FriendlyName)$status  [Type: $($s.Class)]"
    }
} else { Add-ReportLine "No additional sensor class devices." }

Add-ReportLine "`n### 10. AUDIO DEVICES ###"
Add-ReportLine "--- Microphones ---"
$mics = Get-PnpDevice -Class 'AudioEndpoint' -PresentOnly | Where-Object { $_.FriendlyName -match 'Microphone|mic' }
if ($mics) { foreach ($m in $mics) { Add-ReportLine "  $($m.FriendlyName)" } } else { Add-ReportLine "  None." }

Add-ReportLine "--- Speakers / Output ---"
$spks = Get-PnpDevice -Class 'AudioEndpoint' -PresentOnly | Where-Object { $_.FriendlyName -match 'Speaker|Headphone|Line out' }
if ($spks) { foreach ($s in $spks) { Add-ReportLine "  $($s.FriendlyName)" } } else { Add-ReportLine "  None." }

Add-ReportLine "--- Sound Controllers ---"
Get-CimInstance Win32_SoundDevice | ForEach-Object { Add-ReportLine "  $($_.Name)  [Mfr: $($_.Manufacturer)]" }

Add-ReportLine "`n### 11. NETWORK ADAPTERS ###"
try {
    Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
        Add-ReportLine "  $($_.Name) | $($_.InterfaceDescription) | MAC: $($_.MacAddress) | Status: $($_.Status) | Speed: $($_.LinkSpeed)"
    }
} catch { Add-ReportLine "  Unable to list adapters." }

Add-ReportLine "`n### 12. STORAGE CONTROLLER MODE ###"
$storageCtrls = Get-CimInstance Win32_SCSIController, Win32_IDEController -ErrorAction SilentlyContinue | Where-Object { $_.Name }
if ($storageCtrls) {
    foreach ($ctrl in $storageCtrls) {
        $vmdFlag = if ($ctrl.Name -match 'VMD|RST|RAID|Intel.*Controller') {
            "VMD/RST ENABLED (Linux needs 'vmd' module or BIOS switch to AHCI/NVMe)"
        } else { "Standard NVMe/AHCI" }
        Add-ReportLine "  $($ctrl.Name) | $vmdFlag | PNP: $($ctrl.PNPDeviceID)"
    }
} else { Add-ReportLine "  No SCSI/IDE controllers found." }

Add-ReportLine "`n### 13. DRIVER INVENTORY (DCH & INBOX) ###"
$thirdPartyRaw = pnputil /enum-drivers 2>$null | Out-String
if ($thirdPartyRaw -match "Published Name") {
    Add-ReportLine "--- Third-Party / DCH Drivers ---"
    $thirdPartyLines = $thirdPartyRaw -split "`r`n" | Where-Object { $_ -match "Published Name|Driver Version|Provider Name|Class Name" }
    foreach ($line in $thirdPartyLines) { Add-ReportLine "  $line" }
} else { Add-ReportLine "  No third-party drivers detected via pnputil." }

Add-ReportLine "--- Firmware Versions ---"
Get-PhysicalDisk | Where-Object MediaType -eq 'SSD' | ForEach-Object {
    Add-ReportLine "  SSD: $($_.FriendlyName) | FW: $($_.FirmwareVersion) | Serial: $($_.SerialNumber)"
}
Add-ReportLine "  BIOS: $($bios.SMBIOSBIOSVersion) | Date: $($bios.ReleaseDate)"

Add-ReportLine "`n### 14. WI-FI / BLUETOOTH CAPABILITIES ###"
try {
    $wlanDrv = netsh wlan show drivers 2>$null
    if ($wlanDrv) {
        $wlanDrv | Where-Object { $_ -match 'Radio|802.11|Channel|MIMO|Firmware' } | ForEach-Object { Add-ReportLine "  $_.Trim()" }
    } else { Add-ReportLine "  Could not retrieve WLAN driver info." }
} catch { Add-ReportLine "  netsh wlan unavailable." }

Add-ReportLine "`n### 15. RAW HARDWARE IDs (PCI/USB) FOR linux-hardware.org ###"
$criticalClasses = @('Display','Camera','Image','Biometric','HIDClass','Mouse','Net','Media','Sensor','DiskDrive','SCSIAdapter','System')
$rawIDs = [System.Collections.ArrayList]::new()

foreach ($cls in $criticalClasses) {
    Get-PnpDevice -Class $cls -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object {
        $id = $_.InstanceId
        if ($id -match '(?i)(PCI|USB|HID|ACPI)\\(VEN_[A-F0-9]+&DEV_[A-F0-9]+|VID_[A-F0-9]+&PID_[A-F0-9]+)') {
            $clean = $Matches[2]
            [void]$rawIDs.Add("$clean | $($_.FriendlyName) | Class: $cls")
        }
    }
}
$rawIDs | Sort-Object -Unique | ForEach-Object { Add-ReportLine "  $_" }

$headerIDs = "# Hardware IDs for linux-hardware.org and libfprint`n# Generated: $(Get-Date)`n"
$headerIDs + ($rawIDs | Sort-Object -Unique | Out-String) | Out-File $ArchIDsFile -Encoding UTF8

$drvLines = [System.Collections.ArrayList]::new()
[void]$drvLines.Add("# Driver and Firmware Summary for Linux Migration")
[void]$drvLines.Add("# Generated: $(Get-Date)")
[void]$drvLines.Add("")
[void]$drvLines.Add("=== STORAGE CONTROLLER MODE ===")
foreach ($ctrl in $storageCtrls) {
    $mode = if ($ctrl.Name -match 'VMD|RST|RAID') { "VMD/RAID" } else { "Standard" }
    [void]$drvLines.Add("$($ctrl.Name) : $mode")
}
[void]$drvLines.Add("")
[void]$drvLines.Add("=== FIRMWARE ===")
Get-PhysicalDisk | Where-Object MediaType -eq 'SSD' | ForEach-Object {
    [void]$drvLines.Add("SSD: $($_.FriendlyName) FW=$($_.FirmwareVersion) S/N=$($_.SerialNumber)")
}
[void]$drvLines.Add("BIOS: $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))")
[void]$drvLines.Add("")
[void]$drvLines.Add("=== CRITICAL DRIVERS (third-party) ===")
$thirdPartyLines | ForEach-Object { [void]$drvLines.Add($_) }
$drvLines | Out-File $ArchDrvFile -Encoding UTF8

Add-ReportLine "`n### 16. DxDiag REPORT ###"
Add-ReportLine "A separate DirectX diagnostic file is being created: $DxDiagFile"
$dxdiagProc = Start-Process -FilePath "dxdiag" -ArgumentList "/t `"$DxDiagFile`"" -Wait -NoNewWindow -PassThru
Add-ReportLine "DxDiag exit code: $($dxdiagProc.ExitCode)"

Add-ReportLine "`n### 17. BATTERY & POWER ###"
Add-ReportLine "Battery report saved to: $BatteryReport"
powercfg /batteryreport /output "`"$BatteryReport`"" 2>$null | Out-Null

Add-ReportLine "`n================================================================================"
Add-ReportLine "   END OF REPORT"
Add-ReportLine "================================================================================"
$script:reportLines | Out-File -FilePath $ReportFile -Encoding UTF8

Write-Host "Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "DxDiag saved to : $DxDiagFile" -ForegroundColor Green
Write-Host "Linux Hardware IDs saved to: $ArchIDsFile" -ForegroundColor Cyan
Write-Host "Linux Drivers/Firmware saved to: $ArchDrvFile" -ForegroundColor Cyan
Write-Host "Battery report saved to: $BatteryReport" -ForegroundColor Cyan
Write-Host "Done. You can now copy these files before wiping Windows." -ForegroundColor Magenta