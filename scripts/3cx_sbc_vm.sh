#!/bin/bash
#
# ============================================================================
#                         3CX SBC VM PROVISIONER
# ============================================================================
#  Script Name: 3cx_sbc_vm.sh
#  Description: Creates a Proxmox VM for 3CX Session Border Controller with
#               multiple installation methods: Official ISO, automated cloud
#               image, or DietPi base.
#  Author:      Limehawk LLC
#  Version:     1.0.0
#  Date:        December 2024
#  Usage:       ./3cx_sbc_vm.sh
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
#  Provisions a complete Proxmox VM for running 3CX Session Border Controller.
#  Offers three installation methods to suit different needs: official 3CX ISO
#  for guaranteed compatibility, automated Debian cloud image with auto-install,
#  or DietPi as a lightweight base.
#
#  CONFIGURATION
#  -----------------------------------------------------------------------
#  - DEFAULT_RAM: Default RAM allocation in MB
#  - DEFAULT_CORES: Default CPU core count
#  - DEFAULT_STORAGE: Default Proxmox storage name
#  - DEFAULT_BRIDGE: Default network bridge
#  - DEFAULT_HOSTNAME: Default VM hostname
#  - DISK_SIZE: VM disk size
#
#  BEHAVIOR
#  -----------------------------------------------------------------------
#  1. Prompts for installation method (ISO, automated, DietPi)
#  2. Collects VM configuration (RAM, CPU, storage, network)
#  3. Downloads required image (3CX ISO or Debian cloud image)
#  4. Creates and configures Proxmox VM
#  5. Sets up cloud-init for automated method
#  6. Optionally starts the VM
#
#  PREREQUISITES
#  -----------------------------------------------------------------------
#  - Must run ON Proxmox host (not inside VM)
#  - Root access required
#  - Network connectivity for image downloads
#  - whiptail for interactive menus
#  - Sufficient storage space
#
#  SECURITY NOTES
#  -----------------------------------------------------------------------
#  - Root password for automated method is hashed before storage
#  - Cloud-init snippets stored in /var/lib/vz/snippets/
#  - Temporary files cleaned up on exit
#
#  EXIT CODES
#  -----------------------------------------------------------------------
#  0 - Success
#  1 - Failure (error occurred)
#
#  EXAMPLE OUTPUT
#  -----------------------------------------------------------------------
#  === 3CX SBC VM PROVISIONER ===
#  --------------------------------------------------------------
#
#  === CONFIGURATION ===
#  --------------------------------------------------------------
#  Method: auto
#  VMID: 105
#  RAM: 2048 MB
#  Cores: 2
#  Storage: local-lvm
#  Bridge: vmbr0
#  Hostname: 3cx-sbc
#
#  === DOWNLOAD ===
#  --------------------------------------------------------------
#  Downloading Debian 12 cloud image...
#  Download complete
#
#  === VM CREATION ===
#  --------------------------------------------------------------
#  Creating VM 105...
#  Importing disk...
#  Configuring cloud-init...
#  VM created
#
#  === RESULT ===
#  --------------------------------------------------------------
#  Status: Success
#  VMID: 105
#  Start command: qm start 105
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
DEFAULT_RAM="2048"                 # Default RAM in MB
DEFAULT_CORES="2"                  # Default CPU cores
DEFAULT_STORAGE="local-lvm"        # Default Proxmox storage
DEFAULT_BRIDGE="vmbr0"             # Default network bridge
DEFAULT_HOSTNAME="3cx-sbc"         # Default VM hostname
DISK_SIZE="20G"                    # VM disk size

# Image URLs
ISO_URL="https://downloads-global.3cx.com/downloads/debian12iso/debian-amd64-netinst-3cx.iso"
DEBIAN_CLOUD_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
DIETPI_SCRIPT_URL="https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/dietpi_install.sh"

# 3CX Repository
REPO_KEY_URL="https://repo.3cx.com/key.pub"
REPO_LINE="deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx bookworm main"
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Cleanup temporary files
cleanup() {
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

echo ""
echo "=== 3CX SBC VM PROVISIONER ==="
echo "--------------------------------------------------------------"

# Check if running on Proxmox
if ! command -v qm &>/dev/null; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "This script must be run on a Proxmox host"
    echo "qm command not found"
    echo ""
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "This script must be run as root"
    echo ""
    exit 1
fi

# Choose installation method
METHOD=$(whiptail --title "3CX SBC VM" --menu "Select installation method:" 14 70 3 \
    "iso"    "Official 3CX ISO (manual setup, guaranteed compatibility)" \
    "auto"   "Automated install (Debian cloud image + apt)" \
    "dietpi" "DietPi base (lightweight, then install 3CX manually)" \
    3>&1 1>&2 2>&3)

if [[ $? -ne 0 ]]; then
    echo "Cancelled"
    exit 0
fi

# Get next available VMID
VMID=$(pvesh get /cluster/nextid)

# Collect VM configuration
RAM=$(whiptail --inputbox "Enter RAM in MB:" 8 50 "$DEFAULT_RAM" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0
CORES=$(whiptail --inputbox "Enter CPU cores:" 8 50 "$DEFAULT_CORES" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0
STORAGE=$(whiptail --inputbox "Enter storage name:" 8 50 "$DEFAULT_STORAGE" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0
BRIDGE=$(whiptail --inputbox "Enter network bridge:" 8 50 "$DEFAULT_BRIDGE" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0
HOSTNAME=$(whiptail --inputbox "Enter VM hostname:" 8 50 "$DEFAULT_HOSTNAME" --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0

echo ""
echo "=== CONFIGURATION ==="
echo "--------------------------------------------------------------"
echo "Method: $METHOD"
echo "VMID: $VMID"
echo "RAM: $RAM MB"
echo "Cores: $CORES"
echo "Storage: $STORAGE"
echo "Bridge: $BRIDGE"
echo "Hostname: $HOSTNAME"

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

case $METHOD in
    iso)
        echo ""
        echo "=== DOWNLOAD ==="
        echo "--------------------------------------------------------------"
        echo "Downloading official 3CX Debian 12 ISO..."

        ISO_NAME="debian-amd64-netinst-3cx.iso"
        if ! wget -q --show-progress "$ISO_URL"; then
            echo ""
            echo "=== ERROR OCCURRED ==="
            echo "--------------------------------------------------------------"
            echo "Failed to download 3CX ISO"
            echo "URL: $ISO_URL"
            echo ""
            exit 1
        fi
        echo "Download complete"

        # Move ISO to Proxmox ISO storage
        ISO_PATH="/var/lib/vz/template/iso/$ISO_NAME"
        mv "$ISO_NAME" "$ISO_PATH"

        echo ""
        echo "=== VM CREATION ==="
        echo "--------------------------------------------------------------"
        echo "Creating VM $VMID..."

        qm create "$VMID" \
            --name "$HOSTNAME" \
            --memory "$RAM" \
            --cores "$CORES" \
            --net0 "virtio,bridge=$BRIDGE" \
            --scsihw virtio-scsi-pci \
            --scsi0 "${STORAGE}:20,discard=on,ssd=1" \
            --ide2 "local:iso/$ISO_NAME,media=cdrom" \
            --boot order='ide2;scsi0' \
            --ostype l26 \
            --agent enabled=1

        qm set "$VMID" --description "<p align=\"center\"><strong>3CX SBC</strong> (Official ISO)<br>Boot and select SBC during setup</p>"

        echo "VM created"

        echo ""
        echo "=== RESULT ==="
        echo "--------------------------------------------------------------"
        echo "Status: Success"
        echo "VMID: $VMID"
        echo ""
        echo "=== NEXT STEPS ==="
        echo "--------------------------------------------------------------"
        echo "1. Start VM: qm start $VMID"
        echo "2. Open console in Proxmox web UI"
        echo "3. Follow Debian installer"
        echo "4. After reboot, select 'SBC' when asked"
        echo "5. Enter Provisioning URL and Auth Key"
        echo ""
        echo "Remove ISO after install: qm set $VMID --ide2 none"
        ;;

    auto)
        # Get root password
        ROOT_PASSWORD=$(whiptail --passwordbox "Enter root password for VM:" 8 50 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0
        ROOT_PASSWORD_CONFIRM=$(whiptail --passwordbox "Confirm root password:" 8 50 --title "3CX SBC VM" 3>&1 1>&2 2>&3) || exit 0

        if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
            echo ""
            echo "=== ERROR OCCURRED ==="
            echo "--------------------------------------------------------------"
            echo "Passwords do not match"
            echo ""
            exit 1
        fi

        echo ""
        echo "=== DOWNLOAD ==="
        echo "--------------------------------------------------------------"
        echo "Downloading Debian 12 cloud image..."

        DEBIAN_IMAGE="debian-12-generic-amd64.qcow2"
        if ! wget -q --show-progress "$DEBIAN_CLOUD_URL"; then
            echo ""
            echo "=== ERROR OCCURRED ==="
            echo "--------------------------------------------------------------"
            echo "Failed to download Debian cloud image"
            echo ""
            exit 1
        fi
        echo "Download complete"

        echo "Resizing disk to $DISK_SIZE..."
        qemu-img resize "$DEBIAN_IMAGE" "$DISK_SIZE"

        echo ""
        echo "=== VM CREATION ==="
        echo "--------------------------------------------------------------"
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

        echo "Configuring cloud-init..."
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
  - wget -qO- $REPO_KEY_URL | gpg --dearmor | tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null
  - echo "$REPO_LINE" > /etc/apt/sources.list.d/3cxpbx.list
  - apt-get update
  - apt-get -y install 3cxsbc
  - systemctl enable 3cxsbc
  - systemctl restart 3cxsbc
EOF

        qm set "$VMID" --cicustom "user=local:snippets/3cx-sbc-${VMID}.yaml"
        qm set "$VMID" --ipconfig0 ip=dhcp
        qm set "$VMID" --description "<p align=\"center\"><strong>3CX SBC</strong> (Automated)<br>3CX SBC auto-installs on first boot</p>"

        echo "VM created"

        echo ""
        echo "=== RESULT ==="
        echo "--------------------------------------------------------------"
        echo "Status: Success"
        echo "VMID: $VMID"
        echo "3CX SBC will auto-install on first boot (2-5 min)"
        echo ""
        echo "=== NEXT STEPS ==="
        echo "--------------------------------------------------------------"
        echo "1. Start VM: qm start $VMID"
        echo "2. Wait for cloud-init to complete"
        echo "3. SSH as root: ssh root@<vm-ip>"
        echo "4. Configure: 3cxsbc --config"
        ;;

    dietpi)
        echo ""
        echo "=== DIETPI METHOD ==="
        echo "--------------------------------------------------------------"
        echo "This will launch the DietPi VM installer."
        echo ""
        echo "After DietPi setup, SSH in and run:"
        echo ""
        echo "  wget -qO- $REPO_KEY_URL | gpg --dearmor | sudo tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null"
        echo "  echo '$REPO_LINE' | sudo tee /etc/apt/sources.list.d/3cxpbx.list"
        echo "  sudo apt update && sudo apt install 3cxsbc"
        echo "  sudo 3cxsbc --config"

        if whiptail --yesno "Launch DietPi VM installer now?" 8 50 --title "3CX SBC VM"; then
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [[ -f "$SCRIPT_DIR/dietpi_install.sh" ]]; then
                bash "$SCRIPT_DIR/dietpi_install.sh"
            else
                bash <(curl -sSfL "$DIETPI_SCRIPT_URL")
            fi
        fi
        exit 0
        ;;
esac

# Offer to start VM
if whiptail --yesno "Start VM $VMID now?" 8 40 --title "3CX SBC VM"; then
    echo ""
    echo "=== STARTING VM ==="
    echo "--------------------------------------------------------------"
    qm start "$VMID"
    echo "VM $VMID started"
fi

echo ""
echo "=== SCRIPT COMPLETE ==="
echo "--------------------------------------------------------------"
echo ""

exit 0
