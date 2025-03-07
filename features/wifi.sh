#!/bin/bash

# ZorinOS Kiosk WiFi Setup Script
# Feature: Hide network settings from kiosk user and configure WiFi

echo "[DEBUG] Starting wifi.sh script"
echo "[DEBUG] Script path: $(readlink -f "$0")"
echo "[DEBUG] Current directory: $(pwd)"

# Exit on any error
set -e
echo "[DEBUG] Error handling enabled with 'set -e'"

# Check if running as root
echo "[DEBUG] Checking if script is running as root"
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Please use sudo."
  exit 1
fi
echo "[DEBUG] Script is running as root, continuing"

# Source the environment file
echo "[DEBUG] Checking for environment file"
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env"
  echo "[DEBUG] ENV_FILE not defined, using default: $ENV_FILE"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")"
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/.env"
        echo "[DEBUG] Looking for .env next to kiosk_setup.sh: $ENV_FILE"
        break
      fi
    done
  fi
fi

echo "[DEBUG] Checking if environment file exists at: $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  echo "[ERROR] Environment file not found at $ENV_FILE"
  echo "[ERROR] Please specify the correct path using the ENV_FILE variable."
  exit 1
fi

echo "[DEBUG] Sourcing environment file: $ENV_FILE"
source "$ENV_FILE"
echo "[DEBUG] Environment file sourced successfully"

# Hide network settings from kiosk user
echo "[DEBUG] Feature: Restricting network settings access"

# Check if dconf is installed
echo "[DEBUG] Checking if dconf is installed"
if ! command -v dconf &> /dev/null; then
  echo "[DEBUG] dconf not found, installing dconf-cli package"
  apt update && apt install -y dconf-cli || {
    echo "[ERROR] Failed to install dconf-cli. Network settings restrictions may not work properly."
    # Continue script execution despite error
  }
fi
echo "[DEBUG] dconf is available"

# Create a policy to hide network settings from standard users
echo "[DEBUG] Creating dconf profile directory"
mkdir -p /etc/dconf/profile/
echo "[DEBUG] Writing user profile configuration"
echo "user-db:user
system-db:local" > /etc/dconf/profile/user

# Create directory for dconf database files
echo "[DEBUG] Creating dconf database directory"
mkdir -p /etc/dconf/db/local.d/

# Create network settings restrictions
echo "[DEBUG] Creating network settings restrictions file"
cat > /etc/dconf/db/local.d/00-network << EOF
[org/gnome/nm-applet]
disable-connected-notifications=true
disable-disconnected-notifications=true
suppress-wireless-networks-available=true

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF
echo "[DEBUG] Network settings restrictions file created"

# Create locks to prevent user from changing these settings
echo "[DEBUG] Creating dconf locks directory"
mkdir -p /etc/dconf/db/local.d/locks/
echo "[DEBUG] Creating network settings locks file"
cat > /etc/dconf/db/local.d/locks/network << EOF
/org/gnome/nm-applet/disable-connected-notifications
/org/gnome/nm-applet/disable-disconnected-notifications
/org/gnome/nm-applet/suppress-wireless-networks-available
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF
echo "[DEBUG] Network settings locks file created"

# Update the dconf database
echo "[DEBUG] Updating dconf database"
dconf update || {
  echo "[ERROR] Failed to update dconf database. Network settings restrictions may not be applied."
  # Continue script execution despite error
}

echo "[DEBUG] Network settings restrictions applied successfully"

# Function to configure WiFi
configure_wifi() {
  local ssid="$1"
  local password="$2"
  
  echo "[DEBUG] Configuring WiFi connection for SSID: $ssid"
  
  # Check if NetworkManager is installed
  echo "[DEBUG] Checking if NetworkManager is installed"
  if command -v nmcli &> /dev/null; then
    echo "[DEBUG] NetworkManager found, proceeding with configuration"
    
    # Properly escape special characters in password for nmcli
    echo "[DEBUG] Escaping special characters in password"
    local escaped_password=$(printf '%s\n' "$password" | sed 's/[\/&]/\\&/g; s/[$]/\\$/g; s/["]/\\"/g; s/[`]/\\`/g')
    
    # Check if connection already exists
    echo "[DEBUG] Checking if connection already exists"
    if nmcli connection show | grep -q "$ssid"; then
      echo "[DEBUG] WiFi connection for $ssid already exists, updating password"
      nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$escaped_password" || {
        echo "[ERROR] Error updating WiFi connection. Please check your credentials."
        # Continue script execution despite error
      }
    else
      echo "[DEBUG] Creating new WiFi connection for $ssid"
      nmcli device wifi connect "$ssid" password "$escaped_password" || {
        echo "[ERROR] Error creating WiFi connection. Please check your credentials and signal strength."
        # Continue script execution despite error
      }
    fi
    
    # Set connection to autoconnect if connection exists
    echo "[DEBUG] Checking if connection exists to set autoconnect"
    if nmcli connection show | grep -q "$ssid"; then
      echo "[DEBUG] Setting $ssid to autoconnect"
      nmcli connection modify "$ssid" connection.autoconnect yes
      echo "[DEBUG] WiFi configuration completed successfully"
    else
      echo "[ERROR] WiFi connection not found after configuration attempt"
    fi
    return 0
  else
    echo "[DEBUG] NetworkManager not found, attempting to install"
    if apt update && apt install -y network-manager; then
      echo "[DEBUG] NetworkManager installed, restarting service"
      systemctl restart NetworkManager
      
      # Wait for NetworkManager to start
      echo "[DEBUG] Waiting for NetworkManager to initialize"
      sleep 5
      
      # Verify NetworkManager is running
      echo "[DEBUG] Verifying NetworkManager is running"
      if systemctl is-active --quiet NetworkManager; then
        echo "[DEBUG] NetworkManager is running, configuring WiFi"
        
        # Properly escape special characters in password
        echo "[DEBUG] Escaping special characters in password"
        local escaped_password=$(printf '%s\n' "$password" | sed 's/[\/&]/\\&/g; s/[$]/\\$/g; s/["]/\\"/g; s/[`]/\\`/g')
        
        # Configure WiFi
        echo "[DEBUG] Connecting to WiFi network"
        nmcli device wifi connect "$ssid" password "$escaped_password" || {
          echo "[ERROR] Error creating WiFi connection. Please check your credentials and signal strength."
          # Continue script execution despite error
        }
        
        # Set connection to autoconnect if connection exists
        echo "[DEBUG] Checking if connection exists to set autoconnect"
        if nmcli connection show | grep -q "$ssid"; then
          echo "[DEBUG] Setting $ssid to autoconnect"
          nmcli connection modify "$ssid" connection.autoconnect yes
          echo "[DEBUG] WiFi configuration completed successfully"
        else
          echo "[ERROR] WiFi connection not found after configuration attempt"
        fi
      else
        echo "[ERROR] NetworkManager service failed to start. WiFi configuration skipped."
        return 1
      fi
    else
      echo "[ERROR] Failed to install NetworkManager. WiFi configuration skipped."
      return 1
    fi
  fi
  return 0
}

# Configure WiFi
echo "[DEBUG] Feature: WiFi Configuration"
echo "[DEBUG] Checking WiFi configuration settings"

# Check if WiFi credentials are provided
echo "[DEBUG] Checking if WiFi credentials are provided in environment file"
if [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PASSWORD" ]; then
  echo "[DEBUG] WiFi credentials not provided in environment file, skipping WiFi setup"
else
  echo "[DEBUG] WiFi credentials found, SSID: $WIFI_SSID"
  # Print environment variables for debugging
  echo "[DEBUG] WIFI_SSID=$WIFI_SSID"
  # Don't print the actual password for security reasons
  echo "[DEBUG] WIFI_PASSWORD=********"
  
  # Call the WiFi configuration function
  echo "[DEBUG] Calling WiFi configuration function"
  configure_wifi "$WIFI_SSID" "$WIFI_PASSWORD"
  echo "[DEBUG] WiFi configuration function completed with status: $?"
fi

echo "[DEBUG] WiFi setup script completed"