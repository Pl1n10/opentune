<#
.SYNOPSIS
    DSC Configuration for "pc-genitori" node

.DESCRIPTION
    This is the main entry point for the "pc-genitori" Windows machine.
    It imports baseline configurations and adds node-specific settings.

    In dsc-cp, set config_path = "nodes/pc-genitori.ps1"

.NOTES
    Part of dsc-cp example configurations
#>

# =============================================================================
# Import Baseline Configurations
# =============================================================================

# Get the script's directory for relative imports
$scriptDir = $PSScriptRoot

# Import baseline configuration definitions
. "$scriptDir\..\baselines\common.ps1"
. "$scriptDir\..\baselines\security.ps1"

# =============================================================================
# Compile Baseline MOFs
# =============================================================================

# Create output directory structure
$mofOutputBase = "$scriptDir\..\mof\pc-genitori"

# Ensure output directories exist
if (-not (Test-Path $mofOutputBase)) {
    New-Item -Path $mofOutputBase -ItemType Directory -Force | Out-Null
}

# Compile baseline configurations
Write-Host "Compiling CommonBaseline..."
CommonBaseline -OutputPath "$mofOutputBase\common"

Write-Host "Compiling SecurityBaseline..."
SecurityBaseline -OutputPath "$mofOutputBase\security"

# =============================================================================
# Node-Specific Configuration
# =============================================================================

Configuration PcGenitori {
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node "localhost" {

        # =====================================================================
        # Privacy Settings - Disable Cortana
        # =====================================================================
        Registry DisableCortana {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            ValueName = "AllowCortana"
            ValueType = "Dword"
            ValueData = 0
            Ensure    = "Present"
        }

        # Disable web search in Start Menu
        Registry DisableWebSearch {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            ValueName = "DisableWebSearch"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Disable Telemetry (Basic level)
        # =====================================================================
        Registry TelemetryBasic {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            ValueName = "AllowTelemetry"
            ValueType = "Dword"
            ValueData = 0  # 0 = Security (Enterprise only), 1 = Basic
            Ensure    = "Present"
        }

        # =====================================================================
        # Disable Consumer Features (pre-installed apps suggestions)
        # =====================================================================
        Registry DisableConsumerFeatures {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
            ValueName = "DisableWindowsConsumerFeatures"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Lock Screen Settings
        # =====================================================================
        # Disable lock screen app notifications
        Registry DisableLockScreenNotifications {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            ValueName = "DisableLockScreenAppNotifications"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Remote Desktop - Disabled for home PC
        # =====================================================================
        Registry DisableRDP {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
            ValueName = "fDenyTSConnections"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Windows Update - Configure for home use
        # =====================================================================
        # Set active hours (9 AM to 11 PM)
        Registry ActiveHoursStart {
            Key       = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            ValueName = "ActiveHoursStart"
            ValueType = "Dword"
            ValueData = 9
            Ensure    = "Present"
        }

        Registry ActiveHoursEnd {
            Key       = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            ValueName = "ActiveHoursEnd"
            ValueType = "Dword"
            ValueData = 23
            Ensure    = "Present"
        }
    }
}

# =============================================================================
# Compile Node-Specific Configuration
# =============================================================================

Write-Host "Compiling PcGenitori configuration..."
PcGenitori -OutputPath $mofOutputBase

Write-Host ""
Write-Host "MOF files generated in: $mofOutputBase" -ForegroundColor Green
Write-Host ""
Write-Host "Generated MOFs:"
Get-ChildItem -Path $mofOutputBase -Filter "*.mof" -Recurse | ForEach-Object {
    Write-Host "  - $($_.FullName)"
}
