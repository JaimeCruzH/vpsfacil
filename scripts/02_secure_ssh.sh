#!/bin/bash
# ============================================================
# scripts/02_secure_ssh.sh — Seguridad SSH
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Deshabilita login SSH con password (solo llaves)
#   2. Deshabilita login SSH como root
#   3. Instala y configura fail2ban (protección fuerza bruta)
#   4. Mantiene puerto 22 (el cambio de puerto va en el paso 4 con UFW)
#
# ADVERTENCIA CRÍTICA:
#   Antes de ejecutar este script debes haber verificado que
#   puedes conectarte con el usuario admin usando llave SSH.
#   Si no lo has comprobado, este script te dejará sin acceso.
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/../lib"

# Si las librerías no existen donde se esperan, asumir ejecución remota y limpiar SCRIPT_DIR
if [[ ! -f "${LIB_DIR}/colors.sh" ]] 2>/dev/null; then
    SCRIPT_DIR=""
fi

# Si se ejecuta remotamente (vía curl | bash), descargar librerías desde GitHub
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
print_header "Paso 3 de 10 — Seguridad SSH"
# ============================================================

check_root

log_warning "ADVERTENCIA CRÍTICA — LEE ANTES DE CONTINUAR"
echo ""
log_info "Este paso deshabilitará el acceso SSH con contraseña."
log_info "Después de este paso, SOLO podrás entrar al servidor"
log_info "usando la llave SSH que guardaste en el paso anterior."
echo ""
log_info "Si tienes alguna duda sobre si guardaste correctamente"
log_info "tu llave SSH, cancela ahora y verifica primero."
echo ""

# Verificar que el usuario admin existe y tiene llave SSH
if ! id "$ADMIN_USER" &>/dev/null; then
    log_error "El usuario '${ADMIN_USER}' no existe."
    log_info  "Ejecuta primero el paso 2 (Crear usuario admin)"
    exit 1
fi

AUTH_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"
if [[ ! -f "$AUTH_KEYS" ]] || [[ ! -s "$AUTH_KEYS" ]]; then
    log_error "No se encontró llave SSH autorizada para '${ADMIN_USER}'"
    log_error "Archivo: ${AUTH_KEYS}"
    log_info  "Ejecuta primero el paso 2 para generar las llaves SSH"
    exit 1
fi

log_success "Llave SSH de '${ADMIN_USER}' verificada ✓"
echo ""

if ! confirm "¿Confirmas que puedes conectarte con '${ADMIN_USER}' usando llave SSH?"; then
    log_info "Operación cancelada. Verifica tu conexión SSH antes de continuar."
    exit 0
fi

# ============================================================
# BACKUP DE CONFIGURACIÓN SSH ACTUAL
# ============================================================
log_step "Haciendo backup de configuración SSH actual"

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

cp "$SSHD_CONFIG" "$BACKUP_FILE"
log_success "Backup guardado en: ${BACKUP_FILE} ✓"

# ============================================================
# FUNCIÓN HELPER: modificar o agregar opción en sshd_config
# ============================================================
set_ssh_option() {
    local key="$1"
    local value="$2"

    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        # La opción existe (comentada o no) — reemplazarla
        sed -i "s|^#\?${key}.*|${key} ${value}|" "$SSHD_CONFIG"
    else
        # La opción no existe — agregarla al final
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

# ============================================================
# 1. DESHABILITAR LOGIN COMO ROOT
# ============================================================
log_step "Deshabilitando login SSH como root"

set_ssh_option "PermitRootLogin" "no"
log_success "Login como root deshabilitado ✓"

# ============================================================
# 2. DESHABILITAR AUTENTICACIÓN POR CONTRASEÑA
# ============================================================
log_step "Deshabilitando autenticación SSH por contraseña"

set_ssh_option "PasswordAuthentication" "no"
set_ssh_option "ChallengeResponseAuthentication" "no"
set_ssh_option "KbdInteractiveAuthentication" "no"
set_ssh_option "UsePAM" "yes"

log_success "Autenticación por contraseña deshabilitada ✓"

# ============================================================
# 3. CONFIGURACIONES DE SEGURIDAD ADICIONALES
# ============================================================
log_step "Aplicando configuraciones de seguridad adicionales"

# Solo permitir autenticación por llave pública
set_ssh_option "PubkeyAuthentication" "yes"
set_ssh_option "AuthorizedKeysFile" ".ssh/authorized_keys"

# Seguridad adicional
set_ssh_option "X11Forwarding" "no"
set_ssh_option "AllowAgentForwarding" "no"
set_ssh_option "AllowTcpForwarding" "no"
set_ssh_option "MaxAuthTries" "3"
set_ssh_option "LoginGraceTime" "30"
set_ssh_option "ClientAliveInterval" "300"
set_ssh_option "ClientAliveCountMax" "2"

# Restringir acceso solo al usuario admin
set_ssh_option "AllowUsers" "${ADMIN_USER}"

log_success "Configuraciones de seguridad aplicadas ✓"

# ============================================================
# 4. PUERTO SSH
# ============================================================
log_step "Puerto SSH"

SSH_PORT="22"
log_info "Puerto SSH mantenido en: 22"
log_info "El cambio de puerto se realizará en el paso 4 (Firewall),"
log_info "donde UFW podrá abrir el nuevo puerto de forma segura."

# ============================================================
# 5. INSTALAR Y CONFIGURAR FAIL2BAN
# ============================================================
log_step "Instalando fail2ban (protección contra fuerza bruta)"

log_info "Fail2ban bloquea automáticamente IPs que intentan"
log_info "adivinar contraseñas o llaves SSH incorrectas."

wait_for_dpkg

DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban > /dev/null 2>&1

# Crear configuración personalizada (no editar fail2ban.conf directamente)
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Bloquear IP por 1 hora después de 3 intentos fallidos
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban > /dev/null 2>&1

log_success "Fail2ban instalado y configurado ✓"
log_info    "  Intentos fallidos permitidos: 3"
log_info    "  Tiempo de bloqueo: 24 horas"

# ============================================================
# 6. VERIFICAR Y RECARGAR SSH
# ============================================================
log_step "Verificando y aplicando nueva configuración SSH"

# Verificar que la configuración no tiene errores
if sshd -t 2>/dev/null; then
    log_success "Configuración SSH válida ✓"
else
    log_error "Error en la configuración SSH. Restaurando backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    log_success "Backup restaurado. SSH no fue modificado."
    exit 1
fi

# Recargar SSH (no reiniciar — mantiene sesiones activas)
systemctl reload sshd
log_success "Configuración SSH recargada ✓"

# ============================================================
# 7. GUARDAR PUERTO EN CONFIGURACIÓN
# ============================================================
# Actualizar setup.conf con el puerto SSH
if [[ -f "${ADMIN_HOME}/setup.conf" ]]; then
    if grep -q "^SSH_PORT=" "${ADMIN_HOME}/setup.conf"; then
        sed -i "s|^SSH_PORT=.*|SSH_PORT=\"${SSH_PORT}\"|" "${ADMIN_HOME}/setup.conf"
    else
        echo "SSH_PORT=\"${SSH_PORT}\"" >> "${ADMIN_HOME}/setup.conf"
    fi
fi

# ============================================================
# INSTRUCCIONES FINALES CRÍTICAS
# ============================================================
echo ""
print_separator
echo ""
log_info "Si puedes leer este mensaje, tu conexión SSH con '${ADMIN_USER}' sigue activa."
log_info "La nueva configuración de SSH se aplicó correctamente."
echo ""
log_info "A partir de ahora root NO puede conectarse por SSH."
log_info "Solo '${ADMIN_USER}' con llave SSH tiene acceso."
echo ""
wait_for_user "Presiona Enter para continuar..."

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Seguridad SSH configurada exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Resumen de cambios:${COLOR_RESET}"
echo -e "    Login root:          ${COLOR_RED}DESHABILITADO${COLOR_RESET}"
echo -e "    Login por contraseña: ${COLOR_RED}DESHABILITADO${COLOR_RESET}"
echo -e "    Login por llave SSH: ${COLOR_GREEN}HABILITADO${COLOR_RESET}"
echo -e "    Usuario permitido:   ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo -e "    Puerto SSH:          ${COLOR_CYAN}${SSH_PORT}${COLOR_RESET}"
echo -e "    Fail2ban:            ${COLOR_GREEN}ACTIVO${COLOR_RESET} (bloquea 3 intentos fallidos)"
echo -e "    Backup config:       ${COLOR_CYAN}${BACKUP_FILE}${COLOR_RESET}"
echo ""
log_info "Próximo paso: Instalar Firewall UFW (opción 4)"
echo ""
