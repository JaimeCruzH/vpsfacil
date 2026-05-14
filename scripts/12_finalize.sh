#!/bin/bash
# ============================================================
# scripts/12_finalize.sh — Finalizar: Permisos y Seguridad SSH
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Barrido completo de permisos (chown al usuario admin)
#   2. Verifica membresía en grupo docker
#   3. Guía al usuario para configurar Bitvise SSH en Windows
#   4. Espera confirmación de conexión SSH con usuario admin
#   5. Aplica hardening SSH (deshabilita root y passwords)
#   6. Instala fail2ban (protección contra fuerza bruta)
#
# IMPORTANTE: Este es el ÚLTIMO paso de la instalación.
# Después de este paso, root NO podrá conectarse por SSH.
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
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh" -o "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true
fi

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config
source "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true

# ============================================================
print_header "Paso 12 de 12 — Finalizar: Permisos y Seguridad SSH"
# ============================================================

check_root

# ============================================================
# 1. BARRIDO COMPLETO DE PERMISOS
# ============================================================
log_step "Asignando permisos al usuario ${ADMIN_USER}"

# Propiedad recursiva de todo el home
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}"

# Permisos de directorios
chmod 750 "${ADMIN_HOME}"
chmod 755 "${APPS_DIR}"

# SSH
chmod 700 "${ADMIN_HOME}/.ssh"
chmod 600 "${ADMIN_HOME}/.ssh/authorized_keys" 2>/dev/null || true
chmod 600 "${ADMIN_HOME}/.ssh/id_rsa_${ADMIN_USER}" 2>/dev/null || true
chmod 600 "${ADMIN_HOME}/.ssh/id_rsa_${ADMIN_USER}.pub" 2>/dev/null || true

# Archivos sensibles
chmod 600 "${ADMIN_HOME}/setup.conf" 2>/dev/null || true

# Certificados
if [[ -f "${CERT_KEY}" ]]; then
    chmod 600 "${CERT_KEY}"
fi

# Archivos .env en cada app (contienen secretos)
for env_file in "${APPS_DIR}"/*/.env; do
    if [[ -f "$env_file" ]]; then
        chmod 600 "$env_file"
    fi
done

log_success "Permisos asignados correctamente ✓"

# ============================================================
# 2. VERIFICAR MEMBRESÍA EN GRUPO DOCKER
# ============================================================
log_step "Verificando grupo docker"

if groups "$ADMIN_USER" | grep -q "docker"; then
    log_success "'${ADMIN_USER}' ya pertenece al grupo docker ✓"
else
    usermod -aG docker "$ADMIN_USER"
    log_success "'${ADMIN_USER}' agregado al grupo docker ✓"
fi

# ============================================================
# 3. MIGRAR STACKS A PORTAINER (Limited → Editable)
# ============================================================
log_step "Registrando stacks en Portainer como editables"

if portainer_load_creds 2>/dev/null; then
    JWT=$(portainer_login "$PORTAINER_USER" "$PORTAINER_PASS" 2>/dev/null) || JWT=""
    if [[ -n "$JWT" ]]; then
        # Asegurar que el entorno Docker local existe
        portainer_ensure_endpoint "$JWT"
        ENDPOINT_ID=$(portainer_endpoint_id "$JWT" 2>/dev/null) || ENDPOINT_ID=""

        if [[ -z "$ENDPOINT_ID" ]]; then
            log_warning "No hay entorno Docker local en Portainer. Stacks no migrados."
        else
            for stack_name in kopia filebrowser beszel; do
                APP_COMPOSE="${APPS_DIR}/${stack_name}/docker-compose.yml"
                if [[ ! -f "$APP_COMPOSE" ]]; then
                    continue
                fi

                # Verificar si ya existe como stack gestionado en Portainer
                EXISTING_STACKS=$(curl -sk -X GET "${PORTAINER_URL}/api/stacks" \
                    -H "Authorization: Bearer ${JWT}" 2>/dev/null)
                STACK_ID=$(echo "$EXISTING_STACKS" | \
                    jq -r --arg name "$stack_name" \
                    '.[] | select(.Name==$name) | .Id' 2>/dev/null || echo "")

                if [[ -n "$STACK_ID" ]]; then
                    log_info "${stack_name}: ya registrado en Portainer (ID: ${STACK_ID})"
                    continue
                fi

                # No existe como stack gestionado — detener contenedor y crear via API
                log_process "Migrando ${stack_name} a stack editable..."

                # Detener el contenedor creado por docker compose
                cd "${APPS_DIR}/${stack_name}" 2>/dev/null || continue
                docker compose down 2>/dev/null || true

                # Crear via API de Portainer (esto lo hace editable)
                COMPOSE_CONTENT=$(cat "$APP_COMPOSE")
                if portainer_stack_deploy "$JWT" "$ENDPOINT_ID" "$stack_name" "$COMPOSE_CONTENT"; then
                    log_success "${stack_name}: migrado a stack editable ✓"
                else
                    # Fallback: volver a levantar con docker compose
                    log_warning "${stack_name}: no se pudo migrar, restaurando..."
                    docker compose up -d 2>/dev/null || true
                fi
            done
        fi
    else
        log_warning "No se pudo conectar con Portainer API. Stacks no migrados."
    fi
else
    log_warning "Credenciales de Portainer no encontradas. Stacks no migrados."
fi

echo ""

# ============================================================
# 4. VERIFICAR LLAVE SSH
# ============================================================
log_step "Verificando llave SSH"

AUTH_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"
if [[ ! -f "$AUTH_KEYS" ]] || [[ ! -s "$AUTH_KEYS" ]]; then
    log_error "No se encontró llave SSH autorizada para '${ADMIN_USER}'"
    log_error "Archivo: ${AUTH_KEYS}"
    log_info  "Algo salió mal en el paso 2. Re-ejecuta la instalación."
    exit 1
fi

log_success "Llave SSH de '${ADMIN_USER}' verificada ✓"

# ============================================================
# 5. INSTRUCCIONES DE BITVISE PARA WINDOWS
# ============================================================
echo ""
print_separator
echo ""
log_warning "PASO CRÍTICO — CONFIGURA TU ACCESO SSH ANTES DE CONTINUAR"
echo ""
log_info "Antes de endurecer la seguridad del servidor, debes verificar"
log_info "que puedes conectarte con el usuario '${ADMIN_USER}' vía SSH."
echo ""

PRIVATE_KEY="${ADMIN_HOME}/.ssh/id_rsa_${ADMIN_USER}"

# Mostrar la clave privada
echo ""
echo -e "${COLOR_BOLD_YELLOW}╔══ LLAVE PRIVADA SSH — COPIA TODO ESTE BLOQUE ══════════════╗${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║ Desde -----BEGIN hasta -----END incluido                   ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
echo ""
cat "$PRIVATE_KEY"
echo ""
print_separator

echo ""
windows_instruction "CÓMO CONFIGURAR BITVISE SSH EN TU PC WINDOWS

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
log_warning "IMPORTANTE: Abre una NUEVA ventana de Bitvise SSH y verifica"
log_warning "que puedes conectarte como '${ADMIN_USER}' ANTES de continuar."
log_warning "Si continúas sin verificar, podrías perder acceso al servidor."
echo ""

if ! confirm "¿Pudiste conectarte exitosamente como '${ADMIN_USER}' vía SSH?"; then
    log_info "Operación cancelada. Configura tu acceso SSH y vuelve a ejecutar."
    log_info "Re-ejecuta: sudo bash setup.sh"
    exit 0
fi

# ============================================================
# 6. HARDENING SSH
# ============================================================
echo ""
log_step "Aplicando seguridad SSH"

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Backup
cp "$SSHD_CONFIG" "$BACKUP_FILE"
log_success "Backup SSH guardado en: ${BACKUP_FILE} ✓"

# Función helper para modificar sshd_config
set_ssh_option() {
    local key="$1"
    local value="$2"
    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s|^#\?${key}.*|${key} ${value}|" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Deshabilitar root login
log_step "Deshabilitando login SSH como root"
set_ssh_option "PermitRootLogin" "no"
log_success "Login como root deshabilitado ✓"

# Deshabilitar autenticación por contraseña
log_step "Deshabilitando autenticación SSH por contraseña"
set_ssh_option "PasswordAuthentication" "no"
set_ssh_option "ChallengeResponseAuthentication" "no"
set_ssh_option "KbdInteractiveAuthentication" "no"
set_ssh_option "UsePAM" "yes"
log_success "Autenticación por contraseña deshabilitada ✓"

# Configuraciones de seguridad adicionales
log_step "Aplicando configuraciones de seguridad adicionales"
set_ssh_option "PubkeyAuthentication" "yes"
set_ssh_option "AuthorizedKeysFile" ".ssh/authorized_keys"
set_ssh_option "X11Forwarding" "no"
set_ssh_option "AllowAgentForwarding" "no"
set_ssh_option "AllowTcpForwarding" "no"
set_ssh_option "MaxAuthTries" "3"
set_ssh_option "LoginGraceTime" "30"
set_ssh_option "ClientAliveInterval" "300"
set_ssh_option "ClientAliveCountMax" "2"
set_ssh_option "AllowUsers" "${ADMIN_USER}"
log_success "Configuraciones de seguridad aplicadas ✓"

# ============================================================
# 7. INSTALAR FAIL2BAN
# ============================================================
log_step "Instalando fail2ban (protección contra fuerza bruta)"

wait_for_dpkg

DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban > /dev/null 2>&1

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = 22
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban > /dev/null 2>&1

log_success "Fail2ban instalado y configurado ✓"

# ============================================================
# 8. VERIFICAR Y RECARGAR SSH
# ============================================================
log_step "Verificando y aplicando nueva configuración SSH"

if sshd -t 2>/dev/null; then
    log_success "Configuración SSH válida ✓"
else
    log_error "Error en la configuración SSH. Restaurando backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    log_success "Backup restaurado. SSH no fue modificado."
    exit 1
fi

systemctl reload sshd
log_success "Configuración SSH recargada ✓"

# Guardar puerto SSH en configuración
if [[ -f "${ADMIN_HOME}/setup.conf" ]]; then
    if grep -q "^SSH_PORT=" "${ADMIN_HOME}/setup.conf"; then
        sed -i "s|^SSH_PORT=.*|SSH_PORT=\"22\"|" "${ADMIN_HOME}/setup.conf"
    else
        echo "SSH_PORT=\"22\"" >> "${ADMIN_HOME}/setup.conf"
    fi
fi

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Seguridad SSH configurada exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Resumen de seguridad:${COLOR_RESET}"
echo -e "    Login root:           ${COLOR_RED}DESHABILITADO${COLOR_RESET}"
echo -e "    Login por contraseña: ${COLOR_RED}DESHABILITADO${COLOR_RESET}"
echo -e "    Login por llave SSH:  ${COLOR_GREEN}HABILITADO${COLOR_RESET}"
echo -e "    Usuario permitido:    ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo -e "    Puerto SSH:           ${COLOR_CYAN}22${COLOR_RESET}"
echo -e "    Fail2ban:             ${COLOR_GREEN}ACTIVO${COLOR_RESET} (bloquea 3 intentos fallidos)"
echo -e "    Backup config:        ${COLOR_CYAN}${BACKUP_FILE}${COLOR_RESET}"
echo ""
