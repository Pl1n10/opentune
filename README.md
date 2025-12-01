# OpenTune (dsc-cp)

**GitOps Control Plane for Windows DSC**

OpenTune is a self-hosted GitOps control plane for managing Windows configurations
using PowerShell Desired State Configuration (DSC).

## 🎯 Philosophy

- **Git is the source of truth** - All configurations are stored in Git repositories
- **Pull-based model** - Agents pull their desired state, never push commands
- **Self-healing** - Nodes automatically remediate configuration drift
- **Open-source & self-hosted** - No cloud dependencies required

---

## 🚀 Quick Start with Docker

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/opentune.git
cd opentune

# Generate API key and start
export ADMIN_API_KEY=$(openssl rand -base64 32)
echo "Save this key: $ADMIN_API_KEY"

docker compose up -d

# Open http://localhost:8000
```

That's it! 🎉

---

## 📁 Project Structure

```
opentune/
├── backend/              # FastAPI backend (API + serves frontend)
├── frontend/             # React web UI
├── agent/                # PowerShell agent for Windows nodes
├── example-dsc-repo/     # Example DSC configuration repository
├── deploy/               # Systemd & nginx configs (non-Docker)
├── docs/                 # Documentation
├── Dockerfile            # Multi-stage build
├── docker-compose.yml    # Quick start (SQLite)
└── docker-compose.prod.yml  # Production (PostgreSQL)
```

---

## 🐳 Docker Deployment

### Basic (SQLite)

```bash
# Start
ADMIN_API_KEY=your-secret-key docker compose up -d

# View logs
docker compose logs -f

# Stop
docker compose down
```

### Production (PostgreSQL)

```bash
# Copy production config
cp docker-compose.prod.yml docker-compose.override.yml

# Edit passwords!
nano docker-compose.override.yml

# Start
docker compose up -d
```

See [docs/DOCKER.md](docs/DOCKER.md) for full Docker guide.

---

## 🖥️ Manual Deployment (without Docker)

See [docs/DEPLOY.md](docs/DEPLOY.md) for detailed instructions on deploying to a VM.

Quick summary:
```bash
# Install deps
sudo apt install python3 python3-venv nodejs npm git

# Clone & setup
git clone https://github.com/YOUR_USERNAME/opentune.git /opt/opentune
cd /opt/opentune
python3 -m venv venv && source venv/bin/activate
pip install -r backend/requirements.txt
cd frontend && npm install && npm run build && cd ..

# Configure
cp backend/.env.example backend/.env
nano backend/.env  # Set ADMIN_API_KEY

# Run
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

---

## 📖 Usage Workflow

### 1. Access the Web UI

Open `http://your-server:8000` and enter your `ADMIN_API_KEY`.

### 2. Add a Git Repository

Repositories → Add Repository
- Name: `security-baseline`
- URL: `https://github.com/yourorg/dsc-configs.git`
- Branch: `main`

### 3. Create a Policy

Policies → Add Policy
- Name: `workstation-security`
- Repository: select your repo
- Config Path: `nodes/workstation.ps1`

### 4. Register a Node

Nodes → Add Node
- Name: `pc-genitori`
- **⚠️ Save the token!** It's shown only once.

### 5. Assign Policy to Node

Click on the node → Select policy → Assign

### 6. Install Agent on Windows

```powershell
.\Install-DscCpAgent.ps1 `
  -ControlPlaneUrl "http://your-server:8000" `
  -NodeId 1 `
  -NodeToken "TOKEN-FROM-STEP-4"
```

The agent runs every 30 minutes and:
1. Fetches desired state from OpenTune
2. Pulls the Git repository
3. Compiles & applies DSC configuration
4. Reports results back

---

## 📋 API Reference

### Admin Endpoints (require `X-Admin-API-Key`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/nodes` | List nodes |
| POST | `/api/v1/nodes` | Create node |
| PUT | `/api/v1/nodes/{id}/policy` | Assign policy |
| GET | `/api/v1/repositories` | List repos |
| POST | `/api/v1/repositories` | Add repo |
| GET | `/api/v1/policies` | List policies |
| POST | `/api/v1/policies` | Create policy |
| GET | `/api/v1/runs` | List runs |
| GET | `/api/v1/runs/stats` | Get statistics |

### Agent Endpoints (require `X-Node-Token`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/agents/nodes/{id}/desired-state` | Get config |
| POST | `/api/v1/agents/nodes/{id}/runs` | Report run |
| POST | `/api/v1/agents/nodes/{id}/heartbeat` | Heartbeat |

Full API docs at `/api/docs` (Swagger UI).

---

## 📦 DSC Repository Structure

See `example-dsc-repo/` for a working example:

```
dsc-config-repo/
├── baselines/
│   ├── common.ps1       # Windows Update, Time service
│   └── security.ps1     # Defender, Firewall, UAC, SMBv1
├── nodes/
│   └── workstation.ps1  # Node-specific config
└── mof/                 # Compiled MOF output
```

---

## 🔐 Security

- Admin API uses `X-Admin-API-Key` header
- Node tokens hashed with bcrypt
- Tokens shown only once at creation
- HTTPS recommended for production
- Git auth via HTTPS + PAT

---

## 🛣️ Roadmap

- [x] FastAPI backend
- [x] React web UI
- [x] Docker support
- [x] PostgreSQL support
- [ ] Webhook notifications
- [ ] Node groups/tags
- [ ] RBAC
- [ ] Audit logging
- [ ] Dark mode

---

## 📄 License

MIT License
