#!/bin/bash
#
# ============================================================================
#                         3CX SBC MANAGER
# ============================================================================
#  Script Name: 3cx_sbc_manager.sh
#  Description: Install or upgrade 3CX Session Border Controller on Debian 12.
#               Handles repository configuration, package management, and
#               service verification.
#  Author:      Limehawk LLC
#  Version:     1.0.0
#  Date:        December 2024
#  Usage:       ./3cx_sbc_manager.sh [install|upgrade]
# ============================================================================
#
# ============================================================================
#      ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
#      ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
#      ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
#      ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
#      ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
#      ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
# ============================================================================
#
#  PURPOSE
#  -----------------------------------------------------------------------
#  Manages 3CX Session Border Controller installation and upgrades on
#  Debian 12 systems. Automatically configures the 3CX apt repository using
#  modern GPG keyring method, handles legacy apt-key migrations, and
#  verifies service status after installation.
#
#  CONFIGURATION
#  -----------------------------------------------------------------------
#  - REPO_KEY_URL: URL for 3CX GPG key
#  - REPO_URL: 3CX apt repository URL
#  - KEYRING_PATH: Path to store GPG keyring
#  - SOURCES_PATH: Path to apt sources list
#  - CONFIG_FILE: Path to 3CX SBC configuration
#
#  BEHAVIOR
#  -----------------------------------------------------------------------
#  1. Validates Debian 12+ environment
#  2. Detects if 3CX SBC is already installed
#  3. Prompts for action (install/upgrade) if not specified
#  4. Configures 3CX repository with modern GPG keyring
#  5. Installs or upgrades 3cxsbc package
#  6. Verifies service is running
#  7. Displays next steps for configuration
#
#  PREREQUISITES
#  -----------------------------------------------------------------------
#  - Root access required
#  - Debian 12 (Bookworm) or later
#  - Network connectivity
#  - Run INSIDE VM, not on Proxmox host
#
#  SECURITY NOTES
#  -----------------------------------------------------------------------
#  - Configuration backup stored in /root/
#  - GPG key verified from official 3CX repository
#  - No secrets exposed in output
#
#  EXIT CODES
#  -----------------------------------------------------------------------
#  0 - Success
#  1 - Failure (error occurred)
#
#  EXAMPLE OUTPUT
#  -----------------------------------------------------------------------
#  === 3CX SBC MANAGER ===
#  --------------------------------------------------------------
#  OS: Debian 12 (bookworm)
#  Status: Not installed
#
#  === REPOSITORY SETUP ===
#  --------------------------------------------------------------
#  Configuring 3CX repository...
#  Repository configured
#
#  === INSTALLATION ===
#  --------------------------------------------------------------
#  Updating package lists...
#  Installing 3cxsbc package...
#  Starting service...
#
#  === RESULT ===
#  --------------------------------------------------------------
#  Status: Success
#  Version: 20.0.0.1234
#
#  === NEXT STEPS ===
#  --------------------------------------------------------------
#  1. Get Provisioning URL and Auth Key from 3CX Management Console
#  2. Configure at: /etc/3cxsbc.conf
#  3. Or use: 3cxsbc --config
#
#  === SCRIPT COMPLETE ===
#
#  CHANGELOG
#  -----------------------------------------------------------------------
#  2024-12-18 v1.0.0 Initial release with Limehawk Style A formatting
#
# ============================================================================

# ============================================================================
# CONFIGURATION SETTINGS - Modify these as needed
# ============================================================================
REPO_KEY_URL="https://repo.3cx.com/key.pub"          # 3CX GPG key URL
REPO_URL="http://repo.3cx.com/3cx"                   # 3CX apt repository
KEYRING_PATH="/usr/share/keyrings/3cx-archive-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/3cxpbx.list"
CONFIG_FILE="/etc/3cxsbc.conf"                       # 3CX SBC config file
BACKUP_DIR="/root"                                   # Backup directory base
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Setup or update 3CX repository
setup_repository() {
    local needs_update=false

    # Check for legacy apt-key
    if apt-key list 2>/dev/null | grep -qi "3cx"; then
        echo "Migrating from legacy apt-key to modern keyring..."
        apt-key del "$(apt-key list 2>/dev/null | grep -B1 -i 3cx | head -1 | awk '{print $NF}')" 2>/dev/null || true
        needs_update=true
    fi

    # Check if sources file needs updating
    if [[ -f "$SOURCES_PATH" ]]; then
        if grep -q "downloads-global.3cx.com" "$SOURCES_PATH" || ! grep -q "signed-by" "$SOURCES_PATH"; then
            needs_update=true
        fi
    else
        needs_update=true
    fi

    if [[ "$needs_update" == "true" ]]; then
        echo "Configuring 3CX repository..."
        if ! wget -qO- "$REPO_KEY_URL" | gpg --dearmor | tee "$KEYRING_PATH" > /dev/null; then
            echo ""
            echo "=== ERROR OCCURRED ==="
            echo "--------------------------------------------------------------"
            echo "Failed to download GPG key from $REPO_KEY_URL"
            echo ""
            exit 1
        fi
        echo "deb [arch=amd64 by-hash=yes signed-by=$KEYRING_PATH] $REPO_URL bookworm main" > "$SOURCES_PATH"
        echo "Repository configured"
    else
        echo "Repository already configured"
    fi
}

# Backup configuration file
backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_path="${BACKUP_DIR}/3cxsbc-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_path"
        cp "$CONFIG_FILE" "$backup_path/"
        echo "Configuration backed up to: $backup_path"
        echo "$backup_path"
    fi
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

echo ""
echo "=== 3CX SBC MANAGER ==="
echo "--------------------------------------------------------------"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "This script must be run as root"
    echo ""
    exit 1
fi

# Check Debian version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "debian" ]]; then
        echo ""
        echo "=== ERROR OCCURRED ==="
        echo "--------------------------------------------------------------"
        echo "This script requires Debian"
        echo "Detected: $ID"
        echo ""
        exit 1
    fi
    if [[ "$VERSION_ID" -lt 12 ]]; then
        echo ""
        echo "=== ERROR OCCURRED ==="
        echo "--------------------------------------------------------------"
        echo "3CX SBC requires Debian 12 (Bookworm) or later"
        echo "Detected: Debian $VERSION_ID"
        echo ""
        exit 1
    fi
else
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "Cannot detect OS version"
    echo ""
    exit 1
fi

echo "OS: Debian $VERSION_ID ($VERSION_CODENAME)"

# Check if 3CX SBC is already installed
IS_INSTALLED=false
CURRENT_VERSION=""
if dpkg -l 3cxsbc &>/dev/null; then
    IS_INSTALLED=true
    CURRENT_VERSION=$(dpkg -l 3cxsbc | awk '/3cxsbc/{print $3}')
    echo "Status: Installed (version $CURRENT_VERSION)"
else
    echo "Status: Not installed"
fi

# Determine action
ACTION=""
if [[ "$1" == "install" ]] || [[ "$1" == "upgrade" ]]; then
    ACTION="$1"
else
    echo ""
    if [[ "$IS_INSTALLED" == "true" ]]; then
        echo "Options:"
        echo "  1) Upgrade to latest version"
        echo "  2) Reinstall"
        echo "  3) Exit"
        echo ""
        read -p "Select option [1-3]: " choice
        case $choice in
            1) ACTION="upgrade" ;;
            2) ACTION="install" ;;
            3) echo "Exiting."; exit 0 ;;
            *)
                echo ""
                echo "=== ERROR OCCURRED ==="
                echo "--------------------------------------------------------------"
                echo "Invalid selection: $choice"
                echo ""
                exit 1
                ;;
        esac
    else
        read -p "Install 3CX SBC? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            echo "Exiting."
            exit 0
        fi
        ACTION="install"
    fi
fi

echo ""
echo "=== REPOSITORY SETUP ==="
echo "--------------------------------------------------------------"
setup_repository

if [[ "$ACTION" == "upgrade" ]]; then
    echo ""
    echo "=== BACKUP ==="
    echo "--------------------------------------------------------------"
    BACKUP_PATH=$(backup_config)

    echo ""
    echo "=== SERVICE STOP ==="
    echo "--------------------------------------------------------------"
    echo "Stopping 3CX SBC service..."
    systemctl stop 3cxsbc 2>/dev/null || echo "Service was not running"
fi

echo ""
echo "=== PACKAGE UPDATE ==="
echo "--------------------------------------------------------------"
echo "Updating package lists..."
if ! apt-get update; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "Failed to update package lists"
    echo ""
    exit 1
fi

echo ""
echo "=== INSTALLATION ==="
echo "--------------------------------------------------------------"
if [[ "$ACTION" == "upgrade" ]]; then
    echo "Upgrading 3cxsbc package..."
    apt-get -y install --only-upgrade 3cxsbc || apt-get -y install 3cxsbc
else
    echo "Installing 3cxsbc package..."
    if ! apt-get -y install 3cxsbc; then
        echo ""
        echo "=== ERROR OCCURRED ==="
        echo "--------------------------------------------------------------"
        echo "Failed to install 3cxsbc package"
        echo ""
        exit 1
    fi
fi

echo ""
echo "=== SERVICE START ==="
echo "--------------------------------------------------------------"
echo "Starting 3CX SBC service..."
systemctl restart 3cxsbc
sleep 3

echo ""
echo "=== RESULT ==="
echo "--------------------------------------------------------------"

if systemctl is-active --quiet 3cxsbc; then
    NEW_VERSION=$(dpkg -l 3cxsbc | awk '/3cxsbc/{print $3}')
    echo "Status: Success"
    echo "Version: $NEW_VERSION"
    if [[ "$ACTION" == "upgrade" ]] && [[ -n "$CURRENT_VERSION" ]]; then
        echo "Previous: $CURRENT_VERSION"
    fi
    if [[ -n "$BACKUP_PATH" ]]; then
        echo "Backup: $BACKUP_PATH"
    fi

    echo ""
    echo "=== NEXT STEPS ==="
    echo "--------------------------------------------------------------"
    echo "1. Get Provisioning URL and Auth Key from 3CX Management Console"
    echo "2. Configure at: $CONFIG_FILE"
    echo "3. Or use: 3cxsbc --config"
else
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "3CX SBC service failed to start"
    echo "Check logs with: journalctl -u 3cxsbc"
    echo ""
    exit 1
fi

echo ""
echo "=== SCRIPT COMPLETE ==="
echo "--------------------------------------------------------------"
echo ""

exit 0
