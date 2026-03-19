#!/bin/bash
# ============================================================
# scripts/00_precheck.sh — Pre-verificaciones del sistema
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Verifica que el OS es Debian 12
#   2. Verifica conectividad a internet
#   3. Verifica espacio en disco (mínimo 10 GB)
#   4. Verifica RAM disponible (mínimo 1 GB)
#   5. Actualiza el sistema (apt update + upgrade)
#   6. Instala dependencias base necesarias para todos los scripts
#   7. Configura zona horaria
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

# --- Cargar librerías ---
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
print_header "Paso 1 de 10 — Pre-verificaciones del Sistema"
# ============================================================

log_info "Verificando que el sistema cumpla todos los requisitos"
log_info "antes de comenzar la instalación..."
echo ""

# ============================================================
# 1. VERIFICAR ROOT
# ============================================================
log_step "Verificando permisos de administrador"
check_root
log_success "Ejecutando como root ✓"

# ============================================================
# 2. VERIFICAR OS DEBIAN 12
# ============================================================
log_step "Verificando sistema operativo"

if [[ ! -f /etc/os-release ]]; then
    log_error "No se puede determinar el sistema operativo"
    log_info  "VPSfacil requiere Debian 12 (Bookworm)"
    exit 1
fi

OS_ID=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION=$(grep "^VERSION_ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')

log_info "Sistema detectado: ${OS_NAME}"

if [[ "$OS_ID" != "debian" ]]; then
    log_error "Sistema operativo no compatible: ${OS_ID}"
    log_info  "VPSfacil requiere Debian 12. Sistemas basados en Ubuntu o CentOS no son soportados."
    exit 1
fi

if [[ "$OS_VERSION" != "12" ]]; then
    log_error "Versión de Debian no compatible: ${OS_VERSION}"
    log_info  "VPSfacil requiere Debian 12 (Bookworm). Tienes Debian ${OS_VERSION}."
    exit 1
fi

log_success "Sistema operativo: ${OS_NAME} ✓"

# ============================================================
# 3. VERIFICAR CONECTIVIDAD A INTERNET
# ============================================================
log_step "Verificando conectividad a internet"

SERVIDORES_TEST=("google.com" "cloudflare.com" "github.com")
INTERNET_OK=false

for servidor in "${SERVIDORES_TEST[@]}"; do
    if curl -s --max-time 5 "https://${servidor}" > /dev/null 2>&1; then
        INTERNET_OK=true
        break
    fi
done

if [[ "$INTERNET_OK" == "false" ]]; then
    log_error "Sin conectividad a internet"
    log_info  "Verifica la configuración de red de tu VPS:"
    log_info  "  - Revisa la configuración en el panel de Contabo"
    log_info  "  - Verifica que el VPS tenga IP pública asignada"
    log_info  "  - Intenta: ping 8.8.8.8"
    exit 1
fi

log_success "Conectividad a internet confirmada ✓"

# ============================================================
# 4. VERIFICAR ESPACIO EN DISCO
# ============================================================
log_step "Verificando espacio en disco"

DISCO_DISPONIBLE_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
DISCO_TOTAL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $2}')
DISCO_MINIMO=10

log_info "Espacio disponible: ${DISCO_DISPONIBLE_GB} GB de ${DISCO_TOTAL_GB} GB"

if [[ "$DISCO_DISPONIBLE_GB" -lt "$DISCO_MINIMO" ]]; then
    log_error "Espacio en disco insuficiente: ${DISCO_DISPONIBLE_GB} GB disponibles"
    log_info  "VPSfacil requiere al menos ${DISCO_MINIMO} GB libres"
    log_info  "Libera espacio o amplía el disco antes de continuar"
    exit 1
fi

log_success "Espacio en disco: ${DISCO_DISPONIBLE_GB} GB disponibles ✓"

# ============================================================
# 5. VERIFICAR RAM
# ============================================================
log_step "Verificando memoria RAM"

RAM_TOTAL_MB=$(free -m | awk '/^Mem:/ {print $2}')
RAM_DISPONIBLE_MB=$(free -m | awk '/^Mem:/ {print $7}')
RAM_MINIMA_MB=1024  # 1 GB

log_info "RAM total: $((RAM_TOTAL_MB / 1024)) GB  |  Disponible: $((RAM_DISPONIBLE_MB / 1024)) GB"

if [[ "$RAM_TOTAL_MB" -lt "$RAM_MINIMA_MB" ]]; then
    log_error "RAM insuficiente: ${RAM_TOTAL_MB} MB"
    log_info  "VPSfacil requiere al menos 1 GB de RAM"
    exit 1
fi

log_success "Memoria RAM: $((RAM_TOTAL_MB / 1024)) GB ✓"

# ============================================================
# 6. VERIFICAR ARQUITECTURA
# ============================================================
log_step "Verificando arquitectura del sistema"

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    log_error "Arquitectura no compatible: ${ARCH}"
    log_info  "VPSfacil soporta x86_64 (AMD64) y aarch64 (ARM64)"
    exit 1
fi

log_success "Arquitectura: ${ARCH} ✓"

# ============================================================
# 7. ACTUALIZAR SISTEMA
# ============================================================
log_step "Actualizando lista de paquetes del sistema"
log_info "Esto puede tomar unos minutos dependiendo de la velocidad del servidor..."

# Esperar que terminen procesos apt automáticos del sistema
_wait_apt_lock() {
    local locks=("/var/lib/dpkg/lock-frontend" "/var/lib/dpkg/lock" "/var/cache/apt/archives/lock")
    local waited=0 shown=0
    while true; do
        local busy=false
        for lock in "${locks[@]}"; do
            if fuser "$lock" >/dev/null 2>&1; then
                busy=true
                break
            fi
        done
        if [[ "$busy" == "false" ]]; then
            break
        fi
        if [[ $shown -eq 0 ]]; then
            log_warning "Sistema ejecutando actualizaciones automáticas, esperando..."
            shown=1
        fi
        printf "."
        sleep 3
        waited=$((waited + 3))
        if [[ $waited -ge 300 ]]; then
            echo ""
            log_error "Timeout esperando apt lock"
            exit 1
        fi
    done
    if [[ $shown -eq 1 ]]; then
        echo ""
        log_success "Sistema libre ✓"
    fi
}
_wait_apt_lock

apt-get update -q 2>&1 | tail -3

log_success "Lista de paquetes actualizada ✓"

log_step "Instalando actualizaciones de seguridad"
log_info "Se aplicarán actualizaciones disponibles del sistema..."

DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    2>&1 | tail -5

log_success "Sistema actualizado ✓"

# ============================================================
# 8. INSTALAR DEPENDENCIAS BASE
# ============================================================
log_step "Instalando dependencias base"
log_info "Instalando herramientas necesarias para todos los pasos..."

PAQUETES=(
    # Herramientas de red y descarga
    "curl"
    "wget"
    "ca-certificates"
    "apt-transport-https"
    # Criptografía y certificados
    "gnupg"
    "openssl"
    # Herramientas de sistema
    "lsb-release"
    "software-properties-common"
    # Herramientas de diagnóstico
    "net-tools"
    "netcat-openbsd"
    "dnsutils"
    # Utilidades de texto y JSON
    "jq"
    "git"
    # Editor de texto básico
    "nano"
    # Control de procesos
    "htop"
    # Compresión
    "tar"
    "gzip"
    # Generación de contraseñas
    "pwgen"
    # Sudo
    "sudo"
)

PAQUETES_INSTALADOS=0
PAQUETES_YA_EXISTENTES=0

for paquete in "${PAQUETES[@]}"; do
    if dpkg -l "$paquete" &> /dev/null 2>&1; then
        PAQUETES_YA_EXISTENTES=$((PAQUETES_YA_EXISTENTES + 1))
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$paquete" > /dev/null 2>&1
        PAQUETES_INSTALADOS=$((PAQUETES_INSTALADOS + 1))
        log_info "  Instalado: ${paquete}"
    fi
done

log_success "Dependencias base: ${PAQUETES_INSTALADOS} instalados, ${PAQUETES_YA_EXISTENTES} ya existían ✓"

# ============================================================
# 9. CONFIGURAR ZONA HORARIA
# ============================================================
log_step "Configurando zona horaria"

ZONA_ACTUAL=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
log_info "Zona horaria actual: ${ZONA_ACTUAL}"
log_info "Zona horaria configurada para VPSfacil: ${TIMEZONE}"

if [[ "$ZONA_ACTUAL" != "$TIMEZONE" ]]; then
    if timedatectl set-timezone "$TIMEZONE" 2>/dev/null; then
        log_success "Zona horaria configurada: ${TIMEZONE} ✓"
    else
        log_warning "No se pudo configurar la zona horaria automáticamente"
        log_info    "Puedes configurarla manualmente con: timedatectl set-timezone ${TIMEZONE}"
    fi
else
    log_success "Zona horaria ya configurada: ${TIMEZONE} ✓"
fi

# ============================================================
# 10. CONFIGURAR HOSTNAME (opcional)
# ============================================================
log_step "Verificando hostname del servidor"

HOSTNAME_ACTUAL=$(hostname)
log_info "Hostname actual: ${HOSTNAME_ACTUAL}"

HOSTNAME_RECOMENDADO="vps-${ADMIN_USER}"

if [[ "$HOSTNAME_ACTUAL" != "$HOSTNAME_RECOMENDADO" ]]; then
    echo ""
    log_info "Se recomienda cambiar el hostname a: ${HOSTNAME_RECOMENDADO}"
    if confirm "¿Cambiar el hostname del servidor?"; then
        hostnamectl set-hostname "$HOSTNAME_RECOMENDADO"
        # Actualizar /etc/hosts
        if ! grep -q "$HOSTNAME_RECOMENDADO" /etc/hosts; then
            echo "127.0.0.1    ${HOSTNAME_RECOMENDADO}" >> /etc/hosts
        fi
        log_success "Hostname cambiado a: ${HOSTNAME_RECOMENDADO} ✓"
    else
        log_info "Hostname no cambiado (continuando con: ${HOSTNAME_ACTUAL})"
    fi
fi

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Pre-verificaciones completadas exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Resumen del sistema:${COLOR_RESET}"
echo -e "    OS:          ${COLOR_CYAN}${OS_NAME}${COLOR_RESET}"
echo -e "    Arquitectura: ${COLOR_CYAN}${ARCH}${COLOR_RESET}"
echo -e "    RAM:          ${COLOR_CYAN}$((RAM_TOTAL_MB / 1024)) GB${COLOR_RESET}"
echo -e "    Disco libre:  ${COLOR_CYAN}${DISCO_DISPONIBLE_GB} GB${COLOR_RESET}"
echo -e "    IP pública:   ${COLOR_CYAN}$(get_public_ip)${COLOR_RESET}"
echo -e "    Zona horaria: ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
echo ""
log_info "Próximo paso: Crear usuario admin '${ADMIN_USER}' (opción 2 del menú)"
echo ""
