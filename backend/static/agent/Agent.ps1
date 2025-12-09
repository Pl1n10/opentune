<#
.SYNOPSIS
    OpenTune Agent - Dual-Mode DSC Client for Windows

.DESCRIPTION
    This agent supports two execution modes:
    
    1. STANDALONE MODE
       Uses a local Git repository (or package) to apply DSC configurations.
       No server/control plane required.
       
    2. CENTRALIZED MODE
       Connects to an OpenTune control plane server to receive desired state
       and report run results.
    
    The mode is determined by the config.json file.

.PARAMETER ConfigPath
    Path to the agent configuration JSON file.
    Default: C:\dsc-agent\config.json

.PARAMETER WorkDir
    Working directory for repos/packages and temp files.
    Default: C:\dsc-agent\work

.PARAMETER LogDir
    Directory for log files.
    Default: C:\dsc-agent\logs

.PARAMETER Force
    Force DSC apply even if Test-DscConfiguration passes.

.EXAMPLE
    .\Agent.ps1
    Run with default settings.

.EXAMPLE
    .\Agent.ps1 -Force
    Force apply configuration.

.NOTES
    Author: OpenTune Project
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "C:\dsc-agent\config.json",
    [string]$WorkDir    = "C:\dsc-agent\work",
    [string]$LogDir     = "C:\dsc-agent\logs",
    [switch]$Force
)

# =============================================================================
# Configuration
# =============================================================================

$script:AgentVersion = "1.0.0"
$ErrorActionPreference = "Stop"

# =============================================================================
# Initialize Logging
# =============================================================================

function Initialize-AgentLogging {
    param([string]$LogDirectory)
    
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd"
    $script:LogFile = Join-Path $LogDirectory "opentune-agent-$timestamp.log"
    
    # Rotate old logs (keep last 7 days)
    Get-ChildItem -Path $LogDirectory -Filter "opentune-agent-*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-AgentLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Load Modules
# =============================================================================

function Import-AgentModules {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    
    $modulesDir = Join-Path $scriptDir "modules"
    
    # Check if modules exist locally
    $dscCorePath = Join-Path $modulesDir "DscGitCore.psm1"
    $adapterPath = Join-Path $modulesDir "OpenTuneAdapter.psm1"
    
    if (-not (Test-Path $dscCorePath)) {
        throw "DscGitCore.psm1 not found at: $dscCorePath"
    }
    
    if (-not (Test-Path $adapterPath)) {
        throw "OpenTuneAdapter.psm1 not found at: $adapterPath"
    }
    
    Import-Module $dscCorePath -Force -DisableNameChecking -Global
    Import-Module $adapterPath -Force -DisableNameChecking -Global
    
    Write-AgentLog "Modules loaded successfully" -Level DEBUG
}

# =============================================================================
# Configuration Loading
# =============================================================================

function Read-AgentConfig {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    
    $content = Get-Content -Path $Path -Raw -ErrorAction Stop
    $config = $content | ConvertFrom-Json
    
    # Validate mode
    if (-not $config.mode) {
        throw "Missing required config field: mode (must be 'standalone' or 'centralized')"
    }
    
    $validModes = @("standalone", "centralized")
    if ($config.mode -notin $validModes) {
        throw "Invalid mode: $($config.mode). Must be one of: $($validModes -join ', ')"
    }
    
    # Validate mode-specific fields
    switch ($config.mode) {
        "standalone" {
            if (-not $config.config_path) {
                throw "Standalone mode requires 'config_path' field"
            }
            # repo_url is optional if using package mode
        }
        "centralized" {
            $required = @("server_url", "node_id", "node_token")
            foreach ($field in $required) {
                if (-not $config.$field) {
                    throw "Centralized mode requires '$field' field"
                }
            }
        }
    }
    
    return $config
}

# =============================================================================
# Execution Functions
# =============================================================================

function Invoke-StandaloneMode {
    param(
        [Parameter(Mandatory)]
        $Config,
        
        [string]$WorkDir,
        
        [switch]$Force
    )
    
    Write-AgentLog "Executing in STANDALONE mode"
    
    # Check if we have a package path (Gitless) or repo URL (Git)
    if ($Config.package_path -and (Test-Path $Config.package_path)) {
        # Package mode
        Write-AgentLog "Using local package: $($Config.package_path)"
        
        return Invoke-DscFromPackage -PackagePath $Config.package_path `
                                      -ConfigPath $Config.config_path `
                                      -WorkDir $WorkDir `
                                      -Force:$Force
    }
    elseif ($Config.repo_url) {
        # Git mode
        Write-AgentLog "Using Git repository: $($Config.repo_url)"
        
        $branch = if ($Config.branch) { $Config.branch } else { "main" }
        
        return Invoke-DscFromGit -RepoUrl $Config.repo_url `
                                  -Branch $branch `
                                  -ConfigPath $Config.config_path `
                                  -WorkDir $WorkDir `
                                  -Force:$Force
    }
    else {
        throw "Standalone mode requires either 'repo_url' or 'package_path'"
    }
}

function Invoke-CentralizedMode {
    param(
        [Parameter(Mandatory)]
        $Config,
        
        [string]$WorkDir,
        
        [switch]$Force
    )
    
    Write-AgentLog "Executing in CENTRALIZED mode"
    Write-AgentLog "Server: $($Config.server_url)"
    Write-AgentLog "Node ID: $($Config.node_id)"
    
    # Check if we should use Git or Package mode
    $useGit = $Config.use_git -eq $true
    
    return Invoke-OpenTuneOnce -ServerUrl $Config.server_url `
                                -NodeId $Config.node_id `
                                -NodeToken $Config.node_token `
                                -WorkDir $WorkDir `
                                -UseGit:$useGit `
                                -Force:$Force `
                                -MaxRetries 3
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Start-AgentRun {
    param(
        [string]$ConfigPath,
        [string]$WorkDir,
        [string]$LogDir,
        [switch]$Force
    )
    
    $runStartTime = Get-Date
    $result = @{
        status  = "failed"
        summary = ""
        commit  = $null
    }
    
    try {
        # Initialize logging
        Initialize-AgentLogging -LogDirectory $LogDir
        
        Write-AgentLog "========================================"
        Write-AgentLog "OpenTune Agent v$script:AgentVersion"
        Write-AgentLog "========================================"
        
        # Load modules
        Import-AgentModules
        
        # Ensure work directory exists
        if (-not (Test-Path $WorkDir)) {
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
        }
        
        # Load configuration
        Write-AgentLog "Loading configuration from: $ConfigPath"
        $config = Read-AgentConfig -Path $ConfigPath
        Write-AgentLog "Mode: $($config.mode)"
        
        # Execute based on mode
        switch ($config.mode) {
            "standalone" {
                $result = Invoke-StandaloneMode -Config $config -WorkDir $WorkDir -Force:$Force
            }
            "centralized" {
                $result = Invoke-CentralizedMode -Config $config -WorkDir $WorkDir -Force:$Force
            }
        }
        
        return $result
    }
    catch {
        $result.status = "failed"
        $result.summary = "Agent error: $($_.Exception.Message)"
        Write-AgentLog $result.summary -Level ERROR
        return $result
    }
    finally {
        $duration = (Get-Date) - $runStartTime
        Write-AgentLog "Agent run completed in $([int]$duration.TotalSeconds) seconds"
        Write-AgentLog "Final status: $($result.status)"
        Write-AgentLog "========================================"
    }
}

# =============================================================================
# Run Agent
# =============================================================================

$result = Start-AgentRun -ConfigPath $ConfigPath `
                         -WorkDir $WorkDir `
                         -LogDir $LogDir `
                         -Force:$Force

# Exit with appropriate code
if ($result.status -eq "success" -or $result.status -eq "skipped") {
    exit 0
}
else {
    exit 1
}
