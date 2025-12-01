# OpenTune - Docker Deployment Guide

La via più semplice per deployare OpenTune.

## Quick Start (30 secondi)

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/opentune.git
cd opentune

# 2. Generate a secure API key
export ADMIN_API_KEY=$(openssl rand -base64 32)
echo "Your API Key: $ADMIN_API_KEY"

# 3. Start!
docker compose up -d

# 4. Open http://localhost:8000
```

---

## Comandi Essenziali

```bash
# Avvia
docker compose up -d

# Ferma
docker compose down

# Vedi i log
docker compose logs -f

# Riavvia
docker compose restart

# Rebuild dopo modifiche
docker compose up -d --build

# Stato
docker compose ps
```

---

## Configurazione

### Variabili d'ambiente

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `ADMIN_API_KEY` | `CHANGE-ME...` | **Obbligatorio!** Chiave per accesso admin |
| `DATABASE_URL` | `sqlite:///./data/opentune.db` | Connection string database |
| `PROJECT_NAME` | `opentune` | Nome progetto (UI) |
| `DEBUG` | `false` | Abilita log SQL |

### Metodo 1: Variabili inline

```bash
ADMIN_API_KEY=mia-chiave-segreta docker compose up -d
```

### Metodo 2: File .env

```bash
# Crea file .env nella root del progetto
cat > .env << EOF
ADMIN_API_KEY=mia-chiave-segreta-molto-lunga
PROJECT_NAME=opentune
DEBUG=false
EOF

# Avvia (legge automaticamente .env)
docker compose up -d
```

---

## Persistenza Dati

I dati sono salvati in un Docker volume chiamato `opentune_data`.

```bash
# Vedi i volumi
docker volume ls

# Backup del database SQLite
docker compose exec opentune cat /app/data/opentune.db > backup.db

# Restore
docker compose down
docker run --rm -v opentune_data:/data -v $(pwd):/backup alpine \
  cp /backup/backup.db /data/opentune.db
docker compose up -d
```

---

## Produzione con PostgreSQL

Per ambienti production, usa PostgreSQL invece di SQLite:

```bash
# Usa il compose di produzione
cp docker-compose.prod.yml docker-compose.override.yml

# IMPORTANTE: Modifica le password!
nano docker-compose.override.yml

# Avvia
docker compose up -d
```

Il file `docker-compose.override.yml` viene automaticamente mergiato con `docker-compose.yml`.

---

## HTTPS con Traefik

Esempio con Traefik come reverse proxy:

```yaml
# docker-compose.override.yml
services:
  opentune:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.opentune.rule=Host(`opentune.tuodominio.com`)"
      - "traefik.http.routers.opentune.entrypoints=websecure"
      - "traefik.http.routers.opentune.tls.certresolver=letsencrypt"
    networks:
      - traefik
    ports: []  # Rimuovi la porta pubblica

networks:
  traefik:
    external: true
```

---

## HTTPS con Nginx (esterno)

Se hai già Nginx sulla VM host:

```bash
# docker-compose.override.yml - esponi solo su localhost
services:
  opentune:
    ports:
      - "127.0.0.1:8000:8000"
```

```nginx
# /etc/nginx/sites-available/opentune
server {
    listen 80;
    server_name opentune.tuodominio.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name opentune.tuodominio.com;

    ssl_certificate /etc/letsencrypt/live/opentune.tuodominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/opentune.tuodominio.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Troubleshooting

### Container non parte

```bash
# Vedi i log
docker compose logs opentune

# Entra nel container per debug
docker compose exec opentune /bin/bash
```

### Database locked (SQLite)

```bash
# Riavvia il container
docker compose restart opentune
```

### Porta già in uso

```bash
# Cambia porta nel docker-compose.yml o usa override
# docker-compose.override.yml
services:
  opentune:
    ports:
      - "9000:8000"  # Usa porta 9000 invece di 8000
```

### Reset completo

```bash
# ⚠️ ATTENZIONE: cancella tutti i dati!
docker compose down -v
docker compose up -d
```

---

## Aggiornamenti

```bash
# Pull nuova versione
git pull origin main

# Rebuild e riavvia
docker compose up -d --build
```

---

## Monitoring

### Health check manuale

```bash
curl http://localhost:8000/health
# {"status":"healthy"}
```

### Con Prometheus (esempio)

Il health check endpoint può essere usato con qualsiasi sistema di monitoring:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'opentune'
    static_configs:
      - targets: ['opentune:8000']
    metrics_path: /health
```

---

## Build Locale dell'Immagine

Se vuoi buildare l'immagine senza docker-compose:

```bash
# Build
docker build -t opentune:latest .

# Run
docker run -d \
  --name opentune \
  -p 8000:8000 \
  -e ADMIN_API_KEY=tua-chiave \
  -v opentune_data:/app/data \
  opentune:latest
```

---

## Architettura Container

```
┌─────────────────────────────────────┐
│           Docker Container          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │     Python (FastAPI)        │   │
│  │     - API endpoints         │   │
│  │     - Serves React frontend │   │
│  └─────────────────────────────┘   │
│                │                    │
│                ▼                    │
│  ┌─────────────────────────────┐   │
│  │   /app/data/opentune.db     │   │
│  │   (SQLite - volume mount)   │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
         │
         ▼ Port 8000
    ┌─────────┐
    │ Browser │
    └─────────┘
```

Con PostgreSQL:

```
┌────────────────┐     ┌────────────────┐
│   opentune     │────▶│   PostgreSQL   │
│   container    │     │   container    │
└────────────────┘     └────────────────┘
        │
        ▼ Port 8000
   ┌─────────┐
   │ Browser │
   └─────────┘
```
