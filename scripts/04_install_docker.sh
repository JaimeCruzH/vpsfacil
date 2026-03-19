#!/bin/bash
# ============================================================
# scripts/04_install_docker.sh — Instalar Docker & Compose
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Instala Docker CE (Community Edition) oficial
#   2. Instala Docker Compose v2 (plugin integrado)
#   3. Agrega el usuario admin al grupo docker
#   4. Verifica la instalación con contenedor de prueba
#   5. Configura Docker para iniciar con el sistema
#
# NOTA: El fix Docker/UFW ya fue aplicado en el paso anterior
#       (daemon.json con iptables: false)
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
print_header "Paso 5 de 10 — Instalar Docker & Docker Compose"
# ============================================================

check_root

log_info "Docker es la plataforma que ejecuta todas las aplicaciones"
log_info "del servidor de forma aislada y segura."
echo ""

# ============================================================
# 1. VERIFICAR SI DOCKER YA ESTÁ INSTALADO
# ============================================================
log_step "Verificando instalación existente de Docker"

if command_exists docker; then
    DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_info "Docker ya está instalado: versión ${DOCKER_VERSION}"

    if confirm "¿Deseas reinstalar/actualizar Docker?"; then
        log_process "Se procederá con la instalación..."
    else
        log_info "Omitiendo instalación de Docker"
        # Verificar que sigue funcionando
        if docker info > /dev/null 2>&1; then
            log_success "Docker está funcionando correctamente ✓"
            # Asegurar que el usuario admin está en el grupo docker
            if ! groups "$ADMIN_USER" | grep -q "docker"; then
                usermod -aG docker "$ADMIN_USER"
                log_success "Usuario '${ADMIN_USER}' agregado al grupo docker ✓"
            fi
            log_info "Próximo paso: Instalar Tailscale VPN (opción 6)"
            exit 0
        else
            log_warning "Docker está instalado pero no funciona. Reinstalando..."
        fi
    fi
fi

# ============================================================
# 2. ELIMINAR VERSIONES ANTIGUAS O CONFLICTIVAS
# ============================================================
log_step "Eliminando versiones antiguas de Docker (si existen)"

wait_for_dpkg

PAQUETES_VIEJOS=(
    docker
    docker-engine
    docker.io
    containerd
    runc
    docker-doc
    docker-compose
    podman-docker
)

for pkg in "${PAQUETES_VIEJOS[@]}"; do
    if dpkg -l "$pkg" &>/dev/null 2>&1; then
        log_process "Eliminando: ${pkg}"
        apt-get remove -y -q "$pkg" > /dev/null 2>&1 || true
    fi
done

log_success "Paquetes antiguos eliminados ✓"

# ============================================================
# 3. INSTALAR DEPENDENCIAS PARA REPOSITORIO DOCKER
# ============================================================
log_step "Preparando repositorio oficial de Docker"

log_process "Instalando dependencias..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    ca-certificates \
    curl \
    gnupg \
    lsb-release > /dev/null 2>&1

# Agregar clave GPG oficial de Docker
log_process "Agregando clave GPG de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
chmod a+r /etc/apt/keyrings/docker.gpg

# Agregar repositorio de Docker
log_process "Agregando repositorio de Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualizar lista de paquetes
apt-get update -q > /dev/null 2>&1

log_success "Repositorio oficial de Docker agregado ✓"

# ============================================================
# 4. INSTALAR DOCKER CE Y DOCKER COMPOSE V2
# ============================================================
log_step "Instalando Docker CE y Docker Compose v2"

log_process "Descargando e instalando Docker (puede tomar 2-5 minutos)..."

DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin 2>&1 | tail -3

log_success "Docker CE instalado ✓"
log_success "Docker Compose v2 (plugin) instalado ✓"

# ============================================================
# 5. VERIFICAR QUE EL FIX DOCKER/UFW ESTÁ APLICADO
# ============================================================
log_step "Verificando configuración de seguridad Docker/UFW"

DOCKER_DAEMON="/etc/docker/daemon.json"

if [[ -f "$DOCKER_DAEMON" ]] && grep -q '"iptables": false' "$DOCKER_DAEMON"; then
    log_success "Fix Docker/UFW ya aplicado (del paso anterior) ✓"
else
    log_warning "Aplicando fix Docker/UFW ahora..."
    mkdir -p /etc/docker
    if [[ -f "$DOCKER_DAEMON" ]]; then
        # Existe pero sin el fix — agregar
        python3 -c "
import json
with open('${DOCKER_DAEMON}', 'r') as f:
    config = json.load(f)
config['iptables'] = False
config['log-driver'] = 'json-file'
config['log-opts'] = {'max-size': '10m', 'max-file': '3'}
with open('${DOCKER_DAEMON}', 'w') as f:
    json.dump(config, f, indent=2)
"
    else
        cat > "$DOCKER_DAEMON" << 'EOF'
{
  "iptables": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi
    log_success "Fix Docker/UFW aplicado ✓"
fi

# ============================================================
# 6. INICIAR Y HABILITAR DOCKER
# ============================================================
log_step "Iniciando Docker"

systemctl enable docker > /dev/null 2>&1
systemctl start docker > /dev/null 2>&1

log_process "Esperando que Docker inicie..."
INTENTOS=0
while ! docker info > /dev/null 2>&1; do
    INTENTOS=$((INTENTOS + 1))
    if [[ $INTENTOS -gt 30 ]]; then
        log_error "Docker no inició después de 30 segundos"
        log_info  "Verifica el estado con: systemctl status docker"
        exit 1
    fi
    sleep 1
    printf "."
done
echo ""

log_success "Docker daemon iniciado y funcionando ✓"

# ============================================================
# 7. AGREGAR USUARIO ADMIN AL GRUPO DOCKER
# ============================================================
log_step "Configurando permisos para '${ADMIN_USER}'"

if groups "$ADMIN_USER" | grep -q "docker"; then
    log_info "Usuario '${ADMIN_USER}' ya está en el grupo docker"
else
    usermod -aG docker "$ADMIN_USER"
    log_success "Usuario '${ADMIN_USER}' agregado al grupo docker ✓"
fi

log_info "Nota: El cambio de grupo toma efecto en la próxima sesión SSH"

# ============================================================
# 8. CREAR RED DOCKER INTERNA
# ============================================================
log_step "Creando red Docker interna para VPSfacil"

if docker network ls | grep -q "$DOCKER_NETWORK"; then
    log_info "Red '${DOCKER_NETWORK}' ya existe"
else
    docker network create \
        --driver bridge \
        --subnet "172.20.0.0/16" \
        "$DOCKER_NETWORK" > /dev/null 2>&1
    log_success "Red Docker '${DOCKER_NETWORK}' creada ✓"
fi

# ============================================================
# 9. PRUEBA DE FUNCIONAMIENTO
# ============================================================
log_step "Verificando Docker con contenedor de prueba"

log_process "Ejecutando hello-world (primera vez puede tardar unos segundos)..."
if docker run --rm hello-world > /dev/null 2>&1; then
    log_success "Prueba de Docker exitosa ✓"
else
    log_error "El contenedor de prueba falló"
    log_info  "Verifica el estado: systemctl status docker"
    exit 1
fi

# Limpiar imagen de prueba
docker rmi hello-world > /dev/null 2>&1 || true

# ============================================================
# MOSTRAR VERSIONES INSTALADAS
# ============================================================
DOCKER_VER=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
COMPOSE_VER=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Docker instalado y configurado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Versiones instaladas:${COLOR_RESET}"
echo -e "    Docker CE:       ${COLOR_CYAN}${DOCKER_VER}${COLOR_RESET}"
echo -e "    Docker Compose:  ${COLOR_CYAN}v${COMPOSE_VER}${COLOR_RESET} (plugin v2)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Configuración:${COLOR_RESET}"
echo -e "    Grupo docker:    ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET} agregado"
echo -e "    Inicio auto:     ${COLOR_GREEN}HABILITADO${COLOR_RESET}"
echo -e "    Fix UFW:         ${COLOR_GREEN}APLICADO${COLOR_RESET} (iptables: false)"
echo -e "    Red interna:     ${COLOR_CYAN}${DOCKER_NETWORK}${COLOR_RESET}"
echo -e "    Logs:            ${COLOR_CYAN}JSON, máx 10MB x 3 archivos${COLOR_RESET}"
echo ""
log_warning "Importante: Cierra y vuelve a abrir tu sesión SSH para"
log_warning "que '${ADMIN_USER}' pueda usar Docker sin sudo."
echo ""
log_info "Próximo paso: Instalar Tailscale VPN (opción 6)"
echo ""
