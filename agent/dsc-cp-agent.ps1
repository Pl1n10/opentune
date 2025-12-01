<#
.SYNOPSIS
    dsc-cp Agent - GitOps DSC client for Windows

.DESCRIPTION
    This agent implements a pull-based GitOps loop for PowerShell DSC:
    1. Fetches desired state from dsc-cp control plane
    2. Clones/pulls the Git repository
    3. Executes DSC configuration (MOF or .ps1)
    4. Reports results back to control plane

.PARAMETER ConfigPath
    Path to the agent configuration JSON file.
    Default: C:\ProgramData\dsc-cp\agent-config.json

.PARAMETER WorkDir
    Working directory for Git repos and temp files.
    Default: C:\ProgramData\dsc-cp\work

.PARAMETER LogDir
    Directory for log files.
    Default: C:\ProgramData\dsc-cp\logs

.PARAMETER MaxRetries
    Maximum API retry attempts.
    Default: 3

.PARAMETER Force
    Force DSC apply even if Test-DscConfiguration passes.

.EXAMPLE
    .\dsc-cp-agent.ps1
    Run with default settings.

.EXAMPLE
    .\dsc-cp-agent.ps1 -Force -MaxRetries 5
    Force apply and retry up to 5 times on API failures.

.NOTES
    Author: dsc-cp project
    Version: 0.2.0
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "C:\ProgramData\dsc-cp\agent-config.json",
    [string]$WorkDir    = "C:\ProgramData\dsc-cp\work",
    [string]$LogDir     = "C:\ProgramData\dsc-cp\logs",
    [int]$MaxRetries    = 3,
    [switch]$Force
)

# =============================================================================
# Configuration
# =============================================================================

$script:AgentVersion = "0.2.0"
$script:RetryDelaySeconds = @(5, 15, 30)  # Exponential backoff delays

# =============================================================================
# Logging Functions
# =============================================================================

function Initialize-Logging {
    param([string]$LogDirectory)
    
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd"
    $script:LogFile = Join-Path $LogDirectory "dsc-cp-agent-$timestamp.log"
    
    # Rotate old logs (keep last 7 days)
    Get-ChildItem -Path $LogDirectory -Filter "dsc-cp-agent-*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    # Write to file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Configuration Management
# =============================================================================

function Read-AgentConfig {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    
    $content = Get-Content -Path $Path -Raw -ErrorAction Stop
    $config = $content | ConvertFrom-Json
    
    # Validate required fields
    $requiredFields = @("controlPlaneUrl", "nodeId", "nodeToken")
    foreach ($field in $requiredFields) {
        if (-not $config.$field) {
            throw "Missing required config field: $field"
        }
    }
    
    return $config
}

# =============================================================================
# API Communication (with retry logic)
# =============================================================================

function Invoke-ApiWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Url,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [hashtable]$Body = $null,
        
        [int]$MaxAttempts = 3
    )
    
    $headers = @{
        "X-Node-Token" = $NodeToken
        "Content-Type" = "application/json"
        "User-Agent"   = "dsc-cp-agent/$script:AgentVersion"
    }
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            $params = @{
                Method      = $Method
                Uri         = $Url
                Headers     = $headers
                ErrorAction = "Stop"
            }
            
            if ($Body) {
                $params.Body = ($Body | ConvertTo-Json -Depth 10)
            }
            
            $response = Invoke-RestMethod @params
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            # Don't retry on client errors (4xx) except 429 (rate limit)
            if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                Write-Log "API error (non-retryable): $statusCode - $($_.Exception.Message)" -Level ERROR
                throw
            }
            
            if ($attempt -lt $MaxAttempts) {
                $delay = $script:RetryDelaySeconds[$attempt - 1]
                Write-Log "API request failed (attempt $attempt/$MaxAttempts). Retrying in ${delay}s..." -Level WARN
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    Write-Log "API request failed after $MaxAttempts attempts" -Level ERROR
    throw $lastError
}

function Get-DesiredState {
    param(
        [string]$ControlPlaneUrl,
        [int]$NodeId,
        [string]$NodeToken,
        [int]$MaxRetries
    )
    
    $url = "$ControlPlaneUrl/api/v1/agents/nodes/$NodeId/desired-state"
    Write-Log "Fetching desired state from: $url"
    
    return Invoke-ApiWithRetry -Method GET -Url $url -NodeToken $NodeToken -MaxAttempts $MaxRetries
}

function Send-RunReport {
    param(
        [string]$ControlPlaneUrl,
        [int]$NodeId,
        [string]$NodeToken,
        [hashtable]$ReportData,
        [int]$MaxRetries
    )
    
    $url = "$ControlPlaneUrl/api/v1/agents/nodes/$NodeId/runs"
    Write-Log "Reporting run to: $url (status: $($ReportData.status))"
    
    return Invoke-ApiWithRetry -Method POST -Url $url -NodeToken $NodeToken -Body $ReportData -MaxAttempts $MaxRetries
}

# =============================================================================
# Git Operations
# =============================================================================

function Ensure-Directory {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Log "Created directory: $Path" -Level DEBUG
    }
}

function Invoke-GitOperation {
    param(
        [string]$RepoUrl,
        [string]$Branch,
        [string]$RepoDir
    )
    
    Ensure-Directory -Path $RepoDir
    
    $gitDir = Join-Path $RepoDir ".git"
    $isNewClone = $false
    
    if (-not (Test-Path $gitDir)) {
        Write-Log "Cloning repository: $RepoUrl"
        
        # Clone without showing URL (may contain credentials)
        $result = & git clone --quiet $RepoUrl $RepoDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed: $result"
        }
        $isNewClone = $true
    }
    
    Push-Location $RepoDir
    try {
        # Fetch all updates
        Write-Log "Fetching updates..." -Level DEBUG
        & git fetch --all --quiet 2>&1 | Out-Null
        
        # Checkout and pull the specified branch
        Write-Log "Checking out branch: $Branch"
        & git checkout $Branch --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout branch: $Branch"
        }
        
        # Reset to remote branch (discard local changes)
        & git reset --hard "origin/$Branch" --quiet 2>&1 | Out-Null
        
        # Get current commit
        $commit = & git rev-parse HEAD
        $shortCommit = $commit.Substring(0, 8)
        
        Write-Log "Repository ready at commit: $shortCommit"
        
        return @{
            Commit      = $commit
            ShortCommit = $shortCommit
            IsNewClone  = $isNewClone
        }
    }
    finally {
        Pop-Location
    }
}

# =============================================================================
# DSC Execution
# =============================================================================

function Invoke-DscConfiguration {
    <#
    .SYNOPSIS
        Execute DSC configuration from a file or directory.
    
    .DESCRIPTION
        Supports two modes:
        - .ps1 file: Compiles the configuration and applies the resulting MOF
        - Directory/MOF: Applies pre-compiled MOF files directly
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        
        [string]$MofOutputDir,
        
        [switch]$Force
    )
    
    $result = @{
        Success       = $false
        Summary       = ""
        ConfigType    = "unknown"
        ResourceCount = 0
    }
    
    try {
        # Determine config type
        if (Test-Path $ConfigPath -PathType Leaf) {
            $extension = [System.IO.Path]::GetExtension($ConfigPath).ToLower()
            
            if ($extension -eq ".ps1") {
                $result.ConfigType = "ps1-configuration"
                Write-Log "Detected PowerShell DSC configuration script"
                
                # Execute the .ps1 to compile MOF
                Write-Log "Compiling DSC configuration..."
                
                # Create temp MOF output directory
                $mofDir = if ($MofOutputDir) { $MofOutputDir } else { 
                    Join-Path ([System.IO.Path]::GetDirectoryName($ConfigPath)) "mof-output"
                }
                Ensure-Directory -Path $mofDir
                
                # Execute the configuration script
                # The script should generate MOF files
                Push-Location (Split-Path $ConfigPath -Parent)
                try {
                    # Source the script (this compiles configs and generates MOFs)
                    . $ConfigPath
                }
                finally {
                    Pop-Location
                }
                
                # Find generated MOF files
                $mofFiles = Get-ChildItem -Path $mofDir -Filter "*.mof" -Recurse -ErrorAction SilentlyContinue
                if ($mofFiles.Count -eq 0) {
                    # Check parent directory structure for MOF output
                    $parentMofDir = Join-Path (Split-Path $ConfigPath -Parent) ".." "mof"
                    if (Test-Path $parentMofDir) {
                        $mofDir = $parentMofDir
                        $mofFiles = Get-ChildItem -Path $mofDir -Filter "*.mof" -Recurse -ErrorAction SilentlyContinue
                    }
                }
                
                if ($mofFiles.Count -eq 0) {
                    throw "No MOF files generated after running configuration script"
                }
                
                Write-Log "Found $($mofFiles.Count) MOF file(s) in $mofDir"
                $ConfigPath = $mofDir
            }
            elseif ($extension -eq ".mof") {
                $result.ConfigType = "mof-file"
                Write-Log "Detected pre-compiled MOF file"
                $ConfigPath = Split-Path $ConfigPath -Parent
            }
            else {
                throw "Unsupported config file type: $extension (expected .ps1 or .mof)"
            }
        }
        elseif (Test-Path $ConfigPath -PathType Container) {
            $result.ConfigType = "mof-directory"
            Write-Log "Detected MOF directory"
            
            $mofFiles = Get-ChildItem -Path $ConfigPath -Filter "*.mof" -Recurse
            if ($mofFiles.Count -eq 0) {
                throw "No MOF files found in directory: $ConfigPath"
            }
            Write-Log "Found $($mofFiles.Count) MOF file(s)"
        }
        else {
            throw "Config path does not exist: $ConfigPath"
        }
        
        # Test current configuration state
        Write-Log "Testing current DSC configuration state..."
        $testResult = Test-DscConfiguration -Path $ConfigPath -ErrorAction SilentlyContinue
        
        if ($testResult -and -not $Force) {
            Write-Log "System is already in desired state (Test-DscConfiguration passed)"
            $result.Success = $true
            $result.Summary = "System already in desired state - no changes needed"
            return $result
        }
        
        # Apply configuration
        Write-Log "Applying DSC configuration..."
        $startTime = Get-Date
        
        Start-DscConfiguration -Path $ConfigPath -Wait -Verbose -Force -ErrorAction Stop
        
        $duration = (Get-Date) - $startTime
        Write-Log "DSC configuration applied successfully in $([int]$duration.TotalSeconds) seconds"
        
        # Verify the configuration was applied
        $verifyResult = Test-DscConfiguration -Path $ConfigPath -ErrorAction SilentlyContinue
        
        if ($verifyResult) {
            $result.Success = $true
            $result.Summary = "Configuration applied successfully in $([int]$duration.TotalSeconds)s"
        }
        else {
            $result.Success = $false
            $result.Summary = "Configuration applied but verification failed"
        }
        
        return $result
    }
    catch {
        $result.Success = $false
        $result.Summary = "DSC execution failed: $($_.Exception.Message)"
        Write-Log $result.Summary -Level ERROR
        return $result
    }
}

# =============================================================================
# Main Agent Loop
# =============================================================================

function Start-AgentRun {
    param(
        [string]$ConfigPath,
        [string]$WorkDir,
        [string]$LogDir,
        [int]$MaxRetries,
        [switch]$Force
    )
    
    $runStartTime = Get-Date
    $runResult = @{
        Status    = "failed"
        GitCommit = $null
        Summary   = ""
    }
    
    try {
        # Initialize logging
        Initialize-Logging -LogDirectory $LogDir
        Write-Log "========================================" 
        Write-Log "dsc-cp Agent v$script:AgentVersion starting"
        Write-Log "========================================" 
        
        # Load configuration
        Write-Log "Loading configuration from: $ConfigPath"
        $config = Read-AgentConfig -Path $ConfigPath
        
        $controlPlaneUrl = $config.controlPlaneUrl.TrimEnd("/")
        $nodeId = [int]$config.nodeId
        $nodeToken = [string]$config.nodeToken
        
        Write-Log "Node ID: $nodeId"
        Write-Log "Control Plane: $controlPlaneUrl"
        
        # Ensure work directory exists
        Ensure-Directory -Path $WorkDir
        
        # Get desired state from control plane
        $desiredState = Get-DesiredState -ControlPlaneUrl $controlPlaneUrl `
                                         -NodeId $nodeId `
                                         -NodeToken $nodeToken `
                                         -MaxRetries $MaxRetries
        
        if (-not $desiredState.policy_assigned) {
            Write-Log "No policy assigned to this node. Nothing to do."
            $runResult.Status = "skipped"
            $runResult.Summary = "No policy assigned"
            return $runResult
        }
        
        $policyId   = $desiredState.policy_id
        $policyName = $desiredState.policy_name
        $repoUrl    = $desiredState.repository.url
        $branch     = $desiredState.repository.branch
        $dscPath    = $desiredState.config_path
        
        Write-Log "Policy: $policyName (ID: $policyId)"
        Write-Log "Repository branch: $branch"
        Write-Log "Config path: $dscPath"
        
        # Sync Git repository
        $repoDir = Join-Path $WorkDir "repo"
        $gitResult = Invoke-GitOperation -RepoUrl $repoUrl -Branch $branch -RepoDir $repoDir
        $runResult.GitCommit = $gitResult.Commit
        
        # Build full path to DSC config
        $fullConfigPath = Join-Path $repoDir $dscPath
        Write-Log "Full config path: $fullConfigPath"
        
        if (-not (Test-Path $fullConfigPath)) {
            throw "DSC config path not found: $fullConfigPath"
        }
        
        # Execute DSC configuration
        $dscResult = Invoke-DscConfiguration -ConfigPath $fullConfigPath -Force:$Force
        
        if ($dscResult.Success) {
            $runResult.Status = "success"
            $runResult.Summary = $dscResult.Summary
            Write-Log "DSC configuration completed successfully" 
        }
        else {
            $runResult.Status = "failed"
            $runResult.Summary = $dscResult.Summary
            Write-Log "DSC configuration failed: $($dscResult.Summary)" -Level ERROR
        }
        
        # Report results to control plane
        $reportData = @{
            policy_id  = $policyId
            git_commit = $runResult.GitCommit
            status     = $runResult.Status
            summary    = $runResult.Summary
        }
        
        $reportResponse = Send-RunReport -ControlPlaneUrl $controlPlaneUrl `
                                         -NodeId $nodeId `
                                         -NodeToken $nodeToken `
                                         -ReportData $reportData `
                                         -MaxRetries $MaxRetries
        
        Write-Log "Run reported successfully. Run ID: $($reportResponse.run_id)"
        
        return $runResult
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Log "Agent run failed: $errorMsg" -Level ERROR
        
        $runResult.Status = "failed"
        $runResult.Summary = "Agent error: $errorMsg"
        
        # Try to report the failure (best effort)
        try {
            $config = Read-AgentConfig -Path $ConfigPath
            if ($config -and $runResult.GitCommit) {
                Send-RunReport -ControlPlaneUrl $config.controlPlaneUrl.TrimEnd("/") `
                              -NodeId $config.nodeId `
                              -NodeToken $config.nodeToken `
                              -ReportData @{
                                  policy_id  = 0
                                  git_commit = $runResult.GitCommit
                                  status     = "failed"
                                  summary    = $runResult.Summary
                              } `
                              -MaxRetries 1 | Out-Null
            }
        }
        catch {
            Write-Log "Failed to report error to control plane" -Level WARN
        }
        
        return $runResult
    }
    finally {
        $duration = (Get-Date) - $runStartTime
        Write-Log "Agent run completed in $([int]$duration.TotalSeconds) seconds"
        Write-Log "Final status: $($runResult.Status)"
        Write-Log "========================================"
    }
}

# =============================================================================
# Entry Point
# =============================================================================

$ErrorActionPreference = "Stop"

$result = Start-AgentRun -ConfigPath $ConfigPath `
                         -WorkDir $WorkDir `
                         -LogDir $LogDir `
                         -MaxRetries $MaxRetries `
                         -Force:$Force

# Exit with appropriate code
if ($result.Status -eq "success" -or $result.Status -eq "skipped") {
    exit 0
}
else {
    exit 1
}
