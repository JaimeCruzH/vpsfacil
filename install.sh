#!/bin/bash
# ============================================================
# install.sh — Bootstrap de instalación VPSfacil
#
# Uso (como root en el VPS):
#   bash <(curl -fsSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/install.sh)
#
# Qué hace:
#   1. Actualiza la lista de paquetes
#   2. Instala git si no está instalado
#   3. Clona (o actualiza) el repositorio de VPSfacil
#   4. Ejecuta setup.sh
# ============================================================

set -euo pipefail

REPO_URL="https://github.com/JaimeCruzH/vpsfacil.git"
REPO_DIR="/opt/vpsfacil"

echo ""
echo -e "\033[1;34m╔══════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;34m║\033[0m        Descargando VPSfacil...                               \033[1;34m║\033[0m"
echo -e "\033[1;34m╚══════════════════════════════════════════════════════════════╝\033[0m"
echo ""

# 1. Esperar que terminen procesos apt automáticos (common on fresh VPS)
wait_apt() {
    local locks=("/var/lib/dpkg/lock-frontend" "/var/lib/dpkg/lock" "/var/cache/apt/archives/lock")
    local waited=0
    local shown=0

    while true; do
        local busy=false
        for lock in "${locks[@]}"; do
            if fuser "$lock" >/dev/null 2>&1; then
                busy=true
                break
            fi
        done
        [[ "$busy" == "false" ]] && break

        if [[ $shown -eq 0 ]]; then
            echo -e "\033[1;33m[⚠]\033[0m El sistema está ejecutando actualizaciones automáticas."
            echo -e "\033[1;34m[→]\033[0m Esperando que terminen (puede tardar 1-2 minutos)..."
            shown=1
        fi
        printf "."
        sleep 3
        waited=$((waited + 3))

        if [[ $waited -ge 300 ]]; then
            echo ""
            echo -e "\033[1;31m[✗]\033[0m Timeout esperando apt. Intenta ejecutar:"
            echo -e "    systemctl stop unattended-upgrades && bash install.sh"
            exit 1
        fi
    done
    [[ $shown -eq 1 ]] && echo -e "\n\033[1;32m[✓]\033[0m Sistema libre, continuando..."
}

wait_apt

# 2. Actualizar paquetes e instalar git
echo -e "\033[1;34m[→]\033[0m Actualizando lista de paquetes..."
apt-get update -q

if ! command -v git &>/dev/null; then
    echo -e "\033[1;34m[→]\033[0m Instalando git..."
    apt-get install -y -q git
fi

echo -e "\033[1;32m[✓]\033[0m Git disponible: $(git --version)"

# 2. Clonar o actualizar repositorio en /opt (accesible por todos los usuarios)
if [[ -d "$REPO_DIR/.git" ]]; then
    echo -e "\033[1;34m[→]\033[0m Actualizando repositorio existente..."
    git -C "$REPO_DIR" pull --ff-only
else
    echo -e "\033[1;34m[→]\033[0m Clonando repositorio VPSfacil en ${REPO_DIR}..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Permisos: root instala, pero cualquier usuario con sudo puede ejecutarlo
chmod 755 "$REPO_DIR"

echo -e "\033[1;32m[✓]\033[0m Repositorio listo en: ${REPO_DIR}"

# 3. Ejecutar setup principal
echo ""
bash "${REPO_DIR}/setup.sh"
