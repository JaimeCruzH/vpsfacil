#!/bin/bash
# ============================================================
# lib/config.sh — Variables globales y configuración central
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Este archivo se carga SIEMPRE como primer paso en todos los
# scripts. Define las variables que usan todos los demás.
#
# Orden de carga:
#   1. lib/colors.sh   → colores y print_header
#   2. lib/config.sh   → este archivo, variables globales
#   3. lib/utils.sh    → funciones que usan las variables
# ============================================================

# ============================================================
# FUNCIÓN PRINCIPAL: cargar o pedir configuración
# ============================================================
# Llama a esta función al inicio de cada script:
#   source_config
#
# Si existe setup.conf → carga silenciosamente
# Si NO existe → pide dominio y usuario al usuario
# ============================================================
source_config() {
    # 1. Si las variables ya están en el entorno (heredadas de setup.sh), usarlas
    if [[ -n "${DOMAIN:-}" && -n "${ADMIN_USER:-}" ]]; then
        _derive_config_vars
        return 0
    fi

    # 2. Buscar archivo de configuración en ubicaciones conocidas
    local config_file=""
    local candidates=(
        "${HOME}/setup.conf"
        "/tmp/vpsfacil_setup.conf"
        "/root/setup.conf"
    )
    # Si se ejecuta con sudo, buscar también en el home del usuario real
    if [[ -n "${SUDO_USER:-}" && -d "/home/${SUDO_USER}" ]]; then
        candidates+=("/home/${SUDO_USER}/setup.conf")
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            config_file="$candidate"
            break
        fi
    done

    if [[ -n "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        _derive_config_vars
        return 0
    fi

    # 3. No se encontró configuración — el usuario debe ejecutar setup.sh primero
    echo ""
    echo -e "\033[1;31m[✗]\033[0m Error: No se encontró configuración guardada"
    echo -e "\033[0;34m[ℹ]\033[0m Ejecuta primero: bash setup.sh"
    echo ""
    exit 1
}

# ============================================================
# FUNCIÓN: solicitar configuración inicial al usuario
# (llamada solo desde setup.sh en la primera ejecución)
# ============================================================
ask_initial_config() {
    print_header "Configuración Inicial"

    log_info "Antes de instalar necesitamos dos datos básicos:"
    log_info "  1. Tu nombre de dominio (ej: miempresa.com)"
    log_info "  2. El nombre del usuario administrador a crear en el servidor"
    echo ""
    log_info "Esta información se usará en toda la instalación."
    echo ""
    print_separator
    echo ""

    # --- Dominio ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 1 de 3 — Dominio${COLOR_RESET}"
    echo ""
    log_info "Escribe el nombre de tu dominio principal."
    log_info "Ejemplos: agentexperto.work  |  miempresa.com  |  startup.io"
    echo ""
    while true; do
        DOMAIN=$(prompt_input "¿Cuál es tu dominio?" "agentexperto.work")
        DOMAIN="${DOMAIN,,}"  # convertir a minúsculas

        # Regex corregida: valida que haya al menos una parte + punto + TLD
        if [[ "$DOMAIN" =~ ^([a-z0-9][a-z0-9-]*\.)+[a-z]{2,}$ ]]; then
            break
        else
            log_warning "Formato inválido. Escribe solo el dominio, sin http ni www."
            log_info    "Correcto:   agentexperto.work"
            log_info    "Incorrecto: https://agentexperto.work  o  www.agentexperto.work"
        fi
    done

    echo ""
    print_separator
    echo ""

    # --- Usuario admin ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 2 de 3 — Usuario administrador${COLOR_RESET}"
    echo ""
    log_info "Este usuario reemplazará a 'root' como administrador del servidor."
    log_info "Con él te conectarás vía SSH después de la instalación."
    log_info "Usa solo letras minúsculas, números y guión bajo (sin espacios)."
    log_info "Ejemplos: jaime  |  admin  |  carlos_lopez"
    echo ""
    while true; do
        ADMIN_USER=$(prompt_input "¿Qué nombre de usuario quieres crear?" "admin")
        ADMIN_USER="${ADMIN_USER,,}"  # convertir a minúsculas

        if [[ "$ADMIN_USER" =~ ^[a-z][a-z0-9_]{1,31}$ ]]; then
            break
        else
            log_warning "Nombre inválido. Solo letras minúsculas, números y guión bajo."
            log_info    "Correcto:   jaime  |  admin  |  mi_usuario"
            log_info    "Incorrecto: Mi Usuario  |  123admin  |  admin@host"
        fi
    done

    echo ""
    print_separator
    echo ""

    # --- Zona horaria ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 3 de 3 — Zona horaria${COLOR_RESET}"
    echo ""
    log_info "Define la zona horaria del servidor (afecta logs y backups)."
    log_info "Ejemplos:"
    log_info "  América: America/Santiago  |  America/Bogota  |  America/Mexico_City"
    log_info "  Europa:  Europe/Madrid     |  Europe/London"
    log_info "  Si no estás seguro, usa: UTC"
    echo ""
    TIMEZONE=$(prompt_input "¿Cuál es tu zona horaria?" "America/Santiago")

    echo ""

    # Confirmar configuración
    print_separator
    log_info "Resumen de configuración:"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Dominio:${COLOR_RESET}       ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Usuario admin:${COLOR_RESET} ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Zona horaria:${COLOR_RESET}  ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Home del usuario:${COLOR_RESET} ${COLOR_CYAN}/home/${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Apps en:${COLOR_RESET}       ${COLOR_CYAN}/home/${ADMIN_USER}/apps${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}URL VPN base:${COLOR_RESET}  ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET}"
    echo ""
    print_separator

    if ! confirm "¿Es correcta esta configuración?"; then
        log_info "Volvamos a intentarlo..."
        ask_initial_config
        return
    fi

    _derive_config_vars
    save_config
}

# ============================================================
# FUNCIÓN: derivar variables a partir de DOMAIN y ADMIN_USER
# (interna, no llamar directamente)
# ============================================================
_derive_config_vars() {
    # Directorios
    export ADMIN_HOME="/home/${ADMIN_USER}"
    export APPS_DIR="${ADMIN_HOME}/apps"
    export CERTS_DIR="${APPS_DIR}/certs"
    export BACKUP_DIR="${APPS_DIR}/backups"

    # Subdominios VPN
    export VPN_SUBDOMAIN="vpn.${DOMAIN}"              # vpn.agentexperto.work
    export CF_WILDCARD="*.vpn.${DOMAIN}"              # *.vpn.agentexperto.work

    # URLs de cada aplicación (via Tailscale VPN)
    export URL_PORTAINER="https://portainer.vpn.${DOMAIN}:9443"
    export URL_N8N="https://n8n.vpn.${DOMAIN}:5678"
    export URL_FILEBROWSER="https://files.vpn.${DOMAIN}:8080"
    export URL_OPENCLAW="https://openclaw.vpn.${DOMAIN}:18789"
    export URL_KOPIA="https://kopia.vpn.${DOMAIN}:51515"

    # Configuración de archivos de certificado
    export CERT_FILE="${CERTS_DIR}/origin-cert.pem"
    export CERT_KEY="${CERTS_DIR}/origin-cert-key.pem"
    export CERT_CA="${CERTS_DIR}/cloudflare-ca.crt"
}

# ============================================================
# FUNCIÓN: guardar configuración en archivo
# ============================================================
save_config() {
    local config_file

    # Si ya existe el home del usuario admin, guardar ahí
    if [[ -d "/home/${ADMIN_USER}" ]]; then
        config_file="/home/${ADMIN_USER}/setup.conf"
    else
        # Durante la instalación inicial, aún no existe el usuario
        # Guardarlo temporalmente en /tmp y moverlo después
        config_file="/tmp/vpsfacil_setup.conf"
    fi

    cat > "$config_file" << EOF
# ============================================================
# VPSfacil - Configuración de instalación
# Generado automáticamente el $(date '+%Y-%m-%d %H:%M:%S')
# NO editar manualmente a menos que sepas lo que haces
# ============================================================

DOMAIN="${DOMAIN}"
ADMIN_USER="${ADMIN_USER}"
TIMEZONE="${TIMEZONE:-America/Santiago}"
INSTALLATION_DATE="$(date '+%Y-%m-%d')"
EOF

    chmod 600 "$config_file"
    log_success "Configuración guardada en: ${config_file}"
}

# ============================================================
# VARIABLES DE CONFIGURACIÓN FIJA (puertos y versiones)
# Estas NO cambian con el usuario — son constantes del sistema
# ============================================================

# Puertos internos de aplicaciones
readonly PORT_SSH="22"
readonly PORT_TAILSCALE="41641"
readonly PORT_PORTAINER="9443"
readonly PORT_N8N="5678"
readonly PORT_FILEBROWSER="8080"
readonly PORT_OPENCLAW_WS="18789"
readonly PORT_OPENCLAW_HTTP="18790"
readonly PORT_KOPIA="51515"

# Imágenes Docker (versiones fijadas para reproducibilidad)
readonly IMG_PORTAINER="portainer/portainer-ce:latest"
readonly IMG_N8N="docker.n8n.io/n8nio/n8n:latest"
readonly IMG_POSTGRES="postgres:16-alpine"
readonly IMG_FILEBROWSER="filebrowser/filebrowser:latest"
readonly IMG_KOPIA="kopia/kopia:latest"
readonly IMG_OPENCLAW="node:24-bookworm"

# Timeouts (en segundos)
readonly TIMEOUT_DOCKER_START=60
readonly TIMEOUT_APP_START=120
readonly TIMEOUT_USER_INPUT=300

# Red Docker interna
readonly DOCKER_NETWORK="vpsfacil-net"

# Versión mínima de Docker requerida
readonly DOCKER_MIN_VERSION="24"
