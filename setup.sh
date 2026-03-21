#!/bin/bash
# ============================================================
# setup.sh — Script principal de VPSfacil
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# ARCHIVO AUTOCONTENIDO - incluye todas las librerías
# Descarga y ejecuta con:
#   curl -sSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/setup.sh | bash
#   o:
#   curl -sSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/setup.sh > setup.sh && bash setup.sh
#
# Ejecuta los 11 pasos de instalación como root, sin interrupciones.
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
    echo -e "${COLOR_BOLD_BLUE}║${COLOR_RESET}  ${COLOR_BOLD_CYAN}Instalación Automatizada de VPS v2.0${COLOR_RESET}                    ${COLOR_BOLD_BLUE}║${COLOR_RESET}"
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
        respuesta="$(echo "$respuesta" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "${respuesta,,}" in
            si|sí|s|yes|y) return 0 ;;
            no|n)           return 1 ;;
            "") ;;
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
    respuesta="$(echo "$respuesta" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

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
    pass="$(echo "$pass" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
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

wait_for_dpkg() {
    local max_wait=120
    local elapsed=0

    while fuser /var/lib/dpkg/lock-frontend > /dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock > /dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock > /dev/null 2>&1; do
        if [[ $elapsed -eq 0 ]]; then
            log_process "Esperando que dpkg/apt termine (otro proceso lo está usando)..."
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
            log_warning "dpkg sigue bloqueado después de ${max_wait}s. Continuando de todos modos..."
            break
        fi
    done
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

_derive_config_vars() {
    export ADMIN_HOME="/home/${ADMIN_USER}"
    export APPS_DIR="${ADMIN_HOME}/apps"
    export CERTS_DIR="${APPS_DIR}/certs"
    export BACKUP_DIR="${APPS_DIR}/backups"

    export VPN_SUBDOMAIN="vpn.${DOMAIN}"
    export CF_WILDCARD="*.vpn.${DOMAIN}"

    export URL_PORTAINER="https://portainer.vpn.${DOMAIN}:9443"
    export URL_FILEBROWSER="http://files.vpn.${DOMAIN}:8080"
    export URL_KOPIA="https://kopia.vpn.${DOMAIN}:51515"

    export CERT_FILE="${CERTS_DIR}/origin-cert.pem"
    export CERT_KEY="${CERTS_DIR}/origin-cert-key.pem"
    export CERT_CA="${CERTS_DIR}/cloudflare-ca.crt"

    export ADMIN_PASS="${ADMIN_PASS:-}"
}

save_config() {
    local config_file="/tmp/vpsfacil_setup.conf"

    # Escribir línea por línea con printf %q para escapar caracteres especiales
    {
        echo "# VPSfacil - Configuración de instalación"
        echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        printf 'DOMAIN=%q\n' "$DOMAIN"
        printf 'ADMIN_USER=%q\n' "$ADMIN_USER"
        printf 'TIMEZONE=%q\n' "${TIMEZONE:-America/Santiago}"
        printf 'INSTALLATION_DATE=%q\n' "$(date '+%Y-%m-%d')"
        printf 'ADMIN_PASS=%q\n' "$ADMIN_PASS"
        printf 'PORTAINER_ADMIN=%q\n' "$PORTAINER_ADMIN"
        printf 'PORTAINER_PASS=%q\n' "$PORTAINER_PASS"
        printf 'KOPIA_PASS=%q\n' "$KOPIA_PASS"
    } > "$config_file"

    chmod 600 "$config_file"
    log_success "Configuración guardada en: ${config_file}"
}

# ============================================================
# LIBRERÍAS EMBEBIDAS (progress.sh)
# ============================================================

PROGRESS_LOG="/tmp/vpsfacil_progress.log"

declare -gA CORE_STEPS=(
    [1]="Pre-verificaciones del Sistema"
    [2]="Crear Usuario Administrador"
    [3]="Firewall UFW"
    [4]="Docker & Docker Compose"
    [5]="Tailscale VPN"
    [6]="DNS Cloudflare"
    [7]="Certificados SSL"
    [8]="Portainer"
    [9]="Kopia Backup"
    [10]="File Browser"
    [11]="Finalizar: Permisos y SSH"
)

progress_init() {
    if [[ -f "$PROGRESS_LOG" ]]; then
        log_info "Detectada instalación previa. Continuando desde donde se quedó..."
    else
        > "$PROGRESS_LOG"
        log_info "Iniciando nuevo registro de progreso"
    fi
}

progress_is_completed() {
    local step_num="$1"
    if [[ -f "$PROGRESS_LOG" ]]; then
        grep -q "^PASO=${step_num}|.*STATUS=completado" "$PROGRESS_LOG" 2>/dev/null
        return $?
    fi
    return 1
}

progress_start_step() {
    local step_num="$1"
    local start_epoch=$(date +%s)
    export "STEP_${step_num}_START=$start_epoch"
}

progress_complete_step() {
    local step_num="$1"
    local step_name="${CORE_STEPS[$step_num]}"

    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local end_epoch=$(date +%s)
    local start_var="STEP_${step_num}_START"
    local start_epoch="${!start_var:-0}"

    local duration=0
    if [[ $start_epoch -gt 0 ]]; then
        duration=$((end_epoch - start_epoch))
    fi

    local duration_str=$(printf "%dm%02ds" $((duration / 60)) $((duration % 60)))

    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=completado|FIN=$end_time|DURACION=$duration_str" >> "$PROGRESS_LOG"

    unset "STEP_${step_num}_START"
}

progress_fail_step() {
    local step_num="$1"
    local step_name="${CORE_STEPS[$step_num]}"
    local error_msg="${2:-Unknown error}"

    local fail_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=fallido|FALLO=$fail_time|ERROR=$error_msg" >> "$PROGRESS_LOG"

    unset "STEP_${step_num}_START"
}

progress_get_total_duration() {
    if [[ ! -f "$PROGRESS_LOG" ]]; then
        echo "0"
        return
    fi

    local total_seconds=0
    while IFS='|' read -r step name status rest; do
        if [[ "$status" == "STATUS=completado" ]]; then
            local dur_field=""
            dur_field=$(echo "$rest" | grep -o "DURACION=[^|]*" || echo "")
            if [[ "$dur_field" =~ DURACION=([0-9]+)m([0-9]+)s ]]; then
                local mins="${BASH_REMATCH[1]}"
                local secs="${BASH_REMATCH[2]}"
                total_seconds=$((total_seconds + 10#$mins * 60 + 10#$secs))
            fi
        fi
    done < "$PROGRESS_LOG"

    echo "$total_seconds"
}

progress_show() {
    local completed_count=0
    local total_count=11

    local completed_steps=""
    if [[ -f "$PROGRESS_LOG" ]]; then
        if grep -q "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null; then
            completed_count=$(grep "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null | wc -l | tr -d ' ')
        fi
        completed_steps=$(grep "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null | cut -d'|' -f1 | sed 's/PASO=//' | tr '\n' ' ' 2>/dev/null || echo "")
    fi

    local percentage=$((completed_count * 100 / total_count))

    local bar_length=30
    local filled=$((percentage * bar_length / 100))
    local empty=$((bar_length - filled))

    local progress_bar=""
    for ((i = 0; i < filled; i++)); do
        progress_bar+="█"
    done
    for ((i = 0; i < empty; i++)); do
        progress_bar+="░"
    done

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    printf "║  Instalación VPSfacil: Progreso %d/%d (%d%%)                  ║\n" "$completed_count" "$total_count" "$percentage"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║                                                               ║"
    printf "║  [%s] %d%%                                ║\n" "$progress_bar" "$percentage"
    echo "║                                                               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    for step_num in 1 2 3 4 5 6 7 8 9 10 11; do
        local step_name="${CORE_STEPS[$step_num]}"
        local status_icon="⏸"
        local info="[en espera]"

        if [[ " $completed_steps " =~ " $step_num " ]]; then
            status_icon="✓"
            local duration=$(grep "^PASO=$step_num|" "$PROGRESS_LOG" 2>/dev/null | grep "STATUS=completado" 2>/dev/null | tail -1 | grep -o "DURACION=[^|]*" 2>/dev/null | cut -d'=' -f2 || echo "")
            if [[ -n "$duration" ]]; then
                info="[completado $duration]"
            else
                info="[completado]"
            fi
        fi

        printf "║  %-1s Paso %-2d: %-35s %s  ║\n" "$status_icon" "$step_num" "$step_name" "$info"
    done

    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================
# CONFIGURACIÓN FIJA (puertos y versiones)
# ============================================================

readonly PORT_SSH="22"
readonly PORT_TAILSCALE="41641"
readonly PORT_PORTAINER="9443"
readonly PORT_FILEBROWSER="8080"
readonly PORT_KOPIA="51515"

readonly IMG_PORTAINER="portainer/portainer-ce:latest"
readonly IMG_FILEBROWSER="filebrowser/filebrowser:latest"
readonly IMG_KOPIA="kopia/kopia:latest"

readonly TIMEOUT_DOCKER_START=60
readonly TIMEOUT_APP_START=120
readonly TIMEOUT_USER_INPUT=300

readonly DOCKER_NETWORK="vpsfacil-net"
readonly DOCKER_MIN_VERSION="24"

# ============================================================
# FUNCIÓN: Recopilar TODA la configuración al inicio
# ============================================================
ask_all_config() {
    print_header "Configuración Inicial"

    log_info "Solo 3 preguntas antes de empezar."
    log_info "Después, la instalación corre sin interrupciones"
    log_info "(excepto Cloudflare y Tailscale que requieren interacción)."
    echo ""
    print_separator
    echo ""

    # --- Pregunta 1: Dominio ---
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
        fi
    done

    echo ""
    print_separator
    echo ""

    # --- Pregunta 2: Usuario admin ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 2 de 3 — Usuario administrador${COLOR_RESET}"
    echo ""
    log_info "Este usuario reemplazará a 'root' como administrador del servidor."
    log_info "Usa solo letras minúsculas, números y guión bajo (sin espacios)."
    echo ""
    while true; do
        ADMIN_USER=$(prompt_input "¿Qué nombre de usuario quieres crear?" "admin")
        ADMIN_USER="${ADMIN_USER,,}"

        if [[ "$ADMIN_USER" =~ ^[a-z][a-z0-9_]{1,31}$ ]]; then
            if getent passwd "$ADMIN_USER" > /dev/null 2>&1; then
                echo ""
                log_warning "El usuario '${ADMIN_USER}' ya existe en el sistema"
                if confirm "¿Deseas eliminarlo y recrearlo desde cero?"; then
                    log_process "Eliminando usuario existente: ${ADMIN_USER}"
                    userdel -r "$ADMIN_USER" 2>/dev/null || true
                    log_success "Usuario ${ADMIN_USER} eliminado ✓"
                    break
                else
                    log_warning "Por favor, elige un nombre de usuario diferente"
                    echo ""
                    continue
                fi
            else
                break
            fi
        else
            log_warning "Nombre inválido. Solo letras minúsculas, números y guión bajo."
        fi
    done

    echo ""
    print_separator
    echo ""

    # --- Pregunta 3: Contraseña admin ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 2b — Contraseña del usuario admin${COLOR_RESET}"
    echo ""
    log_info "Define una contraseña para el usuario '${ADMIN_USER}'."
    log_info "Requisitos: mínimo 12 caracteres, solo letras (a-z, A-Z) y números (0-9)."
    log_warning "Guarda esta contraseña en un lugar seguro."
    echo ""

    while true; do
        ADMIN_PASS=$(prompt_password "Contraseña para '${ADMIN_USER}'")
        ADMIN_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$ADMIN_PASS" != "$ADMIN_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        elif [[ ${#ADMIN_PASS} -lt 12 ]]; then
            log_warning "Mínimo 12 caracteres."
        elif [[ ! "$ADMIN_PASS" =~ ^[a-zA-Z0-9]+$ ]]; then
            log_warning "Solo se permiten letras (a-z, A-Z) y números (0-9). Sin espacios ni símbolos."
        else
            break
        fi
    done

    echo ""
    print_separator
    echo ""

    # --- Pregunta 4: Zona horaria ---
    echo -e "${COLOR_BOLD_WHITE}PREGUNTA 3 de 3 — Zona horaria${COLOR_RESET}"
    echo ""
    log_info "Define la zona horaria del servidor (afecta logs y backups)."
    log_info "Ejemplos: America/Santiago  |  America/Bogota  |  America/Mexico_City"
    echo ""
    TIMEZONE=$(prompt_input "¿Cuál es tu zona horaria?" "America/Santiago")

    # Portainer y Kopia usan las mismas credenciales del admin
    PORTAINER_ADMIN="$ADMIN_USER"
    PORTAINER_PASS="$ADMIN_PASS"
    KOPIA_PASS="$ADMIN_PASS"

    echo ""
    print_separator
    echo ""

    # --- Resumen y confirmación ---
    log_info "Resumen de configuración:"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Dominio:${COLOR_RESET}          ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Usuario admin:${COLOR_RESET}    ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Zona horaria:${COLOR_RESET}     ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Home:${COLOR_RESET}             ${COLOR_CYAN}/home/${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Apps en:${COLOR_RESET}          ${COLOR_CYAN}/home/${ADMIN_USER}/apps${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}URL VPN base:${COLOR_RESET}     ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET}"
    echo ""
    log_info "Las credenciales del admin se usarán también para Portainer y Kopia."
    echo ""
    print_separator

    if ! confirm "¿Es correcta esta configuración?"; then
        log_info "Volvamos a intentarlo..."
        ask_all_config
        return
    fi

    # Exportar todo
    export DOMAIN ADMIN_USER ADMIN_PASS TIMEZONE
    export PORTAINER_ADMIN PORTAINER_PASS KOPIA_PASS

    _derive_config_vars
    save_config
}

# ============================================================
# FUNCIÓN: Ejecutar un script de instalación (local o remoto)
# ============================================================
run_phase_script() {
    local script_name="$1"
    local script_path

    if [[ -n "${SCRIPT_DIR}" && "${SCRIPT_DIR}" != "" ]]; then
        script_path="${SCRIPT_DIR}/scripts/${script_name}"
        if [[ ! -f "$script_path" ]]; then
            log_error "Script no encontrado: $script_path"
            return 1
        fi
        bash "$script_path"
    else
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
# FUNCIÓN: Ejecutar un paso con tracking de progreso
# ============================================================
run_step() {
    local step_num="$1"
    local script_name="$2"
    local description="$3"

    # Saltar si ya completado (para resume)
    if progress_is_completed "$step_num"; then
        log_info "Paso $step_num ya completado, saltando..."
        return 0
    fi

    progress_start_step "$step_num"

    # Ejecutar el script
    set +e
    run_phase_script "$script_name"
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]]; then
        progress_complete_step "$step_num"
        echo ""
        progress_show
    else
        progress_fail_step "$step_num" "Exit code $exit_code"
        echo ""
        progress_show
        echo ""
        log_error "INSTALACIÓN DETENIDA en Paso $step_num: $description"
        log_info "El progreso ha sido guardado. Cuando resuelvas el error,"
        log_info "reconéctate como root y ejecuta nuevamente: bash setup.sh"
        exit 1
    fi
}

# ============================================================
# HABILITAR STRICT MODE
# ============================================================
set -euo pipefail

# ============================================================
# SCRIPT PRINCIPAL
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# Solo usar scripts locales si es un repo git completo (desarrollo local)
# En producción (VPS), siempre descargar scripts frescos de GitHub
if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/.git" ]]; then
    SCRIPT_DIR=""
fi

clear
print_banner
echo ""
print_header "Instalación VPSfacil"
echo ""

log_success "Sistema de instalación VPSfacil v2.0"
echo ""

# Verificación inicial
check_root
check_debian12
check_internet

echo ""

# ============================================================
# DETECTAR INSTALACIÓN PREVIA (RESUME)
# ============================================================
RESUME_MODE=false

# Buscar config en /tmp o en home del usuario (si ya se instaló antes)
CONFIG_FOUND=""
if [[ -f "/tmp/vpsfacil_setup.conf" ]]; then
    CONFIG_FOUND="/tmp/vpsfacil_setup.conf"
fi

if [[ -f "$PROGRESS_LOG" && -n "$CONFIG_FOUND" ]]; then
    echo ""
    log_warning "Se detectó una instalación previa en progreso."
    echo ""

    # Cargar configuración previa
    source "$CONFIG_FOUND"
    _derive_config_vars

    # Mostrar progreso actual
    set +e
    progress_show
    set -e

    if confirm "¿Deseas continuar desde donde se quedó?"; then
        RESUME_MODE=true
        log_success "Continuando instalación previa..."
        # Exportar variables
        export DOMAIN ADMIN_USER ADMIN_PASS TIMEZONE
        export PORTAINER_ADMIN PORTAINER_PASS KOPIA_PASS
    else
        if confirm "¿Deseas empezar de CERO (se borrará el progreso anterior)?"; then
            rm -f "$PROGRESS_LOG"
            rm -f "/tmp/vpsfacil_setup.conf"
            log_info "Progreso anterior eliminado."
        else
            log_info "Cancelado."
            exit 0
        fi
    fi
fi

# Si no es resume, pedir toda la configuración
if [[ "$RESUME_MODE" == "false" ]]; then
    ask_all_config
fi

# Inicializar progreso
progress_init

echo ""
print_separator
echo ""
log_info "Configuración:"
echo -e "    Dominio:  ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
echo -e "    Usuario:  ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo ""
log_info "Iniciando instalación de 11 pasos..."
echo ""
print_separator

# ============================================================
# EJECUTAR LOS 11 PASOS
# ============================================================

run_step 1  "00_precheck.sh"           "Pre-verificaciones del Sistema"
run_step 2  "01_create_user.sh"        "Crear Usuario Administrador"
run_step 3  "03_install_firewall.sh"   "Instalar Firewall UFW"
run_step 4  "04_install_docker.sh"     "Instalar Docker & Docker Compose"
run_step 5  "05_install_tailscale.sh"  "Instalar Tailscale VPN"
run_step 6  "07_setup_dns.sh"          "Configurar DNS en Cloudflare"
run_step 7  "06_setup_certificates.sh" "Configurar Certificados SSL"
run_step 8  "08_install_portainer.sh"  "Instalar Portainer"
run_step 9  "09_install_kopia.sh"      "Instalar Kopia Backup"
run_step 10 "10_install_filebrowser.sh" "Instalar File Browser"
run_step 11 "11_finalize.sh"           "Finalizar: Permisos y Seguridad SSH"

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
echo ""

# Calcular duración total
total_seconds=$(progress_get_total_duration)
total_mins=$((total_seconds / 60))
total_secs=$((total_seconds % 60))

echo ""
print_separator
echo ""
log_success "¡Instalación VPSfacil Completada!"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Tiempo total:${COLOR_RESET}      ${COLOR_CYAN}${total_mins}m ${total_secs}s${COLOR_RESET}"
echo ""
# Leer credenciales de Kopia si existen
KOPIA_WEB_USER=""
KOPIA_WEB_PASS=""
if [[ -f "${APPS_DIR}/kopia/.env" ]]; then
    KOPIA_WEB_USER=$(grep "KOPIA_WEB_USER=" "${APPS_DIR}/kopia/.env" 2>/dev/null | cut -d= -f2 || echo "")
    KOPIA_WEB_PASS=$(grep "KOPIA_WEB_PASS=" "${APPS_DIR}/kopia/.env" 2>/dev/null | cut -d= -f2 || echo "")
fi

echo -e "  ${COLOR_BOLD_WHITE}Acceso a las aplicaciones (requiere Tailscale VPN):${COLOR_RESET}"
echo ""
echo -e "    ${COLOR_BOLD_WHITE}Portainer${COLOR_RESET} (gestión Docker):"
echo -e "      URL:        ${COLOR_CYAN}${URL_PORTAINER}${COLOR_RESET}"
echo -e "      Usuario:    ${COLOR_CYAN}${PORTAINER_ADMIN}${COLOR_RESET}"
echo -e "      Contraseña: ${COLOR_CYAN}(la misma del usuario admin)${COLOR_RESET}"
echo ""
echo -e "    ${COLOR_BOLD_WHITE}Kopia Backup${COLOR_RESET} (backups automáticos):"
echo -e "      URL:            ${COLOR_CYAN}${URL_KOPIA}${COLOR_RESET}"
echo -e "      Usuario web:    ${COLOR_CYAN}${KOPIA_WEB_USER:-admin}${COLOR_RESET}"
echo -e "      Contraseña web: ${COLOR_CYAN}${KOPIA_WEB_PASS:-ver /home/${ADMIN_USER}/apps/kopia/.env}${COLOR_RESET}"
echo -e "      Cifrado backup: ${COLOR_CYAN}(la misma del usuario admin)${COLOR_RESET}"
echo ""
echo -e "    ${COLOR_BOLD_WHITE}File Browser${COLOR_RESET} (gestor de archivos):"
echo -e "      URL:        ${COLOR_CYAN}${URL_FILEBROWSER}${COLOR_RESET}"
echo -e "      Auth:       ${COLOR_GREEN}Sin login (VPN es la seguridad)${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Conexión SSH (después de paso 11):${COLOR_RESET}"
echo -e "    Usuario:      ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo -e "    Auth:         ${COLOR_CYAN}Llave SSH (root deshabilitado)${COLOR_RESET}"
echo ""
print_separator
echo ""

# Limpiar archivos temporales
rm -f "/tmp/vpsfacil_setup.conf"
rm -f "$PROGRESS_LOG"
log_success "Archivos temporales limpiados."
echo ""
log_success "VPSfacil finalizado. ¡Tu VPS está listo!"
echo ""
