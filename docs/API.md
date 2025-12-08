# OpenTune API Reference

Complete REST API documentation for OpenTune v1.0.

## Overview

OpenTune exposes two distinct API surfaces:

| API Surface | Authentication | Purpose |
|-------------|----------------|---------|
| **Admin API** | `X-Admin-API-Key` header | Manage nodes, policies, repositories |
| **Agent API** | `X-Node-Token` header | Fetch config, report runs, heartbeat |

Base URL: `http://your-server:8000/api/v1`

---

## Authentication

### Admin Authentication

All admin endpoints require the `X-Admin-API-Key` header:

```bash
curl -H "X-Admin-API-Key: your-secret-key" \
     http://localhost:8000/api/v1/nodes/
```

### Agent Authentication

Agent endpoints require the `X-Node-Token` header with the node's unique token:

```bash
curl -H "X-Node-Token: node-token-from-registration" \
     http://localhost:8000/api/v1/agents/nodes/1/desired-state
```

### Error Response

Authentication failures return:

```json
{
  "detail": "Invalid or missing API key"
}
```

HTTP Status: `401 Unauthorized` or `403 Forbidden`

---

## Common Response Models

### Error Model

```json
{
  "detail": "Human-readable error message"
}
```

### Pagination

List endpoints support optional pagination:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `skip` | int | 0 | Number of records to skip |
| `limit` | int | 100 | Maximum records to return |

---

## Admin API

### Nodes

#### List Nodes

```
GET /api/v1/nodes/
```

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "name": "workstation-01",
    "assigned_policy_id": 1,
    "last_seen_at": "2024-01-15T10:30:00Z",
    "last_status": "success",
    "created_at": "2024-01-10T09:00:00Z"
  }
]
```

#### Create Node

```
POST /api/v1/nodes/
```

**Request:**

```json
{
  "name": "workstation-01"
}
```

**Response:** `201 Created`

```json
{
  "node": {
    "id": 1,
    "name": "workstation-01",
    "assigned_policy_id": null,
    "last_seen_at": null,
    "last_status": null,
    "created_at": "2024-01-15T10:00:00Z"
  },
  "token": "abc123def456..."
}
```

> ⚠️ **Important:** The `token` is only returned once. Store it securely.

#### Get Node

```
GET /api/v1/nodes/{node_id}
```

**Response:** `200 OK`

```json
{
  "id": 1,
  "name": "workstation-01",
  "assigned_policy_id": 1,
  "last_seen_at": "2024-01-15T10:30:00Z",
  "last_status": "success",
  "created_at": "2024-01-10T09:00:00Z"
}
```

#### Delete Node

```
DELETE /api/v1/nodes/{node_id}
```

**Response:** `200 OK`

```json
{
  "ok": true,
  "message": "Node deleted"
}
```

#### Assign Policy to Node

```
PUT /api/v1/nodes/{node_id}/policy
```

**Request:**

```json
{
  "policy_id": 1
}
```

**Response:** `200 OK`

```json
{
  "id": 1,
  "name": "workstation-01",
  "assigned_policy_id": 1,
  "last_seen_at": null,
  "last_status": null,
  "created_at": "2024-01-10T09:00:00Z"
}
```

To unassign a policy, send `policy_id: null`.

#### Regenerate Node Token

```
POST /api/v1/nodes/{node_id}/regenerate-token
```

**Response:** `200 OK`

```json
{
  "token": "new-token-xyz789..."
}
```

> The old token is immediately invalidated.

#### Get Bootstrap Info

```
POST /api/v1/nodes/{node_id}/bootstrap
```

Regenerates the token and returns bootstrap URL.

**Response:** `200 OK`

```json
{
  "node": {
    "id": 1,
    "name": "workstation-01"
  },
  "token": "new-token-xyz789...",
  "bootstrap_url": "http://server:8000/api/v1/agents/nodes/1/bootstrap.ps1?token=new-token-xyz789..."
}
```

#### Get Node Runs

```
GET /api/v1/nodes/{node_id}/runs
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 20 | Maximum runs to return |

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "node_id": 1,
    "policy_id": 1,
    "git_commit": "abc123",
    "status": "success",
    "summary": "Configuration applied successfully",
    "started_at": "2024-01-15T10:30:00Z",
    "finished_at": "2024-01-15T10:31:00Z"
  }
]
```

---

### Repositories

#### List Repositories

```
GET /api/v1/repositories/
```

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "name": "security-baseline",
    "url": "https://github.com/org/dsc-configs.git",
    "branch": "main",
    "created_at": "2024-01-10T09:00:00Z"
  }
]
```

#### Create Repository

```
POST /api/v1/repositories/
```

**Request:**

```json
{
  "name": "security-baseline",
  "url": "https://github.com/org/dsc-configs.git",
  "branch": "main"
}
```

For private repositories, include credentials in URL:

```json
{
  "name": "private-configs",
  "url": "https://TOKEN@github.com/org/private-repo.git",
  "branch": "main"
}
```

**Response:** `201 Created`

```json
{
  "id": 1,
  "name": "security-baseline",
  "url": "https://github.com/org/dsc-configs.git",
  "branch": "main",
  "created_at": "2024-01-15T10:00:00Z"
}
```

#### Get Repository

```
GET /api/v1/repositories/{repo_id}
```

**Response:** `200 OK`

#### Update Repository

```
PUT /api/v1/repositories/{repo_id}
```

**Request:**

```json
{
  "name": "new-name",
  "url": "https://github.com/org/new-repo.git",
  "branch": "develop"
}
```

**Response:** `200 OK`

#### Delete Repository

```
DELETE /api/v1/repositories/{repo_id}
```

**Response:** `200 OK`

```json
{
  "ok": true,
  "message": "Repository deleted"
}
```

> ⚠️ Cannot delete a repository that is referenced by policies.

---

### Policies

#### List Policies

```
GET /api/v1/policies/
```

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "name": "workstation-security",
    "repository_id": 1,
    "config_path": "nodes/workstation.ps1",
    "created_at": "2024-01-10T09:00:00Z"
  }
]
```

#### Create Policy

```
POST /api/v1/policies/
```

**Request:**

```json
{
  "name": "workstation-security",
  "repository_id": 1,
  "config_path": "nodes/workstation.ps1"
}
```

**Response:** `201 Created`

```json
{
  "id": 1,
  "name": "workstation-security",
  "repository_id": 1,
  "config_path": "nodes/workstation.ps1",
  "created_at": "2024-01-15T10:00:00Z"
}
```

#### Get Policy

```
GET /api/v1/policies/{policy_id}
```

**Response:** `200 OK`

#### Update Policy

```
PUT /api/v1/policies/{policy_id}
```

**Request:**

```json
{
  "name": "updated-policy",
  "repository_id": 2,
  "config_path": "nodes/new-config.ps1"
}
```

**Response:** `200 OK`

#### Delete Policy

```
DELETE /api/v1/policies/{policy_id}
```

**Response:** `200 OK`

> ⚠️ Cannot delete a policy that is assigned to nodes.

---

### Runs

#### List Runs

```
GET /api/v1/runs/
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `skip` | int | 0 | Records to skip |
| `limit` | int | 100 | Maximum records |
| `node_id` | int | null | Filter by node |
| `policy_id` | int | null | Filter by policy |
| `status` | string | null | Filter by status |

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "node_id": 1,
    "policy_id": 1,
    "git_commit": "abc123def456",
    "status": "success",
    "summary": "Configuration applied successfully in 45s",
    "started_at": "2024-01-15T10:30:00Z",
    "finished_at": "2024-01-15T10:31:00Z"
  }
]
```

**Status Values:**

| Status | Description |
|--------|-------------|
| `success` | Configuration applied successfully |
| `failed` | Configuration failed to apply |
| `skipped` | No policy assigned or already in desired state |
| `error` | Agent error (network, parsing, etc.) |

#### Get Run Statistics

```
GET /api/v1/runs/stats
```

**Response:** `200 OK`

```json
{
  "total_runs": 150,
  "success_count": 140,
  "failed_count": 8,
  "skipped_count": 2,
  "success_rate": 93.33,
  "runs_last_24h": 48,
  "runs_last_7d": 336
}
```

---

## Agent API

These endpoints are called by the OpenTune agent running on Windows nodes.

### Get Desired State

```
GET /api/v1/agents/nodes/{node_id}/desired-state
```

**Headers:** `X-Node-Token: <token>`

**Response:** `200 OK`

```json
{
  "node_id": 1,
  "node_name": "workstation-01",
  "policy_assigned": true,
  "policy_id": 1,
  "policy_name": "workstation-security",
  "config_path": "nodes/workstation.ps1",
  "repository": {
    "id": 1,
    "url": "https://github.com/org/dsc-configs.git",
    "branch": "main"
  },
  "package_url": "http://server:8000/api/v1/agents/nodes/1/package"
}
```

If no policy is assigned:

```json
{
  "node_id": 1,
  "node_name": "workstation-01",
  "policy_assigned": false,
  "policy_id": null,
  "policy_name": null,
  "config_path": null,
  "repository": null,
  "package_url": null
}
```

### Download Configuration Package

```
GET /api/v1/agents/nodes/{node_id}/package
```

**Headers:** `X-Node-Token: <token>`

**Response:** `200 OK`

Returns a ZIP file containing:
- The DSC configuration file
- Supporting files (baselines, modules)
- Metadata file (`_opentune_meta.txt`)

**Response Headers:**

| Header | Description |
|--------|-------------|
| `Content-Type` | `application/zip` |
| `Content-Disposition` | `attachment; filename="config-{policy_id}.zip"` |
| `X-Commit-Hash` | Git commit hash of the configuration |
| `X-Package-Hash` | SHA256 hash of the ZIP contents |

### Report Run

```
POST /api/v1/agents/nodes/{node_id}/runs
```

**Headers:** `X-Node-Token: <token>`

**Request:**

```json
{
  "policy_id": 1,
  "git_commit": "abc123def456",
  "status": "success",
  "summary": "Configuration applied successfully in 45s",
  "started_at": "2024-01-15T10:30:00Z"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `policy_id` | int | Yes | ID of the applied policy |
| `git_commit` | string | No | Commit hash of the configuration |
| `status` | string | Yes | One of: `success`, `failed`, `skipped`, `error` |
| `summary` | string | No | Human-readable result description |
| `started_at` | datetime | No | When the run started (defaults to now) |

**Response:** `200 OK`

```json
{
  "ok": true,
  "run_id": 42,
  "message": "Run recorded with status: success"
}
```

### Heartbeat

```
POST /api/v1/agents/nodes/{node_id}/heartbeat
```

**Headers:** `X-Node-Token: <token>`

Updates `last_seen_at` without reporting a run. Useful when no policy is assigned.

**Response:** `200 OK`

```json
{
  "ok": true,
  "server_time": "2024-01-15T10:30:00Z",
  "node_id": 1,
  "node_name": "workstation-01"
}
```

---

## Bootstrap Endpoints

### Download Bootstrap Script

```
GET /api/v1/agents/nodes/{node_id}/bootstrap.ps1?token={token}
```

**Authentication:** Token passed as query parameter (for easy download).

**Response:** `200 OK`

Returns a PowerShell script (`.ps1`) with embedded configuration:
- Server URL
- Node ID
- Node Token

The script:
1. Creates agent directory structure
2. Downloads agent and modules
3. Writes secure configuration
4. Creates Windows Scheduled Task
5. Runs initial reconciliation

**Content-Type:** `text/plain; charset=utf-8`

---

## Static Files

The server serves agent files at `/static/agent/`:

| Path | Description |
|------|-------------|
| `/static/agent/Agent.ps1` | Main agent script |
| `/static/agent/modules/DscGitCore.psm1` | DSC execution engine |
| `/static/agent/modules/OpenTuneAdapter.psm1` | Control plane adapter |

These files require no authentication.

---

## Health Check

```
GET /health
```

**Response:** `200 OK`

```json
{
  "status": "healthy"
}
```

Used for monitoring and load balancer health checks.

---

## OpenAPI Documentation

Interactive API documentation is available at:

| URL | Format |
|-----|--------|
| `/api/docs` | Swagger UI |
| `/api/redoc` | ReDoc |
| `/api/openapi.json` | OpenAPI 3.0 JSON schema |

---

## Rate Limiting

Currently, OpenTune does not implement rate limiting. For production deployments, consider using a reverse proxy (nginx, Traefik) with rate limiting enabled.

Recommended limits:
- Admin API: 100 requests/minute
- Agent API: 10 requests/minute per node

---

## Error Codes

| HTTP Code | Meaning |
|-----------|---------|
| `200` | Success |
| `201` | Created |
| `400` | Bad Request - Invalid input |
| `401` | Unauthorized - Missing credentials |
| `403` | Forbidden - Invalid credentials |
| `404` | Not Found - Resource doesn't exist |
| `409` | Conflict - Resource already exists or referenced |
| `422` | Unprocessable Entity - Validation error |
| `500` | Internal Server Error |

---

## SDK Examples

### Python

```python
import requests

BASE_URL = "http://localhost:8000/api/v1"
API_KEY = "your-admin-api-key"

headers = {"X-Admin-API-Key": API_KEY}

# List nodes
response = requests.get(f"{BASE_URL}/nodes/", headers=headers)
nodes = response.json()

# Create node
response = requests.post(
    f"{BASE_URL}/nodes/",
    headers=headers,
    json={"name": "new-workstation"}
)
result = response.json()
print(f"Token: {result['token']}")  # Save this!
```

### PowerShell

```powershell
$baseUrl = "http://localhost:8000/api/v1"
$apiKey = "your-admin-api-key"

$headers = @{
    "X-Admin-API-Key" = $apiKey
    "Content-Type" = "application/json"
}

# List nodes
$nodes = Invoke-RestMethod -Uri "$baseUrl/nodes/" -Headers $headers

# Create node
$body = @{ name = "new-workstation" } | ConvertTo-Json
$result = Invoke-RestMethod -Uri "$baseUrl/nodes/" -Method Post -Headers $headers -Body $body
Write-Host "Token: $($result.token)"  # Save this!
```

### curl

```bash
# List nodes
curl -H "X-Admin-API-Key: your-key" http://localhost:8000/api/v1/nodes/

# Create node
curl -X POST \
     -H "X-Admin-API-Key: your-key" \
     -H "Content-Type: application/json" \
     -d '{"name": "new-workstation"}' \
     http://localhost:8000/api/v1/nodes/
```
