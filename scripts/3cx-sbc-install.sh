#!/bin/bash
# 3CX SBC Installer for Debian 12 Bookworm
# WARNING: Run this INSIDE your VM, not on the Proxmox host!

set -e

tred=$(tput setaf 1)
tgreen=$(tput setaf 2)
tyellow=$(tput setaf 3)
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

# Check and add 3CX repository (modern method)
KEYRING_PATH="/usr/share/keyrings/3cx-archive-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/3cxpbx.list"

if [[ ! -f "$SOURCES_PATH" ]]; then
    echo "Adding 3CX repository..."

    # Download and add GPG key (current 3CX method)
    wget -qO- https://repo.3cx.com/key.pub | gpg --dearmor | tee "$KEYRING_PATH" > /dev/null

    # Add repository with signed-by
    echo "deb [arch=amd64 by-hash=yes signed-by=$KEYRING_PATH] http://repo.3cx.com/3cx bookworm main" > "$SOURCES_PATH"

    success "3CX repository added"
else
    echo "3CX repository already configured"
fi

# Update and install
echo "Updating package lists..."
apt-get update

echo "Installing 3CX SBC..."
apt-get -y install 3cxsbc || fail "Installation of 3cxsbc package failed"

# Start service
systemctl restart 3cxsbc
sleep 3

if systemctl is-active --quiet 3cxsbc; then
    success "3CX SBC installed and running!"
    echo ""
    echo "Next steps:"
    echo "  1. Get your Provisioning URL and Auth Key from 3CX Management Console"
    echo "  2. Configure at: /etc/3cxsbc.conf"
    echo "  3. Or use: 3cxsbc --config"
    echo ""
else
    fail "3CX SBC service failed to start"
fi
