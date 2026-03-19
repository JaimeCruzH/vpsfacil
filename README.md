# VPSfacil - Automated VPS Installation System

**VPSfacil** is an interactive, automated installation system that enables non-technical users to deploy a complete VPS stack on Contabo (Debian 12) with a single command.

## Quick Start

### Prerequisites
- Contabo VPS running Debian 12
- SSH access to VPS (via root or sudo user)
- Domain: `agentexperto.work` with Cloudflare DNS
- Windows 11 PC with Bitvise SSH Client

### Installation Command

Run this command on your Debian 12 VPS:

```bash
bash <(curl -sSL setup.agentexperto.work)
```

Or, to install from a local file:

```bash
bash setup.sh
```

## What Gets Installed

### Core Components (Required)
1. **User Setup** — Create secure `jaime` user with SSH key auth
2. **Docker & Portainer** — Container runtime and management UI
3. **Nginx Proxy Manager** — Reverse proxy with SSL/TLS certificates
4. **UFW Firewall** — Security firewall with sensible defaults
5. **Tailscale** — VPN access to VPS
6. **Kopia Backup** — Automated backup solution

### Optional Applications
- **N8N** — Workflow automation platform
- **OpenClaw** — Custom application
- **File Browser** — Web-based file manager

## Directory Structure

All applications are installed under `/home/jaime/apps/`:

```
/home/jaime/apps/
├── nginx/          # Reverse proxy
├── portainer/      # Container management
├── tailscale/      # VPN access
├── kopia/          # Backup solution
├── n8n/            # Workflow automation (optional)
├── openclaw/       # Custom app (optional)
├── filebrowser/    # File manager (optional)
└── backups/        # Backup storage
```

Each application folder contains:
- `docker-compose.yml` — Service configuration
- `.env` — Environment variables and secrets
- `data/` — Persistent storage volume
- `config/` — Application-specific configuration

## Key Features

### 🎯 Interactive Installation
- Step-by-step guidance with clear prompts
- Instructions for both server (VPS) and client (Windows PC)
- Color-coded messages (Info, Success, Warning, Error)
- Confirmation before destructive actions

### 🔒 Security First
- SSH key-based authentication only (no passwords)
- Firewall enabled by default
- Rootless operation (everything runs as `jaime` user)
- Automated backups with encryption

### 📦 Easy Management
- All apps in one organized location
- Individual app backup/restore
- Docker Compose for standardized deployment
- Portainer UI for visual management

### 🔄 Restorable
- Single app: `tar -czf appname-backup.tar.gz /home/jaime/apps/appname/`
- All apps: `tar -czf full-apps-backup.tar.gz /home/jaime/apps/`
- Kopia automates incremental backups

## Progress Tracking & Recovery

### Automatic Progress Saving

If the installation is interrupted (network issue, timeout, etc.), **your progress is automatically saved**. You don't need to re-enter data or re-run completed steps.

**How it works:**
1. All your configuration (domain, username, passwords) is saved to `/tmp/vpsfacil_install.conf` after FASE A
2. Each completed step is recorded in `/tmp/vpsfacil_core_progress.log`
3. When you reconnect and re-run `install_core.sh`, it shows:
   - ✓ Completed steps (with duration)
   - ⏸ Pending steps
   - Overall progress percentage

### Resuming an Interrupted Installation

If installation is interrupted in FASE B:

```bash
# Reconnect to your VPS as the admin user
ssh adminuser@your-vps-ip

# Re-run installation_core script - it will resume from where it stopped
bash ~/install_core.sh
```

The script will display the current progress and continue with the next pending step. No re-entering of configuration needed.

### Progress Bar Example

```
╔═══════════════════════════════════════════════════════════════╗
║  FASE B - Instalación Core: Progreso 3/7 (43%)      ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  [████████████░░░░░░░░░░░░░░░░] 43%                   ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║  ✓ Paso  4: Firewall UFW [completado en 2m15s]   ║
║  ✓ Paso  6: Docker & Docker Compose [completado en 4m30s] ║
║  ✓ Paso  7: Certificados SSL (Let's Encrypt) [completado en 1m45s] ║
║  ⏸ Paso  8: DNS Cloudflare [en espera]          ║
║  ⏸ Paso  9: Portainer [en espera]                ║
║  ⏸ Paso 10: Kopia Backup [en espera]             ║
║  ⏸ Paso 11: File Browser [en espera]             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

## After Installation

### Access Applications

All applications are accessed via subdomains:
- N8N: `https://n8n.agentexperto.work`
- File Browser: `https://files.agentexperto.work`
- OpenClaw: `https://openclaw.agentexperto.work`
- Portainer: `https://portainer.agentexperto.work` (internal)

### SSH Access

Connect as `jaime` user:

```bash
ssh -i /path/to/jaime_key jaime@your-vps-ip
```

### View Application Logs

```bash
cd /home/jaime/apps/appname
docker-compose logs -f
```

### Stop/Start Applications

```bash
# Stop specific app
cd /home/jaime/apps/appname
docker-compose down

# Restart specific app
docker-compose up -d
```

## Troubleshooting

### Port Already in Use
```bash
sudo netstat -tlnp | grep :PORT_NUMBER
```

### Docker Daemon Not Running
```bash
sudo systemctl restart docker
```

### Permission Denied
Make sure you're using the `jaime` user:
```bash
sudo -u jaime docker ps
```

### Check Application Status
```bash
cd /home/jaime/apps/appname
docker-compose ps
```

## Support

For detailed technical documentation, see [CLAUDE.md](./CLAUDE.md)

For issues or questions, check the troubleshooting section or contact your system administrator.

---

**Version:** 1.0.0
**Last Updated:** 2026-03-18
**Target OS:** Debian 12
**Domain:** agentexperto.work
