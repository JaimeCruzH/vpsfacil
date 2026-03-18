#!/bin/bash
# ============================================================
# lib/utils.sh — Funciones de utilidad comunes
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# IMPORTANTE: Este archivo depende de lib/config.sh y
# lib/colors.sh. Siempre se cargan juntos desde setup.sh
# ============================================================

# ============================================================
# FUNCIONES DE LOGGING
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

# ============================================================
# VERIFICACIONES DE USUARIO Y SISTEMA
# ============================================================

# Verificar que se ejecuta como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        log_info  "Usa: sudo bash $0"
        exit 1
    fi
}

# Verificar que NO se ejecuta como root (para pasos como admin)
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Este script NO debe ejecutarse como root"
        log_info  "Usa: su - ${ADMIN_USER} y luego ejecuta el script"
        exit 1
    fi
}

# Verificar conectividad a internet
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

# Verificar que un comando existe en el sistema
command_exists() {
    command -v "$1" &> /dev/null
}

# Verificar OS es Debian 12
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

# ============================================================
# CONFIRMACIONES Y INPUT DEL USUARIO
# ============================================================

# Confirmación S/N
# Uso: confirm "¿Deseas continuar?" && echo "Sí" || echo "No"
confirm() {
    local prompt="$1"
    local respuesta

    while true; do
        echo -ne "${PREFIX_PROMPT} ${prompt} ${COLOR_BOLD_WHITE}(sí/no)${COLOR_RESET}: "
        read -r respuesta
        case "${respuesta,,}" in
            si|sí|s|yes|y) return 0 ;;
            no|n)           return 1 ;;
            *) log_warning "Por favor responde 'sí' o 'no'" ;;
        esac
    done
}

# Pedir dato al usuario con valor por defecto opcional
# Uso: valor=$(prompt_input "¿Cuál es tu dominio?" "example.com")
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local respuesta

    if [[ -n "$default" ]]; then
        echo -ne "${PREFIX_PROMPT} ${prompt} ${COLOR_CYAN}[${default}]${COLOR_RESET}: "
    else
        echo -ne "${PREFIX_PROMPT} ${prompt}: "
    fi

    read -r respuesta

    if [[ -z "$respuesta" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$respuesta"
    fi
}

# Pedir contraseña sin mostrarla en pantalla
# Uso: pass=$(prompt_password "Ingresa la contraseña")
prompt_password() {
    local prompt="$1"
    local pass

    echo -ne "${PREFIX_PROMPT} ${prompt}: "
    read -rs pass
    echo ""
    echo "$pass"
}

# Pausar y esperar que el usuario presione Enter
wait_for_user() {
    local mensaje="${1:-Presiona Enter para continuar...}"
    echo ""
    echo -ne "${PREFIX_PROMPT} ${mensaje}"
    read -r
    echo ""
}

# ============================================================
# GESTIÓN DE DIRECTORIOS DE APLICACIONES
# ============================================================
# NOTA: Requiere que ADMIN_USER y APPS_DIR estén definidos
# en lib/config.sh (cargado antes de este archivo)

# Obtener ruta de una app específica
get_app_dir() {
    local appname="$1"
    echo "${APPS_DIR}/${appname}"
}

# Crear estructura de directorios para una app
# Uso: ensure_app_dir "n8n"
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

# Agregar variable a archivo .env de una app
# Uso: add_env_var "n8n" "DB_HOST" "localhost"
add_env_var() {
    local appname="$1"
    local key="$2"
    local value="$3"
    local env_file
    env_file="$(get_app_dir "$appname")/.env"

    # Eliminar clave existente si ya existe
    sed -i "/^${key}=/d" "$env_file" 2>/dev/null || true

    # Agregar nueva clave
    echo "${key}=${value}" >> "$env_file"
}

# ============================================================
# OPERACIONES DOCKER
# ============================================================

# Verificar que Docker está instalado y corriendo
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

# Desplegar aplicación con docker compose
# Uso: deploy_app "n8n"
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

# ============================================================
# HEALTH CHECKS
# ============================================================

# Esperar que un puerto esté disponible
# Uso: wait_for_port "localhost" 9000 60
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

# ============================================================
# UTILIDADES VARIAS
# ============================================================

# Generar contraseña aleatoria segura
# Uso: pass=$(generate_password 20)
generate_password() {
    local length="${1:-20}"
    openssl rand -base64 32 | tr -d '=+/' | cut -c1-"$length"
}

# Generar token aleatorio (hexadecimal)
# Uso: token=$(generate_token 32)
generate_token() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Obtener IP pública del servidor
get_public_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null || \
    curl -s --max-time 10 https://ifconfig.me 2>/dev/null || \
    echo "No disponible"
}

# Mostrar instrucción de acción en PC Windows
# Para cuando el usuario debe hacer algo en su computador local
windows_instruction() {
    echo ""
    echo -e "${COLOR_BOLD_YELLOW}┌─ ACCIÓN REQUERIDA EN TU PC WINDOWS ─────────────────────┐${COLOR_RESET}"
    while IFS= read -r line; do
        echo -e "${COLOR_BOLD_YELLOW}│${COLOR_RESET} ${line}"
    done <<< "$1"
    echo -e "${COLOR_BOLD_YELLOW}└──────────────────────────────────────────────────────────┘${COLOR_RESET}"
    echo ""
}
