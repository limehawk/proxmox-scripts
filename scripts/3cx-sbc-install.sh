# WARNING: DO NOT RUN THIS SCRIPT ON THE HOST. RUN INSIDE YOUR VM. 

#!/bin/bash
# Simplified SBC Install Script with Repository Check

tred=$(tput setaf 1)
tgreen=$(tput setaf 2)
tdef=$(tput sgr0)

# Function to display an error and exit
function fail() {
    echo -e "${tred}error: $1$tdef" >&2
    exit 1
}

# Function to prompt for user input
function prompt() {
    read -p "$1" response
    echo $response
}

# Function to check and add repository if not present
function check_and_add_repo() {
    local repo_url="http://downloads-global.3cx.com/downloads/debian"
    grep -q "$repo_url" /etc/apt/sources.list /etc/apt/sources.list.d/* || {
        echo "Adding 3CX repository"
        echo "deb $repo_url stable main" > /etc/apt/sources.list.d/3cxpbx.list
        wget -qO - "$repo_url/public.key" | apt-key add -
    }
}

# Function to install SBC
function install_sbc() {
    apt-get update && apt-get -y install 3cxsbc || fail "Installation of 3cxsbc package failed"
    systemctl restart 3cxsbc
    systemctl is-active --quiet 3cxsbc || fail "3CXSBC service failed to start"
    echo "${tgreen}3CXSBC is installed and running.$tdef"
}

# Ask for Provisioning URL
pbx_url=$(prompt "Enter the Provisioning URL: ")
[[ "$pbx_url" =~ ^https:\/\/ ]] || fail "Invalid URL. Must start with https://"

# Ask for SBC Authentication KEY ID
pbx_key=$(prompt "Enter the SBC Authentication KEY ID: ")
[ -z "$pbx_key" ] && fail "SBC Authentication KEY ID is required"

# Check and add repository
check_and_add_repo

# Installation
install_sbc

echo "Installation complete. Access the configuration at /etc/3cxsbc.conf"
