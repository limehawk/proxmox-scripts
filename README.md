# Proxmox Scripts

A collection of scripts for Proxmox Virtual Environment (PVE).

## Quick Start

### DietPi VM Installer
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/dietpi-install.sh)
```
Interactive menu with all available DietPi images (Trixie, Bookworm, Forky + UEFI variants).

### 3CX SBC VM Provisioner
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/3cx_sbc_vm.sh)
```
Creates a VM for 3CX Session Border Controller with three methods:
- **Official ISO** - Downloads 3CX Debian ISO, manual setup
- **Automated** - Debian cloud image with auto-install via cloud-init
- **DietPi** - Use DietPi as base, install 3CX manually

### 3CX SBC Manager (In-VM)
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/3cx_sbc_manager.sh)
```
> **Note:** Run inside your VM, not on the Proxmox host.

Install or upgrade 3CX SBC on existing Debian 12 systems.

### Proxmox Updater
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/proxmox_updater.sh)
```
Automated updates with safe VM shutdown and reboot if needed.

## Documentation

📖 **[Full documentation on the Wiki](https://github.com/limehawk/proxmox-scripts/wiki)**

## Script Sources

| Script | Source |
|--------|--------|
| dietpi-install.sh | [limehawk/proxmox-dietpi-installer](https://github.com/limehawk/proxmox-dietpi-installer) |

Scripts are automatically synced from their source repos via GitHub Actions.
