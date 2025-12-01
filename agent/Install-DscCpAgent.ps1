<#
.SYNOPSIS
    Install dsc-cp agent on Windows

.DESCRIPTION
    This script:
    - Creates the required directory structure
    - Copies agent files to C:\ProgramData\dsc-cp
    - Creates a scheduled task to run the agent every 30 minutes
    - Optionally configures the agent

.PARAMETER ControlPlaneUrl
    URL of the dsc-cp control plane (required for initial setup)

.PARAMETER NodeId
    Node ID from the control plane (required for initial setup)

.PARAMETER NodeToken
    Node authentication token (required for initial setup)

.PARAMETER Interval
    Run interval in minutes. Default: 30

.PARAMETER Uninstall
    Remove the agent and scheduled task

.EXAMPLE
    .\Install-DscCpAgent.ps1 -ControlPlaneUrl "https://dsc-cp.example.com" -NodeId 1 -NodeToken "abc123..."
    Install and configure the agent

.EXAMPLE
    .\Install-DscCpAgent.ps1 -Uninstall
    Remove the agent
#>

[CmdletBinding()]
param(
    [string]$ControlPlaneUrl,
    [int]$NodeId,
    [string]$NodeToken,
    [int]$Interval = 30,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$InstallDir = "C:\ProgramData\dsc-cp"
$TaskName = "dsc-cp-agent"

function Install-Agent {
    Write-Host "Installing dsc-cp agent..." -ForegroundColor Cyan
    
    # Create directories
    $dirs = @(
        $InstallDir,
        "$InstallDir\work",
        "$InstallDir\logs"
    )
    
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "  Created: $dir"
        }
    }
    
    # Copy agent script
    $scriptSource = Join-Path $PSScriptRoot "dsc-cp-agent.ps1"
    $scriptDest = Join-Path $InstallDir "dsc-cp-agent.ps1"
    
    if (Test-Path $scriptSource) {
        Copy-Item -Path $scriptSource -Destination $scriptDest -Force
        Write-Host "  Copied agent script to: $scriptDest"
    }
    else {
        Write-Warning "Agent script not found at $scriptSource"
        Write-Warning "Please copy dsc-cp-agent.ps1 to $InstallDir manually"
    }
    
    # Create or update config
    $configPath = Join-Path $InstallDir "agent-config.json"
    
    if ($ControlPlaneUrl -and $NodeId -and $NodeToken) {
        $config = @{
            controlPlaneUrl = $ControlPlaneUrl
            nodeId = $NodeId
            nodeToken = $NodeToken
        }
        
        $config | ConvertTo-Json | Set-Content -Path $configPath
        Write-Host "  Created config: $configPath" -ForegroundColor Green
    }
    elseif (-not (Test-Path $configPath)) {
        Write-Warning "No configuration provided. Please create $configPath manually."
        Write-Host @"
  
  Example config:
  {
    "controlPlaneUrl": "https://dsc-cp.example.com",
    "nodeId": 1,
    "nodeToken": "your-token-here"
  }
"@
    }
    
    # Create scheduled task
    Write-Host "`nConfiguring scheduled task..." -ForegroundColor Cyan
    
    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Removed existing task"
    }
    
    # Create new task
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptDest`"" `
        -WorkingDirectory $InstallDir
    
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $Interval) `
        -RepetitionDuration (New-TimeSpan -Days 9999)
    
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew
    
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "dsc-cp GitOps DSC agent - runs every $Interval minutes" | Out-Null
    
    Write-Host "  Created scheduled task: $TaskName (every $Interval minutes)" -ForegroundColor Green
    
    Write-Host "`n✓ Installation complete!" -ForegroundColor Green
    Write-Host "`nNext steps:"
    Write-Host "  1. Verify configuration in $configPath"
    Write-Host "  2. Run manually: & '$scriptDest'"
    Write-Host "  3. Or wait for scheduled task to run"
}

function Uninstall-Agent {
    Write-Host "Uninstalling dsc-cp agent..." -ForegroundColor Cyan
    
    # Remove scheduled task
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Removed scheduled task"
    }
    
    # Remove installation directory (optional - ask user)
    if (Test-Path $InstallDir) {
        $response = Read-Host "Remove installation directory $InstallDir? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-Host "  Removed installation directory"
        }
        else {
            Write-Host "  Keeping installation directory (contains logs and config)"
        }
    }
    
    Write-Host "`n✓ Uninstallation complete!" -ForegroundColor Green
}

# Main
if ($Uninstall) {
    Uninstall-Agent
}
else {
    Install-Agent
}
