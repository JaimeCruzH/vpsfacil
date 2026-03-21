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
# INSTALADOR: OPENCLAW
# ============================================================
install_openclaw() {
    print_header "Instalar OpenClaw — Asistente IA Personal"

    log_info "OpenClaw conecta múltiples plataformas de mensajería"
    log_info "(WhatsApp, Telegram, Slack, Discord...) con modelos de IA."
    echo ""
    log_info "Repositorio: https://github.com/openclaw/openclaw"
    echo ""

    # ── Advertencia de seguridad ──────────────────────────────
    echo -e "${COLOR_BOLD_RED}╔══ ADVERTENCIA DE SEGURIDAD CRÍTICA ════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║  OpenClaw requiere tus credenciales personales de Claude.  ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║  Estas dan acceso completo a tu cuenta de Claude.          ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║  Por eso OpenClaw NUNCA se expone a internet.              ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║  Solo accesible vía Tailscale VPN (red privada).           ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""

    if ! confirm "¿Entiendes los riesgos y deseas continuar?"; then
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
        log_info "  1) Reinstalar (actualiza la imagen y reconfigura)"
        log_info "  2) Cancelar"
        echo ""
        local opt
        opt=$(prompt_input "¿Qué deseas hacer?" "2")
        if [[ "$opt" != "1" ]]; then
            log_info "Cancelado."
            return 0
        fi
        log_process "Deteniendo contenedor anterior..."
        docker stop openclaw 2>/dev/null || true
        docker rm   openclaw 2>/dev/null || true
    fi

    check_docker || { log_error "Docker no está disponible."; return 1; }

    # ── 1. Directorios ────────────────────────────────────────
    log_step "Creando estructura de directorios"
    mkdir -p "${APP_DIR}/config"
    mkdir -p "${APP_DIR}/data"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
    log_success "Directorio: ${APP_DIR} ✓"

    # ── 2. Credenciales de Claude ─────────────────────────────
    log_step "Configurar credenciales de Claude"

    echo ""
    log_info "Necesitas obtener tus credenciales de sesión de Claude."
    echo ""

    windows_instruction "CÓMO OBTENER LAS CREDENCIALES DE CLAUDE

1. Abre Chrome o Edge en Windows

2. Ve a: https://claude.ai  y asegúrate de estar logueado

3. Presiona F12 para abrir las DevTools del navegador

4. Ve a la pestaña: Application (o 'Aplicación' en español)

5. En el panel izquierdo: Storage → Cookies → https://claude.ai

6. Busca y copia estos dos valores:
   - sessionKey           → empieza con 'sk-ant-sid...'
   - __Secure-next-auth.session-token

7. En la pestaña Network, carga cualquier página de claude.ai,
   haz clic en una petición y copia el encabezado 'Cookie' completo"

    echo ""
    wait_for_user "Presiona Enter cuando tengas las credenciales listas..."
    echo ""

    log_warning "Las credenciales NO se mostrarán mientras las escribes."
    echo ""

    local CLAUDE_AI_SESSION_KEY CLAUDE_WEB_SESSION_KEY CLAUDE_WEB_COOKIE

    CLAUDE_AI_SESSION_KEY=$(prompt_password "sessionKey de Claude (sk-ant-sid...)")
    echo ""
    CLAUDE_WEB_SESSION_KEY=$(prompt_password "__Secure-next-auth.session-token")
    echo ""

    log_info "Pega el contenido del header Cookie completo de claude.ai"
    log_info "Termina con ENTER y luego CTRL+D:"
    echo ""
    CLAUDE_WEB_COOKIE=""
    while IFS= read -r linea 2>/dev/null || true; do
        linea="${linea//$'\r'/}"
        CLAUDE_WEB_COOKIE+="${linea}"
    done

    if [[ -z "$CLAUDE_AI_SESSION_KEY" ]]; then
        log_error "La sessionKey de Claude no puede estar vacía."
        return 1
    fi

    # ── 3. Token de gateway ───────────────────────────────────
    log_step "Generando token de Gateway"
    local GATEWAY_TOKEN
    GATEWAY_TOKEN=$(generate_token 32)
    log_success "Token de Gateway generado ✓"

    # ── 4. Archivo .env ───────────────────────────────────────
    log_step "Guardando configuración"

    cat > "${APP_DIR}/.env" << EOF
# OpenClaw — VPSfacil
# CONFIDENCIAL — NO compartir ni subir a GitHub

OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=true

CLAUDE_AI_SESSION_KEY=${CLAUDE_AI_SESSION_KEY}
CLAUDE_WEB_SESSION_KEY=${CLAUDE_WEB_SESSION_KEY}
CLAUDE_WEB_COOKIE=${CLAUDE_WEB_COOKIE}

TZ=${TIMEZONE:-America/Santiago}
EOF

    chmod 600 "${APP_DIR}/.env"
    chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
    log_success "Archivo .env creado con permisos 600 ✓"

    # ── 5. Dockerfile ─────────────────────────────────────────
    log_step "Preparando imagen Docker de OpenClaw"

    cat > "${APP_DIR}/Dockerfile" << 'DOCKERFILE'
FROM node:24-bookworm

RUN npm install -g pnpm

RUN pnpm add -g openclaw@latest

USER node
WORKDIR /home/node

EXPOSE 18789 18790

CMD ["node", "/usr/local/lib/node_modules/openclaw/openclaw.mjs", "gateway", "--allow-unconfigured"]
DOCKERFILE

    chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/Dockerfile"

    # ── 6. Construir imagen ───────────────────────────────────
    log_step "Construyendo imagen Docker de OpenClaw"
    log_process "Puede tardar 3-5 minutos la primera vez..."

    cd "$APP_DIR"
    docker build -t openclaw-vpsfacil:latest . 2>&1 | tail -10
    log_success "Imagen openclaw-vpsfacil:latest construida ✓"

    # ── 7. Docker Compose ─────────────────────────────────────
    log_step "Generando docker-compose.yml"

    local CLAUDE_AI_ESC CLAUDE_WEB_ESC CLAUDE_COOKIE_ESC
    CLAUDE_AI_ESC=$(compose_escape "$CLAUDE_AI_SESSION_KEY")
    CLAUDE_WEB_ESC=$(compose_escape "$CLAUDE_WEB_SESSION_KEY")
    CLAUDE_COOKIE_ESC=$(compose_escape "$CLAUDE_WEB_COOKIE")

    local COMPOSE_CONTENT
    COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# OpenClaw — VPSfacil
# Acceso: http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}
# SOLO vía Tailscale VPN — NUNCA exponer a internet
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
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: "true"
      CLAUDE_AI_SESSION_KEY: "${CLAUDE_AI_ESC}"
      CLAUDE_WEB_SESSION_KEY: "${CLAUDE_WEB_ESC}"
      CLAUDE_WEB_COOKIE: "${CLAUDE_COOKIE_ESC}"
    ports:
      - "${PORT_OPENCLAW_WS}:18789"
      - "${PORT_OPENCLAW_HTTP}:18790"
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

    log_success "OpenClaw está corriendo ✓"

    # ── Resumen ───────────────────────────────────────────────
    echo ""
    print_separator
    echo ""
    log_success "OpenClaw instalado exitosamente"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Acceso (requiere Tailscale VPN):${COLOR_RESET}"
    echo -e "    URL:     ${COLOR_CYAN}http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}${COLOR_RESET}"
    echo -e "    Token:   ${COLOR_CYAN}${GATEWAY_TOKEN}${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Configuración inicial (en el servidor):${COLOR_RESET}"
    echo -e "    ${COLOR_CYAN}docker exec -it openclaw node openclaw.mjs onboard${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
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
