<#
.SYNOPSIS
    DscGitCore - Standalone DSC Execution Engine

.DESCRIPTION
    This module provides the core functionality for executing DSC configurations
    from a Git repository or ZIP package, without requiring any control plane.
    
    It supports two source modes:
    - Git: Clone/pull from a Git repository (requires Git installed)
    - Package: Extract from a ZIP file (Gitless mode)

.NOTES
    Module: DscGitCore
    Version: 1.0.0
#>

# =============================================================================
# Module Configuration
# =============================================================================

$script:ModuleVersion = "1.0.0"
$script:DefaultWorkDir = "C:\dsc-agent\work"
$script:DefaultLogDir = "C:\dsc-agent\logs"

# =============================================================================
# Helper Functions
# =============================================================================

function Write-DscLog {
    <#
    .SYNOPSIS
        Write a log entry to console and optionally to file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        
        [string]$LogFile = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    # File output
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
}

function Ensure-Directory {
    <#
    .SYNOPSIS
        Ensure a directory exists, creating it if necessary.
    #>
    param([Parameter(Mandatory)][string]$Path)
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Test-GitAvailable {
    <#
    .SYNOPSIS
        Check if Git is available on the system.
    #>
    try {
        $null = & git --version 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# =============================================================================
# Git Operations
# =============================================================================

function Invoke-GitCloneOrPull {
    <#
    .SYNOPSIS
        Clone a repository if it doesn't exist, or pull updates if it does.
    
    .PARAMETER RepoUrl
        The Git repository URL.
    
    .PARAMETER Branch
        The branch to checkout.
    
    .PARAMETER DestinationPath
        Local path for the repository.
    
    .OUTPUTS
        Hashtable with Commit, ShortCommit, and IsNewClone properties.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl,
        
        [string]$Branch = "main",
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    Ensure-Directory -Path $DestinationPath
    
    $gitDir = Join-Path $DestinationPath ".git"
    $isNewClone = $false
    
    if (-not (Test-Path $gitDir)) {
        Write-DscLog "Cloning repository..."
        
        $result = & git clone --quiet --branch $Branch $RepoUrl $DestinationPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed: $result"
        }
        $isNewClone = $true
    }
    else {
        Write-DscLog "Updating existing repository..."
        
        Push-Location $DestinationPath
        try {
            & git fetch --all --quiet 2>&1 | Out-Null
            & git checkout $Branch --quiet 2>&1 | Out-Null
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to checkout branch: $Branch"
            }
            
            & git reset --hard "origin/$Branch" --quiet 2>&1 | Out-Null
        }
        finally {
            Pop-Location
        }
    }
    
    # Get commit hash
    Push-Location $DestinationPath
    try {
        $commit = & git rev-parse HEAD
        $shortCommit = $commit.Substring(0, [Math]::Min(8, $commit.Length))
    }
    finally {
        Pop-Location
    }
    
    Write-DscLog "Repository ready at commit: $shortCommit"
    
    return @{
        Commit      = $commit
        ShortCommit = $shortCommit
        IsNewClone  = $isNewClone
    }
}

# =============================================================================
# Package Operations (Gitless)
# =============================================================================

function Expand-ConfigPackage {
    <#
    .SYNOPSIS
        Extract a configuration package (ZIP) to the work directory.
    
    .PARAMETER ZipPath
        Path to the ZIP file.
    
    .PARAMETER DestinationPath
        Path to extract to.
    
    .OUTPUTS
        The commit hash from metadata, or "unknown".
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    Write-DscLog "Extracting package to: $DestinationPath"
    
    # Clean destination
    if (Test-Path $DestinationPath) {
        Remove-Item -Path $DestinationPath -Recurse -Force
    }
    
    Ensure-Directory -Path $DestinationPath
    
    # Extract ZIP
    Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
    
    # Read metadata if present
    $metaPath = Join-Path $DestinationPath "_opentune_meta.txt"
    if (Test-Path $metaPath) {
        $meta = Get-Content $metaPath -Raw
        Write-DscLog "Package metadata loaded" -Level DEBUG
        
        if ($meta -match "commit=([a-f0-9]+)") {
            return $matches[1]
        }
    }
    
    return "unknown"
}

# =============================================================================
# DSC Execution
# =============================================================================

function Invoke-DscFromPath {
    <#
    .SYNOPSIS
        Execute DSC configuration from a local path.
    
    .PARAMETER ConfigPath
        Path to the DSC configuration (.ps1 file or MOF directory).
    
    .PARAMETER Force
        Force apply even if system is already in desired state.
    
    .OUTPUTS
        Hashtable with Success, Summary, and ConfigType properties.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        
        [switch]$Force
    )
    
    $result = @{
        Success    = $false
        Summary    = ""
        ConfigType = "unknown"
    }
    
    try {
        # Determine config type and process accordingly
        if (Test-Path $ConfigPath -PathType Leaf) {
            $extension = [System.IO.Path]::GetExtension($ConfigPath).ToLower()
            
            if ($extension -eq ".ps1") {
                $result.ConfigType = "ps1-configuration"
                Write-DscLog "Processing PowerShell DSC configuration script"
                
                # Create MOF output directory
                $mofDir = Join-Path (Split-Path $ConfigPath -Parent) "mof-output"
                Ensure-Directory -Path $mofDir
                
                # Execute the configuration script to compile MOF
                Write-DscLog "Compiling DSC configuration..."
                Push-Location (Split-Path $ConfigPath -Parent)
                try {
                    . $ConfigPath
                }
                finally {
                    Pop-Location
                }
                
                # Find generated MOF files
                $mofFiles = Get-ChildItem -Path $mofDir -Filter "*.mof" -Recurse -ErrorAction SilentlyContinue
                
                if ($mofFiles.Count -eq 0) {
                    # Check parent mof directory
                    $parentMofDir = Join-Path (Split-Path $ConfigPath -Parent) ".." "mof"
                    if (Test-Path $parentMofDir) {
                        $mofDir = $parentMofDir
                        $mofFiles = Get-ChildItem -Path $mofDir -Filter "*.mof" -Recurse -ErrorAction SilentlyContinue
                    }
                }
                
                if ($mofFiles.Count -eq 0) {
                    throw "No MOF files generated after running configuration script"
                }
                
                Write-DscLog "Found $($mofFiles.Count) MOF file(s)"
                $ConfigPath = $mofDir
            }
            elseif ($extension -eq ".mof") {
                $result.ConfigType = "mof-file"
                Write-DscLog "Processing pre-compiled MOF file"
                $ConfigPath = Split-Path $ConfigPath -Parent
            }
            else {
                throw "Unsupported config file type: $extension (expected .ps1 or .mof)"
            }
        }
        elseif (Test-Path $ConfigPath -PathType Container) {
            $result.ConfigType = "mof-directory"
            Write-DscLog "Processing MOF directory"
            
            $mofFiles = Get-ChildItem -Path $ConfigPath -Filter "*.mof" -Recurse
            if ($mofFiles.Count -eq 0) {
                throw "No MOF files found in directory: $ConfigPath"
            }
            Write-DscLog "Found $($mofFiles.Count) MOF file(s)"
        }
        else {
            throw "Config path does not exist: $ConfigPath"
        }
        
        # Test current configuration state
        Write-DscLog "Testing current DSC configuration state..."
        $testResult = Test-DscConfiguration -Path $ConfigPath -ErrorAction SilentlyContinue
        
        if ($testResult -and -not $Force) {
            Write-DscLog "System is already in desired state"
            $result.Success = $true
            $result.Summary = "System already in desired state - no changes needed"
            return $result
        }
        
        # Apply configuration
        Write-DscLog "Applying DSC configuration..."
        $startTime = Get-Date
        
        Start-DscConfiguration -Path $ConfigPath -Wait -Verbose -Force -ErrorAction Stop
        
        $duration = (Get-Date) - $startTime
        Write-DscLog "DSC configuration applied in $([int]$duration.TotalSeconds) seconds"
        
        # Verify
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
        Write-DscLog $result.Summary -Level ERROR
        return $result
    }
}

# =============================================================================
# Main Exported Functions
# =============================================================================

function Invoke-DscFromGit {
    <#
    .SYNOPSIS
        Execute DSC configuration from a Git repository.
    
    .DESCRIPTION
        Clones or updates a Git repository and executes the DSC configuration
        at the specified path. This function requires Git to be installed.
    
    .PARAMETER RepoUrl
        The Git repository URL.
    
    .PARAMETER Branch
        The branch to use (default: main).
    
    .PARAMETER ConfigPath
        Path to the configuration within the repository.
    
    .PARAMETER WorkDir
        Working directory for the repository clone.
    
    .PARAMETER Force
        Force apply even if system is already in desired state.
    
    .OUTPUTS
        Hashtable with status, summary, and commit properties.
    
    .EXAMPLE
        $result = Invoke-DscFromGit -RepoUrl "https://github.com/org/dsc-configs.git" -ConfigPath "nodes/server01.ps1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl,
        
        [string]$Branch = "main",
        
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        
        [string]$WorkDir = $script:DefaultWorkDir,
        
        [switch]$Force
    )
    
    $result = @{
        status  = "failed"
        summary = ""
        commit  = $null
    }
    
    try {
        # Check Git availability
        if (-not (Test-GitAvailable)) {
            throw "Git is not installed or not in PATH. Please install Git or use package mode."
        }
        
        Write-DscLog "========================================" 
        Write-DscLog "DscGitCore - Standalone Mode"
        Write-DscLog "========================================"
        Write-DscLog "Repository: $RepoUrl"
        Write-DscLog "Branch: $Branch"
        Write-DscLog "Config: $ConfigPath"
        
        # Clone or update repository
        $repoDir = Join-Path $WorkDir "repo"
        $gitResult = Invoke-GitCloneOrPull -RepoUrl $RepoUrl -Branch $Branch -DestinationPath $repoDir
        $result.commit = $gitResult.Commit
        
        # Build full config path
        $fullConfigPath = Join-Path $repoDir $ConfigPath
        
        if (-not (Test-Path $fullConfigPath)) {
            throw "Config path not found: $fullConfigPath"
        }
        
        # Execute DSC
        $dscResult = Invoke-DscFromPath -ConfigPath $fullConfigPath -Force:$Force
        
        $result.status = if ($dscResult.Success) { "success" } else { "failed" }
        $result.summary = $dscResult.Summary
        
        Write-DscLog "========================================"
        Write-DscLog "Result: $($result.status)"
        Write-DscLog "========================================"
        
        return $result
    }
    catch {
        $result.status = "failed"
        $result.summary = "Error: $($_.Exception.Message)"
        Write-DscLog $result.summary -Level ERROR
        return $result
    }
}

function Invoke-DscFromPackage {
    <#
    .SYNOPSIS
        Execute DSC configuration from a ZIP package.
    
    .DESCRIPTION
        Extracts a configuration package and executes the DSC configuration
        at the specified path. This function does NOT require Git.
    
    .PARAMETER PackagePath
        Path to the ZIP package file.
    
    .PARAMETER ConfigPath
        Path to the configuration within the package.
    
    .PARAMETER WorkDir
        Working directory for extraction.
    
    .PARAMETER Force
        Force apply even if system is already in desired state.
    
    .OUTPUTS
        Hashtable with status, summary, and commit properties.
    
    .EXAMPLE
        $result = Invoke-DscFromPackage -PackagePath "C:\temp\config.zip" -ConfigPath "nodes/server01.ps1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,
        
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        
        [string]$WorkDir = $script:DefaultWorkDir,
        
        [switch]$Force
    )
    
    $result = @{
        status  = "failed"
        summary = ""
        commit  = $null
    }
    
    try {
        Write-DscLog "========================================" 
        Write-DscLog "DscGitCore - Package Mode (Gitless)"
        Write-DscLog "========================================"
        Write-DscLog "Package: $PackagePath"
        Write-DscLog "Config: $ConfigPath"
        
        if (-not (Test-Path $PackagePath)) {
            throw "Package file not found: $PackagePath"
        }
        
        # Extract package
        $extractDir = Join-Path $WorkDir "config"
        $commitHash = Expand-ConfigPackage -ZipPath $PackagePath -DestinationPath $extractDir
        $result.commit = $commitHash
        
        Write-DscLog "Package extracted, commit: $($commitHash.Substring(0, [Math]::Min(8, $commitHash.Length)))"
        
        # Build full config path
        $fullConfigPath = Join-Path $extractDir $ConfigPath
        
        if (-not (Test-Path $fullConfigPath)) {
            throw "Config path not found in package: $fullConfigPath"
        }
        
        # Execute DSC
        $dscResult = Invoke-DscFromPath -ConfigPath $fullConfigPath -Force:$Force
        
        $result.status = if ($dscResult.Success) { "success" } else { "failed" }
        $result.summary = $dscResult.Summary
        
        Write-DscLog "========================================"
        Write-DscLog "Result: $($result.status)"
        Write-DscLog "========================================"
        
        return $result
    }
    catch {
        $result.status = "failed"
        $result.summary = "Error: $($_.Exception.Message)"
        Write-DscLog $result.summary -Level ERROR
        return $result
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Invoke-DscFromGit',
    'Invoke-DscFromPackage',
    'Invoke-DscFromPath',
    'Invoke-GitCloneOrPull',
    'Expand-ConfigPackage',
    'Write-DscLog',
    'Ensure-Directory',
    'Test-GitAvailable'
)
