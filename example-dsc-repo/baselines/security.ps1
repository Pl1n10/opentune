<#
.SYNOPSIS
    Security Hardening Baseline Configuration

.DESCRIPTION
    This DSC configuration implements security best practices:
    - Windows Defender enabled
    - Windows Firewall enabled
    - SMBv1 disabled
    - UAC enabled
    - Various security registry settings

.NOTES
    Part of dsc-cp example configurations
    Based on CIS Windows benchmarks (simplified)
#>

Configuration SecurityBaseline {
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node "localhost" {

        # =====================================================================
        # Windows Defender
        # =====================================================================
        # Ensure Windows Defender service is running
        Service DefenderService {
            Name        = "WinDefend"
            State       = "Running"
            StartupType = "Automatic"
        }

        # Defender Network Inspection Service
        Service DefenderNetworkService {
            Name        = "WdNisSvc"
            State       = "Running"
            StartupType = "Manual"
        }

        # =====================================================================
        # Windows Firewall
        # =====================================================================
        # Ensure Windows Firewall service is running
        Service FirewallService {
            Name        = "MpsSvc"
            State       = "Running"
            StartupType = "Automatic"
        }

        # Enable firewall for all profiles via registry
        Registry FirewallDomainEnabled {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile"
            ValueName = "EnableFirewall"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        Registry FirewallPrivateEnabled {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile"
            ValueName = "EnableFirewall"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        Registry FirewallPublicEnabled {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile"
            ValueName = "EnableFirewall"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # SMBv1 - Disabled (security vulnerability)
        # =====================================================================
        # Disable SMBv1 protocol (WannaCry, NotPetya vulnerabilities)
        WindowsOptionalFeature DisableSMB1 {
            Name   = "SMB1Protocol"
            Ensure = "Disable"
        }

        # Also disable via registry for older systems
        Registry DisableSMB1Server {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
            ValueName = "SMB1"
            ValueType = "Dword"
            ValueData = 0
            Ensure    = "Present"
        }

        # =====================================================================
        # User Account Control (UAC)
        # =====================================================================
        # Enable UAC
        Registry EnableUAC {
            Key       = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            ValueName = "EnableLUA"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # UAC prompt behavior for admins - Prompt for consent on secure desktop
        Registry UACConsentPromptAdmin {
            Key       = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            ValueName = "ConsentPromptBehaviorAdmin"
            ValueType = "Dword"
            ValueData = 2
            Ensure    = "Present"
        }

        # UAC prompt behavior for standard users - Prompt for credentials
        Registry UACConsentPromptUser {
            Key       = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            ValueName = "ConsentPromptBehaviorUser"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Additional Security Settings
        # =====================================================================
        
        # Disable AutoRun for all drives
        Registry DisableAutoRun {
            Key       = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            ValueName = "NoDriveTypeAutoRun"
            ValueType = "Dword"
            ValueData = 255
            Ensure    = "Present"
        }

        # Enable DEP (Data Execution Prevention) for all programs
        Registry EnableDEP {
            Key       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
            ValueName = "NoDataExecutionPrevention"
            ValueType = "Dword"
            ValueData = 0
            Ensure    = "Present"
        }

        # Disable anonymous SID enumeration
        Registry DisableAnonymousSID {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
            ValueName = "RestrictAnonymousSAM"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }

        # =====================================================================
        # Audit Policy - Enable security auditing
        # =====================================================================
        # Note: Full audit policy typically requires Group Policy or auditpol.exe
        # This is a basic registry-based approach

        Registry AuditLogonEvents {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
            ValueName = "AuditBaseObjects"
            ValueType = "Dword"
            ValueData = 1
            Ensure    = "Present"
        }
    }
}
