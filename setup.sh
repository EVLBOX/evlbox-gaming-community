#!/usr/bin/env bash
# Gaming Community in a Box — Phase 2: Setup Wizard
# Customer runs this on first SSH login.
# TUI wizard (whiptail) collects config, picks optional services, and starts everything.

set -euo pipefail

STACK_DIR="/opt/evlbox/stack"
STOAT_DIR="/opt/evlbox/stoat"
ENV_FILE="$STACK_DIR/.env"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root: sudo evlbox setup"
        exit 1
    fi
}

check_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq whiptail
    fi
}

# Build Caddyfile from template based on enabled profiles
generate_caddyfile() {
    local profiles="$1"
    cp "$STACK_DIR/templates/Caddyfile.template" "$STACK_DIR/templates/Caddyfile"

    # Remove blocks for disabled services
    for svc in forum blog screenshots paste; do
        local tag
        tag=$(echo "$svc" | tr '[:lower:]' '[:upper:]')
        if [[ ! ",$profiles," == *",$svc,"* ]]; then
            sed -i "/##${tag}_START##/,/##${tag}_END##/d" "$STACK_DIR/templates/Caddyfile"
        else
            # Remove the marker lines, keep the content
            sed -i "/##${tag}_START##/d; /##${tag}_END##/d" "$STACK_DIR/templates/Caddyfile"
        fi
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
check_root
check_whiptail

cd "$STACK_DIR"

TERM=ansi
export TERM

whiptail --title "EVLBOX — Gaming Community in a Box" --msgbox \
"Welcome to the Gaming Community in a Box setup wizard!\n\n\
This will configure your self-hosted gaming community.\n\
Stoat (Discord-like chat) is the core service.\n\
You'll choose which optional services to enable.\n\n\
Press OK to begin." 14 60

# ---- Domain ----
DOMAIN=$(whiptail --title "Domain Configuration" --inputbox \
"Enter your domain name (e.g., gaming.example.com).\n\n\
Stoat chat will be at: chat.DOMAIN\n\
Other services get subdomains based on your choices.\n\n\
Leave blank for IP-only mode (self-signed cert)." 14 60 "" 3>&1 1>&2 2>&3) || true

if [ -z "$DOMAIN" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    DOMAIN="$SERVER_IP"
    whiptail --title "IP-Only Mode" --msgbox \
    "Running in IP-only mode at $SERVER_IP.\n\
Services will use self-signed certificates.\n\
You can add a domain later by editing .env and restarting." 10 60
fi

# ---- Admin Email ----
ADMIN_EMAIL=$(whiptail --title "Admin Email" --inputbox \
"Enter your admin email address.\n\
Used for SSL certificates and admin accounts." 10 60 "admin@${DOMAIN}" 3>&1 1>&2 2>&3) || true

# ---- Service Selection ----
SELECTED=$(whiptail --title "Choose Your Services" --checklist \
"Stoat (chat) is always installed. Pick your extras:\n\
Use SPACE to toggle, ENTER to confirm." 18 65 5 \
"forum"         "Flarum — Community forum"              ON \
"voice"         "Mumble — Low-latency voice chat"       ON \
"screenshots"   "Zipline — Screenshot & image hosting"  ON \
"paste"         "PrivateBin — Encrypted paste service"  ON \
"blog"          "Ghost — Community blog / news"          OFF \
3>&1 1>&2 2>&3) || true

# Parse selections into comma-separated profile list
PROFILES=""
for item in $SELECTED; do
    item=$(echo "$item" | tr -d '"')
    if [ -z "$PROFILES" ]; then
        PROFILES="$item"
    else
        PROFILES="$PROFILES,$item"
    fi
done

# If nothing selected, that's fine — just Stoat
if [ -z "$PROFILES" ]; then
    whiptail --title "Minimal Install" --msgbox \
    "No optional services selected.\n\
Only Stoat (chat) will be installed.\n\
You can enable services later with: evlbox enable <service>" 10 60
fi

# ---- Generate passwords ----
MARIADB_ROOT_PW=$(generate_password)
FLARUM_DB_PW=$(generate_password)
FLARUM_ADMIN_PW=$(generate_password)
GHOST_DB_PW=$(generate_password)
ZIPLINE_SECRET=$(generate_password)
MUMBLE_PW=$(generate_password)

# ---- Customize passwords for selected services ----
if [[ ",$PROFILES," == *",forum,"* ]]; then
    if whiptail --title "Flarum Admin" --yesno \
    "Set a custom Flarum admin password?\n(Otherwise one will be auto-generated)" 10 60; then
        FLARUM_ADMIN_PW=$(whiptail --title "Flarum Admin Password" --passwordbox \
        "Enter your Flarum forum admin password (min 8 characters):" 10 60 3>&1 1>&2 2>&3) || true
        if [ ${#FLARUM_ADMIN_PW} -lt 8 ]; then
            FLARUM_ADMIN_PW=$(generate_password)
            whiptail --title "Password" --msgbox "Password too short. Auto-generated one will be used." 8 60
        fi
    fi
fi

if [[ ",$PROFILES," == *",voice,"* ]]; then
    if whiptail --title "Mumble Voice Chat" --yesno \
    "Set a custom Mumble SuperUser password?\n(Used to administer voice channels)" 10 60; then
        MUMBLE_PW=$(whiptail --title "Mumble SuperUser Password" --passwordbox \
        "Enter Mumble SuperUser password:" 10 60 3>&1 1>&2 2>&3) || true
    fi
fi

# ---- Write .env ----
cat > "$ENV_FILE" << EOF
# Gaming Community in a Box — Generated by setup.sh
# $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Active service profiles (comma-separated)
COMPOSE_PROFILES=${PROFILES}

DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}

# MariaDB (used by forum and blog)
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PW}

# Flarum
FLARUM_DB_NAME=flarum
FLARUM_DB_USER=flarum
FLARUM_DB_PASSWORD=${FLARUM_DB_PW}
FLARUM_ADMIN_USER=admin
FLARUM_ADMIN_PASSWORD=${FLARUM_ADMIN_PW}
FLARUM_ADMIN_EMAIL=${ADMIN_EMAIL}

# Ghost
GHOST_DB_NAME=ghost
GHOST_DB_USER=ghost
GHOST_DB_PASSWORD=${GHOST_DB_PW}

# Zipline
ZIPLINE_CORE_SECRET=${ZIPLINE_SECRET}

# Mumble
MUMBLE_SUPERUSER_PASSWORD=${MUMBLE_PW}
EOF

chmod 600 "$ENV_FILE"

# ---- Create MariaDB init script (only matters if forum or blog enabled) ----
mkdir -p "$STACK_DIR/templates/initdb"
cat > "$STACK_DIR/templates/initdb/init.sql" << EOF
CREATE DATABASE IF NOT EXISTS \`flarum\`;
CREATE USER IF NOT EXISTS 'flarum'@'%' IDENTIFIED BY '${FLARUM_DB_PW}';
GRANT ALL PRIVILEGES ON \`flarum\`.* TO 'flarum'@'%';

CREATE DATABASE IF NOT EXISTS \`ghost\`;
CREATE USER IF NOT EXISTS 'ghost'@'%' IDENTIFIED BY '${GHOST_DB_PW}';
GRANT ALL PRIVILEGES ON \`ghost\`.* TO 'ghost'@'%';

FLUSH PRIVILEGES;
EOF

# ---- Generate Caddyfile from template ----
generate_caddyfile "$PROFILES"

# ---- Configure Stoat ----
whiptail --title "Setting up Stoat" --infobox \
"Configuring Stoat chat platform...\nThis generates encryption keys and config." 8 60

if [ -d "$STOAT_DIR" ]; then
    # Create shared Docker network for cross-compose communication
    docker network create evlbox 2>/dev/null || true

    # Copy our override to disable Stoat's built-in Caddy
    cp "$STACK_DIR/templates/stoat-compose.override.yml" "$STOAT_DIR/compose.override.yml"

    cd "$STOAT_DIR"
    # Run Stoat's own config generator with our domain
    if [ -f "$STOAT_DIR/generate_config.sh" ]; then
        bash "$STOAT_DIR/generate_config.sh" <<< "$DOMAIN"
    fi
else
    echo "WARNING: Stoat directory not found at $STOAT_DIR"
    echo "Stoat should have been cloned during provisioning."
fi

# ---- Register Stoat as additional compose project for evlbox CLI ----
cat > "$STACK_DIR/.compose-projects" << 'EOF'
# Additional compose projects managed by this stack
/opt/evlbox/stoat/compose.yml
EOF

# ---- Save credentials file ----
CREDS_FILE="/root/evlbox-credentials.txt"
{
    echo "=== EVLBOX Gaming Community in a Box — Credentials ==="
    echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    echo "Domain: ${DOMAIN}"
    echo "Admin Email: ${ADMIN_EMAIL}"
    echo "Enabled Services: Stoat${PROFILES:+, }${PROFILES//,/, }"
    echo ""
    echo "--- Service URLs ---"
    echo "Chat: https://chat.${DOMAIN}"
    [[ ",$PROFILES," == *",forum,"* ]]        && echo "Forum:        https://forum.${DOMAIN}"
    [[ ",$PROFILES," == *",blog,"* ]]         && echo "Blog:         https://blog.${DOMAIN}"
    [[ ",$PROFILES," == *",screenshots,"* ]]  && echo "Screenshots:  https://screenshots.${DOMAIN}"
    [[ ",$PROFILES," == *",paste,"* ]]        && echo "Paste:        https://paste.${DOMAIN}"
    [[ ",$PROFILES," == *",voice,"* ]]        && echo "Voice:        ${DOMAIN}:64738 (Mumble)"
    echo ""
    echo "--- Credentials ---"
    echo "Stoat: Set up at https://chat.${DOMAIN}"
    [[ ",$PROFILES," == *",forum,"* ]]        && echo "Flarum Admin: admin / ${FLARUM_ADMIN_PW}"
    [[ ",$PROFILES," == *",voice,"* ]]        && echo "Mumble SuperUser: SuperUser / ${MUMBLE_PW}"
    [[ ",$PROFILES," == *",blog,"* ]]         && echo "Ghost: Set up at https://blog.${DOMAIN}/ghost"
    [[ ",$PROFILES," == *",screenshots,"* ]]  && echo "Zipline: Set up at https://screenshots.${DOMAIN}"
    echo ""
    echo "--- Internal (do not share) ---"
    echo "MariaDB Root Password: ${MARIADB_ROOT_PW}"
    echo ""
    echo "DELETE THIS FILE after saving your credentials somewhere safe!"
} > "$CREDS_FILE"

chmod 600 "$CREDS_FILE"

# ---- Start services ----
whiptail --title "Starting Services" --infobox \
"Starting your gaming community services...\n\nThis may take a minute on first boot." 8 60

cd "$STOAT_DIR"
docker compose up -d

cd "$STACK_DIR"
docker compose up -d

# ---- Build summary ----
SUMMARY="Your Gaming Community in a Box is running!\n\n"
SUMMARY+="Service URLs:\n"
SUMMARY+="  Chat: https://chat.${DOMAIN}\n"
[[ ",$PROFILES," == *",forum,"* ]]        && SUMMARY+="  Forum:        https://forum.${DOMAIN}\n"
[[ ",$PROFILES," == *",blog,"* ]]         && SUMMARY+="  Blog:         https://blog.${DOMAIN}\n"
[[ ",$PROFILES," == *",screenshots,"* ]]  && SUMMARY+="  Screenshots:  https://screenshots.${DOMAIN}\n"
[[ ",$PROFILES," == *",paste,"* ]]        && SUMMARY+="  Paste:        https://paste.${DOMAIN}\n"
[[ ",$PROFILES," == *",voice,"* ]]        && SUMMARY+="  Voice:        ${DOMAIN}:64738 (Mumble)\n"
SUMMARY+="\nCredentials saved to: /root/evlbox-credentials.txt\n"
SUMMARY+="Delete that file after saving your passwords!\n\n"
SUMMARY+="Run 'evlbox status' to check service health.\n"
SUMMARY+="Run 'evlbox enable <service>' to add services later.\n"
SUMMARY+="Run 'evlbox help' for more commands."

whiptail --title "Setup Complete!" --msgbox "$SUMMARY" 24 62
