#!/bin/bash
# ============================================================
# setup.sh — Script principal de VPSfacil
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# ARCHIVO AUTOCONTENENIDO - incluye todas las librerías
# Descarga y ejecuta con:
#   curl -sSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/setup.sh | bash
#   o:
#   curl -sSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/setup.sh > setup.sh && bash setup.sh
#
# Requisitos:
#   - Debian 12 (Bookworm)
#   - Ejecutar como root
# ============================================================

# ============================================================
# LIBRERÍAS EMBEBIDAS (colors.sh)
# ============================================================

# --- Colores base ---
readonly COLOR_RESET="\033[0m"
readonly COLOR_BOLD="\033[1m"

readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_MAGENTA="\033[0;35m"
readonly COLOR_CYAN="\033[0;36m"
readonly COLOR_WHITE="\033[0;37m"

readonly COLOR_BOLD_RED="\033[1;31m"
readonly COLOR_BOLD_GREEN="\033[1;32m"
readonly COLOR_BOLD_YELLOW="\033[1;33m"
readonly COLOR_BOLD_BLUE="\033[1;34m"
readonly COLOR_BOLD_MAGENTA="\033[1;35m"
readonly COLOR_BOLD_CYAN="\033[1;36m"
readonly COLOR_BOLD_WHITE="\033[1;37m"

# --- Prefijos de mensajes ---
readonly PREFIX_INFO=""
readonly PREFIX_SUCCESS="${COLOR_BOLD_GREEN}[✓]${COLOR_RESET}"
readonly PREFIX_WARNING="${COLOR_BOLD_YELLOW}[⚠]${COLOR_RESET}"
readonly PREFIX_ERROR="${COLOR_BOLD_RED}[✗]${COLOR_RESET}"
readonly PREFIX_PROMPT="${COLOR_BOLD_CYAN}[?]${COLOR_RESET}"
readonly PREFIX_PROCESS="${COLOR_BOLD_MAGENTA}[⏳]${COLOR_RESET}"
readonly PREFIX_STEP="${COLOR_BOLD_WHITE}[→]${COLOR_RESET}"

# --- Función: Separador simple ---
print_separator() {
    echo -e "${COLOR_BLUE}────────────────────────────────────────────────────────────${COLOR_RESET}"
}

# --- Función: Cabecera de sección ---
print_header() {
    local title="$1"
    local width=60
    local title_len=${#title}
    local padding=$(( (width - title_len) / 2 ))
    local left_pad
    left_pad=$(printf '%*s' "$padding" '')
    local right_pad
    right_pad=$(printf '%*s' "$((width - title_len - padding))" '')

    echo ""
    echo -e "${COLOR_BOLD_BLUE}╔$(printf '═%.0s' $(seq 1 $width))╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}${COLOR_BOLD_WHITE}${left_pad}${title}${right_pad}${COLOR_RESET}${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}╚$(printf '═%.0s' $(seq 1 $width))╝${COLOR_RESET}"
    echo ""
}

# --- Función: Banner principal del proyecto ---
print_banner() {
    echo ""
    echo -e "${COLOR_BOLD_BLUE}╔══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}                                                              ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN}██╗   ██╗██████╗ ███████╗███████╗ █████╗  ██████╗██╗██╗${COLOR_RESET}                 ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN}██║   ██║██╔══██╗██╔════╝██╔════╝██╔══██╗██╔════╝██║██║${COLOR_RESET}                 ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN}██║   ██║██████╔╝███████╗█████╗  ███████║██║     ██║██║${COLOR_RESET}                 ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN}╚██╗ ██╔╝██╔═══╝ ╚════██║██╔══╝  ██╔══██║██║     ██║██║${COLOR_RESET}                 ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN} ╚████╔╝ ██║     ███████║██║     ██║  ██║╚██████╗██║███████╗${COLOR_RESET}           ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_GREEN}  ╚═══╝  ╚═╝     ╚══════╝╚═╝     ╚═╝  ╚═╝╚═════╝╚═╝╚══════╝${COLOR_RESET}           ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}                                                              ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_CYAN}Instalación Automatizada de VPS v1.0${COLOR_RESET}                    ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_WHITE}Debian 12 · Docker · Tailscale VPN${COLOR_RESET}                      ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}                                                              ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
    echo -e "${COLOR_BOLD_BLUE}╚══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

# ============================================================
# LIBRERÍAS EMBEBIDAS (utils.sh)
# ============================================================

log_info() {
    echo -e "${PREFIX_INFO} $1"
}

log_success() {
    echo -e "${PREFIX_SUCCESS} $1"
}

log_warning() {
    echo -e "${PREFIX_WARNING} $1"
}

log_error() {
    echo -e "${PREFIX_ERROR} $1" >&2
}

log_prompt() {
    echo -e "${PREFIX_PROMPT} $1"
}

log_process() {
    echo -e "${PREFIX_PROCESS} $1"
}

log_step() {
    echo ""
    echo -e "${PREFIX_STEP} ${COLOR_BOLD_WHITE}$1${COLOR_RESET}"
    echo -e "${COLOR_BLUE}$(printf '─%.0s' $(seq 1 55))${COLOR_RESET}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        log_info  "Usa: sudo bash $0"
        exit 1
    fi
}

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Este script NO debe ejecutarse como root"
        log_info  "Usa: su - ${ADMIN_USER} y luego ejecuta el script"
        exit 1
    fi
}

check_internet() {
    log_process "Verificando conectividad a internet..."
    if curl -s --max-time 10 https://www.google.com > /dev/null 2>&1; then
        log_success "Conectividad a internet confirmada"
        return 0
    else
        log_error "Sin conectividad a internet"
        log_info  "Verifica la configuración de red del VPS antes de continuar"
        return 1
    fi
}

command_exists() {
    command -v "$1" &> /dev/null
}

check_debian12() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "No se puede determinar el sistema operativo"
        return 1
    fi

    local os_id os_version
    os_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
    os_version=$(grep "^VERSION_ID=" /etc/os-release | cut -d= -f2 | tr -d '"')

    if [[ "$os_id" != "debian" || "$os_version" != "12" ]]; then
        log_error "Sistema operativo no compatible: ${os_id} ${os_version}"
        log_info  "VPSfacil requiere Debian 12 (Bookworm)"
        return 1
    fi

    log_success "Sistema operativo: Debian 12 (Bookworm) ✓"
    return 0
}

confirm() {
    local prompt="$1"
    local respuesta

    while true; do
        echo -ne "${PREFIX_PROMPT} ${prompt} ${COLOR_BOLD_WHITE}(sí/no)${COLOR_RESET}: " >&2
        read -r respuesta < /dev/tty
        respuesta="${respuesta//$'\r'/}"
        case "${respuesta,,}" in
            si|sí|s|yes|y) return 0 ;;
            no|n)           return 1 ;;
            *) log_warning "Por favor responde 'sí' o 'no'" ;;
        esac
    done
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local respuesta

    if [[ -n "$default" ]]; then
        echo -ne "${PREFIX_PROMPT} ${prompt} ${COLOR_CYAN}[${default}]${COLOR_RESET}: " >&2
    else
        echo -ne "${PREFIX_PROMPT} ${prompt}: " >&2
    fi

    read -r respuesta < /dev/tty
    respuesta="${respuesta//$'\r'/}"

    if [[ -z "$respuesta" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$respuesta"
    fi
}

prompt_password() {
    local prompt="$1"
    local pass

    echo -ne "${PREFIX_PROMPT} ${prompt}: " >&2
    read -rs pass < /dev/tty
    pass="${pass//$'\r'/}"
    echo "" >&2
    echo "$pass"
}

wait_for_user() {
    local mensaje="${1:-Presiona Enter para continuar...}"
    echo ""
    echo -ne "${PREFIX_PROMPT} ${mensaje}" >&2
    read -r < /dev/tty
    echo "" >&2
}

get_app_dir() {
    local appname="$1"
    echo "${APPS_DIR}/${appname}"
}

ensure_app_dir() {
    local appname="$1"
    local app_dir
    app_dir=$(get_app_dir "$appname")

    log_process "Creando estructura de directorios para: ${appname}"

    mkdir -p "${app_dir}/data"
    mkdir -p "${app_dir}/config"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$app_dir"
    chmod -R 755 "$app_dir"

    log_success "Directorio creado: ${app_dir}"
}

add_env_var() {
    local appname="$1"
    local key="$2"
    local value="$3"
    local env_file
    env_file="$(get_app_dir "$appname")/.env"

    sed -i "/^${key}=/d" "$env_file" 2>/dev/null || true
    echo "${key}=${value}" >> "$env_file"
}

check_docker() {
    if ! command_exists docker; then
        log_error "Docker no está instalado"
        return 1
    fi

    if ! docker info > /dev/null 2>&1; then
        log_error "El daemon de Docker no está corriendo"
        return 1
    fi

    log_success "Docker disponible ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    return 0
}

deploy_app() {
    local appname="$1"
    local app_dir
    app_dir=$(get_app_dir "$appname")

    if [[ ! -f "${app_dir}/docker-compose.yml" ]]; then
        log_error "No se encontró docker-compose.yml en: ${app_dir}"
        return 1
    fi

    log_process "Desplegando ${appname}..."

    cd "$app_dir"
    docker compose down 2>/dev/null || true
    docker compose pull
    docker compose up -d
    cd - > /dev/null

    log_success "${appname} desplegado correctamente"
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local elapsed=0

    log_process "Esperando que el puerto ${port} esté disponible (máx. ${timeout}s)..."

    while ! nc -z "$host" "$port" 2>/dev/null; do
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "El puerto ${port} no respondió en ${timeout} segundos"
            return 1
        fi
        printf "."
        sleep 2
    done

    echo ""
    log_success "Puerto ${port} disponible"
    return 0
}

compose_escape() {
    local val="$1"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    val="${val//\$/\$\$}"
    echo "$val"
}

generate_password() {
    local length="${1:-20}"
    openssl rand -base64 32 | tr -d '=+/' | cut -c1-"$length"
}

generate_token() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

get_public_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null || \
    curl -s --max-time 10 https://ifconfig.me 2>/dev/null || \
    echo "No disponible"
}

windows_instruction() {
    echo ""
    echo -e "${COLOR_BOLD_YELLOW}┌─ ACCIÓN REQUERIDA EN TU PC WINDOWS ─────────────────────┐${COLOR_RESET}"
    while IFS= read -r line; do
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET} ${line}"
    done <<< "$1"
    echo -e "${COLOR_BOLD_YELLOW}└──────────────────────────────────────────────────────────┘${COLOR_RESET}"
    echo ""
}

# ============================================================
# LIBRERÍAS EMBEBIDAS (config.sh)
# ============================================================

source_config() {
    if [[ -n "${DOMAIN:-}" && -n "${ADMIN_USER:-}" ]]; then
        _derive_config_vars
        return 0
    fi

    local config_file=""
    local candidates=(
        "${HOME}/setup.conf"
        "/tmp/vpsfacil_setup.conf"
        "/root/setup.conf"
    )
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
        source "$config_file"
        _derive_config_vars
        return 0
    fi

    echo ""
    echo -e "\033[1;31m[✗]\033[0m Error: No se encontró configuración guardada"
    echo -e "\033[0;34m[ℹ]\033[0m Ejecuta primero: bash setup.sh"
    echo ""
    exit 1
}

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

    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 1 de 3 — Dominio${COLOR_RESET}"
    echo ""
    log_info "Escribe el nombre de tu dominio principal."
    log_info "Ejemplos: agentexperto.work  |  miempresa.com  |  startup.io"
    echo ""
    while true; do
        DOMAIN=$(prompt_input "¿Cuál es tu dominio?" "agentexperto.work")
        DOMAIN="${DOMAIN,,}"

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

    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 2 de 3 — Usuario administrador${COLOR_RESET}"
    echo ""
    log_info "Este usuario reemplazará a 'root' como administrador del servidor."
    log_info "Con él te conectarás vía SSH después de la instalación."
    log_info "Usa solo letras minúsculas, números y guión bajo (sin espacios)."
    log_info "Ejemplos: jaime  |  admin  |  carlos_lopez"
    echo ""
    while true; do
        ADMIN_USER=$(prompt_input "¿Qué nombre de usuario quieres crear?" "admin")
        ADMIN_USER="${ADMIN_USER,,}"

        if [[ "$ADMIN_USER" =~ ^[a-z][a-z0-9_]{1,31}$ ]]; then
            # Verificar si el usuario ya existe
            if id "$ADMIN_USER" &>/dev/null; then
                echo ""
                log_warning "El usuario '$ADMIN_USER' ya existe en el sistema"
                if confirm "¿Deseas eliminarlo y recrearlo desde cero?"; then
                    log_process "Eliminando usuario existente: $ADMIN_USER"
                    userdel -r "$ADMIN_USER" 2>/dev/null || true
                    log_success "Usuario $ADMIN_USER eliminado"
                    echo ""
                    break
                else
                    log_warning "Por favor, elige un nombre de usuario diferente"
                    echo ""
                fi
            else
                break
            fi
        else
            log_warning "Nombre inválido. Solo letras minúsculas, números y guión bajo."
            log_info    "Correcto:   jaime  |  admin  |  mi_usuario"
            log_info    "Incorrecto: Mi Usuario  |  123admin  |  admin@host"
        fi
    done

    echo ""
    print_separator
    echo ""

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

_derive_config_vars() {
    export ADMIN_HOME="/home/${ADMIN_USER}"
    export APPS_DIR="${ADMIN_HOME}/apps"
    export CERTS_DIR="${APPS_DIR}/certs"
    export BACKUP_DIR="${APPS_DIR}/backups"

    export VPN_SUBDOMAIN="vpn.${DOMAIN}"
    export CF_WILDCARD="*.vpn.${DOMAIN}"

    export URL_PORTAINER="https://portainer.vpn.${DOMAIN}:9443"
    export URL_N8N="https://n8n.vpn.${DOMAIN}:5678"
    export URL_FILEBROWSER="http://files.vpn.${DOMAIN}:8080"
    export URL_OPENCLAW="https://openclaw.vpn.${DOMAIN}:18789"
    export URL_KOPIA="https://kopia.vpn.${DOMAIN}:51515"

    export CERT_FILE="${CERTS_DIR}/origin-cert.pem"
    export CERT_KEY="${CERTS_DIR}/origin-cert-key.pem"
    export CERT_CA="${CERTS_DIR}/cloudflare-ca.crt"
}

save_config() {
    local config_file

    if [[ -d "/home/${ADMIN_USER}" ]]; then
        config_file="/home/${ADMIN_USER}/setup.conf"
    else
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

# Puertos internos
readonly PORT_SSH="22"
readonly PORT_TAILSCALE="41641"
readonly PORT_PORTAINER="9443"
readonly PORT_N8N="5678"
readonly PORT_FILEBROWSER="8080"
readonly PORT_OPENCLAW_WS="18789"
readonly PORT_OPENCLAW_HTTP="18790"
readonly PORT_KOPIA="51515"

# Imágenes Docker
readonly IMG_PORTAINER="portainer/portainer-ce:latest"
readonly IMG_N8N="docker.n8n.io/n8nio/n8n:latest"
readonly IMG_POSTGRES="postgres:16-alpine"
readonly IMG_FILEBROWSER="filebrowser/filebrowser:latest"
readonly IMG_KOPIA="kopia/kopia:latest"
readonly IMG_OPENCLAW="node:24-bookworm"

# Timeouts
readonly TIMEOUT_DOCKER_START=60
readonly TIMEOUT_APP_START=120
readonly TIMEOUT_USER_INPUT=300

# Red Docker
readonly DOCKER_NETWORK="vpsfacil-net"

# Versión mínima Docker
readonly DOCKER_MIN_VERSION="24"

# ============================================================
# LIBRERÍAS EMBEBIDAS (install_prompts.sh)
# ============================================================

collect_all_inputs() {
    local config_file="/tmp/vpsfacil_install.conf"

    clear
    print_banner
    echo ""
    print_header "Instalación Automática - Recolección de Datos"
    echo ""
    log_info "Se harán todas las preguntas ahora. Después, la instalación"
    log_info "correrá sin interrupciones hasta completarse."
    echo ""
    print_separator
    echo ""

    log_step "Credenciales de Portainer"
    echo ""
    log_info "Usuario administrador de Portainer (será creado automáticamente):"
    PORTAINER_ADMIN=$(prompt_input "Usuario Portainer" "admin")
    echo ""

    while true; do
        PORTAINER_PASS=$(prompt_password "Contraseña para ${PORTAINER_ADMIN} en Portainer")
        PORTAINER_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$PORTAINER_PASS" == "$PORTAINER_PASS2" && ${#PORTAINER_PASS} -ge 8 ]]; then
            break
        elif [[ "$PORTAINER_PASS" != "$PORTAINER_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        else
            log_warning "Mínimo 8 caracteres."
        fi
    done
    echo ""

    log_step "Contraseña de Cifrado de Kopia"
    echo ""
    log_warning "Esta contraseña cifra tus backups. Guárdala en un lugar seguro."
    log_info "SIN ella, no podrás restaurar tus backups."
    echo ""

    while true; do
        KOPIA_PASS=$(prompt_password "Contraseña para cifrar backups de Kopia")
        KOPIA_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$KOPIA_PASS" == "$KOPIA_PASS2" && ${#KOPIA_PASS} -ge 8 ]]; then
            break
        elif [[ "$KOPIA_PASS" != "$KOPIA_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        else
            log_warning "Mínimo 8 caracteres."
        fi
    done
    echo ""

    print_separator
    echo ""
    log_info "Resumen de configuración:"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Dominio:${COLOR_RESET}           ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Usuario admin:${COLOR_RESET}      ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Zona horaria:${COLOR_RESET}       ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Portainer:${COLOR_RESET}"
    echo -e "     Usuario:     ${COLOR_CYAN}${PORTAINER_ADMIN}${COLOR_RESET}"
    echo -e "     Contraseña:  ●●●●●●●●"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Kopia:${COLOR_RESET}"
    echo -e "     Cifrado:     ●●●●●●●●"
    echo ""
    print_separator
    echo ""

    if ! confirm "¿Es correcta esta configuración?"; then
        log_info "Volviendo atrás..."
        collect_all_inputs
        return
    fi

    cat > "$config_file" << EOF
# ============================================================
# Configuración de Instalación Automática - VPSfacil
# Generado automáticamente por setup.sh
# NO editar manualmente
# ============================================================

# Configuración básica
DOMAIN="${DOMAIN}"
ADMIN_USER="${ADMIN_USER}"
TIMEZONE="${TIMEZONE}"
INSTALLATION_DATE="$(date '+%Y-%m-%d')"

# Credenciales Portainer
PORTAINER_ADMIN="${PORTAINER_ADMIN}"
PORTAINER_PASS="${PORTAINER_PASS}"

# Contraseña Kopia
KOPIA_PASS="${KOPIA_PASS}"

# Bandera para instalar_core.sh
INSTALLATION_MODE="automatic"
EOF

    chmod 600 "$config_file"
    log_success "Configuración guardada en: $config_file ✓"
    echo ""
}

# ============================================================
# FUNCIÓN: Ejecutar un script de instalación (local o remoto)
# ============================================================
run_phase_script() {
    local script_name="$1"
    local script_path

    if [[ -n "${SCRIPT_DIR}" && "${SCRIPT_DIR}" != "" ]]; then
        # Ejecución local — usar script del repo
        script_path="${SCRIPT_DIR}/scripts/${script_name}"
        if [[ ! -f "$script_path" ]]; then
            log_error "Script no encontrado: $script_path"
            return 1
        fi
        bash "$script_path"
    else
        # Ejecución remota — descargar a archivo temporal y ejecutar
        local tmp_script
        tmp_script=$(mktemp)
        curl -sSL "${REPO_RAW}/scripts/${script_name}?v=$(date +%s)" > "$tmp_script"
        bash "$tmp_script"
        local exit_code=$?
        rm -f "$tmp_script"
        return $exit_code
    fi
}

# ============================================================
# HABILITAR STRICT MODE AHORA QUE LAS LIBRERÍAS ESTÁN CARGADAS
# ============================================================
set -euo pipefail

# ============================================================
# SCRIPT PRINCIPAL - setup.sh
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || SCRIPT_DIR=""

clear
print_banner
echo ""
print_header "FASE A - Preparación (setup.sh)"
echo ""

log_success "Sistema de instalación VPSfacil"
log_success "Ejecución: FASE A (como root)"
echo ""

# Verificación inicial
check_root
check_debian12
check_internet

echo ""
log_success "Procediendo con FASE A..."
echo ""

# Pedir configuración inicial
ask_initial_config

# Detectar y eliminar otros usuarios adicionales (que no sean root ni el admin que se crea)
echo ""
log_step "Verificación de usuarios del sistema"
echo ""

EXTRA_USERS=$(getent passwd | awk -F: '$3 >= 1000 {print $1}' | grep -v "^${ADMIN_USER}$" || true)

if [[ -n "$EXTRA_USERS" ]]; then
    log_warning "Se detectaron usuarios adicionales en el sistema:"
    echo "$EXTRA_USERS" | while read user; do
        log_warning "  - $user"
    done
    echo ""

    if confirm "¿Deseas eliminarlos para comenzar con una instalación limpia?"; then
        echo "$EXTRA_USERS" | while read user; do
            log_process "Eliminando usuario: $user"
            userdel -r "$user" 2>/dev/null || true
            log_success "Usuario $user eliminado"
        done
        echo ""
    else
        log_error "No se puede continuar con usuarios adicionales. Operación cancelada."
        exit 1
    fi
else
    log_success "Sistema limpio - solo root detectado"
    echo ""
fi

# Ejecutar PASO 1: precheck
log_step "Paso 1 - Verificaciones previas"
run_phase_script "00_precheck.sh" || { log_error "Paso 1 falló"; exit 1; }

# Ejecutar PASO 2: crear usuario
echo ""
log_step "Paso 2 - Crear usuario administrador"
run_phase_script "01_create_user.sh" || { log_error "Paso 2 falló"; exit 1; }

# Ejecutar PASO 3: secure SSH
echo ""
log_step "Paso 3 - Hardening SSH"
run_phase_script "02_secure_ssh.sh" || { log_error "Paso 3 falló"; exit 1; }

# Ejecutar PASO 5: Tailscale
echo ""
log_step "Paso 5 - Instalar Tailscale VPN"
run_phase_script "05_install_tailscale.sh" || { log_error "Paso 5 falló"; exit 1; }

# Recolectar credenciales Portainer y Kopia
echo ""
log_step "Recolectando datos para instalación automática"
echo ""
collect_all_inputs

echo ""
print_separator
echo ""
log_success "✓ FASE A completada exitosamente"
echo ""
log_success "Próximo paso:"
log_success "1. Reconéctate a tu VPS como usuario admin vía Bitvise SSH:"
echo ""
echo -e "   ${COLOR_CYAN}ssh ${ADMIN_USER}@<TU_IP_VPS>${COLOR_RESET}"
echo ""
log_success "2. Ejecuta:"
echo ""
echo -e "   ${COLOR_CYAN}bash ~/install_core.sh${COLOR_RESET}"
echo ""
log_success "Para descargar install_core.sh, usa:"
echo ""
echo -e "   ${COLOR_CYAN}curl -sSL \"${REPO_RAW}/scripts/install_core.sh?v=\$(date +%s)\" > ~/install_core.sh && bash ~/install_core.sh${COLOR_RESET}"
echo ""
print_separator
echo ""
