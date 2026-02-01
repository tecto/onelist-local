#!/bin/bash
# Onelist Native Installer
# Usage: curl -fsSL https://onelist.my/install.sh | bash
# Or download and run: bash install.sh
#
# This script installs Onelist on Ubuntu 22.04/24.04 with all dependencies
# Compatible with: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ONELIST_USER="onelist"
ONELIST_HOME="/opt/onelist"
ONELIST_REPO="https://github.com/stream-onelist/onelist-local.git"
ONELIST_BRANCH="main"
POSTGRES_DB="onelist_prod"
POSTGRES_USER="onelist"
SERVICE_NAME="onelist"

# Global flags
DRY_RUN=false
SKIP_DEPS=false
FORCE_REINSTALL=false

# Utility functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

fatal() {
    error "$1"
    exit 1
}

progress() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        fatal "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
    
    # Check if user has sudo access
    if ! sudo -n true 2>/dev/null; then
        fatal "This script requires sudo privileges. Please ensure you can run sudo commands."
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log "Running in dry-run mode (no changes will be made)"
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                log "Skipping dependency installation"
                shift
                ;;
            --force)
                FORCE_REINSTALL=true
                log "Forcing reinstallation (existing installation will be removed)"
                shift
                ;;
            --help)
                cat << 'EOF'
Onelist Native Installer

USAGE:
    curl -fsSL https://onelist.my/install.sh | bash
    
    or download and run:
    bash install.sh [OPTIONS]

OPTIONS:
    --dry-run     Show what would be installed without making changes
    --skip-deps   Skip system dependency installation
    --force       Remove existing installation and reinstall
    --help        Show this help message

EXAMPLES:
    # Standard installation
    curl -fsSL https://onelist.my/install.sh | bash
    
    # Dry run to see what would happen
    bash install.sh --dry-run
    
    # Reinstall over existing installation
    bash install.sh --force

SYSTEM REQUIREMENTS:
    - Ubuntu 22.04 LTS or 24.04 LTS
    - 4GB RAM (recommended)
    - 10GB free disk space
    - Internet connection
    - Sudo privileges

For more information, see: https://onelist.my/docs/installation

EOF
                exit 0
                ;;
            *)
                fatal "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Detect OS and version
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        fatal "Cannot detect OS. This installer requires Ubuntu 22.04+ or Debian 12+"
    fi
    
    source /etc/os-release
    
    case "${ID}" in
        ubuntu)
            case "${VERSION_ID}" in
                22.04|24.04)
                    log "Detected Ubuntu ${VERSION_ID} LTS - supported ✓"
                    ;;
                *)
                    warn "Ubuntu ${VERSION_ID} detected. This installer is tested on 22.04 and 24.04 LTS."
                    read -p "Continue anyway? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        fatal "Installation cancelled."
                    fi
                    ;;
            esac
            ;;
        debian)
            warn "Debian detected. This installer is primarily tested on Ubuntu."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                fatal "Installation cancelled."
            fi
            ;;
        *)
            fatal "Unsupported OS: ${ID}. This installer requires Ubuntu 22.04+ or Debian 12+"
            ;;
    esac
}

# Check system requirements
check_requirements() {
    progress "Checking system requirements..."
    
    # Check RAM (in KB)
    local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_gb=$((ram_kb / 1024 / 1024))
    
    if [[ $ram_gb -lt 2 ]]; then
        fatal "Insufficient RAM: ${ram_gb}GB detected, minimum 2GB required"
    elif [[ $ram_gb -lt 4 ]]; then
        warn "Low RAM: ${ram_gb}GB detected, 4GB recommended for optimal performance"
    else
        log "RAM check passed: ${ram_gb}GB available"
    fi
    
    # Check disk space (in /opt where we'll install)
    local disk_free_gb=$(df /opt 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}' || echo "0")
    if [[ $disk_free_gb -lt 5 ]]; then
        fatal "Insufficient disk space: ${disk_free_gb}GB free in /opt, minimum 5GB required"
    else
        log "Disk space check passed: ${disk_free_gb}GB available in /opt"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 github.com &>/dev/null; then
        fatal "No internet connection detected. Internet access is required for installation."
    fi
    
    log "System requirements check passed ✓"
}

# Check for existing installation
check_existing() {
    local existing=false
    
    if id "$ONELIST_USER" &>/dev/null; then
        warn "User '$ONELIST_USER' already exists"
        existing=true
    fi
    
    if [[ -d "$ONELIST_HOME" ]]; then
        warn "Directory '$ONELIST_HOME' already exists"
        existing=true
    fi
    
    if systemctl list-units --type=service | grep -q "$SERVICE_NAME"; then
        warn "Service '$SERVICE_NAME' already exists"
        existing=true
    fi
    
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$POSTGRES_DB"; then
        warn "Database '$POSTGRES_DB' already exists"
        existing=true
    fi
    
    if [[ "$existing" == "true" ]]; then
        if [[ "$FORCE_REINSTALL" == "true" ]]; then
            warn "Existing installation detected, will remove due to --force flag"
        else
            error "Existing Onelist installation detected!"
            echo -e "\nTo reinstall, use: bash install.sh --force"
            echo -e "To check the current installation: systemctl status $SERVICE_NAME"
            exit 1
        fi
    fi
}

# Remove existing installation
remove_existing() {
    progress "Removing existing installation..."
    
    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "Stopping $SERVICE_NAME service..."
        [[ "$DRY_RUN" == "false" ]] && sudo systemctl stop "$SERVICE_NAME"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "Disabling $SERVICE_NAME service..."
        [[ "$DRY_RUN" == "false" ]] && sudo systemctl disable "$SERVICE_NAME"
    fi
    
    # Remove service file
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        log "Removing service file..."
        [[ "$DRY_RUN" == "false" ]] && sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        [[ "$DRY_RUN" == "false" ]] && sudo systemctl daemon-reload
    fi
    
    # Remove application directory
    if [[ -d "$ONELIST_HOME" ]]; then
        log "Removing application directory..."
        [[ "$DRY_RUN" == "false" ]] && sudo rm -rf "$ONELIST_HOME"
    fi
    
    # Remove user (but keep database for safety)
    if id "$ONELIST_USER" &>/dev/null; then
        log "Removing user account..."
        [[ "$DRY_RUN" == "false" ]] && sudo userdel "$ONELIST_USER" || true
    fi
    
    log "Existing installation removed ✓"
}

# Install system dependencies
install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        log "Skipping dependency installation as requested"
        return 0
    fi
    
    progress "Installing system dependencies..."
    
    log "Updating package list..."
    [[ "$DRY_RUN" == "false" ]] && sudo apt update
    
    # Install required packages
    local packages=(
        "curl"
        "git" 
        "build-essential"
        "autoconf"
        "m4"
        "libncurses5-dev"
        "libwxgtk3.0-gtk3-dev"
        "libwxgtk-webview3.0-gtk3-dev"
        "libgl1-mesa-dev"
        "libglu1-mesa-dev"
        "libpng-dev"
        "libssh-dev"
        "unixodbc-dev"
        "xsltproc"
        "fop"
        "libxml2-utils"
        "libncurses-dev"
        "openjdk-11-jdk"
    )
    
    log "Installing build tools and libraries..."
    [[ "$DRY_RUN" == "false" ]] && sudo apt install -y "${packages[@]}"
    
    # Install PostgreSQL with pgvector
    log "Installing PostgreSQL with pgvector..."
    if ! dpkg -l | grep -q postgresql; then
        [[ "$DRY_RUN" == "false" ]] && sudo apt install -y postgresql postgresql-contrib
        [[ "$DRY_RUN" == "false" ]] && sudo systemctl enable postgresql
        [[ "$DRY_RUN" == "false" ]] && sudo systemctl start postgresql
    fi
    
    # Install pgvector extension
    if ! sudo -u postgres psql -c "SELECT * FROM pg_available_extensions WHERE name='vector';" | grep -q vector; then
        log "Installing pgvector extension..."
        # For Ubuntu 22.04/24.04, pgvector is available in packages
        [[ "$DRY_RUN" == "false" ]] && sudo apt install -y postgresql-16-pgvector || \
        [[ "$DRY_RUN" == "false" ]] && sudo apt install -y postgresql-15-pgvector || \
        [[ "$DRY_RUN" == "false" ]] && sudo apt install -y postgresql-14-pgvector
    fi
    
    # Install Node.js 20.x
    log "Installing Node.js..."
    if ! command -v node &> /dev/null || [[ "$(node --version | cut -d. -f1 | cut -dv -f2)" -lt 18 ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt install -y nodejs
        fi
    fi
    
    # Install Erlang and Elixir
    log "Installing Erlang and Elixir..."
    if ! command -v elixir &> /dev/null; then
        if [[ "$DRY_RUN" == "false" ]]; then
            wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
            sudo dpkg -i erlang-solutions_2.0_all.deb
            sudo apt update
            sudo apt install -y esl-erlang elixir
            rm -f erlang-solutions_2.0_all.deb
        fi
    fi
    
    log "Dependencies installed ✓"
}

# Create onelist user and directories
create_user() {
    progress "Creating onelist user and directories..."
    
    if ! id "$ONELIST_USER" &>/dev/null; then
        log "Creating user: $ONELIST_USER"
        [[ "$DRY_RUN" == "false" ]] && sudo useradd --system --home "$ONELIST_HOME" --shell /bin/bash --create-home "$ONELIST_USER"
    fi
    
    # Ensure proper directory ownership
    log "Setting up directory structure..."
    [[ "$DRY_RUN" == "false" ]] && sudo mkdir -p "$ONELIST_HOME"/{storage,config,logs}
    [[ "$DRY_RUN" == "false" ]] && sudo chown -R "$ONELIST_USER":"$ONELIST_USER" "$ONELIST_HOME"
    
    log "User and directories created ✓"
}

# Setup PostgreSQL database
setup_database() {
    progress "Setting up PostgreSQL database..."
    
    # Generate a secure password
    local db_password
    db_password=$(openssl rand -base64 32)
    
    log "Creating database user and database..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo -u postgres psql <<EOF
-- Create user if not exists
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$POSTGRES_USER') THEN
      CREATE USER $POSTGRES_USER WITH PASSWORD '$db_password';
   END IF;
END
\$\$;

-- Create database if not exists
SELECT 'CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$POSTGRES_DB')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;
EOF
        
        # Enable required extensions
        sudo -u postgres psql -d "$POSTGRES_DB" <<EOF
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF
    fi
    
    # Store database URL for later use
    export DATABASE_URL="postgres://$POSTGRES_USER:$db_password@localhost/$POSTGRES_DB"
    
    log "Database setup completed ✓"
    log "Database URL: postgres://$POSTGRES_USER:[PASSWORD]@localhost/$POSTGRES_DB"
}

# Clone and setup Onelist
clone_application() {
    progress "Cloning Onelist application..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Clone as onelist user
        sudo -u "$ONELIST_USER" git clone "$ONELIST_REPO" "$ONELIST_HOME/app"
        cd "$ONELIST_HOME/app"
        
        # Switch to specified branch
        sudo -u "$ONELIST_USER" git checkout "$ONELIST_BRANCH"
        
        log "Application cloned ✓"
    else
        log "Would clone: $ONELIST_REPO -> $ONELIST_HOME/app"
    fi
}

# Install application dependencies
install_app_dependencies() {
    progress "Installing application dependencies..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "$ONELIST_HOME/app"
        
        # Install Elixir dependencies
        log "Installing Elixir dependencies..."
        sudo -u "$ONELIST_USER" -H mix local.hex --force
        sudo -u "$ONELIST_USER" -H mix local.rebar --force
        sudo -u "$ONELIST_USER" -H MIX_ENV=prod mix deps.get
        
        # Install Node.js dependencies
        log "Installing Node.js dependencies..."
        sudo -u "$ONELIST_USER" -H npm install --prefix assets
        
        log "Application dependencies installed ✓"
    else
        log "Would install Elixir and Node.js dependencies"
    fi
}

# Generate configuration
generate_config() {
    progress "Generating application configuration..."
    
    # Generate secrets
    local secret_key_base
    if command -v mix &> /dev/null && [[ "$DRY_RUN" == "false" ]]; then
        cd "$ONELIST_HOME/app"
        secret_key_base=$(sudo -u "$ONELIST_USER" -H mix phx.gen.secret)
    else
        secret_key_base="GENERATED_SECRET_KEY_BASE_REPLACE_IN_PRODUCTION"
    fi
    
    # Create environment file
    local env_file="$ONELIST_HOME/.env"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo -u "$ONELIST_USER" tee "$env_file" > /dev/null <<EOF
# Onelist Production Configuration
# Generated by installer on $(date)

# Database
DATABASE_URL=$DATABASE_URL

# Phoenix
SECRET_KEY_BASE=$secret_key_base
PHX_HOST=localhost
PHX_SERVER=true
PORT=4000
MIX_ENV=prod

# Storage
STORAGE_BACKEND=local
STORAGE_LOCAL_PATH=$ONELIST_HOME/storage

# Optional: Add your OpenAI API key for enhanced features
# OPENAI_API_KEY=your_openai_api_key_here

# Optional: OAuth providers (see docs for setup)
# GITHUB_CLIENT_ID=
# GITHUB_CLIENT_SECRET=
# GOOGLE_CLIENT_ID=  
# GOOGLE_CLIENT_SECRET=
EOF
        
        sudo chown "$ONELIST_USER":"$ONELIST_USER" "$env_file"
        sudo chmod 600 "$env_file"
    fi
    
    log "Configuration generated ✓"
    log "Environment file: $env_file"
}

# Compile application
compile_application() {
    progress "Compiling application..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "$ONELIST_HOME/app"
        
        # Source environment
        set -a
        source "$ONELIST_HOME/.env"
        set +a
        
        # Compile assets
        log "Building assets..."
        sudo -u "$ONELIST_USER" -H MIX_ENV=prod mix assets.deploy
        
        # Compile application
        log "Compiling Elixir application..."
        sudo -u "$ONELIST_USER" -H MIX_ENV=prod mix compile
        
        log "Application compiled ✓"
    else
        log "Would compile application assets and Elixir code"
    fi
}

# Setup database schema
setup_schema() {
    progress "Setting up database schema..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "$ONELIST_HOME/app"
        
        # Source environment
        set -a
        source "$ONELIST_HOME/.env"
        set +a
        
        # Create and migrate database
        log "Creating database schema..."
        sudo -u "$ONELIST_USER" -H MIX_ENV=prod mix ecto.create || true
        sudo -u "$ONELIST_USER" -H MIX_ENV=prod mix ecto.migrate
        
        log "Database schema created ✓"
    else
        log "Would create database schema and run migrations"
    fi
}

# Create systemd service
create_service() {
    progress "Creating systemd service..."
    
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Onelist Phoenix Server
After=network.target postgresql.service
Requires=postgresql.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$ONELIST_USER
Group=$ONELIST_USER
WorkingDirectory=$ONELIST_HOME/app
Environment=MIX_ENV=prod
EnvironmentFile=$ONELIST_HOME/.env
ExecStart=/usr/bin/mix phx.server
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=30
Restart=on-failure
RestartSec=5
RemainAfterExit=false

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$ONELIST_HOME
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true
ProtectKernelModules=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF
        
        # Reload systemd and enable service
        sudo systemctl daemon-reload
        sudo systemctl enable "$SERVICE_NAME"
        
        log "Systemd service created ✓"
    else
        log "Would create systemd service: $service_file"
    fi
}

# Start services
start_service() {
    progress "Starting Onelist service..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo systemctl start "$SERVICE_NAME"
        
        # Wait for service to start
        local timeout=30
        local count=0
        while ! systemctl is-active --quiet "$SERVICE_NAME" && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log "Service started successfully ✓"
        else
            error "Service failed to start within ${timeout}s"
            sudo systemctl status "$SERVICE_NAME" --no-pager
            return 1
        fi
    else
        log "Would start service: $SERVICE_NAME"
    fi
}

# Verify installation
verify_installation() {
    progress "Verifying installation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run completed - no actual changes made"
        return 0
    fi
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "✓ Service is running"
    else
        error "✗ Service is not running"
        return 1
    fi
    
    # Check HTTP endpoint
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f -s http://localhost:4000/health > /dev/null 2>&1; then
            log "✓ HTTP endpoint responding"
            break
        else
            if [[ $attempt -eq $max_attempts ]]; then
                error "✗ HTTP endpoint not responding after ${max_attempts} attempts"
                return 1
            else
                log "Waiting for HTTP endpoint... (attempt $attempt/$max_attempts)"
                sleep 3
                ((attempt++))
            fi
        fi
    done
    
    # Check database connectivity
    if sudo -u "$ONELIST_USER" -H bash -c "cd $ONELIST_HOME/app && source $ONELIST_HOME/.env && MIX_ENV=prod mix ecto.migrate --check-migrated" > /dev/null 2>&1; then
        log "✓ Database connectivity confirmed"
    else
        warn "✗ Database connectivity check failed (may be normal on first run)"
    fi
    
    log "Installation verification completed ✓"
}

# Create setup script for post-install configuration
create_setup_script() {
    progress "Creating setup script for additional configuration..."
    
    local setup_script="$ONELIST_HOME/setup.sh"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo -u "$ONELIST_USER" tee "$setup_script" > /dev/null <<'EOF'
#!/bin/bash
# Onelist Setup Helper
# Run this script to configure optional features

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Onelist Setup Helper${NC}"
echo "This script helps you configure optional features like OpenAI integration and OAuth."
echo

# Function to update environment variable
update_env() {
    local key="$1"
    local value="$2"
    local env_file="$HOME/.env"
    
    if grep -q "^${key}=" "$env_file"; then
        # Update existing
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    elif grep -q "^# ${key}=" "$env_file"; then
        # Uncomment and set
        sed -i "s|^# ${key}=.*|${key}=${value}|" "$env_file"
    else
        # Add new
        echo "${key}=${value}" >> "$env_file"
    fi
}

# OpenAI API Key setup
echo -e "${YELLOW}OpenAI API Key Setup${NC}"
echo "For enhanced AI features (semantic search, smart tagging), add your OpenAI API key."
read -p "Do you want to configure OpenAI? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your OpenAI API key: " openai_key
    if [[ -n "$openai_key" ]]; then
        update_env "OPENAI_API_KEY" "$openai_key"
        echo "OpenAI API key configured."
    fi
fi
echo

# OAuth setup reminder
echo -e "${YELLOW}OAuth Setup${NC}"
echo "For social login (GitHub, Google), you'll need to:"
echo "1. Create OAuth apps at the respective provider"
echo "2. Add the client ID and secret to $HOME/.env"
echo "3. Restart the service with: sudo systemctl restart onelist"
echo
echo "See the documentation for detailed OAuth setup instructions."
echo

echo -e "${GREEN}Setup completed!${NC}"
echo "To restart Onelist with new config: sudo systemctl restart onelist"
echo "To view logs: sudo journalctl -fu onelist"
EOF
        
        sudo chown "$ONELIST_USER":"$ONELIST_USER" "$setup_script"
        sudo chmod +x "$setup_script"
        
        log "Setup script created: $setup_script"
    else
        log "Would create setup script: $setup_script"
    fi
}

# Print success message
print_success() {
    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}🎉 Onelist installation completed! 🎉${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo -e "📍 ${BLUE}Your Onelist instance is running at:${NC}"
    echo -e "   🌐 http://localhost:4000"
    echo
    echo -e "🔧 ${BLUE}Service management:${NC}"
    echo -e "   Start:   sudo systemctl start $SERVICE_NAME"
    echo -e "   Stop:    sudo systemctl stop $SERVICE_NAME"
    echo -e "   Restart: sudo systemctl restart $SERVICE_NAME"
    echo -e "   Status:  sudo systemctl status $SERVICE_NAME"
    echo -e "   Logs:    sudo journalctl -fu $SERVICE_NAME"
    echo
    echo -e "📁 ${BLUE}Important paths:${NC}"
    echo -e "   Application: $ONELIST_HOME/app"
    echo -e "   Config:      $ONELIST_HOME/.env"
    echo -e "   Storage:     $ONELIST_HOME/storage"
    echo -e "   Setup tool:  $ONELIST_HOME/setup.sh"
    echo
    echo -e "⚙️  ${BLUE}Next steps:${NC}"
    echo -e "   1. Visit http://localhost:4000 to create your account"
    echo -e "   2. Run sudo -u $ONELIST_USER $ONELIST_HOME/setup.sh for optional features"
    echo -e "   3. See $ONELIST_HOME/app/docs/DEPLOYMENT.md for advanced configuration"
    echo
    if [[ -f "$ONELIST_HOME/.env" ]]; then
        echo -e "💡 ${YELLOW}Optional enhancements:${NC}"
        if ! grep -q "^OPENAI_API_KEY=" "$ONELIST_HOME/.env" 2>/dev/null || grep -q "^OPENAI_API_KEY=$" "$ONELIST_HOME/.env" 2>/dev/null; then
            echo -e "   • Add OpenAI API key for semantic search and AI features"
        fi
        echo -e "   • Configure OAuth providers for social login"
        echo -e "   • Set up reverse proxy (nginx) for custom domain"
        echo -e "   • Configure backup scripts for data protection"
        echo
    fi
    echo -e "📚 ${BLUE}Documentation:${NC} https://onelist.my/docs"
    echo -e "💬 ${BLUE}Support:${NC} https://onelist.my/support"
    echo
}

# Cleanup function for rollback on error
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        error "Installation failed. Cleaning up..."
        
        # Stop service if running
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            sudo systemctl stop "$SERVICE_NAME" || true
        fi
        
        # Don't remove database or user to avoid data loss
        warn "Partial installation remains. Run with --force to clean up and retry."
    fi
    exit $exit_code
}

# Main installation function
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Parse arguments
    parse_args "$@"
    
    echo -e "${GREEN}Onelist Native Installer${NC}"
    echo "Installing Onelist with native dependencies..."
    echo
    
    # Pre-installation checks
    check_root
    detect_os
    check_requirements
    check_existing
    
    if [[ "$FORCE_REINSTALL" == "true" ]]; then
        remove_existing
    fi
    
    # Installation steps
    install_dependencies
    create_user
    setup_database
    clone_application
    install_app_dependencies
    generate_config
    compile_application
    setup_schema
    create_service
    start_service
    
    # Post-installation
    create_setup_script
    verify_installation
    
    # Success!
    print_success
}

# Run main function with all arguments
main "$@"