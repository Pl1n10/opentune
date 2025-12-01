# dsc-cp Example DSC Configuration Repository

This repository demonstrates the recommended structure for DSC configurations
managed by the **dsc-cp** GitOps control plane.

## Directory Structure

```
dsc-config-repo/
│
├── README.md                 # This file
│
├── baselines/                # Reusable configuration modules
│   ├── common.ps1            # Common OS configuration
│   └── security.ps1          # Security hardening baseline
│
├── nodes/                    # Node-specific configurations
│   └── pc-genitori.ps1       # Example: family PC configuration
│
└── mof/                      # Compiled MOF output (auto-generated)
    └── pc-genitori/          # MOFs for pc-genitori node
```

## How It Works

### Baselines (`baselines/`)

Baselines are **reusable DSC configurations** that can be shared across multiple nodes.
They define common patterns like:

- `common.ps1` - Basic OS settings (Windows Update, etc.)
- `security.ps1` - Security hardening (Defender, Firewall, UAC, etc.)

### Node Configurations (`nodes/`)

Each node has its own configuration file that:

1. Imports relevant baselines
2. Compiles baseline MOFs
3. Adds node-specific settings
4. Generates the final MOF files

### MOF Output (`mof/`)

This directory contains compiled MOF files. The dsc-cp agent will:

1. Run the `.ps1` configuration script
2. The script generates MOFs in this directory
3. The agent applies the MOFs using `Start-DscConfiguration`

## Usage with dsc-cp

1. **Register this repository** in dsc-cp:
   ```
   POST /api/v1/repositories
   {
     "name": "security-baseline",
     "url": "https://github.com/yourorg/dsc-configs.git",
     "default_branch": "main"
   }
   ```

2. **Create a policy** pointing to a node config:
   ```
   POST /api/v1/policies
   {
     "name": "family-pc-policy",
     "git_repository_id": 1,
     "config_path": "nodes/pc-genitori.ps1"
   }
   ```

3. **Assign the policy** to a node:
   ```
   PUT /api/v1/nodes/1/policy
   {
     "policy_id": 1
   }
   ```

4. The agent will automatically pull, compile, and apply the configuration.

## Prerequisites

The target Windows machine needs:

- PowerShell 5.1+ (or PowerShell 7)
- Git for Windows
- DSC resources used in configs (e.g., PSDesiredStateConfiguration)

## Testing Locally

```powershell
# Navigate to the repo
cd dsc-config-repo

# Run a node configuration to generate MOFs
. .\nodes\pc-genitori.ps1

# Test the configuration
Test-DscConfiguration -Path .\mof\pc-genitori

# Apply the configuration
Start-DscConfiguration -Path .\mof\pc-genitori -Wait -Verbose -Force
```

## Adding New Nodes

1. Create a new file in `nodes/` (e.g., `nodes/server-web-01.ps1`)
2. Import the baselines you need
3. Add node-specific configuration
4. Create a policy in dsc-cp pointing to the new file
5. Assign the policy to the appropriate node

## Security Considerations

- Never commit secrets to this repository
- Use Windows Credential Manager for sensitive data
- Consider using a private Git repository with PAT authentication
