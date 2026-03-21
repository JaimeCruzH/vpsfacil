#!/bin/bash
# ============================================================
# scripts/06_setup_certificates.sh — Certificados SSL
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Instala certbot + plugin certbot-dns-cloudflare
#   2. Pide API token de Cloudflare con permiso DNS:Edit
#   3. Obtiene certificado wildcard *.vpn.DOMAIN via DNS-01
#      (sin necesidad de exponer el servidor a internet)
#   4. Guarda los archivos en /home/ADMIN/apps/certs/
#   5. Configura renovación automática cada 60 días
#
# Por qué Let's Encrypt + DNS-01:
#   - Certificado reconocido por TODOS los navegadores
#   - No requiere acceso público al servidor
#   - Renovación automática (cron de certbot)
#   - Wildcard cubre todas las subapps con un solo cert
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

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "Paso 6 de 11 — Certificados SSL (Let's Encrypt)"
# ============================================================

check_root

log_info "Obtendremos un certificado SSL wildcard para:"
echo -e "   ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET}"
echo ""
log_info "Este certificado cubre TODAS tus apps (Portainer, N8N,"
log_info "File Browser, Kopia, OpenClaw) con un solo certificado"
log_info "reconocido por todos los navegadores."
echo ""
log_info "El proceso es completamente automático — solo necesitas"
log_info "un API token de Cloudflare con permiso para editar DNS."
echo ""

# ============================================================
# VERIFICAR SI YA EXISTEN CERTIFICADOS VÁLIDOS
# ============================================================
CERT_LIVE_DIR="/etc/letsencrypt/live/vpn.${DOMAIN}"

if [[ -f "${CERT_FILE}" && -f "${CERT_KEY}" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null \
        | cut -d= -f2 || echo "desconocida")
    log_info "Ya existe un certificado instalado (expira: ${EXPIRY})"
    echo ""
    if ! confirm "¿Deseas renovar o reemplazar el certificado?"; then
        log_info "Certificado existente conservado. Continuando..."
        exit 0
    fi
fi

# ============================================================
# 1. INSTALAR CERTBOT + PLUGIN CLOUDFLARE
# ============================================================
log_step "Instalando certbot y plugin Cloudflare"

wait_for_dpkg

apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    certbot \
    python3-certbot-dns-cloudflare \
    > /dev/null 2>&1

log_success "certbot $(certbot --version 2>&1 | head -1) instalado ✓"

# ============================================================
# 2. OBTENER API TOKEN DE CLOUDFLARE
# ============================================================
log_step "Configurar API token de Cloudflare"

echo ""
windows_instruction "CREAR API TOKEN EN CLOUDFLARE

1. Abre: https://dash.cloudflare.com/profile/api-tokens

2. Haz clic en 'Create Token'

3. Usa la plantilla 'Edit zone DNS' (botón 'Use template')

4. En 'Zone Resources':
   Selecciona: Include → Specific zone → ${DOMAIN}

5. Haz clic en 'Continue to summary' → 'Create Token'

6. COPIA el token que aparece (solo se muestra una vez)"

echo ""

# Verificar si ya tenemos el token guardado (del paso 7)
CF_CREDS_FILE="/root/.cloudflare-certbot.ini"
CF_ENV_FILE="${APPS_DIR}/.cloudflare.env"

if [[ -f "$CF_ENV_FILE" ]] && grep -q "CF_API_TOKEN" "$CF_ENV_FILE" 2>/dev/null; then
    EXISTING_TOKEN=$(grep "CF_API_TOKEN=" "$CF_ENV_FILE" | cut -d= -f2 | tr -d '"')
    if [[ -n "$EXISTING_TOKEN" ]]; then
        log_info "Se encontró un API token de Cloudflare guardado previamente."
        if confirm "¿Usar el token guardado?"; then
            CF_API_TOKEN="$EXISTING_TOKEN"
        else
            CF_API_TOKEN=$(prompt_input "Pega tu API token de Cloudflare")
        fi
    fi
else
    CF_API_TOKEN=$(prompt_input "Pega tu API token de Cloudflare")
fi

CF_API_TOKEN="${CF_API_TOKEN//$'\r'/}"

if [[ -z "$CF_API_TOKEN" ]]; then
    log_error "El API token no puede estar vacío"
    exit 1
fi

# ============================================================
# 3. VERIFICAR TOKEN CON LA API DE CLOUDFLARE
# ============================================================
log_step "Verificando token de Cloudflare"

log_process "Verificando token..."
CF_VERIFY=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

if echo "$CF_VERIFY" | grep -q '"status":"active"'; then
    log_success "Token válido y activo ✓"
else
    log_error "Token inválido o sin permisos suficientes"
    log_info  "Verifica que el token tenga permiso: Zone → DNS → Edit"
    exit 1
fi

# ============================================================
# 4. GUARDAR CREDENCIALES PARA CERTBOT
# ============================================================
log_step "Guardando credenciales"

cat > "$CF_CREDS_FILE" << EOF
# Cloudflare API token para certbot DNS-01 challenge
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF

chmod 600 "$CF_CREDS_FILE"
log_success "Credenciales guardadas en ${CF_CREDS_FILE} (permisos 600) ✓"

# Guardar también para el paso 7 (DNS setup) si no existe
if [[ ! -f "$CF_ENV_FILE" ]]; then
    mkdir -p "${APPS_DIR}"
    cat > "$CF_ENV_FILE" << EOF
# Cloudflare API — VPSfacil
CF_API_TOKEN="${CF_API_TOKEN}"
EOF
    chmod 600 "$CF_ENV_FILE"
fi

# ============================================================
# 5. OBTENER CERTIFICADO WILDCARD CON LET'S ENCRYPT
# ============================================================
log_step "Obteniendo certificado SSL de Let's Encrypt"

echo ""
log_info "Solicitando certificado wildcard para: *.vpn.${DOMAIN}"
log_info "Esto puede tardar 30-60 segundos..."
echo ""

# Email para notificaciones de renovación
CF_EMAIL=$(prompt_input "Email para notificaciones de renovación" "admin@${DOMAIN}")

echo ""
log_process "Conectando con Let's Encrypt..."

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials "$CF_CREDS_FILE" \
    --dns-cloudflare-propagation-seconds 30 \
    -d "*.vpn.${DOMAIN}" \
    --non-interactive \
    --agree-tos \
    --email "$CF_EMAIL" \
    --cert-name "vpn.${DOMAIN}" \
    2>&1 | while IFS= read -r line; do
        echo -e "   ${COLOR_WHITE}${line}${COLOR_RESET}"
    done

# Verificar que el certificado fue emitido
if [[ ! -f "${CERT_LIVE_DIR}/fullchain.pem" ]]; then
    log_error "No se pudo obtener el certificado. Revisa los mensajes de arriba."
    log_info  "Causas comunes:"
    log_info  "  - Token sin permiso DNS:Edit"
    log_info  "  - Dominio no gestionado en esta cuenta de Cloudflare"
    exit 1
fi

log_success "Certificado obtenido exitosamente ✓"

# ============================================================
# 6. COPIAR CERTIFICADOS A LA CARPETA DE APPS
# ============================================================
log_step "Instalando certificados en ${CERTS_DIR}"

mkdir -p "${CERTS_DIR}"

# Copiar (no symlink) para que funcionen con Docker y permisos de usuario
cp "${CERT_LIVE_DIR}/fullchain.pem" "${CERT_FILE}"
cp "${CERT_LIVE_DIR}/privkey.pem"   "${CERT_KEY}"

# Permisos
chmod 644 "${CERT_FILE}"
chmod 600 "${CERT_KEY}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${CERTS_DIR}" "${CERT_FILE}" "${CERT_KEY}"

log_success "Certificados instalados en ${CERTS_DIR} ✓"

# ============================================================
# 7. CONFIGURAR RENOVACIÓN AUTOMÁTICA
# ============================================================
log_step "Configurando renovación automática"

# Hook post-renovación: copia los certs renovados a CERTS_DIR
RENEWAL_HOOK="/etc/letsencrypt/renewal-hooks/deploy/vpsfacil-copy-certs.sh"

cat > "$RENEWAL_HOOK" << HOOK
#!/bin/bash
# Copia certs renovados de Let's Encrypt a la carpeta de VPSfacil
CERT_LIVE="/etc/letsencrypt/live/vpn.${DOMAIN}"
CERTS_DIR="${CERTS_DIR}"

cp "\${CERT_LIVE}/fullchain.pem" "\${CERTS_DIR}/origin-cert.pem"
cp "\${CERT_LIVE}/privkey.pem"   "\${CERTS_DIR}/origin-cert-key.pem"
chmod 644 "\${CERTS_DIR}/origin-cert.pem"
chmod 600 "\${CERTS_DIR}/origin-cert-key.pem"
chown ${ADMIN_USER}:${ADMIN_USER} "\${CERTS_DIR}/origin-cert.pem" "\${CERTS_DIR}/origin-cert-key.pem"

# Reiniciar containers que usan los certs
cd "\${CERTS_DIR}/.." && for app in portainer n8n filebrowser kopia; do
    if docker compose -f "\${app}/docker-compose.yml" ps -q 2>/dev/null | grep -q .; then
        docker compose -f "\${app}/docker-compose.yml" restart 2>/dev/null || true
    fi
done
HOOK

chmod +x "$RENEWAL_HOOK"
log_success "Hook de renovación configurado ✓"

# Verificar que el timer de certbot esté activo
if systemctl is-active --quiet certbot.timer 2>/dev/null; then
    log_success "Timer de renovación automática activo ✓"
elif systemctl enable --now certbot.timer 2>/dev/null; then
    log_success "Timer de renovación automática activado ✓"
else
    # Fallback: cron
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    log_success "Cron de renovación automática configurado ✓"
fi

# ============================================================
# 8. VERIFICAR CERTIFICADO
# ============================================================
log_step "Verificando certificado instalado"

CERT_SUBJECT=$(openssl x509 -subject -noout -in "${CERT_FILE}" 2>/dev/null || echo "")
CERT_EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null \
    | cut -d= -f2 || echo "desconocida")
CERT_ISSUER=$(openssl x509 -issuer -noout -in "${CERT_FILE}" 2>/dev/null \
    | grep -oP "O=\K[^,]+" || echo "Let's Encrypt")

echo ""
echo -e "  ${COLOR_BOLD_WHITE}Certificado:${COLOR_RESET}"
echo -e "    Emisor:    ${COLOR_GREEN}${CERT_ISSUER}${COLOR_RESET}"
echo -e "    Cubre:     ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET}"
echo -e "    Expira:    ${COLOR_CYAN}${CERT_EXPIRY}${COLOR_RESET}"
echo -e "    Renueva:   ${COLOR_CYAN}Automáticamente cada 60 días${COLOR_RESET}"
echo ""

# ============================================================
# RESUMEN FINAL
# ============================================================
print_separator
echo ""
log_success "Certificados SSL configurados exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Archivos:${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${CERT_FILE}${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${CERT_KEY}${COLOR_RESET} (permisos 600)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Renovación:${COLOR_RESET} Automática — no requiere intervención manual"
echo ""
log_info "Próximo paso: Configurar DNS en Cloudflare (opción 7)"
echo ""
