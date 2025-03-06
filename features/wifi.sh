#!/bin/bash

# ZorinOS Kiosk WiFi Setup Script
# Feature: Hide network settings from kiosk user

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Hide network settings from kiosk user
echo "Restricting network settings access..."

# Create a policy to hide network settings from standard users
mkdir -p /etc/dconf/profile/
echo "user-db:user
system-db:local" > /etc/dconf/profile/user

# Create directory for dconf database files
mkdir -p /etc/dconf/db/local.d/

# Create network settings restrictions
cat > /etc/dconf/db/local.d/00-network << EOF
[org/gnome/nm-applet]
disable-connected-notifications=true
disable-disconnected-notifications=true
suppress-wireless-networks-available=true

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF

# Create locks to prevent user from changing these settings
mkdir -p /etc/dconf/db/local.d/locks/
cat > /etc/dconf/db/local.d/locks/network << EOF
/org/gnome/nm-applet/disable-connected-notifications
/org/gnome/nm-applet/disable-disconnected-notifications
/org/gnome/nm-applet/suppress-wireless-networks-available
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF

# Update the dconf database
dconf update

echo "Network settings restrictions applied successfully."

# Optional: Configure a static WiFi connection if needed
# This section can be uncommented and configured if you want to set up a specific WiFi connection

# if [ ! -z "$WIFI_SSID" ] && [ ! -z "$WIFI_PASSWORD" ]; then
#   echo "Setting up WiFi connection for SSID: $WIFI_SSID"
#   
#   # Create a NetworkManager connection file
#   cat > /etc/NetworkManager/system-connections/"$WIFI_SSID".nmconnection << EOF
# [connection]
# id=$WIFI_SSID
# uuid=$(uuidgen)
# type=wifi
# autoconnect=true
# permissions=
# 
# [wifi]
# mac-address-blacklist=
# mode=infrastructure
# ssid=$WIFI_SSID
# 
# [wifi-security]
# auth-alg=open
# key-mgmt=wpa-psk
# psk=$WIFI_PASSWORD
# 
# [ipv4]
# dns-search=
# method=auto
# 
# [ipv6]
# addr-gen-mode=stable-privacy
# dns-search=
# method=auto
# 
# [proxy]
# EOF
# 
#   # Set proper permissions for the connection file
#   chmod 600 /etc/NetworkManager/system-connections/"$WIFI_SSID".nmconnection
#   
#   # Restart NetworkManager to apply changes
#   systemctl restart NetworkManager
#   
#   echo "WiFi connection for $WIFI_SSID configured successfully."
# else
#   echo "No WiFi credentials provided in environment file. Skipping WiFi setup."
# fi