<#
.SYNOPSIS
    Common OS Baseline Configuration

.DESCRIPTION
    This DSC configuration defines common OS settings that should be applied
    to all Windows machines. It focuses on basic system hygiene.

.NOTES
    Part of dsc-cp example configurations
#>

Configuration CommonBaseline {
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node "localhost" {

        # =====================================================================
        # Windows Update Service
        # =====================================================================
        # Ensure Windows Update service is running and set to automatic
        Service WindowsUpdateService {
            Name        = "wuauserv"
            State       = "Running"
            StartupType = "Automatic"
        }

        # =====================================================================
        # Time Service
        # =====================================================================
        # Ensure Windows Time service is running for proper time sync
        Service WindowsTimeService {
            Name        = "W32Time"
            State       = "Running"
            StartupType = "Automatic"
        }

        # =====================================================================
        # Event Log Service
        # =====================================================================
        # Ensure Event Log is running (critical for auditing)
        Service EventLogService {
            Name        = "EventLog"
            State       = "Running"
            StartupType = "Automatic"
        }

        # =====================================================================
        # Remote Registry - Disabled for security
        # =====================================================================
        Service RemoteRegistryDisabled {
            Name        = "RemoteRegistry"
            State       = "Stopped"
            StartupType = "Disabled"
        }

        # =====================================================================
        # Power Settings - Prevent sleep on servers
        # =====================================================================
        # Note: This registry key prevents the system from sleeping
        # Uncomment for server workloads
        <#
        Registry DisableSleep {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
            ValueName = "HibernateEnabled"
            ValueType = "Dword"
            ValueData = 0
            Ensure    = "Present"
        }
        #>
    }
}
