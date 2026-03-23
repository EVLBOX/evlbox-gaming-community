#!/usr/bin/env bash
# Gaming Community in a Box — Phase 1: Provisioning
# VirtFusion runs this automatically at deploy time. Customer never sees it.
#
# What it does:
#   1. Bootstraps minimal Debian (curl, git — needed to fetch everything else)
#   2. Installs evlbox-core (Docker, Compose, UFW, fail2ban, CLI, etc.)
#   3. Clones this stack + Stoat
#   4. Pulls all container images
#   5. Opens Mumble port in firewall
#   6. Replaces core's login banner with stack-specific one

set -euo pipefail

# Paths
STACK_DIR="/opt/evlbox/stack"
STOAT_DIR="/opt/evlbox/stoat"

# Pinned versions — bump these when cutting a release
# TODO: change back to tagged versions (e.g., v1.0.0) before production release
EVLBOX_CORE_TAG="main"
STACK_TAG="main"
STOAT_TAG="main"

echo "=== EVLBOX Gaming Community in a Box — Provisioning ==="

# -----------------------------------------------------------------------------
# 0. Immediate login banner — in case customer SSH's in during provisioning.
#    Uses evlbox-00-stack.sh which loads AFTER core's evlbox.sh (alphabetical).
#    Sets EVLBOX_MOTD_SHOWN=1 early so core's banner is suppressed.
# -----------------------------------------------------------------------------
cat > /etc/profile.d/evlbox-00-stack.sh << 'PROFILE'
#!/usr/bin/env bash
export EVLBOX_MOTD_SHOWN=1
if [ -t 1 ]; then
    C='\033[0;36m'
    B='\033[1m'
    D='\033[2m'
    N='\033[0m'
    echo ""
    echo -e "${C}${B}  ╔═══════════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}${B}  ║            EVLBOX — Gaming Community in a Box                ║${N}"
    echo -e "${C}${B}  ╚═══════════════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "  ${D}Server is still being set up. This takes 2-5 minutes.${N}"
    echo -e "  ${D}Wait a moment, then reconnect or run:${N}  evlbox status"
    echo ""
    echo -e "  ${D}Docs:${N} https://evlbox.com/docs"
    echo ""
fi
PROFILE

# -----------------------------------------------------------------------------
# 1. Bootstrap — just enough to run evlbox-core's installer
# -----------------------------------------------------------------------------
echo "[1/6] Bootstrapping base packages..."
apt-get update -qq
apt-get install -y -qq curl git ca-certificates

# -----------------------------------------------------------------------------
# 2. Install evlbox-core (handles Docker, Compose, UFW, fail2ban, CLI, etc.)
# -----------------------------------------------------------------------------
echo "[2/6] Installing evlbox-core (${EVLBOX_CORE_TAG})..."
curl -fsSL "https://raw.githubusercontent.com/EVLBOX/evlbox-core/${EVLBOX_CORE_TAG}/install.sh" | bash

# -----------------------------------------------------------------------------
# 3. Clone repos
# -----------------------------------------------------------------------------
echo "[3/6] Cloning gaming community stack (${STACK_TAG})..."
git clone --branch "$STACK_TAG" https://github.com/EVLBOX/evlbox-gaming-community.git "$STACK_DIR"

echo "[4/6] Cloning Stoat chat platform (${STOAT_TAG})..."
git clone --branch "$STOAT_TAG" https://github.com/stoatchat/self-hosted.git "$STOAT_DIR"

# -----------------------------------------------------------------------------
# 4. Pull container images
# -----------------------------------------------------------------------------
echo "[5/6] Pulling container images (this may take a few minutes)..."
cd "$STOAT_DIR"
docker compose pull

cd "$STACK_DIR"
COMPOSE_PROFILES=forum,voice,wiki,paste,blog docker compose pull

# -----------------------------------------------------------------------------
# 5. Stack-specific firewall rules (evlbox-core handles SSH, HTTP, HTTPS)
# -----------------------------------------------------------------------------
echo "[6/6] Opening Mumble port..."
ufw allow 64738 comment "Mumble voice chat"

# -----------------------------------------------------------------------------
# 6. Stack-specific login banner (ready for setup version)
# -----------------------------------------------------------------------------
cat > /etc/profile.d/evlbox-00-stack.sh << 'PROFILE'
#!/usr/bin/env bash
export EVLBOX_MOTD_SHOWN=1
if [ -t 1 ]; then
    C='\033[0;36m'
    B='\033[1m'
    D='\033[2m'
    N='\033[0m'
    echo ""
    echo -e "${C}${B}  ╔═══════════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}${B}  ║            EVLBOX — Gaming Community in a Box                ║${N}"
    echo -e "${C}${B}  ╚═══════════════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "  ${D}Get started:${N}   evlbox setup"
    echo -e "  ${D}Check status:${N}  evlbox status"
    echo -e "  ${D}View help:${N}     evlbox help"
    echo ""
    echo -e "  ${D}Docs:${N} https://evlbox.com/docs"
    echo ""
fi
PROFILE

echo "=== Provisioning complete ==="
