#!/bin/bash
#
# ============================================================================
#                         PROXMOX VE UPDATER
# ============================================================================
#  Script Name: proxmox_updater.sh
#  Description: Automated Proxmox VE updates with safe VM shutdown and
#               optional reboot when kernel updates require it.
#  Author:      Limehawk LLC
#  Version:     1.0.0
#  Date:        December 2024
#  Usage:       ./proxmox_updater.sh
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
#  Automates the Proxmox VE update process including package list refresh,
#  full system upgrade, and safe handling of reboots when required. When a
#  reboot is needed, all running VMs are gracefully shut down first.
#
#  CONFIGURATION
#  -----------------------------------------------------------------------
#  - VM_SHUTDOWN_WAIT: Initial wait time for VMs to shut down (seconds)
#  - VM_SHUTDOWN_EXTENDED: Extended wait if VMs still running (seconds)
#
#  BEHAVIOR
#  -----------------------------------------------------------------------
#  1. Updates package lists using pveupdate
#  2. Performs full upgrade using pveupgrade
#  3. Checks if reboot is required
#  4. If reboot needed: gracefully shuts down all running VMs
#  5. Waits for VMs to fully power off
#  6. Reboots the host
#
#  PREREQUISITES
#  -----------------------------------------------------------------------
#  - Root access required
#  - Must run on Proxmox VE host (not inside a VM)
#  - Network connectivity for package downloads
#
#  SECURITY NOTES
#  -----------------------------------------------------------------------
#  - Requires root privileges
#  - VMs will need manual restart after reboot (or configure auto-start)
#
#  EXIT CODES
#  -----------------------------------------------------------------------
#  0 - Success (update complete, no reboot needed)
#  1 - Failure (error occurred)
#  Note: Script does not return if reboot is performed
#
#  EXAMPLE OUTPUT
#  -----------------------------------------------------------------------
#  === PROXMOX UPDATER ===
#  --------------------------------------------------------------
#  Started: Thu Dec 18 10:30:00 UTC 2024
#
#  === PACKAGE UPDATE ===
#  --------------------------------------------------------------
#  Running pveupdate...
#  Package lists updated
#
#  === SYSTEM UPGRADE ===
#  --------------------------------------------------------------
#  Running pveupgrade...
#  Upgrade complete
#
#  === REBOOT CHECK ===
#  --------------------------------------------------------------
#  Reboot required: No
#
#  === SCRIPT COMPLETE ===
#  --------------------------------------------------------------
#  Proxmox VE update finished successfully
#  Completed: Thu Dec 18 10:35:00 UTC 2024
#
#  CHANGELOG
#  -----------------------------------------------------------------------
#  2024-12-18 v1.0.0 Initial release with Limehawk Style A formatting
#
# ============================================================================

# ============================================================================
# CONFIGURATION SETTINGS - Modify these as needed
# ============================================================================
VM_SHUTDOWN_WAIT=60                # Initial wait time for VM shutdown (seconds)
VM_SHUTDOWN_EXTENDED=120           # Extended wait if VMs still running (seconds)
# ============================================================================

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

echo ""
echo "=== PROXMOX UPDATER ==="
echo "--------------------------------------------------------------"
echo "Started: $(date)"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "This script must be run as root"
    echo ""
    exit 1
fi

# Check if running on Proxmox
if ! command -v pveupdate &>/dev/null; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "pveupdate command not found"
    echo "This script must be run on a Proxmox VE host"
    echo ""
    exit 1
fi

echo ""
echo "=== PACKAGE UPDATE ==="
echo "--------------------------------------------------------------"
echo "Running pveupdate..."

if ! pveupdate; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "pveupdate failed"
    echo ""
    exit 1
fi

echo "Package lists updated"

echo ""
echo "=== SYSTEM UPGRADE ==="
echo "--------------------------------------------------------------"
echo "Running pveupgrade..."

if ! pveupgrade --shell -y; then
    echo ""
    echo "=== ERROR OCCURRED ==="
    echo "--------------------------------------------------------------"
    echo "pveupgrade failed"
    echo ""
    exit 1
fi

echo "Upgrade complete"

echo ""
echo "=== REBOOT CHECK ==="
echo "--------------------------------------------------------------"

if [[ -f /var/run/reboot-required ]]; then
    echo "Reboot required: Yes"
    echo ""
    echo "=== VM SHUTDOWN ==="
    echo "--------------------------------------------------------------"
    echo "Shutting down all running VMs..."

    VM_COUNT=0
    for vmid in $(qm list | awk 'NR>1 && $3=="running" {print $1}'); do
        echo "Shutting down VM $vmid"
        qm shutdown "$vmid"
        ((VM_COUNT++)) || true
    done

    if [[ $VM_COUNT -gt 0 ]]; then
        echo "Initiated shutdown for $VM_COUNT VM(s)"
        echo "Waiting ${VM_SHUTDOWN_WAIT} seconds for VMs to power off..."
        sleep "$VM_SHUTDOWN_WAIT"

        # Check if any VMs still running
        if qm list | grep -q running; then
            echo "Some VMs still running, waiting additional ${VM_SHUTDOWN_EXTENDED} seconds..."
            sleep "$VM_SHUTDOWN_EXTENDED"
        fi
    else
        echo "No running VMs found"
    fi

    echo ""
    echo "=== REBOOTING ==="
    echo "--------------------------------------------------------------"
    echo "Initiating host reboot..."
    echo "VMs will need to be started manually after reboot"
    echo "(or configure auto-start in Proxmox)"
    reboot
else
    echo "Reboot required: No"
fi

echo ""
echo "=== SCRIPT COMPLETE ==="
echo "--------------------------------------------------------------"
echo "Proxmox VE update finished successfully"
echo "Completed: $(date)"
echo ""

exit 0
