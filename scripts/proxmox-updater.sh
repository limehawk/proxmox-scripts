#!/bin/bash

set -e

echo "Starting Proxmox VE Update: $(date)"

# Update package lists using Proxmox wrapper
pveupdate

# Full upgrade using Proxmox wrapper
pveupgrade --shell -y

# Check if a reboot is required
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required. Shutting down running VMs..."

    # Shut down running VMs
    for vmid in $(qm list | awk 'NR>1 && $3=="running" {print $1}'); do
        echo "Shutting down VM $vmid"
        qm shutdown $vmid
    done

    # Optional: wait longer for all VMs to fully power off
    sleep 60

    # Make sure no VMs are still running
    if qm list | grep -q running; then
        echo "Some VMs are still running, waiting an additional 120 seconds..."
        sleep 120
    fi

    echo "Rebooting the host..."
    reboot
else
    echo "No reboot required."
fi

echo "Proxmox VE Update complete: $(date)"
