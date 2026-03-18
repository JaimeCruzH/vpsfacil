#!/bin/bash
################################################################################
# VPSfacil - Utility Functions Library
# Common functions used across all installation scripts
################################################################################

set -e
trap 'log_error "Script interrupted"' INT TERM

# Source colors if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/colors.sh" ]]; then
  source "${SCRIPT_DIR}/colors.sh"
fi

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Log information message
log_info() {
  local message="$1"
  echo -e "${BLUE}[ℹ]${NC} ${message}"
}

# Log success message
log_success() {
  local message="$1"
  echo -e "${GREEN}[✓]${NC} ${message}"
}

# Log warning message
log_warning() {
  local message="$1"
  echo -e "${YELLOW}[⚠]${NC} ${message}"
}

# Log error message
log_error() {
  local message="$1"
  echo -e "${RED}[✗]${NC} ${message}" >&2
}

# Log a section header
log_header() {
  local title="$1"
  local width=60
  local padding=$((($width - ${#title}) / 2))

  echo ""
  echo -e "${BLUE}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
  echo -e "${BLUE}║$(printf ' %.0s' $(seq 1 $padding))${BOLD}${title}${NORMAL}$(printf ' %.0s' $(seq 1 $((width - padding - ${#title}))))║${NC}"
  echo -e "${BLUE}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
  echo ""
}

# Log a step header
log_step() {
  local step_num="$1"
  local step_title="$2"

  echo ""
  echo -e "${BOLD}${CYAN}Step ${step_num}: ${step_title}${NC}"
  echo -e "${CYAN}$(printf '─%.0s' $(seq 1 50))${NC}"
}

################################################################################
# CONFIRMATION & USER INPUT
################################################################################

# Ask user for Y/N confirmation
confirm() {
  local prompt="$1"
  local response

  while true; do
    echo -n -e "${YELLOW}[?]${NC} ${prompt} (yes/no): "
    read -r response
    case "$response" in
      [yY][eE][sS]|[yY])
        return 0
        ;;
      [nN][oO]|[nN])
        return 1
        ;;
      *)
        log_warning "Please answer yes or no"
        ;;
    esac
  done
}

# Prompt user for input with default value
prompt_input() {
  local prompt="$1"
  local default="$2"
  local response

  if [[ -z "$default" ]]; then
    echo -n -e "${YELLOW}[?]${NC} ${prompt}: "
  else
    echo -n -e "${YELLOW}[?]${NC} ${prompt} [${default}]: "
  fi

  read -r response

  if [[ -z "$response" && -n "$default" ]]; then
    echo "$default"
  else
    echo "$response"
  fi
}

# Pause and wait for user confirmation
wait_for_user() {
  local message="${1:-Press Enter to continue...}"
  echo ""
  echo -n -e "${YELLOW}[?]${NC} ${message}"
  read -r
}

################################################################################
# DIRECTORY MANAGEMENT
################################################################################

# Base apps directory
APPS_BASE_DIR="/home/jaime/apps"

# Get the apps base directory
get_apps_dir() {
  echo "$APPS_BASE_DIR"
}

# Get specific app directory
get_app_dir() {
  local appname="$1"
  echo "${APPS_BASE_DIR}/${appname}"
}

# Ensure app directory structure exists
ensure_app_dir() {
  local appname="$1"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  log_info "Creating application directory structure for: ${appname}"

  # Create main app directory
  sudo -u jaime mkdir -p "$app_dir"

  # Create subdirectories
  sudo -u jaime mkdir -p "${app_dir}/data"
  sudo -u jaime mkdir -p "${app_dir}/config"

  # Set proper permissions
  sudo chown -R jaime:jaime "$app_dir"
  sudo chmod -R 755 "$app_dir"

  log_success "Application directory created: ${app_dir}"
}

# Create docker-compose.yml for app
create_app_compose() {
  local appname="$1"
  local template_file="$2"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  if [[ ! -f "$template_file" ]]; then
    log_error "Template file not found: ${template_file}"
    return 1
  fi

  log_info "Creating docker-compose.yml for ${appname}..."

  sudo -u jaime cp "$template_file" "${app_dir}/docker-compose.yml"
  log_success "docker-compose.yml created"
}

# Create .env file for app
create_app_env() {
  local appname="$1"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  # Create empty .env if it doesn't exist
  if [[ ! -f "${app_dir}/.env" ]]; then
    sudo -u jaime touch "${app_dir}/.env"
    sudo chmod 600 "${app_dir}/.env"
    log_success ".env file created (empty)"
  fi
}

# Add variable to app's .env file
add_env_var() {
  local appname="$1"
  local key="$2"
  local value="$3"
  local app_dir
  app_dir=$(get_app_dir "$appname")
  local env_file="${app_dir}/.env"

  # Remove existing key if present
  sudo -u jaime sed -i "/^${key}=/d" "$env_file"

  # Add new key-value pair
  echo "${key}=${value}" | sudo -u jaime tee -a "$env_file" > /dev/null
}

# Get variable from app's .env file
get_env_var() {
  local appname="$1"
  local key="$2"
  local app_dir
  app_dir=$(get_app_dir "$appname")
  local env_file="${app_dir}/.env"

  if [[ -f "$env_file" ]]; then
    grep "^${key}=" "$env_file" | cut -d'=' -f2 || echo ""
  fi
}

################################################################################
# DOCKER OPERATIONS
################################################################################

# Check if Docker is installed and running
check_docker() {
  if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    return 1
  fi

  if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running"
    return 1
  fi

  log_success "Docker is available and running"
}

# Deploy application using docker-compose
deploy_app() {
  local appname="$1"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  if [[ ! -d "$app_dir" ]]; then
    log_error "Application directory not found: ${app_dir}"
    return 1
  fi

  if [[ ! -f "${app_dir}/docker-compose.yml" ]]; then
    log_error "docker-compose.yml not found in: ${app_dir}"
    return 1
  fi

  log_info "Deploying ${appname}..."

  cd "$app_dir"

  # Stop existing containers if running
  log_info "Stopping any existing containers..."
  sudo -u jaime docker-compose down 2>/dev/null || true

  # Pull latest images
  log_info "Pulling latest images..."
  sudo -u jaime docker-compose pull

  # Start containers
  log_info "Starting containers..."
  sudo -u jaime docker-compose up -d

  cd - > /dev/null
  log_success "${appname} deployed successfully"
}

# Stop application
stop_app() {
  local appname="$1"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  if [[ ! -d "$app_dir" ]]; then
    log_error "Application directory not found: ${app_dir}"
    return 1
  fi

  log_info "Stopping ${appname}..."
  cd "$app_dir"
  sudo -u jaime docker-compose down
  cd - > /dev/null
  log_success "${appname} stopped"
}

# Get container status
app_status() {
  local appname="$1"
  local app_dir
  app_dir=$(get_app_dir "$appname")

  if [[ ! -d "$app_dir" ]]; then
    log_error "Application directory not found: ${app_dir}"
    return 1
  fi

  cd "$app_dir"
  sudo -u jaime docker-compose ps
  cd - > /dev/null
}

################################################################################
# HEALTH CHECKS
################################################################################

# Wait for port to be open
wait_for_port() {
  local port="$1"
  local timeout="${2:-60}"
  local elapsed=0

  log_info "Waiting for port ${port} to open... (timeout: ${timeout}s)"

  while ! nc -z localhost "$port" 2>/dev/null; do
    elapsed=$((elapsed + 1))

    if [[ $elapsed -ge $timeout ]]; then
      log_error "Port ${port} did not open within ${timeout} seconds"
      return 1
    fi

    printf "."
    sleep 1
  done

  echo ""
  log_success "Port ${port} is open"
}

# Check HTTP endpoint
check_http_endpoint() {
  local url="$1"
  local timeout="${2:-30}"

  log_info "Checking HTTP endpoint: ${url}"

  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" || echo "000")

  if [[ "$response" == "200" ]] || [[ "$response" == "301" ]] || [[ "$response" == "302" ]]; then
    log_success "Endpoint is responding (HTTP ${response})"
    return 0
  else
    log_warning "Endpoint returned HTTP ${response}"
    return 1
  fi
}

################################################################################
# FILE OPERATIONS
################################################################################

# Backup app directory
backup_app() {
  local appname="$1"
  local backup_dir="${2:-.}"
  local app_dir
  app_dir=$(get_app_dir "$appname")
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local backup_file="${backup_dir}/${appname}-backup-${timestamp}.tar.gz"

  if [[ ! -d "$app_dir" ]]; then
    log_error "Application directory not found: ${app_dir}"
    return 1
  fi

  log_info "Backing up ${appname} to: ${backup_file}"

  sudo -u jaime tar -czf "$backup_file" -C "${APPS_BASE_DIR}" "${appname}"

  log_success "Backup completed: ${backup_file}"
  echo "$backup_file"
}

# Restore app from backup
restore_app() {
  local backup_file="$1"
  local appname

  if [[ ! -f "$backup_file" ]]; then
    log_error "Backup file not found: ${backup_file}"
    return 1
  fi

  appname=$(basename "$backup_file" | sed 's/-backup-.*//')
  local app_dir
  app_dir=$(get_app_dir "$appname")

  log_warning "This will restore ${appname} from backup"

  if ! confirm "Continue with restore?"; then
    log_info "Restore cancelled"
    return 0
  fi

  # Stop running container
  if [[ -d "$app_dir" ]]; then
    stop_app "$appname" || true
  fi

  # Extract backup
  log_info "Extracting backup..."
  sudo -u jaime tar -xzf "$backup_file" -C "${APPS_BASE_DIR}"

  # Restart application
  log_info "Restarting ${appname}..."
  deploy_app "$appname"

  log_success "Restore completed"
}

################################################################################
# UTILITY HELPERS
################################################################################

# Check if running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    return 1
  fi
}

# Check if running as jaime
check_jaime() {
  if [[ "$EUID" -ne "$(id -u jaime)" ]]; then
    log_error "This command must be run as jaime user"
    return 1
  fi
}

# Get VPS hostname
get_vps_hostname() {
  hostname -f 2>/dev/null || hostname
}

# Check internet connectivity
check_internet() {
  log_info "Checking internet connectivity..."

  if curl -s --max-time 5 https://www.google.com > /dev/null 2>&1; then
    log_success "Internet connectivity confirmed"
    return 0
  else
    log_error "No internet connectivity detected"
    return 1
  fi
}

# Generate random password
generate_password() {
  local length="${1:-16}"
  openssl rand -base64 "$length" | tr -d '=' | head -c "$length"
}

# Check if command exists
command_exists() {
  command -v "$1" &> /dev/null
}

################################################################################
# END OF LIBRARY
################################################################################
