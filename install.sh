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
REPO_DIR="vpsfacil"

echo ""
echo -e "\033[1;34m╔══════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;34m║\033[0m        Descargando VPSfacil...                               \033[1;34m║\033[0m"
echo -e "\033[1;34m╚══════════════════════════════════════════════════════════════╝\033[0m"
echo ""

# 1. Actualizar paquetes e instalar git
echo -e "\033[1;34m[→]\033[0m Actualizando lista de paquetes..."
apt-get update -q

if ! command -v git &>/dev/null; then
    echo -e "\033[1;34m[→]\033[0m Instalando git..."
    apt-get install -y -q git
fi

echo -e "\033[1;32m[✓]\033[0m Git disponible: $(git --version)"

# 2. Clonar o actualizar repositorio
if [[ -d "$REPO_DIR/.git" ]]; then
    echo -e "\033[1;34m[→]\033[0m Actualizando repositorio existente..."
    git -C "$REPO_DIR" pull --ff-only
else
    echo -e "\033[1;34m[→]\033[0m Clonando repositorio VPSfacil..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

echo -e "\033[1;32m[✓]\033[0m Repositorio listo en: $(pwd)/${REPO_DIR}"

# 3. Ejecutar setup principal
echo ""
bash "${REPO_DIR}/setup.sh"
