#!/bin/bash
# 3CX SBC VM Provisioner for Proxmox
# Creates a VM for 3CX Session Border Controller
# Run this ON the Proxmox host

set -e

tred=$(tput setaf 1)
tgreen=$(tput setaf 2)
tyellow=$(tput setaf 3)
tcyan=$(tput setaf 6)
tdef=$(tput sgr0)

function fail() {
    echo -e "${tred}Error: $1${tdef}" >&2
    cleanup
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

# Cleanup function
cleanup() {
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# Check if running on Proxmox
if ! command -v qm &>/dev/null; then
    fail "This script must be run on a Proxmox host"
fi

echo ""
info "╔════════════════════════════════════════╗"
info "║     3CX SBC VM Provisioner             ║"
info "╚════════════════════════════════════════╝"
echo ""

# Choose installation method
METHOD=$(whiptail --title "3CX SBC VM" --menu "Select installation method:" 14 70 3 \
    "iso"    "Official 3CX ISO (manual setup, guaranteed compatibility)" \
    "auto"   "Automated install (Debian cloud image + apt)" \
    "dietpi" "DietPi base (lightweight, then install 3CX manually)" \
    3>&1 1>&2 2>&3) || exit 1

# Get next available VMID
VMID=$(pvesh get /cluster/nextid)
info "Using VMID: $VMID"

# Common VM Configuration
RAM=$(whiptail --inputbox "Enter RAM in MB:" 8 50 2048 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1
CORES=$(whiptail --inputbox "Enter CPU cores:" 8 50 2 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1
STORAGE=$(whiptail --inputbox "Enter storage name:" 8 50 "local-lvm" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1
BRIDGE=$(whiptail --inputbox "Enter network bridge:" 8 50 "vmbr0" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1
HOSTNAME=$(whiptail --inputbox "Enter VM hostname:" 8 50 "3cx-sbc" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1

echo ""
echo "Configuration:"
echo "  Method:   $METHOD"
echo "  VMID:     $VMID"
echo "  RAM:      ${RAM}MB"
echo "  Cores:    $CORES"
echo "  Storage:  $STORAGE"
echo "  Bridge:   $BRIDGE"
echo "  Hostname: $HOSTNAME"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

case $METHOD in
    iso)
        # Download official 3CX Debian ISO
        ISO_URL="https://downloads-global.3cx.com/downloads/debian12iso/debian-amd64-netinst-3cx.iso"
        ISO_NAME="debian-amd64-netinst-3cx.iso"
        ISO_STORAGE="local"  # ISOs typically go to local storage

        echo "Downloading official 3CX Debian 12 ISO..."
        if ! wget -q --show-progress "$ISO_URL"; then
            fail "Failed to download 3CX ISO"
        fi

        # Move ISO to Proxmox ISO storage
        ISO_PATH="/var/lib/vz/template/iso/$ISO_NAME"
        mv "$ISO_NAME" "$ISO_PATH"

        # Create VM with ISO attached
        echo "Creating VM $VMID..."
        qm create "$VMID" \
            --name "$HOSTNAME" \
            --memory "$RAM" \
            --cores "$CORES" \
            --net0 "virtio,bridge=$BRIDGE" \
            --scsihw virtio-scsi-pci \
            --scsi0 "${STORAGE}:20,discard=on,ssd=1" \
            --ide2 "${ISO_STORAGE}:iso/$ISO_NAME,media=cdrom" \
            --boot order='ide2;scsi0' \
            --ostype l26 \
            --agent enabled=1

        DESCRIPTION='
<p align="center">
<strong>3CX SBC</strong> (Official ISO)
<br>
Boot and select "SBC" during 3CX setup
<br><br>
<a href="https://www.3cx.com/docs/3cx-tunnel-session-border-controller/">Documentation</a>
</p>
'
        qm set "$VMID" --description "$DESCRIPTION"

        echo ""
        success "VM $VMID created with 3CX ISO attached!"
        echo ""
        echo "Next steps:"
        echo "  1. Start VM: qm start $VMID"
        echo "  2. Open console: qm terminal $VMID (or use Proxmox web UI)"
        echo "  3. Follow Debian installer"
        echo "  4. After reboot, select 'SBC' when asked what to install"
        echo "  5. Enter your Provisioning URL and Auth Key"
        echo ""
        echo "After installation, you can remove the ISO:"
        echo "  qm set $VMID --ide2 none"
        echo ""
        ;;

    auto)
        # Automated installation with Debian cloud image
        DEBIAN_IMAGE="debian-12-generic-amd64.qcow2"
        DEBIAN_URL="https://cloud.debian.org/images/cloud/bookworm/latest/$DEBIAN_IMAGE"

        # Get root password
        ROOT_PASSWORD=$(whiptail --passwordbox "Enter root password for VM:" 8 50 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1
        ROOT_PASSWORD_CONFIRM=$(whiptail --passwordbox "Confirm root password:" 8 50 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 1

        if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
            fail "Passwords do not match"
        fi

        echo "Downloading Debian 12 cloud image..."
        if ! wget -q --show-progress "$DEBIAN_URL"; then
            fail "Failed to download Debian cloud image"
        fi

        echo "Resizing disk to 20GB..."
        qemu-img resize "$DEBIAN_IMAGE" 20G

        echo "Creating VM $VMID..."
        qm create "$VMID" \
            --name "$HOSTNAME" \
            --memory "$RAM" \
            --cores "$CORES" \
            --net0 "virtio,bridge=$BRIDGE" \
            --scsihw virtio-scsi-pci \
            --ostype l26 \
            --agent enabled=1

        echo "Importing disk..."
        qm importdisk "$VMID" "$DEBIAN_IMAGE" "$STORAGE" --format qcow2

        DISK_PATH=$(qm config "$VMID" | awk '/unused0/{print $2;exit}')
        qm set "$VMID" --scsi0 "$DISK_PATH,discard=on,ssd=1"
        qm set "$VMID" --boot order=scsi0
        qm set "$VMID" --serial0 socket --vga serial0
        qm set "$VMID" --ide2 "${STORAGE}:cloudinit"

        # Create cloud-init user-data
        mkdir -p /var/lib/vz/snippets

        cat > "/var/lib/vz/snippets/3cx-sbc-${VMID}.yaml" << EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
chpasswd:
  expire: false
  users:
    - name: root
      password: $(echo "$ROOT_PASSWORD" | openssl passwd -6 -stdin)
      type: RANDOM
ssh_pwauth: true
disable_root: false
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - wget
  - gnupg
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - wget -qO- https://repo.3cx.com/key.pub | gpg --dearmor | tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null
  - echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx bookworm main" > /etc/apt/sources.list.d/3cxpbx.list
  - apt-get update
  - apt-get -y install 3cxsbc
  - systemctl enable 3cxsbc
  - systemctl restart 3cxsbc
EOF

        qm set "$VMID" --cicustom "user=local:snippets/3cx-sbc-${VMID}.yaml"
        qm set "$VMID" --ipconfig0 ip=dhcp

        DESCRIPTION='
<p align="center">
<strong>3CX SBC</strong> (Automated)
<br>
3CX SBC auto-installs on first boot
<br><br>
<a href="https://www.3cx.com/docs/3cx-tunnel-session-border-controller/">Documentation</a>
</p>
'
        qm set "$VMID" --description "$DESCRIPTION"

        echo ""
        success "VM $VMID created!"
        echo ""
        echo "3CX SBC will auto-install on first boot (takes 2-5 min)."
        echo ""
        echo "Start VM: qm start $VMID"
        echo "Console:  qm terminal $VMID"
        echo ""
        echo "After boot, configure 3CX:"
        echo "  SSH as root, then run: 3cxsbc --config"
        echo ""
        ;;

    dietpi)
        # DietPi base - user installs 3CX manually
        echo ""
        info "DietPi method selected."
        echo ""
        echo "This will guide you to create a DietPi VM."
        echo "After DietPi setup, SSH in and run:"
        echo ""
        echo "  wget -qO- https://repo.3cx.com/key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null"
        echo "  echo 'deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx bookworm main' | sudo tee /etc/apt/sources.list.d/3cxpbx.list"
        echo "  sudo apt update && sudo apt install 3cxsbc"
        echo "  sudo 3cxsbc --config"
        echo ""

        if whiptail --yesno "Launch DietPi VM installer now?" 8 50 --title "3CX SBC VM"; then
            # Run the DietPi installer
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [[ -f "$SCRIPT_DIR/dietpi-install.sh" ]]; then
                bash "$SCRIPT_DIR/dietpi-install.sh"
            else
                bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/dietpi-install.sh)
            fi
        fi
        exit 0
        ;;
esac

# Offer to start VM
if whiptail --yesno "Start VM $VMID now?" 8 40 --title "3CX SBC VM"; then
    qm start "$VMID"
    success "VM $VMID started!"
fi
