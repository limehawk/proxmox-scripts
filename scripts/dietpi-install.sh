#!/bin/bash

# Variables for image URL, RAM, and Cores
IMAGE_URL=$(whiptail --inputbox 'Enter the URL for the DietPi image (default: https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bookworm.qcow2.xz):' 8 78 'https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bookworm.qcow2.xz' --title 'DietPi Installation' 3>&1 1>&2 2>&3)
RAM=$(whiptail --inputbox 'Enter the amount of RAM (in MB) for the new virtual machine (default: 2048):' 8 78 2048 --title 'DietPi Installation' 3>&1 1>&2 2>&3)
CORES=$(whiptail --inputbox 'Enter the number of cores for the new virtual machine (default: 2):' 8 78 2 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# Prompt for storage location
STORAGE_LOCATION=$(whiptail --inputbox 'Enter the storage location (default: local-zfs):' 8 78 'local-zfs' --title 'Storage Location' 3>&1 1>&2 2>&3)

# Install xz-utils if missing
dpkg-query -s xz-utils &> /dev/null || { echo 'Installing xz-utils for DietPi image decompression'; apt-get update; apt-get -y install xz-utils; }

# Get the next available VMID
ID=$(pvesh get /cluster/nextid)

# Create the configuration file for the new VM
touch "/etc/pve/qemu-server/$ID.conf"

# Set disk parameter for the specified storage
qm_disk_param="${STORAGE_LOCATION}:vm-$ID-disk-0"

# Download DietPi image
wget "$IMAGE_URL"

# Decompress the image
IMAGE_NAME=${IMAGE_URL##*/}
xz -d "$IMAGE_NAME"
IMAGE_NAME=${IMAGE_NAME%.xz}
sleep 3

# Import the qcow2 file to the specified storage
qm importdisk "$ID" "$IMAGE_NAME" "$STORAGE_LOCATION" || { echo "Error importing disk"; exit 1; }

# Set VM settings
qm set "$ID" --cores "$CORES" || { echo "Error setting cores"; exit 1; }
qm set "$ID" --memory "$RAM" || { echo "Error setting memory"; exit 1; }
qm set "$ID" --net0 'virtio,bridge=vmbr0' || { echo "Error setting net0"; exit 1; }

# Ensure the correct disk is attached
if ! qm config "$ID" | grep -q "$qm_disk_param"; then
    echo "Disk $qm_disk_param not found for VM $ID."
    exit 1
fi

# Attach the disk as SCSI device
qm set "$ID" --scsi0 "$qm_disk_param" || { echo "Error attaching SCSI disk"; exit 1; }
qm set "$ID" --boot order=scsi0 || { echo "Error setting boot order"; exit 1; }
qm set "$ID" --scsihw virtio-scsi-pci || { echo "Error setting SCSI hardware"; exit 1; }
qm set "$ID" --name 'dietpi' >/dev/null

# Set VM description with dynamic values
qm set "$ID" --description "
# DietPi VM - Managed by Limehawk

**Quick Links:**
- **[DietPi Website](https://dietpi.com/)**
- **[Documentation](https://dietpi.com/docs/)**
- **[Community Forum](https://dietpi.com/forum/)**
- **[Latest News](https://dietpi.com/blog/)**

## Features
- Fast and Reliable VM Solutions
- Enhanced Security Features
- Performance Optimized

## Configuration Details
| Property | Value |
|----------|-------|
| Cores    | $CORES |
| Memory   | ${RAM}MB |
| Network  | virtio, bridge=vmbr0 |
| Storage  | $STORAGE_LOCATION |

_**Note:** This VM is powered by **Limehawk**. For more information and support, visit our [website](https://limehawk.io)._ 
" >/dev/null

# Inform user that the virtual machine is created
echo "VM $ID Created."

# Start the virtual machine
qm start "$ID"
