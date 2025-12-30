<#
.SYNOPSIS
    OpenTune One-Click Setup Wizard
    
.DESCRIPTION
    Interactive wizard to install and configure the OpenTune DSC agent.
    Supports both Centralized (server) and Standalone (Git/local) modes.
    
    Usage:
        iwr https://opentune.robertonovara.dev/setup.ps1 | iex
    
.NOTES
    Author: OpenTune Project
    Version: 1.0.0
    Requires: Windows 10+, PowerShell 5.1+, Administrator privileges
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# =============================================================================
# Configuration
# =============================================================================

$Script:Config = @{
    Version        = "1.0.0"
    InstallDir     = "C:\ProgramData\OpenTune"
    AgentDir       = "C:\ProgramData\OpenTune\agent"
    ConfigsDir     = "C:\ProgramData\OpenTune\configs"
    LogsDir        = "C:\ProgramData\OpenTune\logs"
    WorkDir        = "C:\ProgramData\OpenTune\work"
    TaskName       = "OpenTune DSC Agent"
    TaskInterval   = 30  # minutes
    
    # Download URLs (hosted on opentune.robertonovara.dev)
    BaseUrl        = "https://opentune.robertonovara.dev"
    AgentScript    = "https://opentune.robertonovara.dev/agent/Agent.ps1"
    ModuleCore     = "https://opentune.robertonovara.dev/agent/modules/DscGitCore.psm1"
    ModuleAdapter  = "https://opentune.robertonovara.dev/agent/modules/OpenTuneAdapter.psm1"
}

# =============================================================================
# UI Helper Functions
# =============================================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                           ║" -ForegroundColor Cyan
    Write-Host "  ║             OpenTune Setup Wizard v$($Script:Config.Version)               ║" -ForegroundColor Cyan
    Write-Host "  ║         GitOps Configuration Management for Windows       ║" -ForegroundColor Cyan
    Write-Host "  ║                                                           ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    
    $icon = switch ($Type) {
        "INFO"    { "○"; $color = "Cyan" }
        "SUCCESS" { "✓"; $color = "Green" }
        "WARN"    { "⚠"; $color = "Yellow" }
        "ERROR"   { "✗"; $color = "Red" }
        "INPUT"   { "?"; $color = "Magenta" }
        default   { "·"; $color = "White" }
    }
    
    Write-Host "  [$icon] " -ForegroundColor $color -NoNewline
    Write-Host $Message
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Read-UserChoice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 1
    )
    
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host ""
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $num = $i + 1
        if ($num -eq $Default) {
            Write-Host "    [$num] $($Options[$i])" -ForegroundColor Yellow -NoNewline
            Write-Host " (default)" -ForegroundColor DarkGray
        } else {
            Write-Host "    [$num] $($Options[$i])" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    $choice = Read-Host "  Enter choice [1-$($Options.Count)]"
    
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $Default
    }
    
    $parsed = 0
    if ([int]::TryParse($choice, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $Options.Count) {
        return $parsed
    }
    
    Write-Step "Invalid choice, using default ($Default)" -Type WARN
    return $Default
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required,
        [switch]$Secret
    )
    
    $displayPrompt = "  $Prompt"
    if (-not [string]::IsNullOrWhiteSpace($Default)) {
        $displayPrompt += " [$Default]"
    }
    $displayPrompt += ": "
    
    if ($Secret) {
        $secureInput = Read-Host $displayPrompt -AsSecureString
        $input = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        )
    } else {
        $input = Read-Host $displayPrompt
    }
    
    if ([string]::IsNullOrWhiteSpace($input)) {
        if ($Required -and [string]::IsNullOrWhiteSpace($Default)) {
            Write-Step "This field is required!" -Type ERROR
            return Read-UserInput -Prompt $Prompt -Default $Default -Required:$Required -Secret:$Secret
        }
        return $Default
    }
    
    return $input
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    
    $defaultText = if ($Default) { "Y/n" } else { "y/N" }
    $input = Read-Host "  $Prompt [$defaultText]"
    
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default
    }
    
    return $input.ToLower() -in @("y", "yes", "si", "s", "1", "true")
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

function Test-Prerequisites {
    Write-Section "Checking Prerequisites"
    
    # Check admin privileges
    Write-Step "Checking administrator privileges..."
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Step "This script requires Administrator privileges!" -Type ERROR
        Write-Host ""
        Write-Host "  Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        Write-Host ""
        throw "Administrator privileges required"
    }
    Write-Step "Administrator privileges confirmed" -Type SUCCESS
    
    # Check PowerShell version
    Write-Step "Checking PowerShell version..."
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        Write-Step "PowerShell 5.1 or higher required (found: $psVersion)" -Type ERROR
        throw "PowerShell version too old"
    }
    Write-Step "PowerShell $psVersion detected" -Type SUCCESS
    
    # Check Windows version
    Write-Step "Checking Windows version..."
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Step "Windows 10 or higher recommended" -Type WARN
    } else {
        Write-Step "Windows $($osVersion.Major).$($osVersion.Minor) detected" -Type SUCCESS
    }
    
    # Check network connectivity
    Write-Step "Checking network connectivity..."
    try {
        $null = Invoke-WebRequest -Uri "https://opentune.robertonovara.dev" -Method Head -TimeoutSec 10 -UseBasicParsing
        Write-Step "Network connectivity OK" -Type SUCCESS
    } catch {
        Write-Step "Cannot reach opentune.robertonovara.dev - check your connection" -Type WARN
    }
    
    # Check for existing installation
    if (Test-Path $Script:Config.AgentDir) {
        Write-Step "Existing OpenTune installation detected" -Type WARN
        $overwrite = Read-YesNo -Prompt "Overwrite existing installation?" -Default $false
        if (-not $overwrite) {
            throw "Installation cancelled by user"
        }
    }
    
    Write-Host ""
    Write-Step "All prerequisites passed!" -Type SUCCESS
    Start-Sleep -Seconds 1
}

# =============================================================================
# Installation Functions
# =============================================================================

function Initialize-Directories {
    Write-Step "Creating directory structure..."
    
    $dirs = @(
        $Script:Config.InstallDir,
        $Script:Config.AgentDir,
        (Join-Path $Script:Config.AgentDir "modules"),
        $Script:Config.ConfigsDir,
        $Script:Config.LogsDir,
        $Script:Config.WorkDir
    )
    
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    
    Write-Step "Directories created at $($Script:Config.InstallDir)" -Type SUCCESS
}

function Get-AgentFiles {
    param(
        [string]$ServerUrl = $null  # For centralized mode, use server URL
    )
    
    Write-Step "Downloading agent components..."
    
    # Determine base URL for downloads
    $baseUrl = if ($ServerUrl) {
        # Centralized mode: download from the OpenTune server
        $ServerUrl.TrimEnd("/")
    } else {
        # Standalone mode: download from opentune.robertonovara.dev
        $Script:Config.BaseUrl
    }
    
    $downloads = @(
        @{
            Name = "Agent.ps1"
            Url  = "$baseUrl/static/agent/Agent.ps1"
            Path = Join-Path $Script:Config.AgentDir "Agent.ps1"
        },
        @{
            Name = "DscGitCore.psm1"
            Url  = "$baseUrl/static/agent/modules/DscGitCore.psm1"
            Path = Join-Path $Script:Config.AgentDir "modules\DscGitCore.psm1"
        },
        @{
            Name = "OpenTuneAdapter.psm1"
            Url  = "$baseUrl/static/agent/modules/OpenTuneAdapter.psm1"
            Path = Join-Path $Script:Config.AgentDir "modules\OpenTuneAdapter.psm1"
        }
    )
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    foreach ($item in $downloads) {
        Write-Step "  Downloading $($item.Name)..." -Type INFO
        try {
            Invoke-WebRequest -Uri $item.Url -OutFile $item.Path -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Step "Failed to download $($item.Name): $($_.Exception.Message)" -Type ERROR
            throw "Download failed"
        }
    }
    
    Write-Step "Agent components downloaded successfully" -Type SUCCESS
}

function Save-Configuration {
    param(
        [hashtable]$ConfigData
    )
    
    Write-Step "Saving configuration..."
    
    $configPath = Join-Path $Script:Config.AgentDir "config.json"
    $configJson = $ConfigData | ConvertTo-Json -Depth 10
    
    Set-Content -Path $configPath -Value $configJson -Force -Encoding UTF8
    
    # Secure the config file (only Administrators and SYSTEM)
    try {
        $acl = Get-Acl $configPath
        $acl.SetAccessRuleProtection($true, $false)
        
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "Allow")
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "Allow")
        
        $acl.SetAccessRule($adminRule)
        $acl.SetAccessRule($systemRule)
        Set-Acl -Path $configPath -AclObject $acl
        
        Write-Step "Configuration saved and secured" -Type SUCCESS
    } catch {
        Write-Step "Configuration saved (could not set ACL: $($_.Exception.Message))" -Type WARN
    }
    
    return $configPath
}

function Register-ScheduledTask {
    Write-Step "Creating scheduled task..."
    
    $agentPath = Join-Path $Script:Config.AgentDir "Agent.ps1"
    
    # Create action
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
    
    # Create triggers: at startup + every 30 minutes
    $triggerStartup = New-ScheduledTaskTrigger -AtStartup
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $Script:Config.TaskInterval) `
        -RepetitionDuration (New-TimeSpan -Days 9999)
    
    # Create principal (run as SYSTEM)
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    # Create settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew
    
    # Remove existing task if present
    Unregister-ScheduledTask -TaskName $Script:Config.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Register new task
    Register-ScheduledTask `
        -TaskName $Script:Config.TaskName `
        -Action $action `
        -Trigger $triggerStartup, $triggerRepeat `
        -Principal $principal `
        -Settings $settings `
        -Description "OpenTune DSC configuration management agent. Runs every $($Script:Config.TaskInterval) minutes." | Out-Null
    
    Write-Step "Scheduled task created: $($Script:Config.TaskName)" -Type SUCCESS
}

function Invoke-FirstRun {
    Write-Section "Initial Run"
    
    Write-Step "Starting first reconciliation..."
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    
    $agentPath = Join-Path $Script:Config.AgentDir "Agent.ps1"
    
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentPath
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Step "Initial run completed" -Type SUCCESS
    } catch {
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Step "Initial run encountered issues: $($_.Exception.Message)" -Type WARN
        Write-Step "The scheduled task will retry automatically" -Type INFO
    }
}

# =============================================================================
# Mode: Centralized
# =============================================================================

function Install-CentralizedMode {
    Write-Section "Centralized Mode Setup"
    
    Write-Host "  In Centralized mode, this node will:" -ForegroundColor Gray
    Write-Host "    • Connect to your OpenTune server" -ForegroundColor Gray
    Write-Host "    • Receive configuration assignments" -ForegroundColor Gray
    Write-Host "    • Report run results back to server" -ForegroundColor Gray
    Write-Host ""
    
    # Collect server information
    $serverUrl = Read-UserInput -Prompt "OpenTune Server URL (e.g., https://opentune.company.com)" -Required
    $serverUrl = $serverUrl.TrimEnd("/")
    
    # Validate server URL
    Write-Step "Validating server connection..."
    try {
        $healthUrl = "$serverUrl/health"
        $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 10 -UseBasicParsing
        Write-Step "Server connection successful" -Type SUCCESS
    } catch {
        Write-Step "Could not connect to server: $($_.Exception.Message)" -Type WARN
        $continue = Read-YesNo -Prompt "Continue anyway?" -Default $false
        if (-not $continue) {
            throw "Server connection failed"
        }
    }
    
    # Collect node credentials
    Write-Host ""
    Write-Step "Enter the Node ID and Token from the OpenTune web UI" -Type INPUT
    Write-Host "  (You can find these when creating a node or in 'Get Bootstrap')" -ForegroundColor Gray
    Write-Host ""
    
    $nodeId = Read-UserInput -Prompt "Node ID" -Required
    $nodeToken = Read-UserInput -Prompt "Node Token" -Required -Secret
    
    # Validate node ID is numeric
    $nodeIdInt = 0
    if (-not [int]::TryParse($nodeId, [ref]$nodeIdInt)) {
        Write-Step "Node ID must be a number!" -Type ERROR
        throw "Invalid Node ID"
    }
    
    # Create configuration
    $config = @{
        mode       = "centralized"
        server_url = $serverUrl
        node_id    = $nodeIdInt
        node_token = $nodeToken
        use_git    = $false
    }
    
    # Perform installation
    Write-Section "Installing Agent"
    
    Initialize-Directories
    Get-AgentFiles -ServerUrl $serverUrl
    $configPath = Save-Configuration -ConfigData $config
    Register-ScheduledTask
    Invoke-FirstRun
    
    # Summary
    Write-Section "Installation Complete"
    
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║              Centralized Mode - Ready!                    ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Installation Details:" -ForegroundColor White
    Write-Host "    • Mode:           Centralized" -ForegroundColor Gray
    Write-Host "    • Server:         $serverUrl" -ForegroundColor Gray
    Write-Host "    • Node ID:        $nodeIdInt" -ForegroundColor Gray
    Write-Host "    • Agent Path:     $($Script:Config.AgentDir)" -ForegroundColor Gray
    Write-Host "    • Config:         $configPath" -ForegroundColor Gray
    Write-Host "    • Scheduled Task: $($Script:Config.TaskName)" -ForegroundColor Gray
    Write-Host "    • Interval:       Every $($Script:Config.TaskInterval) minutes" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next Steps:" -ForegroundColor White
    Write-Host "    1. Assign a policy to this node in the OpenTune web UI" -ForegroundColor Gray
    Write-Host "    2. The agent will apply the configuration on the next run" -ForegroundColor Gray
    Write-Host ""
}

# =============================================================================
# Mode: Standalone
# =============================================================================

function Install-StandaloneMode {
    Write-Section "Standalone Mode Setup"
    
    Write-Host "  In Standalone mode, this node will:" -ForegroundColor Gray
    Write-Host "    • Pull configurations directly from Git or local files" -ForegroundColor Gray
    Write-Host "    • Operate without an OpenTune server" -ForegroundColor Gray
    Write-Host "    • Perfect for air-gapped or CI/CD environments" -ForegroundColor Gray
    Write-Host ""
    
    # Choose source type
    $sourceChoice = Read-UserChoice `
        -Prompt "Select configuration source:" `
        -Options @("Git Repository", "Local File") `
        -Default 1
    
    $config = @{
        mode = "standalone"
    }
    
    if ($sourceChoice -eq 1) {
        # Git Repository
        $config = Install-StandaloneGit
    } else {
        # Local File
        $config = Install-StandaloneLocal
    }
    
    # Perform installation
    Write-Section "Installing Agent"
    
    Initialize-Directories
    Get-AgentFiles  # Standalone uses opentune.robertonovara.dev
    $configPath = Save-Configuration -ConfigData $config
    Register-ScheduledTask
    Invoke-FirstRun
    
    # Summary
    Write-Section "Installation Complete"
    
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║               Standalone Mode - Ready!                    ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Installation Details:" -ForegroundColor White
    Write-Host "    • Mode:           Standalone ($($config.source))" -ForegroundColor Gray
    if ($config.source -eq "git") {
        Write-Host "    • Repository:     $($config.repo_url)" -ForegroundColor Gray
        Write-Host "    • Branch:         $($config.branch)" -ForegroundColor Gray
        Write-Host "    • Config Path:    $($config.config_path)" -ForegroundColor Gray
    } else {
        Write-Host "    • Config File:    $($config.local_config_path)" -ForegroundColor Gray
    }
    Write-Host "    • Agent Path:     $($Script:Config.AgentDir)" -ForegroundColor Gray
    Write-Host "    • Config:         $configPath" -ForegroundColor Gray
    Write-Host "    • Scheduled Task: $($Script:Config.TaskName)" -ForegroundColor Gray
    Write-Host "    • Interval:       Every $($Script:Config.TaskInterval) minutes" -ForegroundColor Gray
    Write-Host ""
}

function Install-StandaloneGit {
    Write-Host ""
    Write-Step "Configuring Git repository source..." -Type INPUT
    Write-Host ""
    
    # Check if Git is installed
    $gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    if (-not $gitAvailable) {
        Write-Step "Git is not installed on this system!" -Type WARN
        Write-Host "  Standalone Git mode requires Git to be installed." -ForegroundColor Yellow
        Write-Host "  Download from: https://git-scm.com/download/win" -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-YesNo -Prompt "Continue anyway (Git must be installed before first run)?" -Default $false
        if (-not $continue) {
            throw "Git not installed"
        }
    } else {
        Write-Step "Git detected: $(git --version)" -Type SUCCESS
    }
    
    # Collect repository info
    $repoUrl = Read-UserInput -Prompt "Git Repository URL" -Required
    $branch = Read-UserInput -Prompt "Branch" -Default "main"
    $configPath = Read-UserInput -Prompt "Config path in repo (e.g., nodes/workstation.ps1)" -Required
    
    # Check for authentication
    $needsAuth = Read-YesNo -Prompt "Does this repository require authentication?" -Default $false
    
    $config = @{
        mode        = "standalone"
        source      = "git"
        repo_url    = $repoUrl
        branch      = $branch
        config_path = $configPath
    }
    
    if ($needsAuth) {
        Write-Host ""
        Write-Step "Enter Git credentials (will be stored in config.json)" -Type INPUT
        Write-Host "  For GitHub, use a Personal Access Token (PAT) as password" -ForegroundColor Gray
        Write-Host ""
        
        $gitUser = Read-UserInput -Prompt "Git Username" -Required
        $gitToken = Read-UserInput -Prompt "Git Password/Token" -Required -Secret
        
        # Embed credentials in URL (common pattern for Git)
        # https://user:token@github.com/org/repo.git
        $uri = [System.Uri]$repoUrl
        $authUrl = "$($uri.Scheme)://${gitUser}:${gitToken}@$($uri.Host)$($uri.PathAndQuery)"
        $config.repo_url = $authUrl
        
        Write-Step "Credentials embedded in repository URL" -Type SUCCESS
    }
    
    return $config
}

function Install-StandaloneLocal {
    Write-Host ""
    Write-Step "Configuring local file source..." -Type INPUT
    Write-Host ""
    
    $filePath = $null
    
    # Try to use OpenFileDialog (GUI)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Select DSC Configuration File"
        $dialog.Filter = "PowerShell DSC Files (*.ps1)|*.ps1|MOF Files (*.mof)|*.mof|All Files (*.*)|*.*"
        $dialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
        
        Write-Host "  Opening file picker dialog..." -ForegroundColor Gray
        
        $result = $dialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $filePath = $dialog.FileName
        }
    } catch {
        Write-Step "GUI file picker not available (Server Core?)" -Type WARN
    }
    
    # Fallback to manual input
    if (-not $filePath) {
        $filePath = Read-UserInput -Prompt "Enter full path to DSC configuration file" -Required
    }
    
    # Validate file exists
    if (-not (Test-Path $filePath)) {
        Write-Step "File not found: $filePath" -Type ERROR
        throw "Configuration file not found"
    }
    
    Write-Step "Selected: $filePath" -Type SUCCESS
    
    # Copy file to OpenTune configs directory
    $fileName = Split-Path $filePath -Leaf
    $destPath = Join-Path $Script:Config.ConfigsDir $fileName
    
    Write-Step "Copying configuration to $destPath..."
    Copy-Item -Path $filePath -Destination $destPath -Force
    Write-Step "Configuration file copied" -Type SUCCESS
    
    $config = @{
        mode              = "standalone"
        source            = "local"
        local_config_path = $destPath
        config_path       = $fileName
    }
    
    return $config
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Start-Setup {
    try {
        Write-Banner
        
        Write-Host "  Welcome to the OpenTune setup wizard!" -ForegroundColor White
        Write-Host "  This will install and configure the OpenTune DSC agent." -ForegroundColor Gray
        Write-Host ""
        
        # Pre-flight checks
        Test-Prerequisites
        
        # Choose mode
        $modeChoice = Read-UserChoice `
            -Prompt "Select installation mode:" `
            -Options @(
                "Centralized - Connect to OpenTune server for management",
                "Standalone  - Use Git repository or local files directly"
            ) `
            -Default 1
        
        if ($modeChoice -eq 1) {
            Install-CentralizedMode
        } else {
            Install-StandaloneMode
        }
        
        # Final message
        Write-Host "  ───────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Thank you for using OpenTune!" -ForegroundColor Cyan
        Write-Host "  Documentation: https://github.com/Pl1n10/opentune" -ForegroundColor Gray
        Write-Host ""
        
    } catch {
        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║                    Setup Failed                           ║" -ForegroundColor Red
        Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  For help, visit: https://github.com/Pl1n10/opentune/issues" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

# Run the setup
Start-Setup
