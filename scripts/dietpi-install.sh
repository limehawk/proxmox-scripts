#!/bin/bash

# Version 2.4
# This script automates the creation of a Proxmox VM and imports a DietPi image.
# It includes cleanup steps to remove temporary files after the VM is created.

# ========================================
# Variables
# ========================================

# Prompt user for OS version
OS_VERSION=$(whiptail --title "Select DietPi OS Version" --menu "Choose an OS version" 15 60 4 \
"1" "Debian 12 Bookworm" \
"2" "Debian 11 Bullseye" 3>&1 1>&2 2>&3)

case $OS_VERSION in
    1)
        IMAGE_URL="https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bookworm.qcow2.xz"
        ;;
    2)
        IMAGE_URL="https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bullseye.qcow2.xz"
        ;;
    *)
        echo "Invalid selection"
        exit 1
        ;;
esac

# Prompt user for the amount of RAM for the new VM with a default value
RAM=$(whiptail --inputbox 'Enter the amount of RAM (in MB) for the new virtual machine (default: 2048):' 8 78 2048 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# Prompt user for the number of cores for the new VM with a default value
CORES=$(whiptail --inputbox 'Enter the number of cores for the new virtual machine (default: 2):' 8 78 2 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# ========================================
# Install xz-utils if missing
# ========================================

# Check if xz-utils is installed; if not, install it
dpkg-query -s xz-utils &> /dev/null || { 
    echo 'Installing xz-utils for DietPi image decompression'; 
    apt-get update; 
    apt-get -y install xz-utils; 
}

# ========================================
# Get next available VMID
# ========================================

# Get the next available VMID from Proxmox
ID=$(pvesh get /cluster/nextid)

touch "/etc/pve/qemu-server/$ID.conf"

# ========================================
# Prompt user for storage and filesystem
# ========================================

# Prompt user for the storage name where the image should be imported
STORAGE=$(whiptail --inputbox 'Enter the storage name where the image should be imported:' 8 78 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# Ask user about the filesystem type: BTRFS, ZFS, Directory, or LVM-Thin Provisioning
if (whiptail --title "What filesystem are you installing the VM on?" --yesno "If using BTRFS, ZFS or Directory storage? Select YES\n\nIf using LVM-Thin Provisioning? Select NO" 10 78); then
    use_btrfs="y"
else
    use_btrfs="n"
fi

# Set the disk parameter based on the filesystem type
if [ "$use_btrfs" = "y" ]; then
    qm_disk_param="$STORAGE:$ID/vm-$ID-disk-0.raw"
else
    qm_disk_param="$STORAGE:vm-$ID-disk-0"
fi

# ========================================
# Download and Decompress DietPi Image
# ========================================

# Download the DietPi image from the provided URL to /tmp
wget "$IMAGE_URL" -P /tmp/

# Decompress the downloaded image using xz in /tmp
IMAGE_NAME="/tmp/${IMAGE_URL##*/}"
xz -d "$IMAGE_NAME"
IMAGE_NAME=${IMAGE_NAME%.xz}
sleep 3

# ========================================
# Import Disk and Configure VM
# ========================================

# Import the decompressed qcow2 file to the specified storage
qm importdisk "$ID" "$IMAGE_NAME" "$STORAGE"

# Attach the imported disk to the VM with the correct bus/device type
qm set "$ID" --scsihw virtio-scsi-pci # Ensuring SCSI hardware is set
qm set "$ID" --scsi0 "$STORAGE:vm-$ID-disk-0"  # Correct disk path for attachment

# Set VM settings
qm set "$ID" --cores "$CORES"
qm set "$ID" --memory "$RAM"
qm set "$ID" --net0 'virtio,bridge=vmbr0'
qm set "$ID" --boot order='scsi0'
qm set "$ID" --name 'dietpi' >/dev/null
qm set "$ID" --description '### [DietPi Website](https://dietpi.com/)
### [DietPi Docs](https://dietpi.com/docs/)
### [DietPi Forum](https://dietpi.com/forum/)
### [DietPi Blog](https://dietpi.com/blog/)' >/dev/null

# ========================================
# Finalize and Start VM
# ========================================

# Notify the user that the VM has been created
echo "VM $ID Created."

# Start the newly created VM
qm start "$ID"

# ========================================
# Cleanup
# ========================================

# Remove the downloaded and decompressed image files from /tmp
rm -f /tmp/DietPi_Proxmox*
