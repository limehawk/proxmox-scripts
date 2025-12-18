#!/bin/bash
# 3CX SBC Manager - Install or Upgrade
# WARNING: Run this INSIDE your VM, not on the Proxmox host!

set -e

tred=$(tput setaf 1)
tgreen=$(tput setaf 2)
tyellow=$(tput setaf 3)
tcyan=$(tput setaf 6)
tdef=$(tput sgr0)

function fail() {
    echo -e "${tred}Error: $1${tdef}" >&2
    exit 1
}

function warn() {
    echo -e "${tyellow}Warning: $1${tdef}"
}

function success() {
    echo -e "${tgreen}$1${tdef}"
}

function info() {
    echo -e "${tcyan}$1${tdef}"
}

# Check if running as root
[[ $EUID -eq 0 ]] || fail "This script must be run as root"

# Check Debian version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "debian" ]]; then
        fail "This script requires Debian. Detected: $ID"
    fi
    if [[ "$VERSION_ID" -lt 12 ]]; then
        fail "3CX SBC requires Debian 12 (Bookworm) or later. Detected: Debian $VERSION_ID"
    fi
else
    fail "Cannot detect OS version"
fi

echo "Detected: Debian $VERSION_ID ($VERSION_CODENAME)"
echo ""

# Check if 3CX SBC is already installed
IS_INSTALLED=false
CURRENT_VERSION=""
if dpkg -l 3cxsbc &>/dev/null; then
    IS_INSTALLED=true
    CURRENT_VERSION=$(dpkg -l 3cxsbc | awk '/3cxsbc/{print $3}')
fi

# Determine action
ACTION=""
if [[ "$1" == "install" ]] || [[ "$1" == "upgrade" ]]; then
    ACTION="$1"
else
    if [[ "$IS_INSTALLED" == "true" ]]; then
        info "3CX SBC is installed (version: $CURRENT_VERSION)"
        echo ""
        echo "What would you like to do?"
        echo "  1) Upgrade to latest version"
        echo "  2) Reinstall"
        echo "  3) Exit"
        echo ""
        read -p "Select option [1-3]: " choice
        case $choice in
            1) ACTION="upgrade" ;;
            2) ACTION="install" ;;
            3) echo "Exiting."; exit 0 ;;
            *) fail "Invalid selection" ;;
        esac
    else
        info "3CX SBC is not installed"
        echo ""
        read -p "Install 3CX SBC? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            echo "Exiting."
            exit 0
        fi
        ACTION="install"
    fi
fi

# Repository setup function
setup_repository() {
    KEYRING_PATH="/usr/share/keyrings/3cx-archive-keyring.gpg"
    SOURCES_PATH="/etc/apt/sources.list.d/3cxpbx.list"
    NEEDS_UPDATE=false

    # Check for legacy apt-key
    if apt-key list 2>/dev/null | grep -qi "3cx"; then
        echo "Migrating from legacy apt-key to modern keyring..."
        apt-key del "$(apt-key list 2>/dev/null | grep -B1 -i 3cx | head -1 | awk '{print $NF}')" 2>/dev/null || true
        NEEDS_UPDATE=true
    fi

    # Check if sources file needs updating
    if [[ -f "$SOURCES_PATH" ]]; then
        if grep -q "downloads-global.3cx.com" "$SOURCES_PATH" || ! grep -q "signed-by" "$SOURCES_PATH"; then
            NEEDS_UPDATE=true
        fi
    else
        NEEDS_UPDATE=true
    fi

    if [[ "$NEEDS_UPDATE" == "true" ]]; then
        echo "Configuring 3CX repository..."
        wget -qO- https://repo.3cx.com/key.pub | gpg --dearmor | tee "$KEYRING_PATH" > /dev/null
        echo "deb [arch=amd64 by-hash=yes signed-by=$KEYRING_PATH] http://repo.3cx.com/3cx bookworm main" > "$SOURCES_PATH"
        success "Repository configured"
    else
        echo "Repository already configured correctly"
    fi
}

# Backup function
backup_config() {
    CONFIG_FILE="/etc/3cxsbc.conf"
    if [[ -f "$CONFIG_FILE" ]]; then
        BACKUP_DIR="/root/3cxsbc-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$CONFIG_FILE" "$BACKUP_DIR/"
        success "Configuration backed up to $BACKUP_DIR"
        echo "$BACKUP_DIR"
    fi
}

# Install function
do_install() {
    echo ""
    echo "Installing 3CX SBC..."
    echo ""

    setup_repository

    echo "Updating package lists..."
    apt-get update

    echo "Installing 3cxsbc package..."
    apt-get -y install 3cxsbc || fail "Installation failed"

    systemctl restart 3cxsbc
    sleep 3

    if systemctl is-active --quiet 3cxsbc; then
        NEW_VERSION=$(dpkg -l 3cxsbc | awk '/3cxsbc/{print $3}')
        echo ""
        success "3CX SBC installed successfully!"
        echo ""
        echo "Version: $NEW_VERSION"
        echo ""
        echo "Next steps:"
        echo "  1. Get your Provisioning URL and Auth Key from 3CX Management Console"
        echo "  2. Configure at: /etc/3cxsbc.conf"
        echo "  3. Or use: 3cxsbc --config"
        echo ""
    else
        fail "3CX SBC service failed to start"
    fi
}

# Upgrade function
do_upgrade() {
    echo ""
    echo "Upgrading 3CX SBC..."
    echo ""

    BACKUP_PATH=$(backup_config)

    echo "Stopping service..."
    systemctl stop 3cxsbc || warn "Service was not running"

    setup_repository

    echo "Updating package lists..."
    apt-get update

    echo "Upgrading 3cxsbc package..."
    apt-get -y install --only-upgrade 3cxsbc || apt-get -y install 3cxsbc

    echo "Starting service..."
    systemctl start 3cxsbc
    sleep 3

    if systemctl is-active --quiet 3cxsbc; then
        NEW_VERSION=$(dpkg -l 3cxsbc | awk '/3cxsbc/{print $3}')
        echo ""
        success "3CX SBC upgraded successfully!"
        echo ""
        echo "Previous version: $CURRENT_VERSION"
        echo "Current version:  $NEW_VERSION"
        if [[ -n "$BACKUP_PATH" ]]; then
            echo "Config backup:    $BACKUP_PATH"
        fi
        echo ""
    else
        fail "3CX SBC service failed to start after upgrade"
    fi
}

# Execute action
case $ACTION in
    install) do_install ;;
    upgrade) do_upgrade ;;
    *) fail "Unknown action: $ACTION" ;;
esac
