# Proxmox Scripts

A collection of scripts for Proxmox Virtual Environment (PVE).

## Quick Start

### DietPi VM Installer
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/dietpi-install.sh)
```
Interactive menu with all available DietPi images (Trixie, Bookworm, Forky + UEFI variants).

### 3CX SBC Installer
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/3cx-sbc-install.sh)
```
> **Note:** Run inside your VM, not on the Proxmox host. Requires Debian 12+.

### Proxmox Updater
```sh
bash <(curl -sSfL https://raw.githubusercontent.com/limehawk/proxmox-scripts/main/scripts/proxmox-updater.sh)
```
Automated updates with safe VM shutdown and reboot if needed.

## Documentation

📖 **[Full documentation on the Wiki](https://github.com/limehawk/proxmox-scripts/wiki)**

## Script Sources

| Script | Source |
|--------|--------|
| dietpi-install.sh | [limehawk/proxmox-dietpi-installer](https://github.com/limehawk/proxmox-dietpi-installer) |

Scripts are automatically synced from their source repos via GitHub Actions.
