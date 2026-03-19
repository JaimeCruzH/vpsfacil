#!/bin/bash
# ============================================================
# scripts/03_install_firewall.sh — Instalar y configurar UFW
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Instala UFW (Uncomplicated Firewall)
#   2. Aplica el FIX CRÍTICO para Docker+UFW
#      (evita que Docker bypase las reglas del firewall)
#   3. Configura reglas: solo SSH y Tailscale VPN abiertos
#   4. Habilita UFW
#
# FIX CRÍTICO DOCKER/UFW:
#   Por defecto Docker manipula iptables directamente,
#   bypassando UFW. Configuramos Docker con iptables=false
#   ANTES de instalarlo para que UFW controle todo el tráfico.
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
print_header "Paso 4 de 10 — Instalar Firewall UFW"
# ============================================================

check_root

log_info "El firewall controla qué conexiones de red están permitidas."
log_info "Configuraremos reglas estrictas: solo SSH y VPN Tailscale."
log_info "Todas las apps serán accesibles ÚNICAMENTE por VPN."
echo ""

# Leer puerto SSH guardado (puede haber cambiado en paso anterior)
SSH_PORT_ACTUAL="22"
if [[ -f "${ADMIN_HOME}/setup.conf" ]]; then
    source "${ADMIN_HOME}/setup.conf"
    SSH_PORT_ACTUAL="${SSH_PORT:-22}"
fi

log_info "Puerto SSH detectado: ${SSH_PORT_ACTUAL}"
echo ""

# ============================================================
# 1. INSTALAR UFW
# ============================================================
log_step "Instalando UFW"

if command_exists ufw; then
    log_info "UFW ya está instalado"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw > /dev/null 2>&1
    log_success "UFW instalado ✓"
fi

# ============================================================
# 2. FIX CRÍTICO: EVITAR QUE DOCKER BYPASE UFW
# ============================================================
log_step "Aplicando fix crítico Docker + UFW"

log_info "Sin este fix, Docker abre puertos directamente en el"
log_info "firewall del kernel, ignorando las reglas de UFW."
log_info "Este es el problema de seguridad más común en VPS con Docker."
echo ""

DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

# Crear directorio si no existe
mkdir -p /etc/docker

# Verificar si ya existe configuración de Docker
if [[ -f "$DOCKER_DAEMON_CONFIG" ]]; then
    # Verificar si ya tiene iptables: false
    if grep -q '"iptables": false' "$DOCKER_DAEMON_CONFIG"; then
        log_info "Fix Docker/UFW ya aplicado anteriormente"
    else
        # Agregar al JSON existente
        log_process "Actualizando configuración de Docker..."
        # Backup del archivo actual
        cp "$DOCKER_DAEMON_CONFIG" "${DOCKER_DAEMON_CONFIG}.backup"
        # Usar Python para editar JSON correctamente
        python3 -c "
import json
with open('${DOCKER_DAEMON_CONFIG}', 'r') as f:
    config = json.load(f)
config['iptables'] = False
with open('${DOCKER_DAEMON_CONFIG}', 'w') as f:
    json.dump(config, f, indent=2)
"
        log_success "Fix aplicado al daemon.json existente ✓"
    fi
else
    # Crear nuevo daemon.json con configuración segura
    cat > "$DOCKER_DAEMON_CONFIG" << 'EOF'
{
  "iptables": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    log_success "Archivo daemon.json creado con fix Docker/UFW ✓"
fi

log_success "Fix Docker/UFW aplicado ✓"
log_info    "Docker NO podrá abrir puertos sin pasar por UFW"

# ============================================================
# 3. CONFIGURAR REGLAS DE UFW
# ============================================================
log_step "Configurando reglas del firewall"

# Política por defecto: bloquear todo entrante, permitir saliente
ufw --force reset > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1

log_info "Política por defecto: BLOQUEAR todo tráfico entrante"
log_success "Política por defecto configurada ✓"

# --- Puerto SSH ---
log_process "Abriendo puerto SSH (${SSH_PORT_ACTUAL})..."
ufw allow "${SSH_PORT_ACTUAL}/tcp" comment "SSH - Admin access" > /dev/null 2>&1
log_success "Puerto SSH ${SSH_PORT_ACTUAL} abierto ✓"

# --- Puerto Tailscale VPN ---
log_process "Abriendo puerto Tailscale VPN (${PORT_TAILSCALE}/UDP)..."
ufw allow "${PORT_TAILSCALE}/udp" comment "Tailscale VPN WireGuard" > /dev/null 2>&1
log_success "Puerto Tailscale ${PORT_TAILSCALE}/UDP abierto ✓"

# --- Interfaz Tailscale: permitir todo el tráfico VPN ---
# Las apps (Portainer, N8N, etc.) son accesibles SOLO via Tailscale.
# En lugar de abrir puertos individuales al internet, permitimos
# todo el tráfico que llega por la interfaz virtual tailscale0.
# Si Tailscale aún no está instalado, la regla se aplicará luego.
if ip link show tailscale0 &>/dev/null 2>&1; then
    ufw allow in on tailscale0 comment "Permitir todo tráfico VPN Tailscale" > /dev/null 2>&1
    log_success "Tráfico Tailscale VPN permitido ✓"
else
    log_info "Tailscale aún no instalado — la regla se aplica en el paso 6"
fi

# ============================================================
# 4. HABILITAR UFW
# ============================================================
log_step "Habilitando UFW"

log_warning "Al habilitar UFW, todas las conexiones actuales siguen activas."
log_warning "Tu conexión SSH actual NO se cerrará."
echo ""

# Habilitar sin preguntar (--force evita el prompt interactivo de UFW)
echo "y" | ufw enable > /dev/null 2>&1

log_success "UFW habilitado y activo ✓"

# ============================================================
# 5. VERIFICAR ESTADO
# ============================================================
log_step "Verificando estado del firewall"

echo ""
ufw status verbose
echo ""

# ============================================================
# 6. CONFIGURAR UFW PARA INICIAR CON EL SISTEMA
# ============================================================
log_step "Configurando inicio automático"

systemctl enable ufw > /dev/null 2>&1
log_success "UFW se iniciará automáticamente con el servidor ✓"

# ============================================================
# 7. VERIFICAR CONEXIÓN SSH SIGUE FUNCIONANDO
# ============================================================
echo ""
log_info "Tu conexión SSH actual sigue activa."
log_info "Verifica que puedes abrir una nueva sesión antes de continuar."
echo ""

windows_instruction "VERIFICAR QUE EL FIREWALL NO BLOQUEÓ TU ACCESO

1. Abre una NUEVA ventana de Bitvise SSH Client
   (NO cierres la ventana actual)

2. Conéctate con:
   - Host: IP de tu VPS
   - Puerto: ${SSH_PORT_ACTUAL}
   - Usuario: ${ADMIN_USER}

3. Si la conexión funciona → todo correcto, continúa
4. Si falla → dinos el error sin cerrar la ventana actual"

wait_for_user "Presiona Enter cuando hayas verificado que SSH sigue funcionando..."

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Firewall UFW configurado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Reglas activas:${COLOR_RESET}"
echo -e "    Puerto ${SSH_PORT_ACTUAL}/TCP:    ${COLOR_GREEN}ABIERTO${COLOR_RESET} — SSH (admin)"
echo -e "    Puerto ${PORT_TAILSCALE}/UDP: ${COLOR_GREEN}ABIERTO${COLOR_RESET} — Tailscale VPN"
echo -e "    Todo lo demás:   ${COLOR_RED}BLOQUEADO${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Seguridad Docker:${COLOR_RESET}"
echo -e "    Docker/UFW fix:  ${COLOR_GREEN}APLICADO${COLOR_RESET} — Docker no bypasa el firewall"
echo ""
log_info "Próximo paso: Instalar Docker & Docker Compose (opción 5)"
echo ""
