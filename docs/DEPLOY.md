# OpenTune - Guida al Deploy su VM

Questa guida ti accompagna nel deploy di OpenTune su una VM Ubuntu.

## Prerequisiti

- VM con Ubuntu 22.04 LTS (o superiore)
- Almeno 1GB RAM, 10GB disco
- Accesso SSH con sudo
- (Opzionale) Dominio per HTTPS

---

## Parte 1: Preparazione del Repository Git

### Sul tuo computer locale

```bash
# 1. Estrai lo ZIP
unzip opentune-complete.zip
cd dsc-cp

# 2. Inizializza il repository Git
git init

# 3. Aggiungi tutti i file
git add .

# 4. Primo commit
git commit -m "Initial commit: OpenTune v0.2.0

- FastAPI backend with SQLite
- React frontend with Tailwind
- PowerShell DSC agent
- Example DSC configurations"

# 5. Crea il repository su GitHub
#    Vai su https://github.com/new
#    Nome: opentune (o quello che preferisci)
#    NON inizializzare con README (già presente)

# 6. Collega e pusha
git remote add origin https://github.com/TUO_USERNAME/opentune.git
git branch -M main
git push -u origin main
```

---

## Parte 2: Setup della VM

### Connettiti alla VM

```bash
ssh user@IP_DELLA_VM
```

### Installa le dipendenze base

```bash
# Aggiorna il sistema
sudo apt update && sudo apt upgrade -y

# Installa dipendenze
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl

# Installa Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Verifica le installazioni
python3 --version   # Dovrebbe essere 3.10+
node --version      # Dovrebbe essere 20.x
npm --version       # Dovrebbe essere 10.x
```

---

## Parte 3: Clone e Setup

### Clona il repository

```bash
# Crea la directory
sudo mkdir -p /opt/opentune
sudo chown $USER:$USER /opt/opentune

# Clona il repo
git clone https://github.com/TUO_USERNAME/opentune.git /opt/opentune

# Vai nella directory
cd /opt/opentune
```

### Setup Backend

```bash
# Crea virtual environment Python
python3 -m venv venv
source venv/bin/activate

# Installa dipendenze
pip install --upgrade pip
pip install -r backend/requirements.txt

# Crea file di configurazione
cp backend/.env.example backend/.env

# Genera una API key sicura
python3 -c "import secrets; print('ADMIN_API_KEY=' + secrets.token_urlsafe(32))"
# Copia l'output e sostituiscilo nel file .env

# Modifica il file .env
nano backend/.env
```

Esempio `.env`:
```env
PROJECT_NAME=opentune
DATABASE_URL=sqlite:///./opentune.db
ADMIN_API_KEY=TUA_API_KEY_GENERATA
DEBUG=false
```

### Build Frontend

```bash
cd /opt/opentune/frontend

# Installa dipendenze Node
npm install

# Build per produzione
npm run build

# Verifica che dist/ sia stato creato
ls -la dist/
```

---

## Parte 4: Test Manuale

Prima di configurare il servizio, testa che tutto funzioni:

```bash
cd /opt/opentune/backend
source ../venv/bin/activate

# Avvia il server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Apri nel browser: `http://IP_VM:8000`

Se vedi la pagina di login, funziona! Premi `Ctrl+C` per fermare.

---

## Parte 5: Configurazione Servizio Systemd

### Crea l'utente di sistema

```bash
sudo useradd --system --no-create-home --shell /bin/false opentune
```

### Imposta i permessi

```bash
sudo chown -R opentune:opentune /opt/opentune
```

### Installa il servizio

```bash
# Copia il file service
sudo cp /opt/opentune/deploy/opentune.service /etc/systemd/system/

# Ricarica systemd
sudo systemctl daemon-reload

# Abilita all'avvio
sudo systemctl enable opentune

# Avvia il servizio
sudo systemctl start opentune

# Verifica lo stato
sudo systemctl status opentune
```

### Comandi utili

```bash
# Visualizza i log in tempo reale
sudo journalctl -u opentune -f

# Riavvia il servizio
sudo systemctl restart opentune

# Ferma il servizio
sudo systemctl stop opentune
```

---

## Parte 6: Firewall

```bash
# Se usi UFW (Ubuntu Firewall)
sudo ufw allow 8000/tcp
sudo ufw status

# Oppure se usi iptables
sudo iptables -A INPUT -p tcp --dport 8000 -j ACCEPT
```

---

## Parte 7: (Opzionale) HTTPS con Nginx

### Installa Nginx

```bash
sudo apt install -y nginx
```

### Configura il virtual host

```bash
# Copia la configurazione
sudo cp /opt/opentune/deploy/opentune.nginx /etc/nginx/sites-available/opentune

# Modifica il dominio
sudo nano /etc/nginx/sites-available/opentune
# Cambia "opentune.yourdomain.com" con il tuo dominio

# Abilita il sito
sudo ln -s /etc/nginx/sites-available/opentune /etc/nginx/sites-enabled/

# Testa la configurazione
sudo nginx -t

# Ricarica nginx
sudo systemctl reload nginx
```

### Aggiungi HTTPS con Let's Encrypt

```bash
# Installa certbot
sudo apt install -y certbot python3-certbot-nginx

# Ottieni il certificato (segui le istruzioni)
sudo certbot --nginx -d opentune.tuodominio.com

# Il certificato si rinnova automaticamente
sudo systemctl status certbot.timer
```

---

## Parte 8: Primo Accesso

1. Apri `http://IP_VM:8000` (o `https://tuodominio.com` se hai configurato nginx)
2. Inserisci la `ADMIN_API_KEY` dal file `.env`
3. Sei dentro! 🎉

### Workflow iniziale

1. **Repositories** → Aggiungi il tuo repo Git con le config DSC
2. **Policies** → Crea una policy che punta a un file di config
3. **Nodes** → Aggiungi un nodo (salva il token!)
4. **Nodes** → Assegna la policy al nodo
5. Sul PC Windows, installa l'agent con il token

---

## Troubleshooting

### Il servizio non parte

```bash
# Controlla i log
sudo journalctl -u opentune -n 100 --no-pager

# Errori comuni:
# - Permessi: sudo chown -R opentune:opentune /opt/opentune
# - .env mancante: verifica che esista backend/.env
# - Porta occupata: sudo lsof -i :8000
```

### Frontend non carica

```bash
# Verifica che il build esista
ls -la /opt/opentune/frontend/dist/

# Se manca, rebuild
cd /opt/opentune/frontend
npm run build
sudo systemctl restart opentune
```

### Database reset

```bash
# Per ricominciare da zero
sudo systemctl stop opentune
rm /opt/opentune/backend/opentune.db
sudo systemctl start opentune
```

---

## Aggiornamenti

Per aggiornare a una nuova versione:

```bash
cd /opt/opentune

# Ferma il servizio
sudo systemctl stop opentune

# Pull delle modifiche
git pull origin main

# Aggiorna dipendenze Python
source venv/bin/activate
pip install -r backend/requirements.txt

# Rebuild frontend
cd frontend
npm install
npm run build

# Riavvia
sudo systemctl start opentune
```

---

## Riepilogo Comandi

| Azione | Comando |
|--------|---------|
| Stato servizio | `sudo systemctl status opentune` |
| Avvia | `sudo systemctl start opentune` |
| Ferma | `sudo systemctl stop opentune` |
| Riavvia | `sudo systemctl restart opentune` |
| Log live | `sudo journalctl -u opentune -f` |
| Ultimi 100 log | `sudo journalctl -u opentune -n 100` |

---

Buon deploy! 🚀
