#!/bin/bash
# ============================================================
# scripts/01_create_user.sh — Crear usuario administrador
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea el usuario admin con home directory
#   2. Agrega al grupo sudo con NOPASSWD
#   3. Genera par de llaves SSH (pública/privada)
#   4. Configura authorized_keys para acceso por llave
#   5. Crea estructura de directorios /apps/
#   6. Guarda configuración en setup.conf
#
# NOTA: La verificación de conexión SSH y el hardening SSH
# se realizan en el paso 11 (11_finalize.sh), al final de
# toda la instalación.
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

# --- Cargar librerías ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ ! -f "${LIB_DIR}/colors.sh" ]] 2>/dev/null; then
    SCRIPT_DIR=""
fi

if [[ -z "$SCRIPT_DIR" ]] || [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    LIB_DIR="/tmp/vpsfacil_lib_$$"
    mkdir -p "$LIB_DIR"
    curl -sSL "${REPO_RAW}/lib/colors.sh"  -o "${LIB_DIR}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"  -o "${LIB_DIR}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"   -o "${LIB_DIR}/utils.sh"
fi

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "Paso 2 de 12 — Crear Usuario Administrador"
# ============================================================

log_info "Este paso creará el usuario '${ADMIN_USER}' que será"
log_info "el administrador principal del servidor."
echo ""

check_root

# ============================================================
# 1. VERIFICAR SI EL USUARIO YA EXISTE
# ============================================================
log_step "Verificando usuario ${ADMIN_USER}"

if id "$ADMIN_USER" &>/dev/null; then
    log_info "El usuario '${ADMIN_USER}' ya existe en el sistema"
    log_success "Usando usuario existente ✓"
    USUARIO_NUEVO=false
else
    USUARIO_NUEVO=true
fi

# ============================================================
# 2. CREAR USUARIO (si es nuevo)
# ============================================================
if [[ "$USUARIO_NUEVO" == "true" ]]; then
    log_step "Creando usuario ${ADMIN_USER}"

    # Obtener contraseña desde setup.sh (vía ADMIN_PASS) o pedir si no existe
    if [[ -z "${ADMIN_PASS:-}" ]]; then
        echo ""
        log_info "Define una contraseña para el usuario '${ADMIN_USER}'."
        log_info "Esta contraseña la necesitarás ocasionalmente para sudo."
        log_info "Requisitos: mínimo 12 caracteres, solo letras (a-z, A-Z) y números (0-9)."
        log_warning "Guarda esta contraseña en un lugar seguro (ej: gestor de contraseñas)"
        echo ""

        while true; do
            PASS1=$(prompt_password "Ingresa la contraseña para '${ADMIN_USER}'")
            PASS2=$(prompt_password "Confirma la contraseña")

            if [[ "$PASS1" != "$PASS2" ]]; then
                log_warning "Las contraseñas no coinciden. Intenta de nuevo."
            elif [[ ${#PASS1} -lt 12 ]]; then
                log_warning "Mínimo 12 caracteres."
            elif [[ ! "$PASS1" =~ ^[a-zA-Z0-9]+$ ]]; then
                log_warning "Solo se permiten letras (a-z, A-Z) y números (0-9). Sin espacios ni símbolos."
            else
                break
            fi
        done
        ADMIN_PASS="$PASS1"
        unset PASS1 PASS2
    else
        log_info "Usando contraseña configurada en el paso anterior"
    fi

    # Crear usuario
    useradd \
        --create-home \
        --shell /bin/bash \
        --comment "VPSfacil Admin User" \
        "$ADMIN_USER"

    echo "${ADMIN_USER}:${ADMIN_PASS}" | chpasswd

    log_success "Usuario '${ADMIN_USER}' creado con home en /home/${ADMIN_USER} ✓"
fi

# ============================================================
# 3. AGREGAR A GRUPO SUDO
# ============================================================
log_step "Configurando permisos de administrador"

if groups "$ADMIN_USER" | grep -q "sudo"; then
    log_info "El usuario ya tiene permisos sudo"
else
    usermod -aG sudo "$ADMIN_USER"
    log_success "Usuario agregado al grupo sudo ✓"
fi

SUDOERS_FILE="/etc/sudoers.d/${ADMIN_USER}"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    log_success "Sudo sin password configurado ✓"
else
    log_info "Configuración de sudo ya existe"
fi

# ============================================================
# 4. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

DIRS=(
    "${APPS_DIR}"
    "${APPS_DIR}/certs"
    "${APPS_DIR}/backups"
)

for dir in "${DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "  Creado: ${dir}"
    else
        log_info "  Ya existe: ${dir}"
    fi
done

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}"
chmod 750 "${ADMIN_HOME}"
chmod 755 "${APPS_DIR}"

log_success "Estructura de directorios creada en ${APPS_DIR} ✓"

# ============================================================
# 5. GENERAR LLAVES SSH
# ============================================================
log_step "Generando par de llaves SSH"

SSH_DIR="${ADMIN_HOME}/.ssh"
PRIVATE_KEY="${SSH_DIR}/id_rsa_${ADMIN_USER}"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"
fi

if [[ -f "$PRIVATE_KEY" ]]; then
    log_info "Las llaves SSH ya existen. No se generarán nuevas."
else
    log_process "Generando llaves RSA de 4096 bits..."
    sudo -u "$ADMIN_USER" ssh-keygen \
        -t rsa \
        -b 4096 \
        -f "$PRIVATE_KEY" \
        -N "" \
        -C "${ADMIN_USER}@$(hostname)" \
        > /dev/null 2>&1

    log_success "Par de llaves SSH generado ✓"
fi

if ! grep -qF "$(cat "$PUBLIC_KEY")" "$AUTH_KEYS" 2>/dev/null; then
    cat "$PUBLIC_KEY" >> "$AUTH_KEYS"
    log_success "Clave pública agregada a authorized_keys ✓"
else
    log_info "Clave pública ya estaba en authorized_keys"
fi

chmod 600 "$AUTH_KEYS" "$PRIVATE_KEY" "$PUBLIC_KEY"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

# ============================================================
# 6. GUARDAR CONFIGURACIÓN
# ============================================================
log_step "Guardando configuración de VPSfacil"

CONFIG_DEST="${ADMIN_HOME}/setup.conf"

# Escribir con printf %q para escapar caracteres especiales en contraseñas
{
    echo "# VPSfacil - Configuración de instalación"
    echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    printf 'DOMAIN=%q\n' "$DOMAIN"
    printf 'ADMIN_USER=%q\n' "$ADMIN_USER"
    printf 'TIMEZONE=%q\n' "$TIMEZONE"
    printf 'INSTALLATION_DATE=%q\n' "$(date '+%Y-%m-%d')"
    printf 'ADMIN_PASS=%q\n' "${ADMIN_PASS:-}"
} > "$CONFIG_DEST"

# Agregar credenciales si existen
if [[ -n "${PORTAINER_ADMIN:-}" ]]; then
    {
        printf 'PORTAINER_ADMIN=%q\n' "$PORTAINER_ADMIN"
        printf 'PORTAINER_PASS=%q\n' "$PORTAINER_PASS"
        printf 'KOPIA_PASS=%q\n' "$KOPIA_PASS"
    } >> "$CONFIG_DEST"
fi

chmod 600 "$CONFIG_DEST"
chown "${ADMIN_USER}:${ADMIN_USER}" "$CONFIG_DEST"

# También guardar en /tmp para que setup.sh lo encuentre
cp "$CONFIG_DEST" "/tmp/vpsfacil_setup.conf"
chmod 600 "/tmp/vpsfacil_setup.conf"

log_success "Configuración guardada en: ${CONFIG_DEST} ✓"

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "Usuario '${ADMIN_USER}' configurado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Resumen:${COLOR_RESET}"
echo -e "    Usuario:        ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo -e "    Home:           ${COLOR_CYAN}${ADMIN_HOME}${COLOR_RESET}"
echo -e "    Apps en:        ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
echo -e "    Sudo:           ${COLOR_CYAN}Sin password${COLOR_RESET}"
echo -e "    SSH:            ${COLOR_CYAN}RSA 4096 bits${COLOR_RESET}"
echo ""
log_info "La configuración de SSH se completará en el paso 11."
echo ""
