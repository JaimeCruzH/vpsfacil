#!/bin/bash
# ============================================================
# programas_adicionales.sh — Instalar programas opcionales
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Uso: sudo bash programas_adicionales.sh
#
# Requisitos:
#   - Instalación core de VPSfacil completada (12 pasos)
#   - Docker, Tailscale y Portainer funcionando
#   - Ejecutar como root
# ============================================================

set -euo pipefail

# ============================================================
# CARGAR LIBRERÍAS
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/lib"

if [[ ! -f "${LIB_DIR}/colors.sh" ]] 2>/dev/null; then
    SCRIPT_DIR=""
fi

if [[ -z "$SCRIPT_DIR" ]] || [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    LIB_DIR="/tmp/vpsfacil_lib_$$"
    mkdir -p "$LIB_DIR"
    curl -sSL "${REPO_RAW}/lib/colors.sh?v=$(date +%s)"         -o "${LIB_DIR}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh?v=$(date +%s)"         -o "${LIB_DIR}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh?v=$(date +%s)"          -o "${LIB_DIR}/utils.sh"
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh?v=$(date +%s)"  -o "${LIB_DIR}/portainer_api.sh"
fi

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config
source "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true

check_root

# ============================================================
# VERIFICAR QUE LA INSTALACIÓN CORE ESTÁ COMPLETA
# ============================================================
_check_core_ready() {
    local ok=true

    if ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; then
        log_error "Docker no está instalado o no está corriendo."
        log_info  "Completa la instalación core (setup.sh) primero."
        ok=false
    fi

    if ! docker network inspect vpsfacil-net &>/dev/null; then
        log_error "Red Docker 'vpsfacil-net' no encontrada."
        log_info  "Completa la instalación core (setup.sh) primero."
        ok=false
    fi

    if [[ "$ok" == false ]]; then
        exit 1
    fi
}

# ============================================================
# VERIFICAR SI UN PROGRAMA YA ESTÁ INSTALADO
# ============================================================
_is_installed() {
    local container_name="$1"
    docker ps -a --filter "name=^/${container_name}$" --format "{{.Names}}" 2>/dev/null | grep -q "^${container_name}$"
}

_status_label() {
    local container_name="$1"
    if docker ps --filter "name=^/${container_name}$" --format "{{.Names}}" 2>/dev/null | grep -q "^${container_name}$"; then
        echo -e "${COLOR_GREEN}[instalado y corriendo]${COLOR_RESET}"
    elif _is_installed "$container_name"; then
        echo -e "${COLOR_YELLOW}[instalado, detenido]${COLOR_RESET}"
    else
        echo -e "${COLOR_CYAN}[no instalado]${COLOR_RESET}"
    fi
}

# ============================================================
# MENÚ PRINCIPAL
# ============================================================
show_menu() {
    clear
    echo ""
    echo -e "${COLOR_BOLD_WHITE}╔═══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}║          VPSfacil — Programas Adicionales                    ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}╚═══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Dominio:    ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "  Apps en:    ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BOLD_WHITE}  Programas disponibles:${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}1)${COLOR_RESET} OpenClaw       $(_status_label openclaw)"
    echo -e "     Asistente IA personal (WhatsApp, Telegram, Discord...)"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}0)${COLOR_RESET} Salir"
    echo ""
    echo -e "${COLOR_BLUE}$(printf '─%.0s' $(seq 1 65))${COLOR_RESET}"
    echo ""
}

# ============================================================
# UTILIDAD: CREAR REGISTRO DNS EN CLOUDFLARE
# Reutiliza las credenciales guardadas en el paso 6 (DNS core).
# Uso: _create_dns_record "openclaw"   → crea openclaw.vpn.DOMAIN
# ============================================================
_create_dns_record() {
    local subdomain_prefix="$1"
    local fqdn="${subdomain_prefix}.vpn.${DOMAIN}"

    # Cargar credenciales de Cloudflare guardadas en el paso 6
    local CF_ENV_FILE="${APPS_DIR}/.cloudflare.env"
    if [[ ! -f "$CF_ENV_FILE" ]]; then
        log_warning "No se encontraron credenciales de Cloudflare (${CF_ENV_FILE})"
        log_info    "Crea manualmente el registro DNS: ${fqdn} → IP Tailscale"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CF_ENV_FILE"

    if [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ZONE_ID:-}" ]]; then
        log_warning "Credenciales de Cloudflare incompletas en ${CF_ENV_FILE}"
        log_info    "Crea manualmente el registro DNS: ${fqdn} → IP Tailscale"
        return 1
    fi

    # Obtener la IP de Tailscale actual del servidor
    local TAILSCALE_IP
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [[ -z "$TAILSCALE_IP" ]]; then
        log_warning "No se pudo obtener la IP de Tailscale"
        log_info    "Crea manualmente el registro DNS: ${fqdn} → IP Tailscale"
        return 1
    fi

    log_process "Creando registro DNS: ${fqdn} → ${TAILSCALE_IP} ..."

    # Verificar si el registro ya existe
    local EXISTING
    EXISTING=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${fqdn}&type=A" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json")

    local EXISTING_ID
    EXISTING_ID=$(echo "$EXISTING" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); r=d.get('result',[]); print(r[0]['id'] if r else '')" \
        2>/dev/null || echo "")

    local RESULT ACCION
    if [[ -n "$EXISTING_ID" ]]; then
        RESULT=$(curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${EXISTING_ID}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${fqdn}\",\"content\":\"${TAILSCALE_IP}\",\"ttl\":120,\"proxied\":false}")
        ACCION="Actualizado"
    else
        RESULT=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${fqdn}\",\"content\":\"${TAILSCALE_IP}\",\"ttl\":120,\"proxied\":false}")
        ACCION="Creado"
    fi

    local SUCCESS
    SUCCESS=$(echo "$RESULT" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print('true' if d.get('success') else 'false')" \
        2>/dev/null || echo "false")

    if [[ "$SUCCESS" == "true" ]]; then
        log_success "${ACCION}: ${fqdn} → ${TAILSCALE_IP} ✓"
        return 0
    else
        local ERR
        ERR=$(echo "$RESULT" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); e=d.get('errors',[]); print(e[0].get('message','desconocido') if e else 'desconocido')" \
            2>/dev/null || echo "desconocido")
        log_warning "Error creando registro DNS: ${ERR}"
        log_info    "Crea manualmente en Cloudflare: ${fqdn} → ${TAILSCALE_IP}"
        return 1
    fi
}

# ============================================================
# INSTALADOR: OPENCLAW
# ============================================================
install_openclaw() {
    print_header "Instalar OpenClaw — Asistente IA Personal"

    log_info "OpenClaw conecta múltiples plataformas de mensajería"
    log_info "(WhatsApp, Telegram, Slack, Discord...) con modelos de IA."
    echo ""
    log_info "Proveedor de IA: configurable en el onboarding (OpenRouter, etc.)"
    log_info "Repositorio: https://github.com/openclaw/openclaw"
    echo ""

    if ! confirm "¿Deseas instalar OpenClaw?"; then
        log_info "Instalación cancelada."
        return 0
    fi

    # ── Verificar si ya está instalado ───────────────────────
    APP_DIR="${APPS_DIR}/openclaw"
    if _is_installed "openclaw"; then
        echo ""
        log_warning "OpenClaw ya está instalado."
        echo ""
        log_info "Opciones:"
        log_info "  1) Reinstalar (mantiene datos y configuración existente)"
        log_info "  2) Instalación limpia (BORRA todos los datos y configuración)"
        log_info "  3) Desinstalar (elimina el programa y todos sus datos)"
        log_info "  4) Cancelar"
        echo ""
        local opt
        opt=$(prompt_input "¿Qué deseas hacer?" "4")
        case "$opt" in
            1)
                log_process "Deteniendo contenedor anterior..."
                docker stop openclaw 2>/dev/null || true
                docker rm   openclaw 2>/dev/null || true
                ;;
            2)
                echo ""
                log_warning "Esto eliminará permanentemente:"
                log_warning "  - Toda la configuración de OpenClaw (credenciales, onboarding)"
                log_warning "  - Todos los datos del workspace"
                log_warning "  - El token de gateway actual"
                log_warning "  - Directorio: ${APP_DIR}"
                echo ""
                if ! confirm "¿Estás seguro de que quieres borrar todo y empezar de cero?"; then
                    log_info "Cancelado."
                    return 0
                fi
                log_process "Deteniendo y eliminando contenedor..."
                docker stop openclaw 2>/dev/null || true
                docker rm   openclaw 2>/dev/null || true
                log_process "Eliminando todos los datos..."
                rm -rf "${APP_DIR}"
                log_success "Datos eliminados. Iniciando instalación limpia ✓"
                ;;
            3)
                echo ""
                log_warning "Esto eliminará permanentemente:"
                log_warning "  - El contenedor e imagen Docker de OpenClaw"
                log_warning "  - Toda la configuración y datos del workspace"
                log_warning "  - Directorio: ${APP_DIR}"
                echo ""
                if ! confirm "¿Estás seguro de que quieres desinstalar OpenClaw por completo?"; then
                    log_info "Cancelado."
                    return 0
                fi
                log_process "Deteniendo y eliminando contenedor..."
                docker stop openclaw 2>/dev/null || true
                docker rm   openclaw 2>/dev/null || true
                log_process "Eliminando imagen Docker..."
                docker rmi openclaw-vpsfacil:latest 2>/dev/null || true
                log_process "Eliminando todos los datos..."
                rm -rf "${APP_DIR}"
                log_success "OpenClaw desinstalado completamente ✓"
                return 0
                ;;
            *)
                log_info "Cancelado."
                return 0
                ;;
        esac
    fi

    check_docker || { log_error "Docker no está disponible."; return 1; }

    # ── 1. Directorios ────────────────────────────────────────
    log_step "Creando estructura de directorios"
    mkdir -p "${APP_DIR}/config"
    mkdir -p "${APP_DIR}/data"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
    log_success "Directorio: ${APP_DIR} ✓"

    # ── 2. Token de gateway ───────────────────────────────────
    log_step "Generando token de Gateway"
    local GATEWAY_TOKEN
    # Reutilizar token existente si ya hay una instalación previa
    if [[ -f "${APP_DIR}/.env" ]]; then
        GATEWAY_TOKEN=$(grep "OPENCLAW_GATEWAY_TOKEN=" "${APP_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "")
    fi
    if [[ -z "${GATEWAY_TOKEN:-}" ]]; then
        GATEWAY_TOKEN=$(generate_token 32)
    fi
    log_success "Token de Gateway listo ✓"

    # ── 3. Archivo .env ───────────────────────────────────────
    log_step "Guardando configuración"

    cat > "${APP_DIR}/.env" << EOF
# OpenClaw — VPSfacil
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=true
TZ=${TIMEZONE:-America/Santiago}
EOF

    chmod 600 "${APP_DIR}/.env"
    chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
    log_success "Archivo .env creado ✓"

    # ── 4. Dockerfile ─────────────────────────────────────────
    log_step "Preparando imagen Docker de OpenClaw"

    cat > "${APP_DIR}/Dockerfile" << 'DOCKERFILE'
FROM node:24-bookworm

ENV PNPM_HOME="/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"

RUN corepack enable pnpm && pnpm add -g openclaw@latest

USER node
WORKDIR /home/node

EXPOSE 18789 18790

CMD ["/pnpm/openclaw", "gateway", "--allow-unconfigured"]
DOCKERFILE

    chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/Dockerfile"

    # ── 5. Construir imagen ───────────────────────────────────
    log_step "Construyendo imagen Docker de OpenClaw"
    log_process "Puede tardar 3-5 minutos la primera vez..."

    cd "$APP_DIR"
    if ! docker build --network=host --progress=plain -t openclaw-vpsfacil:latest . 2>&1; then
        log_error "Falló la construcción de la imagen Docker."
        log_info  "Revisa el error arriba para más detalles."
        return 1
    fi
    log_success "Imagen openclaw-vpsfacil:latest construida ✓"

    # ── 6. Nginx config (proxy HTTPS → OpenClaw HTTP) ─────────
    log_step "Generando configuración nginx HTTPS"

    mkdir -p "${APP_DIR}/nginx"
    cat > "${APP_DIR}/nginx/openclaw.conf" << NGINXCONF
server {
    listen 18790 ssl;
    server_name openclaw.vpn.${DOMAIN};

    ssl_certificate     /certs/origin-cert.pem;
    ssl_certificate_key /certs/origin-cert-key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 86400;
    }
}
NGINXCONF

    chown -R "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/nginx"
    log_success "Configuración nginx generada ✓"

    # ── 7. Docker Compose ─────────────────────────────────────
    log_step "Generando docker-compose.yml"

    local COMPOSE_CONTENT
    COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# OpenClaw — VPSfacil
# Acceso: https://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}
# SOLO vía Tailscale VPN
# nginx termina SSL y proxea a OpenClaw internamente.
# ============================================================
services:
  openclaw:
    image: openclaw-vpsfacil:latest
    container_name: openclaw
    restart: unless-stopped
    environment:
      HOME: /home/node
      TERM: xterm
      TZ: ${TIMEZONE:-America/Santiago}
      OPENCLAW_GATEWAY_TOKEN: "${GATEWAY_TOKEN}"
    ports:
      - "127.0.0.1:${PORT_OPENCLAW_WS}:18789"
    volumes:
      - ${APP_DIR}/config:/home/node/.openclaw
      - ${APP_DIR}/data:/home/node/.openclaw/workspace
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "18789"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - vpsfacil-net

  openclaw-nginx:
    image: nginx:alpine
    container_name: openclaw-nginx
    restart: unless-stopped
    ports:
      - "${PORT_OPENCLAW_HTTP}:18790"
    volumes:
      - ${APP_DIR}/nginx/openclaw.conf:/etc/nginx/conf.d/openclaw.conf:ro
      - ${CERTS_DIR}/origin-cert.pem:/certs/origin-cert.pem:ro
      - ${CERTS_DIR}/origin-cert-key.pem:/certs/origin-cert-key.pem:ro
    depends_on:
      - openclaw
    networks:
      - vpsfacil-net

networks:
  vpsfacil-net:
    external: true
EOF
)

    echo "$COMPOSE_CONTENT" > "${APP_DIR}/docker-compose.yml"
    chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
    log_success "docker-compose.yml generado ✓"

    # ── 8. Desplegar ──────────────────────────────────────────
    log_step "Desplegando OpenClaw"

    log_process "Registrando stack en Portainer..."
    if portainer_deploy_stack "openclaw" "$COMPOSE_CONTENT" 2>/dev/null; then
        log_success "Stack creado en Portainer ✓"
    else
        log_warning "Portainer no disponible. Desplegando con docker compose..."
        cd "$APP_DIR"
        docker compose up -d
    fi

    log_process "Esperando que OpenClaw inicie..."
    wait_for_port "localhost" "${PORT_OPENCLAW_WS}" 120
    log_process "Esperando que nginx HTTPS inicie..."
    wait_for_port "localhost" "${PORT_OPENCLAW_HTTP}" 30

    log_success "OpenClaw está corriendo ✓"

    # ── DNS en Cloudflare ─────────────────────────────────────
    log_step "Creando registro DNS en Cloudflare"
    _create_dns_record "openclaw" || true

    # ── Resumen ───────────────────────────────────────────────
    echo ""
    print_separator
    echo ""
    log_success "OpenClaw instalado exitosamente"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Acceso (requiere Tailscale VPN):${COLOR_RESET}"
    echo -e "    URL:     ${COLOR_CYAN}https://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}${COLOR_RESET}"
    echo -e "    Token:   ${COLOR_CYAN}${GATEWAY_TOKEN}${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
    echo ""
    print_separator

    # ── Onboarding ────────────────────────────────────────────
    echo ""
    log_info "El siguiente paso es el onboarding de OpenClaw."
    log_info "Te guiará para conectar tus plataformas de mensajería"
    log_info "(WhatsApp, Telegram, Slack, Discord, etc.)."
    echo ""
    if confirm "¿Deseas ejecutar el onboarding ahora?"; then
        echo ""
        echo -e "${COLOR_BOLD_YELLOW}┌─ OPCIONES IMPORTANTES DEL ONBOARDING ───────────────────┐${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}  Workspace dir  → escribe exactamente:"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}    ${COLOR_CYAN}/home/node/.openclaw/workspace${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}    (es el path DENTRO del contenedor, no del servidor)"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}  Gateway bind    → elige ${COLOR_BOLD_WHITE}0.0.0.0${COLOR_RESET} o ${COLOR_BOLD_WHITE}localhost${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}  Gateway auth    → elige ${COLOR_BOLD_WHITE}Token${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}  Tailscale       → elige ${COLOR_BOLD_WHITE}None${COLOR_RESET} (el acceso VPN ya está"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}                    gestionado por DNS + UFW)"
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET}"
        echo -e "${COLOR_BOLD_YELLOW}└──────────────────────────────────────────────────────────┘${COLOR_RESET}"
        echo ""
        log_process "Iniciando onboarding de OpenClaw..."
        echo ""
        docker exec -it openclaw /pnpm/openclaw onboard
        echo ""
        log_success "Onboarding completado."

        # Agregar origen permitido para acceso vía Tailscale VPN
        local CONFIG_FILE="${APP_DIR}/config/openclaw.json"
        if [[ -f "$CONFIG_FILE" ]]; then
            log_process "Configurando origen permitido para acceso VPN..."
            python3 -c "
import json
f = '${CONFIG_FILE}'
with open(f) as fp:
    cfg = json.load(fp)
origins = cfg.setdefault('gateway', {}).setdefault('controlUi', {}).setdefault('allowedOrigins', [])
nuevos = [
    'https://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}',
    'http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}',
]
for o in nuevos:
    if o not in origins:
        origins.append(o)
with open(f, 'w') as fp:
    json.dump(cfg, fp, indent=2)
print('OK')
" && log_success "Orígenes VPN agregados ✓" || log_warning "No se pudo configurar los orígenes automáticamente"
            docker restart openclaw > /dev/null 2>&1
            sleep 3
            docker restart openclaw-nginx > /dev/null 2>&1
            log_success "Contenedores reiniciados con nueva configuración ✓"

            # Leer token guardado por el onboarding y mostrar URL completa
            local SAVED_TOKEN
            SAVED_TOKEN=$(python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
print(cfg.get('gateway', {}).get('auth', {}).get('token', ''))
" 2>/dev/null || echo "")

            echo ""
            print_separator
            echo ""
            log_success "OpenClaw listo para usar"
            echo ""
            echo -e "  ${COLOR_BOLD_WHITE}Abre esta URL en tu navegador (con Tailscale VPN activo):${COLOR_RESET}"
            echo ""
            if [[ -n "$SAVED_TOKEN" ]]; then
                echo -e "  ${COLOR_CYAN}https://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}/#token=${SAVED_TOKEN}${COLOR_RESET}"
                echo ""
                log_info "La URL incluye el token — el primer acceso se aprobará automáticamente."
            else
                echo -e "  ${COLOR_CYAN}https://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}${COLOR_RESET}"
                echo ""
                log_info "Ejecuta esto para obtener la URL con token:"
                log_info "  docker exec -it openclaw /pnpm/openclaw dashboard --no-open"
                log_info "Reemplaza '127.0.0.1:18789' por 'openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_HTTP}' en la URL generada."
            fi
            echo ""
            print_separator
        fi
    else
        echo ""
        log_info "Puedes ejecutarlo más tarde con:"
        log_info "  docker exec -it openclaw /pnpm/openclaw onboard"
    fi
    echo ""

    wait_for_user "Presiona Enter para volver al menú..."
}

# ============================================================
# BUCLE PRINCIPAL
# ============================================================
_check_core_ready

while true; do
    show_menu
    local_opt=$(prompt_input "Selecciona una opción" "0")

    case "$local_opt" in
        1) install_openclaw ;;
        0)
            echo ""
            log_info "Saliendo."
            echo ""
            exit 0
            ;;
        *)
            log_warning "Opción inválida. Elige un número del menú."
            sleep 1
            ;;
    esac
done
