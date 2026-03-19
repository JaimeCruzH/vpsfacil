#!/bin/bash
# ============================================================
# scripts/01_create_user.sh — Crear usuario administrador
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea el usuario admin con home directory
#   2. Agrega al grupo sudo
#   3. Configura sudo sin password (para automatización)
#   4. Genera par de llaves SSH (pública/privada)
#   5. Configura authorized_keys para acceso por llave
#   6. Crea estructura de directorios /apps/
#   7. Guía al usuario para importar la llave privada en Bitvise
#   8. Espera confirmación de que la conexión SSH funciona
#
# IMPORTANTE: Este script crea el usuario que reemplazará a root.
# Después de este paso, NO uses root para conectarte al VPS.
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

# --- Cargar librerías ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "Paso 2 de 10 — Crear Usuario Administrador"
# ============================================================

log_info "Este paso creará el usuario '${ADMIN_USER}' que será"
log_info "el administrador principal del servidor."
log_info ""
log_info "Después de este paso, te conectarás siempre con"
log_info "'${ADMIN_USER}' en lugar de 'root'."
echo ""

check_root

# ============================================================
# 1. VERIFICAR SI EL USUARIO YA EXISTE
# ============================================================
log_step "Verificando usuario ${ADMIN_USER}"

if id "$ADMIN_USER" &>/dev/null; then
    log_warning "El usuario '${ADMIN_USER}' ya existe en el sistema"

    if confirm "¿Deseas continuar con el usuario existente (sin recrearlo)?"; then
        log_info "Continuando con usuario existente..."
        USUARIO_NUEVO=false
    else
        log_error "Operación cancelada. El usuario ya existe y elegiste no continuar."
        log_info  "Si deseas empezar desde cero con este usuario:"
        log_info  "  userdel -r ${ADMIN_USER}  (CUIDADO: elimina todos sus datos)"
        exit 1
    fi
else
    USUARIO_NUEVO=true
fi

# ============================================================
# 2. CREAR USUARIO (si es nuevo)
# ============================================================
if [[ "$USUARIO_NUEVO" == "true" ]]; then
    log_step "Creando usuario ${ADMIN_USER}"

    # Pedir contraseña para el nuevo usuario
    echo ""
    log_info "Define una contraseña para el usuario '${ADMIN_USER}'."
    log_info "Esta contraseña la necesitarás ocasionalmente para sudo."
    log_warning "Guarda esta contraseña en un lugar seguro (ej: gestor de contraseñas)"
    echo ""

    while true; do
        PASS1=$(prompt_password "Ingresa la contraseña para '${ADMIN_USER}'")
        PASS2=$(prompt_password "Confirma la contraseña")

        if [[ "$PASS1" == "$PASS2" ]]; then
            if [[ ${#PASS1} -lt 8 ]]; then
                log_warning "La contraseña debe tener al menos 8 caracteres. Intenta de nuevo."
            else
                break
            fi
        else
            log_warning "Las contraseñas no coinciden. Intenta de nuevo."
        fi
    done

    # Crear usuario con home directory y shell bash
    useradd \
        --create-home \
        --shell /bin/bash \
        --comment "VPSfacil Admin User" \
        "$ADMIN_USER"

    # Asignar contraseña
    echo "${ADMIN_USER}:${PASS1}" | chpasswd
    unset PASS1 PASS2

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

# Configurar sudo sin password (necesario para automatización de scripts)
SUDOERS_FILE="/etc/sudoers.d/${ADMIN_USER}"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    log_success "Sudo sin password configurado para scripts automáticos ✓"
    log_info    "Nota: Esto es necesario para que los scripts de instalación"
    log_info    "funcionen sin interrupciones. Puede ser removido después."
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

# Asignar propiedad al usuario admin
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

# Crear directorio .ssh si no existe
if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"
fi

# Generar llaves si no existen
if [[ -f "$PRIVATE_KEY" ]]; then
    log_info "Las llaves SSH ya existen. No se generarán nuevas."
else
    log_process "Generando llaves RSA de 4096 bits (esto es seguro y puede tardar unos segundos)..."
    sudo -u "$ADMIN_USER" ssh-keygen \
        -t rsa \
        -b 4096 \
        -f "$PRIVATE_KEY" \
        -N "" \
        -C "${ADMIN_USER}@$(hostname)" \
        > /dev/null 2>&1

    log_success "Par de llaves SSH generado ✓"
fi

# Agregar clave pública a authorized_keys
if ! grep -qF "$(cat "$PUBLIC_KEY")" "$AUTH_KEYS" 2>/dev/null; then
    cat "$PUBLIC_KEY" >> "$AUTH_KEYS"
    log_success "Clave pública agregada a authorized_keys ✓"
else
    log_info "Clave pública ya estaba en authorized_keys"
fi

# Asignar permisos correctos
chmod 600 "$AUTH_KEYS" "$PRIVATE_KEY" "$PUBLIC_KEY"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

# Mostrar la clave privada para que el usuario la guarde
echo ""
log_warning "A continuación se mostrará la LLAVE PRIVADA SSH."
log_warning "Debes copiarla y guardarla en tu PC Windows."
log_warning "Sin esta llave, no podrás conectarte al servidor."
echo ""
wait_for_user "Presiona Enter cuando estés listo para ver la llave privada..."

echo ""
print_separator
echo -e "${COLOR_BOLD_YELLOW}╔══ LLAVE PRIVADA SSH — COPIA TODO ESTE BLOQUE ══════════════╗${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║ Desde -----BEGIN hasta -----END incluido                   ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
echo ""
cat "$PRIVATE_KEY"
echo ""
print_separator

# ============================================================
# 6. INSTRUCCIONES PARA BITVISE (Windows)
# ============================================================
echo ""
windows_instruction "CÓMO GUARDAR LA LLAVE SSH EN TU PC WINDOWS

1. Copia TODO el texto de la llave privada que ves arriba
   (desde -----BEGIN RSA PRIVATE KEY----- hasta -----END RSA PRIVATE KEY-----)

2. Abre el Bloc de Notas en Windows (busca 'notepad' en el menú Inicio)

3. Pega el texto copiado

4. Guarda el archivo con el nombre: ${ADMIN_USER}_key.pem
   En la carpeta: C:\\Users\\TuNombre\\.ssh\\
   (si la carpeta .ssh no existe, créala)

5. Abre Bitvise SSH Client

6. En el campo 'Host' ingresa la IP de tu VPS
   (puedes verla en el panel de Contabo)

7. En 'Username' ingresa: ${ADMIN_USER}

8. En 'Initial method' selecciona: publickey

9. Haz clic en 'Client key manager' → 'Import'
   Selecciona el archivo ${ADMIN_USER}_key.pem que guardaste

10. Regresa y haz clic en 'Log in'"

echo ""
log_warning "IMPORTANTE: No cierres esta sesión SSH de root hasta que"
log_warning "hayas verificado que puedes conectarte con '${ADMIN_USER}'."
echo ""
wait_for_user "Presiona Enter SOLO cuando hayas guardado la llave y configurado Bitvise..."

# ============================================================
# 7. VERIFICAR CONEXIÓN (el usuario debe abrir nueva sesión)
# ============================================================
echo ""
log_info "Ahora debes abrir una NUEVA ventana de Bitvise SSH"
log_info "y conectarte con el usuario '${ADMIN_USER}'."
echo ""
log_info "Una vez conectado con '${ADMIN_USER}', ejecuta este comando:"
echo ""
echo -e "   ${COLOR_BOLD_CYAN}echo 'Conexion exitosa con ${ADMIN_USER}'${COLOR_RESET}"
echo ""
log_info "Si ves el mensaje 'Conexion exitosa', vuelve aquí y continúa."
echo ""

wait_for_user "Presiona Enter cuando hayas verificado la conexión con '${ADMIN_USER}'..."

# ============================================================
# 8. GUARDAR CONFIGURACIÓN EN HOME DEL NUEVO USUARIO
# ============================================================
log_step "Guardando configuración de VPSfacil"

CONFIG_DEST="${ADMIN_HOME}/setup.conf"

cat > "$CONFIG_DEST" << EOF
# ============================================================
# VPSfacil - Configuración de instalación
# Generado: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

DOMAIN="${DOMAIN}"
ADMIN_USER="${ADMIN_USER}"
TIMEZONE="${TIMEZONE}"
INSTALLATION_DATE="$(date '+%Y-%m-%d')"
EOF

chmod 600 "$CONFIG_DEST"
chown "${ADMIN_USER}:${ADMIN_USER}" "$CONFIG_DEST"

log_success "Configuración guardada en: ${CONFIG_DEST} ✓"

# ============================================================
# RESUMEN FINAL
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
echo -e "    Sudo:           ${COLOR_CYAN}Sin password (para automatización)${COLOR_RESET}"
echo -e "    SSH:            ${COLOR_CYAN}Por llave RSA 4096 bits${COLOR_RESET}"
echo -e "    Llave privada:  ${COLOR_CYAN}${PRIVATE_KEY}${COLOR_RESET} (en el servidor)"
echo ""
echo ""
print_separator
echo ""
windows_instruction "CÓMO CONTINUAR LA INSTALACIÓN DESDE AHORA

Desde este punto usarás el usuario '${ADMIN_USER}' para todo.
Ya NO necesitas conectarte como root.

PASO A: Abre una nueva conexión en Bitvise con:
   Host:     IP de tu VPS
   Puerto:   ${SSH_PORT:-22}
   Usuario:  ${ADMIN_USER}
   Auth:     publickey → selecciona ${ADMIN_USER}_key.pem

PASO B: Una vez conectado como '${ADMIN_USER}', ejecuta:
   sudo bash /opt/vpsfacil/setup.sh

PASO C: En el menú selecciona la opción 3 para continuar."
echo ""
