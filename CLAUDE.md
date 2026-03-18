# VPSfacil - Automated VPS Installation System

## Project Overview

**VPSfacil** is an automated, interactive VPS setup tool designed to enable non-technical users to install and configure open source applications on a Linux VPS with a single curl command. The project is inspired by [oriondesign.art.br](https://oriondesign.art.br/), which uses a similar model-driven installation approach.

**Target User:** Users with minimal Linux experience but who want to quickly deploy a full-featured VPS stack.

---

## Infrastructure Details

### VPS Specifications
- **Provider:** Contabo
- **OS:** Debian 12
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Disk:** 75 GB SSD

### Domain & DNS
- **Domain:** `agentexperto.work`
- **DNS Provider:** Cloudflare (DNS-only, no CDN)
- **Purpose:** Create subdomains for each installed application

### Client Environment
- **Local OS:** Windows 11 Pro 25H2
- **CPU:** Intel Core Ultra 9 185H
- **RAM:** 32 GB
- **SSH Client:** Bitvise SSH 9.59

### User Profile
- **Age:** 60 years old
- **Linux Knowledge:** Basic
- **Windows Knowledge:** Advanced
- **Role:** Engineer/System Administrator

---

## Network Architecture: Cloudflare DNS + Tailscale VPN + Cloudflare Origin Certificates

**Security-First Design:** All applications accessible ONLY via Tailscale VPN with DNS-friendly HTTPS URLs via Cloudflare Origin Certificates.

```
┌─────────────────────────────────────────────────────────┐
│ User Browser: https://n8n.vpn.agentexperto.work         │
│ (Tailscale VPN must be active)                          │
└─────────────────────────────────────────────────────────┘
        ↓ DNS resolution via Cloudflare
┌─────────────────────────────────────────────────────────┐
│ Cloudflare DNS (DNS-only, no proxy)                     │
│ n8n.vpn.agentexperto.work → 100.91.x.x                  │
│ files.vpn.agentexperto.work → 100.91.x.x                │
│ openclaw.vpn.agentexperto.work → 100.91.x.x             │
└─────────────────────────────────────────────────────────┘
        ↓ VPN tunnel via Tailscale + SSL/TLS encryption
┌─────────────────────────────────────────────────────────┐
│ VPS (Tailscale IP: 100.91.x.x)                          │
│ ├─ Cloudflare Origin Certificates                       │
│ │  └─ *.vpn.agentexperto.work (15-year validity)        │
│ ├─ N8N (HTTPS via cert, port 5678)                      │
│ ├─ File Browser (HTTPS via cert, port 443)              │
│ ├─ OpenClaw (HTTPS via cert, port 18789)                │
│ └─ Portainer (HTTPS via cert, port 9000)                │
└─────────────────────────────────────────────────────────┘
```

**Advantages:**
- ✅ Zero internet exposure (100% private)
- ✅ No DDOS vulnerability
- ✅ DNS-friendly HTTPS names (professional, secure URLs)
- ✅ Valid SSL certificates (Cloudflare Origin, 15-year validity)
- ✅ No Nginx Proxy Manager needed
- ✅ No Let's Encrypt complexity (no 90-day renewals)
- ✅ Double encryption (SSL + Tailscale VPN)
- ✅ Minimal components (less to maintain)
- ✅ Maximum security (VPN-only access)
- ✅ Browser trust (Cloudflare CA is recognized)

---

## Universal Configuration: Domain & Admin User

**VPSfacil is completely customizable** — not tied to any specific domain or username.

### Initial Setup Questions (First Run)

When user runs `setup.sh`, they are asked:

```
[?] Enter your domain name (e.g., example.com):
    agentexperto.work

[?] Enter admin username to create (e.g., admin):
    jaime
```

### Dynamic Variables Used Throughout

All scripts use variables, not hard-coded values:

```bash
DOMAIN="agentexperto.work"        # User input
ADMIN_USER="jaime"                # User input

# Derived automatically:
ADMIN_HOME="/home/${ADMIN_USER}"
APPS_DIR="${ADMIN_HOME}/apps"
CERTS_DIR="${APPS_DIR}/certs"
VPN_SUBDOMAIN="vpn.${DOMAIN}"     # vpn.agentexperto.work
```

### Examples of Universal Usage

**Example 1: User with different domain**
```
Domain: empresa.com
Admin User: ops_admin
Result:
  - Home: /home/ops_admin/
  - Apps: /home/ops_admin/apps/
  - Certs for: *.vpn.empresa.com
  - URLs: n8n.vpn.empresa.com
```

**Example 2: User with different username**
```
Domain: startup.io
Admin User: sysadmin
Result:
  - Home: /home/sysadmin/
  - Apps: /home/sysadmin/apps/
  - Certs for: *.vpn.startup.io
  - URLs: n8n.vpn.startup.io
```

### Configuration Saved

After installation, configuration is saved:
```bash
/home/${ADMIN_USER}/setup.conf

DOMAIN="agentexperto.work"
ADMIN_USER="jaime"
INSTALLATION_DATE="2026-03-18"
```

This file can be sourced later to re-run scripts with same configuration.

---

## Installation Architecture

### Applications Directory Structure

All applications (core and optional) are installed under `/home/jaime/apps/` for:
- **Clear organization** — Easy to identify and manage each application
- **Granular backups** — Backup/restore individual apps without affecting others
- **User ownership** — All owned by `jaime` user with clear permissions
- **Scalability** — Adding new apps follows the same pattern

**Directory structure:**
```
/home/jaime/apps/
├── portainer/          # Portainer (core, VPN-only)
│   ├── docker-compose.yml
│   ├── .env
│   └── data/
├── tailscale/          # Tailscale (core, VPN tunnel)
│   ├── docker-compose.yml
│   └── .env
├── kopia/              # Kopia Backup (core)
│   ├── docker-compose.yml
│   ├── .env
│   └── config/
├── n8n/                # N8N (optional, VPN-only)
│   ├── docker-compose.yml
│   ├── .env
│   ├── config/
│   ├── postgres/       # PostgreSQL database
│   └── data/
├── openclaw/           # OpenClaw (optional, VPN-only)
│   ├── docker-compose.yml
│   ├── .env
│   ├── config/
│   └── data/
├── filebrowser/        # File Browser (optional, VPN-only)
│   ├── docker-compose.yml
│   ├── .env
│   ├── config/
│   └── data/
└── backups/            # Backup storage location (used by Kopia)
    └── (backup artifacts)
```

**Note:** No Nginx Proxy Manager directory needed in this architecture.

### Delivery Method
Users will execute a single curl command that:
1. Downloads and runs `setup.sh` from a remote server
2. Verifies OS compatibility (Debian 12)
3. Checks/installs required dependencies
4. Creates `/home/jaime/apps/` directory structure
5. Installs and configures Tailscale
6. Displays an interactive menu for optional applications
7. Automates configuration and deployment

**Command pattern:**
```bash
bash <(curl -sSL setup.agentexperto.work)
```

### VPN-Only Access Pattern

All applications follow this access pattern:
```
Application URL: https://appname.vpn.agentexperto.work:port
Cloudflare DNS:  appname.vpn.agentexperto.work → Tailscale IP
Access Method:   Tailscale VPN (mandatory)
Port:            Internal container port (no firewall exposure)
```

### Installation Order & Dependencies

All steps assume root access initially, then user `jaime` takes over.

1. **Pre-flight Checks** (`00_precheck.sh`)
   - Verify running as root
   - Verify OS is Debian 12
   - Check internet connectivity
   - Verify required tools (curl, wget, apt)

2. **User Setup** (`01_create_user.sh`)
   - Create user `jaime`
   - Add `jaime` to sudo group
   - Grant passwordless sudo (optional, for automation)
   - Set up SSH key-based auth for `jaime`

3. **Security Hardening** (`02_secure_ssh.sh`)
   - Disable root SSH password login
   - Disable SSH password auth (require keys)
   - Change default SSH port (optional)
   - Configure fail2ban (optional)

4. **Docker** (`03_install_docker.sh`)
   - Install Docker CE
   - Install Docker Compose v2
   - Add `jaime` to docker group
   - Verify installation

5. **Container Management** (`04_install_portainer.sh`)
   - Install Portainer Community Edition
   - Deploy as Docker container
   - Expose Portainer API (internal port)
   - Create initial admin user

6. **Reverse Proxy & SSL** (`05_install_nginx.sh`)
   - Install Nginx Proxy Manager (via Docker)
   - Configure NPM SSL certs (Let's Encrypt)
   - Set up proxy rules template
   - Integrate with Cloudflare DNS

7. **Firewall** (`06_install_firewall.sh`)
   - Install UFW
   - Enable UFW
   - Open SSH port (22)
   - Open HTTP (80)
   - Open HTTPS (443)
   - Tailscale port (if installed)
   - Docker internal ports (restricted)

8. **VPN Access** (`07_install_tailscale.sh`)
   - Install Tailscale
   - Authenticate with Tailscale account
   - Enable subnet routing (optional)
   - Enable SSH over Tailscale

9. **Backup Solution** (`08_install_kopia.sh`)
   - Install Kopia Backup
   - Configure storage backend (local, S3, B2, etc.)
   - Set up automated backup schedule
   - Create restore test documentation

### Optional Applications (Interactive Menu)

After core setup, users can opt-in to:

- **N8N** (`apps/n8n.sh`) — Workflow automation platform
  - Subdomain: `n8n.agentexperto.work`
  - Persistent database setup
  - Environment variables configuration

- **OpenClaw** (`apps/openclaw.sh`) — Personal AI assistant
  - Repository: https://github.com/openclaw/openclaw
  - Subdomain: `openclaw.vpn.agentexperto.work` (VPN-ONLY, NOT public)
  - Port: 18789 (WebSocket)
  - Requires: Claude AI credentials (session keys, cookies) — MUST be private
  - Access: Tailscale VPN only (per official security recommendations)
  - Persistent storage: Config + Workspace directories
  - Base image: node:24-bookworm
  - Non-root user: node
  - Security: No public internet exposure (sensitive credentials)

- **File Browser** (`apps/filebrowser.sh`) — Web-based file manager
  - Subdomain: `files.agentexperto.work`
  - User authentication setup
  - Storage path configuration

---

## Project Structure

```
VPSfacil/
├── CLAUDE.md                       # This file - project documentation
├── README.md                       # User-facing setup guide
├── setup.sh                        # Main entry script (curl downloads this)
│
├── scripts/                        # Core installation modules
│   ├── 00_precheck.sh
│   ├── 01_create_user.sh
│   ├── 02_secure_ssh.sh
│   ├── 03_install_docker.sh
│   ├── 04_install_portainer.sh
│   ├── 05_install_nginx.sh
│   ├── 06_install_firewall.sh
│   ├── 07_install_tailscale.sh
│   └── 08_install_kopia.sh
│
├── apps/                           # Optional application installers
│   ├── n8n.sh
│   ├── openclaw.sh
│   └── filebrowser.sh
│
├── templates/                      # Docker Compose & config templates
│   ├── n8n/
│   │   └── docker-compose.yml
│   ├── openclaw/
│   │   └── docker-compose.yml
│   └── filebrowser/
│       └── docker-compose.yml
│
├── lib/                            # Reusable functions & utilities
│   ├── colors.sh                   # ANSI color definitions
│   ├── utils.sh                    # Common bash utilities
│   ├── menu.sh                     # Interactive menu system
│   ├── portainer_api.sh            # Portainer REST API wrappers
│   ├── nginx_api.sh                # Nginx Proxy Manager API wrappers
│   └── cloudflare_api.sh           # Cloudflare DNS API wrappers
│
└── config/
    └── defaults.conf               # Default ports, paths, timeouts
```

---

## SSL/TLS Certificates: Cloudflare Origin Certificates

**Why needed?**
Browsers require valid SSL certificates for HTTPS URLs, even when accessed via private VPN networks.

**Solution: Cloudflare Origin Certificates**

Cloudflare provides free SSL certificates for your domain with these benefits:
- **Free** — No cost
- **Long validity** — Valid for 15 years (no 90-day renewal hassle)
- **DNS validation** — Validated via Cloudflare DNS (no public access needed)
- **Browser trusted** — Cloudflare CA is recognized by all browsers
- **Wildcard support** — Single cert covers `*.vpn.agentexperto.work`

**Certificate Setup:**

1. **In Cloudflare Dashboard:**
   - Navigate to: SSL/TLS → Origin Server
   - Click: "Create Certificate"
   - Add hostnames: `*.vpn.agentexperto.work`
   - Validity: Choose 15 years
   - Download: Private key + Certificate

2. **On VPS:**
   ```bash
   /home/jaime/apps/certs/
   ├── origin-cert.pem         # Certificate
   ├── origin-cert-key.pem     # Private key
   └── origin-ca-bundle.crt    # CA bundle
   ```

3. **In Application Docker Configs:**
   Each app's docker-compose.yml mounts certificates and configures HTTPS:
   ```yaml
   volumes:
     - /home/jaime/apps/certs/origin-cert.pem:/app/cert.pem
     - /home/jaime/apps/certs/origin-cert-key.pem:/app/key.pem
   environment:
     - CERTIFICATE_PATH=/app/cert.pem
     - CERTIFICATE_KEY_PATH=/app/key.pem
   ```

**Renewal Schedule:**
- **Year 1-15:** No action needed
- **Year 14:** Generate new certificate from Cloudflare
- **Year 15:** Copy new cert to VPS and restart apps

---

## Critical: User Context (ROOT vs JAIME)

**IMPORTANT:** After user `jaime` is created in step `01_create_user.sh`:
- All subsequent installations run under the `jaime` user, NOT root
- Only the initial setup (precheck, user creation, SSH hardening) uses root
- Docker must be accessible by `jaime` (will be added to docker group)
- All application containers are deployed by `jaime` via Portainer
- SSH access to VPS will be via `jaime` user after setup completes

The user `jaime` has passwordless sudo access to allow automated installation steps.

---

## Script Development Conventions

### User Interaction & Messaging

**Every script must be highly interactive and informative:**

1. **Clear Section Headers** — Show what is being done
   ```
   ╔════════════════════════════════════════════════════════╗
   ║       Installing Docker & Docker Compose              ║
   ╚════════════════════════════════════════════════════════╝
   ```

2. **Detailed Step Descriptions** — Explain both server-side and client-side actions
   ```
   [INFO] Setting up Docker credentials...
   [INFO] You will need to enter your Docker Hub credentials (or skip)
   [PROMPT] Docker Hub username (press Enter to skip):
   ```

3. **Progress Indicators** — Show what's happening
   ```
   [✓] Docker installed successfully (version: 24.0.0)
   [⏳] Waiting for Docker daemon to start... (60 seconds)
   [✓] Docker daemon is running
   ```

4. **Client-Side Instructions** — Tell user what to do in their Windows PC
   ```
   [INFO] Next step: Configure SSH key-based auth on your Windows PC
   [INFO]
   [INFO] 1. Open Bitvise SSH Client
   [INFO] 2. Go to: Profile → Authentication
   [INFO] 3. Import the private key saved to: C:\Users\YourName\jaime_key
   [INFO] 4. Test connection to: jaime@your-vps-ip
   [INFO]
   [PROMPT] Press Enter when you have verified SSH connection with jaime user...
   ```

5. **Confirmations & Backups** — Always ask before destructive actions
   ```
   [⚠ WARNING] This will disable root SSH password login
   [⚠ WARNING] Make sure you have a working SSH key for 'jaime' user
   [PROMPT] Continue? (yes/no):
   ```

6. **Error Recovery** — Explain how to fix problems
   ```
   [✗ ERROR] Port 22 is already in use
   [INFO] This might be another SSH service running
   [INFO] Check with: sudo netstat -tlnp | grep :22
   [INFO] To retry, run this script again
   ```

### Bash Style Guide
- **Shebang:** `#!/bin/bash`
- **Error handling:** Always use `set -e` and trap errors
- **Logging:** Use color-coded output (info, success, warning, error, prompt)
- **User input:** Always confirm destructive actions
- **Idempotency:** Scripts should be safe to re-run
- **Verbose output:** Log every major step, wait point, and decision

### Color & Output
- **Info:** Blue `[ℹ]`
- **Success:** Green `[✓]`
- **Warning:** Yellow `[⚠]`
- **Error:** Red `[✗]`

### Application Folder Convention

Every application in `/home/jaime/apps/appname/` must follow this structure:

**Required files/folders:**
- `docker-compose.yml` — Main deployment specification
- `.env` — Environment variables and secrets (created by installer, never in git)
- `data/` — Persistent storage volume (mounted in docker-compose.yml)
- `config/` — Application-specific configuration files (if needed)

**Naming conventions:**
- All folders owned by `jaime:jaime`
- All `docker-compose.yml` files start service with proper name
- All sensitive data in `.env` file (passwords, API keys, tokens)
- All persistent paths use relative paths: `./data/`, `./config/`

**Example docker-compose.yml template:**
```yaml
version: '3.8'
services:
  appname:
    image: appname:latest
    container_name: appname
    restart: unless-stopped
    ports:
      - "8080:8080"  # Internal only, Nginx proxies external access
    environment:
      - APP_PASSWORD=${APP_PASSWORD}
      - APP_USERNAME=${APP_USERNAME}
    volumes:
      - ./data:/app/data
      - ./config:/app/config
    networks:
      - appnetwork

networks:
  appnetwork:
    driver: bridge
```

### Common Functions (from `lib/utils.sh`)
- `log_info(message)`
- `log_success(message)`
- `log_warning(message)`
- `log_error(message)`
- `confirm(prompt)` — Y/N confirmation
- `wait_for_port(port, timeout)` — Health check
- `ensure_app_dir(appname)` — Create `/home/jaime/apps/appname/` structure
- `get_app_dir(appname)` — Return `/home/jaime/apps/appname` path

### API Integration
- **Portainer:** REST API at `http://localhost:9000/api`
- **Nginx Proxy Manager:** API at `http://localhost:81/api`
- **Cloudflare:** DNS API (token-based auth)

### Configuration
- Store secrets in environment variables (not in scripts)
- Support `.env` file injection
- Default values in `config/defaults.conf`

---

## Backup & Restore Procedures

### Single Application Backup
```bash
# Backup N8N application
sudo -u jaime tar -czf ~/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz /home/jaime/apps/n8n/

# Restore N8N application
cd /home/jaime/apps/
tar -xzf ~/n8n-backup-20260318-143015.tar.gz
cd n8n
docker-compose down
docker-compose up -d
```

### Full Applications Backup
```bash
# Backup all apps at once
sudo -u jaime tar -czf ~/full-apps-backup-$(date +%Y%m%d).tar.gz /home/jaime/apps/

# Restore all apps
tar -xzf ~/full-apps-backup-20260318.tar.gz -C /home/jaime/
cd /home/jaime/apps/
for dir in */; do
  cd "$dir" && docker-compose up -d && cd ..
done
```

### Kopia Automated Backups
Kopia monitors `/home/jaime/apps/` and creates automated snapshots:
```bash
# View available snapshots
kopia snapshot list /home/jaime/apps

# Restore specific app from snapshot
kopia restore /home/jaime/apps/n8n@<snapshot-id> /restore/location
```

---

## Future Extensibility

To add a new optional application:

1. Create `apps/myapp.sh` following the template pattern
2. Add Docker Compose template in `templates/myapp/docker-compose.yml`
3. Update the interactive menu in `setup.sh` to include the new option
4. Document subdomain and configuration needs in this file

Each app installer should:
- Create directory `/home/jaime/apps/myapp/`
- Create `/home/jaime/apps/myapp/docker-compose.yml` from template
- Create `/home/jaime/apps/myapp/.env` with custom variables
- Create `/home/jaime/apps/myapp/data/` directory for persistent storage
- Call Portainer API to manage the stack
- Call Nginx Proxy Manager API to set up reverse proxy + SSL
- Verify successful deployment (health check)
- Show user how to verify via browser (subdomain.agentexperto.work)

---

## Security Considerations

1. **SSH:** Root password login disabled after `jaime` user creation
2. **Firewall:** UFW enabled with restrictive default rules
3. **Secrets:** Passwords/tokens via environment variables, not stored in scripts
4. **Updates:** Initial apt-get update/upgrade included in precheck
5. **Cloudflare:** API tokens stored in `.env`, never in git
6. **Backups:** Kopia configured with encrypted remote storage

---

## Testing & Validation

- Manual testing on Contabo Debian 12 VPS
- Verify each script in isolation before integration
- Test full curl delivery (download + execute)
- Validate optional apps deploy correctly to Portainer
- Confirm Nginx Proxy Manager routes traffic correctly
- Test restore functionality of Kopia backups

---

## Notes for User (Jaime, 60)

- All interaction is through simple numbered menus
- Each step shows clear progress indicators
- Error messages explain what went wrong and how to fix
- Scripts are safe to re-run if something fails
- Support for undoing individual steps (rollback) TBD
- SSH access will require key-based auth after setup

---

## Links & References

- [Contabo VPS](https://contabo.com/)
- [Debian 12 Docs](https://www.debian.org/releases/bookworm/)
- [Portainer CE](https://www.portainer.io/)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose](https://docs.docker.com/compose/)
- [Cloudflare API](https://developers.cloudflare.com/)
- [Tailscale](https://tailscale.com/)
- [Kopia Backup](https://kopia.io/)
- [N8N](https://n8n.io/)
- [File Browser](https://filebrowser.org/)

---

## Application-Specific Notes

### OpenClaw Configuration

**What is OpenClaw?**
Personal AI assistant that connects to multiple messaging platforms (WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage) and can process voice/text via voice assistants on macOS, iOS, Android.

**Repository:** [https://github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)

**Docker Deployment Details:**
- **Base Image:** node:24-bookworm
- **Package Manager:** pnpm
- **User:** node (non-root)
- **Entry Point:** `node openclaw.mjs gateway --allow-unconfigured`
- **Ports:** 18789 (WebSocket), 18790 (secondary)

**🔒 SECURITY CONSTRAINT: VPN-ONLY ACCESS**

OpenClaw must be accessible ONLY via Tailscale VPN for these reasons:
1. Claude credentials (session keys, cookies) are sensitive
2. Official OpenClaw docs recommend Tailscale Serve/Funnel for remote access
3. Should never be exposed to public internet
4. Credentials should never pass through unprotected channels

**Required Environment Variables:**
1. **OPENCLAW_GATEWAY_TOKEN** — Gateway authentication token
2. **OPENCLAW_ALLOW_INSECURE_PRIVATE_WS** — Set to "true" (local deployment)
3. **CLAUDE_AI_SESSION_KEY** — Claude AI credentials (SENSITIVE)
4. **CLAUDE_WEB_SESSION_KEY** — Claude web credentials (SENSITIVE)
5. **CLAUDE_WEB_COOKIE** — Claude authentication cookie (SENSITIVE)
6. **TZ** — Timezone (e.g., UTC)

**Persistent Storage:**
```
/home/jaime/apps/openclaw/
├── config/          → /home/node/.openclaw (mounted)
└── data/            → /home/node/.openclaw/workspace (mounted)
```

**Installation Steps (Interactive Menu):**
1. Prompt for Claude credentials (with clear warnings about sensitivity)
2. Generate/prompt for OPENCLAW_GATEWAY_TOKEN
3. Create `/home/jaime/apps/openclaw/` structure
4. Deploy via docker-compose
5. Wait for port 18789 health check (internal only)
6. Create Cloudflare DNS record: `openclaw.vpn.agentexperto.work` → Tailscale IP
7. Display onboarding URL with Tailscale connection requirement
8. Verify user can access via Tailscale VPN

**Access Method:**
- URL: `http://openclaw.vpn.agentexperto.work:18789`
- DNS: Cloudflare resolves to Tailscale IP (100.91.x.x)
- Connection: Requires active Tailscale VPN tunnel
- Port: 18789 (internal, not exposed to firewall)

**Important Notes:**
- OpenClaw requires valid Claude AI credentials (obtained from Claude.ai)
- Configuration is interactive per official docs: `openclaw onboard --install-daemon`
- No external database required (stores locally)
- Gateway token may need generation via CLI or initial setup
- Health check runs every 30 seconds (internal)
- **NEVER expose this application to public internet**
- Credentials stored in `/home/jaime/apps/openclaw/.env` (file permissions: 600)

---

**Status:** Project structure complete. Core architecture finalized. Ready for script development.
