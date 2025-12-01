<#
.SYNOPSIS
    DSC configuration for workstation-01.

.DESCRIPTION
    This is the main entrypoint for the workstation-01 node.
    It imports and compiles baseline configurations, then adds
    node-specific settings.

    In dsc-cp, set config_path to: "nodes/workstation-01.ps1"

.NOTES
    Part of dsc-cp example DSC repository
    
    When this script is executed (dot-sourced) by the dsc-cp agent:
    1. Baseline configurations are imported
    2. Baselines are compiled to MOF files
    3. Node-specific configuration is compiled
    4. The agent then applies all MOFs
#>

# ============================================================================
# Import Baseline Configurations
# ============================================================================

. "$PSScriptRoot\..\baselines\common.ps1"
. "$PSScriptRoot\..\baselines\security.ps1"

# ============================================================================
# Compile Baseline MOFs
# ============================================================================

# Create MOF output directory
$mofOutputDir = "$PSScriptRoot\..\mof\workstation-01"
if (-not (Test-Path $mofOutputDir)) {
    New-Item -Path $mofOutputDir -ItemType Directory -Force | Out-Null
}

# Compile baselines
Write-Host "Compiling CommonBaseline..."
CommonBaseline -OutputPath "$mofOutputDir\common"

Write-Host "Compiling SecurityBaseline..."
SecurityBaseline -OutputPath "$mofOutputDir\security"

# ============================================================================
# Node-Specific Configuration
# ============================================================================

Configuration Workstation01 {

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node "localhost" {

        # ================================================================
        # Workstation-Specific: Disable Cortana
        # ================================================================
        Registry DisableCortana {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            ValueName = "AllowCortana"
            ValueType = "Dword"
            ValueData = "0"
            Ensure    = "Present"
        }

        # ================================================================
        # Workstation-Specific: Disable Web Search in Start Menu
        # ================================================================
        Registry DisableWebSearch {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            ValueName = "DisableWebSearch"
            ValueType = "Dword"
            ValueData = "1"
            Ensure    = "Present"
        }

        # ================================================================
        # Workstation-Specific: Hide "Meet Now" icon in taskbar
        # ================================================================
        Registry HideMeetNow {
            Key       = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            ValueName = "HideSCAMeetNow"
            ValueType = "Dword"
            ValueData = "1"
            Ensure    = "Present"
        }

        # ================================================================
        # Workstation-Specific: Disable Telemetry (set to Security level)
        # ================================================================
        # 0 = Security (Enterprise only), 1 = Basic, 2 = Enhanced, 3 = Full
        Registry SetTelemetryLevel {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            ValueName = "AllowTelemetry"
            ValueType = "Dword"
            ValueData = "0"
            Ensure    = "Present"
        }

        # ================================================================
        # Add more workstation-specific configurations below
        # ================================================================
        # Examples:
        # - Install specific software
        # - Configure power settings
        # - Set up VPN profiles
        # - Configure printers
    }
}

# Compile node-specific configuration
Write-Host "Compiling Workstation01..."
Workstation01 -OutputPath $mofOutputDir

Write-Host "MOF compilation complete. Output directory: $mofOutputDir"
