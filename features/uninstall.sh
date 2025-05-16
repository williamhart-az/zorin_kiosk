#!/bin/bash

# ZorinOS Kiosk Uninstall Script

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

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

# Define kiosk user's home directory
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"

echo "[INFO] Starting uninstallation of ZorinOS Kiosk setup..."

# 1. Disable and remove systemd services
echo "[INFO] Disabling and removing systemd services..."

# Firefox ownership fix service
if systemctl is-enabled firefox-ownership-fix.service &>/dev/null; then
  echo "[DEBUG] Disabling firefox-ownership-fix.service"
  systemctl disable firefox-ownership-fix.service
fi
if [ -f "/etc/systemd/system/firefox-ownership-fix.service" ]; then
  echo "[DEBUG] Removing /etc/systemd/system/firefox-ownership-fix.service"
  rm -f "/etc/systemd/system/firefox-ownership-fix.service"
fi

# Firefox periodic fix service and timer
if systemctl is-enabled firefox-periodic-fix.timer &>/dev/null; then
  echo "[DEBUG] Disabling firefox-periodic-fix.timer"
  systemctl disable firefox-periodic-fix.timer
  systemctl stop firefox-periodic-fix.timer
fi
if [ -f "/etc/systemd/system/firefox-periodic-fix.timer" ]; then
  echo "[DEBUG] Removing /etc/systemd/system/firefox-periodic-fix.timer"
  rm -f "/etc/systemd/system/firefox-periodic-fix.timer"
fi
if systemctl is-enabled firefox-periodic-fix.service &>/dev/null; then
  echo "[DEBUG] Disabling firefox-periodic-fix.service"
  systemctl disable firefox-periodic-fix.service
fi
if [ -f "/etc/systemd/system/firefox-periodic-fix.service" ]; then
  echo "[DEBUG] Removing /etc/systemd/system/firefox-periodic-fix.service"
  rm -f "/etc/systemd/system/firefox-periodic-fix.service"
fi

# Var ownership fix service
if systemctl is-enabled var-ownership-fix.service &>/dev/null; then
  echo "[DEBUG] Disabling var-ownership-fix.service"
  systemctl disable var-ownership-fix.service
fi
if [ -f "/etc/systemd/system/var-ownership-fix.service" ]; then
  echo "[DEBUG] Removing /etc/systemd/system/var-ownership-fix.service"
  rm -f "/etc/systemd/system/var-ownership-fix.service"
fi

# Reload systemd to apply changes
echo "[DEBUG] Reloading systemd daemon"
systemctl daemon-reload

# 2. Remove sudoers entries
echo "[INFO] Removing sudoers entries..."
if [ -f "/etc/sudoers.d/kiosk-firefox" ]; then
  echo "[DEBUG] Removing /etc/sudoers.d/kiosk-firefox"
  rm -f "/etc/sudoers.d/kiosk-firefox"
fi
if [ -f "/etc/sudoers.d/kiosk-firefox-fix" ]; then
  echo "[DEBUG] Removing /etc/sudoers.d/kiosk-firefox-fix"
  rm -f "/etc/sudoers.d/kiosk-firefox-fix"
fi

# 3. Remove scripts from /opt/kiosk
echo "[INFO] Removing kiosk scripts from $OPT_KIOSK_DIR..."
if [ -d "$OPT_KIOSK_DIR" ]; then
  echo "[DEBUG] Removing $OPT_KIOSK_DIR directory"
  rm -rf "$OPT_KIOSK_DIR"
fi

# 4. Remove kiosk user's autostart entries
echo "[INFO] Removing kiosk user's autostart entries..."
AUTOSTART_DIR="$KIOSK_USER_HOME/.config/autostart"
if [ -f "$AUTOSTART_DIR/firefox-profile-fix.desktop" ]; then
  echo "[DEBUG] Removing $AUTOSTART_DIR/firefox-profile-fix.desktop"
  rm -f "$AUTOSTART_DIR/firefox-profile-fix.desktop"
fi

# 5. Ask if the kiosk user should be removed
echo ""
echo "[PROMPT] Do you want to remove the kiosk user '$KIOSK_USERNAME'? (y/n)"
read -r remove_user
if [[ "$remove_user" =~ ^[Yy]$ ]]; then
  echo "[INFO] Removing kiosk user '$KIOSK_USERNAME'..."
  
  # Check if the user is currently logged in
  if who | grep -q "^$KIOSK_USERNAME "; then
    echo "[WARNING] User $KIOSK_USERNAME is currently logged in. Cannot remove while user is active."
    echo "[WARNING] Please log out the user and run this script again to remove the user account."
  else
    # Remove any tmpfs mounts for the user's home directory
    if grep -q "$KIOSK_USER_HOME" /etc/fstab; then
      echo "[DEBUG] Removing tmpfs entry from /etc/fstab"
      sed -i "\#$KIOSK_USER_HOME#d" /etc/fstab
    fi
    
    # Remove the user and their home directory
    echo "[DEBUG] Deleting user $KIOSK_USERNAME and home directory"
    userdel -r "$KIOSK_USERNAME" 2>/dev/null || true
    
    # Remove any remaining home directory if userdel didn't remove it
    if [ -d "$KIOSK_USER_HOME" ]; then
      echo "[DEBUG] Removing $KIOSK_USER_HOME directory"
      rm -rf "$KIOSK_USER_HOME"
    fi
    
    echo "[INFO] Kiosk user removed successfully."
  fi
else
  echo "[INFO] Keeping kiosk user account."
fi

# 6. Disable autologin if configured
echo "[INFO] Checking for autologin configurations..."

# Check for LightDM configuration
if [ -f "/etc/lightdm/lightdm.conf" ]; then
  echo "[DEBUG] Checking LightDM configuration"
  if grep -q "autologin-user=$KIOSK_USERNAME" "/etc/lightdm/lightdm.conf"; then
    echo "[DEBUG] Removing autologin from LightDM configuration"
    sed -i "/autologin-user=$KIOSK_USERNAME/d" "/etc/lightdm/lightdm.conf"
    sed -i "/autologin-user-timeout=0/d" "/etc/lightdm/lightdm.conf"
  fi
fi

# Check for GDM configuration
if [ -f "/etc/gdm3/custom.conf" ]; then
  echo "[DEBUG] Checking GDM configuration"
  if grep -q "AutomaticLoginEnable=true" "/etc/gdm3/custom.conf"; then
    echo "[DEBUG] Removing autologin from GDM configuration"
    sed -i "s/AutomaticLoginEnable=true/AutomaticLoginEnable=false/" "/etc/gdm3/custom.conf"
    sed -i "/AutomaticLogin=$KIOSK_USERNAME/d" "/etc/gdm3/custom.conf"
  fi
fi

# Check for SDDM configuration
if [ -f "/etc/sddm.conf" ]; then
  echo "[DEBUG] Checking SDDM configuration"
  if grep -q "User=$KIOSK_USERNAME" "/etc/sddm.conf"; then
    echo "[DEBUG] Removing autologin from SDDM configuration"
    sed -i "/User=$KIOSK_USERNAME/d" "/etc/sddm.conf"
    sed -i "/Session=/d" "/etc/sddm.conf"
  fi
fi

echo "[INFO] Uninstallation complete!"
echo "[INFO] You may need to reboot your system for all changes to take effect."
echo "[INFO] Recommended: sudo reboot"