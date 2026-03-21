#!/bin/bash
# ============================================================
# scripts/07_setup_dns.sh — Configurar DNS en Cloudflare
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Pide el token de API de Cloudflare
#   2. Detecta automáticamente el Zone ID del dominio
#   3. Obtiene la IP de Tailscale del servidor
#   4. Crea registros DNS tipo A para cada app:
#      portainer.vpn.DOMAIN → Tailscale IP
#      n8n.vpn.DOMAIN       → Tailscale IP
#      files.vpn.DOMAIN     → Tailscale IP
#      openclaw.vpn.DOMAIN  → Tailscale IP
#      kopia.vpn.DOMAIN     → Tailscale IP
#   5. Verifica que los registros se crearon correctamente
#
# IMPORTANTE: Los registros DNS apuntan a la IP privada de
# Tailscale (100.x.x.x), NO a la IP pública del servidor.
# Solo funciona con Tailscale VPN activo.
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
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh" -o "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true
fi


# ============================================================
print_header "Paso 7 de 11 — Configurar DNS en Cloudflare"
# ============================================================

check_root

log_info "Este paso crea automáticamente los registros DNS en"
log_info "Cloudflare para que tus apps tengan URLs amigables."
echo ""
log_info "Cada app tendrá su propio subdominio:"
echo -e "   ${COLOR_CYAN}portainer.vpn.${DOMAIN}${COLOR_RESET} → IP Tailscale"
echo -e "   ${COLOR_CYAN}n8n.vpn.${DOMAIN}${COLOR_RESET}       → IP Tailscale"
echo -e "   ${COLOR_CYAN}files.vpn.${DOMAIN}${COLOR_RESET}     → IP Tailscale"
echo -e "   ${COLOR_CYAN}openclaw.vpn.${DOMAIN}${COLOR_RESET}  → IP Tailscale"
echo -e "   ${COLOR_CYAN}kopia.vpn.${DOMAIN}${COLOR_RESET}     → IP Tailscale"
echo ""

# ============================================================
# 1. OBTENER IP DE TAILSCALE
# ============================================================
log_step "Obteniendo IP de Tailscale"

# Intentar desde setup.conf primero
TAILSCALE_IP=""
if [[ -f "${ADMIN_HOME}/setup.conf" ]]; then
    source "${ADMIN_HOME}/setup.conf"
    TAILSCALE_IP="${TAILSCALE_IP:-}"
fi

# Si no está en el archivo, consultar Tailscale directamente
if [[ -z "$TAILSCALE_IP" ]]; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
fi

if [[ -z "$TAILSCALE_IP" ]]; then
    log_error "No se pudo obtener la IP de Tailscale"
    log_info  "Asegúrate de haber completado el paso 6 (Instalar Tailscale)"
    log_info  "Verifica con: tailscale ip -4"
    exit 1
fi

log_success "IP Tailscale del servidor: ${TAILSCALE_IP} ✓"

# ============================================================
# 2. PEDIR TOKEN DE API DE CLOUDFLARE
# ============================================================
log_step "Configurar acceso a la API de Cloudflare"

echo ""
log_info "Necesitas un token de API de Cloudflare para crear los registros DNS."
echo ""

windows_instruction "CÓMO OBTENER EL TOKEN DE API DE CLOUDFLARE

1. Ve a: https://dash.cloudflare.com/profile/api-tokens

2. Haz clic en 'Create Token'

3. Selecciona la plantilla: 'Edit zone DNS'

4. En 'Zone Resources':
   - Selecciona 'Specific zone'
   - Elige tu dominio: ${DOMAIN}

5. Haz clic en 'Continue to summary' y luego 'Create Token'

6. COPIA el token que aparece (solo se muestra una vez)
   Ejemplo: abc123def456...

NOTA: Este token solo tiene permiso para editar DNS.
No da acceso a tu cuenta completa de Cloudflare."

echo ""
wait_for_user "Presiona Enter cuando tengas el token de API listo..."
echo ""

# Leer el token
while true; do
    CF_API_TOKEN=$(prompt_password "Pega tu token de API de Cloudflare")
    if [[ -n "$CF_API_TOKEN" && ${#CF_API_TOKEN} -gt 20 ]]; then
        break
    fi
    log_warning "Token inválido. Debe tener al menos 20 caracteres."
done

# ============================================================
# 3. VERIFICAR TOKEN Y OBTENER ZONE ID
# ============================================================
log_step "Verificando token y obteniendo Zone ID"

log_process "Conectando con la API de Cloudflare..."

# Verificar token
CF_VERIFY=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

if ! echo "$CF_VERIFY" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
    log_error "Token de Cloudflare inválido o sin permisos"
    log_info  "Verifica que el token tenga permiso 'Edit zone DNS'"
    log_info  "Token ingresado: ${CF_API_TOKEN:0:10}..."
    exit 1
fi

log_success "Token de Cloudflare válido ✓"

# Obtener Zone ID del dominio
log_process "Obteniendo Zone ID para ${DOMAIN}..."

CF_ZONES=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

CF_ZONE_ID=$(echo "$CF_ZONES" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); \
     zones=d.get('result',[]); \
     print(zones[0]['id'] if zones else '')" 2>/dev/null || echo "")

if [[ -z "$CF_ZONE_ID" ]]; then
    log_error "No se encontró la zona DNS para: ${DOMAIN}"
    log_info  "Verifica que el dominio está en tu cuenta de Cloudflare"
    log_info  "y que el token tiene acceso a esa zona"
    exit 1
fi

log_success "Zone ID obtenido: ${CF_ZONE_ID:0:8}... ✓"

# ============================================================
# 4. CREAR REGISTROS DNS
# ============================================================
log_step "Creando registros DNS en Cloudflare"

# Lista de subdominios a crear (prefijo → nombre completo)
declare -A SUBDOMINIOS=(
    ["portainer"]="portainer.vpn.${DOMAIN}"
    ["n8n"]="n8n.vpn.${DOMAIN}"
    ["files"]="files.vpn.${DOMAIN}"
    ["openclaw"]="openclaw.vpn.${DOMAIN}"
    ["kopia"]="kopia.vpn.${DOMAIN}"
)

# Función para crear o actualizar un registro DNS
crear_registro_dns() {
    local nombre="$1"
    local ip="$2"

    # Verificar si ya existe el registro
    EXISTING=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${nombre}&type=A" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json")

    EXISTING_ID=$(echo "$EXISTING" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); \
         r=d.get('result',[]); print(r[0]['id'] if r else '')" 2>/dev/null || echo "")

    if [[ -n "$EXISTING_ID" ]]; then
        # Actualizar registro existente
        RESULT=$(curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${EXISTING_ID}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${nombre}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}")
        ACCION="Actualizado"
    else
        # Crear nuevo registro
        RESULT=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${nombre}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}")
        ACCION="Creado"
    fi

    SUCCESS=$(echo "$RESULT" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print('true' if d.get('success') else 'false')" \
        2>/dev/null || echo "false")

    if [[ "$SUCCESS" == "true" ]]; then
        log_success "${ACCION}: ${nombre} → ${ip} ✓"
        return 0
    else
        ERROR=$(echo "$RESULT" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); \
             errs=d.get('errors',[]); print(errs[0].get('message','unknown') if errs else 'unknown')" \
            2>/dev/null || echo "desconocido")
        log_error "Error creando ${nombre}: ${ERROR}"
        return 1
    fi
}

# Crear todos los registros
ERRORES=0
for prefijo in "${!SUBDOMINIOS[@]}"; do
    nombre="${SUBDOMINIOS[$prefijo]}"
    log_process "Procesando: ${nombre}..."
    if ! crear_registro_dns "$nombre" "$TAILSCALE_IP"; then
        ERRORES=$((ERRORES + 1))
    fi
done

if [[ $ERRORES -gt 0 ]]; then
    log_warning "${ERRORES} registros DNS tuvieron errores"
    log_info    "Puedes crearlos manualmente en Cloudflare Dashboard"
fi

# ============================================================
# 5. GUARDAR TOKEN EN CONFIGURACIÓN
# ============================================================
log_step "Guardando configuración de Cloudflare"

CF_ENV_FILE="${APPS_DIR}/.cloudflare.env"
cat > "$CF_ENV_FILE" << EOF
# Cloudflare API — generado automáticamente
# NO subir a GitHub (está en .gitignore)
CF_API_TOKEN="${CF_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID}"
CF_DOMAIN="${DOMAIN}"
EOF

chmod 600 "$CF_ENV_FILE"
chown "${ADMIN_USER}:${ADMIN_USER}" "$CF_ENV_FILE"

log_success "Credenciales guardadas en: ${CF_ENV_FILE} ✓"

# ============================================================
# 6. VERIFICAR PROPAGACIÓN DNS
# ============================================================
log_step "Verificando propagación DNS"

log_info "Los cambios DNS pueden tardar 1-5 minutos en propagarse."
log_info "Verificando con nslookup..."
echo ""

sleep 10

PRUEBA_HOST="portainer.vpn.${DOMAIN}"
DNS_RESULT=$(nslookup "$PRUEBA_HOST" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")

if [[ "$DNS_RESULT" == "$TAILSCALE_IP" ]]; then
    log_success "DNS propagado correctamente: ${PRUEBA_HOST} → ${DNS_RESULT} ✓"
else
    log_info "DNS aún no propagado (normal, puede tardar 1-5 minutos)"
    log_info "Resultado actual: '${DNS_RESULT:-vacío}'"
    log_info "Esperado: ${TAILSCALE_IP}"
    log_info "Puedes verificar manualmente con: nslookup ${PRUEBA_HOST}"
fi

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "DNS de Cloudflare configurado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Registros DNS creados:${COLOR_RESET}"
for prefijo in "${!SUBDOMINIOS[@]}"; do
    echo -e "    ${COLOR_CYAN}${SUBDOMINIOS[$prefijo]}${COLOR_RESET} → ${COLOR_GREEN}${TAILSCALE_IP}${COLOR_RESET}"
done
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Importante:${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}Estos dominios solo funcionan con Tailscale VPN activo${COLOR_RESET}"
echo -e "    Desde internet sin VPN → ${COLOR_RED}sin acceso${COLOR_RESET}"
echo ""
log_info "Próximo paso: Instalar Portainer (opción 9)"
echo ""
