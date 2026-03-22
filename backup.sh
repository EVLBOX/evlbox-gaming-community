#!/usr/bin/env bash
# Gaming Community in a Box — Backup Script
# Backs up enabled services only. Reads COMPOSE_PROFILES from .env.
# Stoat (MongoDB) is always backed up via mongodump.
#
# Usage: sudo ./backup.sh
# Called by: evlbox backup, evlbox update (pre-update snapshot)

set -euo pipefail

STACK_DIR="/opt/evlbox/stack"
STOAT_DIR="/opt/evlbox/stoat"
BACKUP_DIR="/opt/evlbox/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="gaming-community-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
RETENTION_DAILY=3
RETENTION_WEEKLY=1
STEP=0

# Load env
if [ -f "$STACK_DIR/.env" ]; then
    # shellcheck source=/dev/null
    source "$STACK_DIR/.env"
else
    echo "ERROR: .env not found. Has setup.sh been run?"
    exit 1
fi

PROFILES="${COMPOSE_PROFILES:-}"

has_profile() {
    [[ ",$PROFILES," == *",$1,"* ]]
}

next_step() {
    STEP=$((STEP + 1))
    echo "[$STEP] $1"
}

echo "=== EVLBOX Backup — Gaming Community ==="
echo "Backup: ${BACKUP_NAME}"
echo "Active profiles: Stoat (always)${PROFILES:+, }${PROFILES//,/, }"

mkdir -p "$BACKUP_PATH"

# -----------------------------------------------------------------------------
# Stoat — MongoDB dump (always)
# -----------------------------------------------------------------------------
next_step "Dumping Stoat MongoDB..."
docker compose -f "$STOAT_DIR/compose.yml" exec -T database \
    mongodump --archive --gzip \
    > "$BACKUP_PATH/stoat-mongo.archive.gz" 2>/dev/null

# -----------------------------------------------------------------------------
# MariaDB dump (if forum or blog enabled)
# -----------------------------------------------------------------------------
if has_profile "forum" || has_profile "blog"; then
    next_step "Dumping MariaDB databases..."
    docker compose -f "$STACK_DIR/compose.yml" exec -T mariadb \
        mariadb-dump --all-databases -u root -p"${MARIADB_ROOT_PASSWORD}" \
        > "$BACKUP_PATH/mariadb-all.sql"
fi

# -----------------------------------------------------------------------------
# Per-service volume backups (only enabled services)
# -----------------------------------------------------------------------------
PROJECT="stack"

backup_volume() {
    local volume_name="$1"
    local archive_name="$2"
    next_step "Backing up ${archive_name}..."
    docker run --rm \
        -v "${PROJECT}_${volume_name}":/data:ro \
        -v "$BACKUP_PATH":/backup \
        alpine tar czf "/backup/${archive_name}.tar.gz" -C /data .
}

if has_profile "voice"; then
    backup_volume "mumble_data" "mumble_data"
fi

if has_profile "forum"; then
    backup_volume "flarum_data" "flarum_data"
fi

if has_profile "blog"; then
    backup_volume "ghost_data" "ghost_data"
fi

if has_profile "screenshots"; then
    backup_volume "zipline_data" "zipline_uploads"
    next_step "Dumping Zipline PostgreSQL..."
    docker compose -f "$STACK_DIR/compose.yml" exec -T zipline-db \
        pg_dump -U zipline zipline \
        > "$BACKUP_PATH/zipline-postgres.sql"
fi

if has_profile "paste"; then
    backup_volume "privatebin_data" "privatebin_data"
fi

# -----------------------------------------------------------------------------
# Archive
# -----------------------------------------------------------------------------
next_step "Creating final archive..."
tar czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

echo "Backup saved: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# -----------------------------------------------------------------------------
# Rotation — keep 3 daily + 1 weekly
# -----------------------------------------------------------------------------
echo "Rotating old backups..."
ls -1t "$BACKUP_DIR"/gaming-community-*.tar.gz 2>/dev/null \
    | tail -n +$((RETENTION_DAILY + RETENTION_WEEKLY + 1)) \
    | xargs -r rm -f

echo "=== Backup complete ==="
