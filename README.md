# win2linux-prewipe

![Windows](https://custom-icon-badges.demolab.com/badge/Windows-0078D6?logo=windows11&logoColor=white)
![PowerShell](https://custom-icon-badges.demolab.com/badge/PowerShell-0078D6?logo=powershell&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active%20development-orange)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![PowerShell Syntax Check](https://github.com/RadioPizza/win2linux-prewipe/actions/workflows/powershell-lint.yml/badge.svg)

**win2linux-prewipe** - Universal PowerShell hardware snapshot tool
for Windows-to-Linux migrations.

Collects raw Hardware IDs, EDID/PPI, storage controller mode,
firmware versions, and driver inventory **before wiping the system**.

## 🎯 Problem

Formatting the drive during OS installation destroys critical hardware context:

- Exact `VEN_XXXX&DEV_YYYY` / `VID_XXXX&PID_YYYY` (PCI/USB)
- Intel VMD/RST controller state (affects NVMe detection)
- EDID, physical display size, and calculated PPI
- IR cameras, dot projectors, fingerprint sensors
- SSD/BIOS firmware versions, third‑party drivers

This script preserves that data using **only built‑in Windows components**
– no external tools, no installation.

## 🚀 Quick Start

1. Open PowerShell **as Administrator**.
2. Run:

    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\scripts\Get-WinHardwareSnapshot.ps1
    ```

3. Wait for completion. All reports will be saved to `D:\_BACKUP_BEFORE_CLEAN\`.
    > Note: If your system does not have a D: drive,
    edit the $OutputDir variable inside the script before running,
    or run the script from a location where you have write access.

## 📂 Output Files

    | File | Description |
    |------|-------------|
    | `HardwareReport_*.txt` | Full human-readable diagnostic (CPU, RAM, GPU, displays, input, biometrics, audio, network) |
    | `Linux_HardwareIDs.txt` | Clean `VEN/VID` + device names. Ready for [linux-hardware.org](https://linux-hardware.org) and `libfprint` |
    | `Linux_Drivers_Firmware.txt` | Storage controller mode (VMD/AHCI), SSD/BIOS firmware, third‑party drivers (including DCH) |
    | `dxdiag_*.txt` | Complete DirectX Diagnostic Tool dump |
    | `BatteryReport_*.html` | Battery wear, cycle count, and capacity history (`powercfg`) |

## ⚙️ Requirements

- Windows 10/11
- PowerShell 5.1+ (default)
- Administrator privileges (required for PnP, Storage, EDID registry, `pnputil`)

## 🤝 Contributing

If a device is missed or misidentified:

1. Attach `Linux_HardwareIDs.txt` and the relevant report section
2. Specify exact laptop/motherboard model
3. Open an Issue or PR with a regex or WMI fallback patch

## 📜 License

MIT. See [LICENSE](LICENSE) for details.
