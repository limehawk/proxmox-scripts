#!/bin/bash

# Variables
IMAGE_URL=$(whiptail --inputbox 'Enter the URL for the DietPi image (default: https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bookworm.qcow2.xz):' 8 78 'https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bookworm.qcow2.xz' --title 'DietPi Installation' 3>&1 1>&2 2>&3)
RAM=$(whiptail --inputbox 'Enter the amount of RAM (in MB) for the new virtual machine (default: 2048):' 8 78 2048 --title 'DietPi Installation' 3>&1 1>&2 2>&3)
CORES=$(whiptail --inputbox 'Enter the number of cores for the new virtual machine (default: 2):' 8 78 2 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# Install xz-utils if missing
dpkg-query -s xz-utils &> /dev/null || { echo 'Installing xz-utils for DietPi image decompression'; apt-get update; apt-get -y install xz-utils; }

# Get the next available VMID
ID=$(pvesh get /cluster/nextid)

touch "/etc/pve/qemu-server/$ID.conf"

# Since you're using ZFS, set qm_disk_param for ZFS storage
qm_disk_param="local-zfs:vm-$ID-disk-0"

# Download DietPi image
wget "$IMAGE_URL"

# Decompress the image
IMAGE_NAME=${IMAGE_URL##*/}
xz -d "$IMAGE_NAME"
IMAGE_NAME=${IMAGE_NAME%.xz}
sleep 3

# import the qcow2 file to the default virtual machine storage
qm importdisk "$ID" "$IMAGE_NAME" "local-zfs" || { echo "Error importing disk"; exit 1; }

# Set vm settings
qm set "$ID" --cores "$CORES" || { echo "Error setting cores"; exit 1; }
qm set "$ID" --memory "$RAM" || { echo "Error setting memory"; exit 1; }
qm set "$ID" --net0 'virtio,bridge=vmbr0' || { echo "Error setting net0"; exit 1; }

# Since you're using ZFS, ensure the correct disk is attached
if ! qm config "$ID" | grep -q "$qm_disk_param"; then
    echo "Disk $qm_disk_param not found for VM $ID."
    exit 1
fi

# Attach the disk as SCSI device
qm set "$ID" --scsi0 "$qm_disk_param" || { echo "Error attaching SCSI disk"; exit 1; }
qm set "$ID" --boot order=scsi0 || { echo "Error setting boot order"; exit 1; }
qm set "$ID" --scsihw virtio-scsi-pci || { echo "Error setting SCSI hardware"; exit 1; }
qm set "$ID" --name 'dietpi' >/dev/null
qm set "$ID" --description '### [DietPi Website](https://dietpi.com/)
### [DietPi Docs](https://dietpi.com/docs/)  
### [DietPi Forum](https://dietpi.com/forum/)
### [DietPi Blog](https://dietpi.com/blog/)' >/dev/null

# Tell user the virtual machine is created  
echo "VM $ID Created."

# Start the virtual machine
qm start "$ID"
