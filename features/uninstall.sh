#!/bin/bash

# ZorinOS Kiosk Uninstall Script
# Note: This script does NOT require user_setup.sh to run first

# Exit on any error
set -e

# Function to display messages both to console and log
# This ensures messages are visible regardless of how the script is called
display_message() {
  local message="$1"
  local level="${2:-INFO}"
  
  # Always print to console
  echo "[$level] $message" >&2
  
  # Also echo normally for log capture
  echo "[$level] $message"
}

# Function to get user input with visible prompt
get_user_input() {
  local prompt="$1"
  local response
  
  # Print prompt to stderr so it's visible to user
  echo "$prompt" >&2
  read -r response
  
  echo "$response"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  display_message "This script must be run as root. Please use sudo." "ERROR"
  exit 1
fi

# Source the environment file
display_message "Checking for environment file" "DEBUG"
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env"
  display_message "ENV_FILE not defined, using default: $ENV_FILE" "DEBUG"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")" 
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/.env"
        display_message "Looking for .env next to kiosk_setup.sh: $ENV_FILE" "DEBUG"
        break
      fi
    done
  fi
fi

display_message "Checking if environment file exists at: $ENV_FILE" "DEBUG"
if [ ! -f "$ENV_FILE" ]; then
  display_message "Environment file not found at $ENV_FILE" "ERROR"
  display_message "Please specify the correct path using the ENV_FILE variable." "ERROR"
  exit 1
fi

display_message "Sourcing environment file: $ENV_FILE" "DEBUG"
source "$ENV_FILE"
display_message "Environment file sourced successfully" "DEBUG"

# Define kiosk user's home directory
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"

# Clear screen and show header
clear
echo "===================================================" >&2
echo "           ZORIN OS KIOSK UNINSTALLER            " >&2
echo "===================================================" >&2
echo "" >&2

display_message "Starting uninstallation of ZorinOS Kiosk setup..." "INFO"
display_message "This will remove all kiosk-related configurations and services." "WARNING"
display_message "You will be asked if you want to remove the kiosk user account." "WARNING"
echo "" >&2
echo "Press Enter to continue or Ctrl+C to cancel..." >&2
read

# 1. Disable and remove systemd services
display_message "Disabling and removing systemd services..." "INFO"

# Firefox ownership fix service
if systemctl is-enabled firefox-ownership-fix.service &>/dev/null; then
  display_message "Disabling firefox-ownership-fix.service" "DEBUG"
  systemctl disable firefox-ownership-fix.service
fi
if [ -f "/etc/systemd/system/firefox-ownership-fix.service" ]; then
  display_message "Removing /etc/systemd/system/firefox-ownership-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/firefox-ownership-fix.service"
fi

# Firefox periodic fix service and timer
if systemctl is-enabled firefox-periodic-fix.timer &>/dev/null; then
  display_message "Disabling firefox-periodic-fix.timer" "DEBUG"
  systemctl disable firefox-periodic-fix.timer
  systemctl stop firefox-periodic-fix.timer
fi
if [ -f "/etc/systemd/system/firefox-periodic-fix.timer" ]; then
  display_message "Removing /etc/systemd/system/firefox-periodic-fix.timer" "DEBUG"
  rm -f "/etc/systemd/system/firefox-periodic-fix.timer"
fi
if systemctl is-enabled firefox-periodic-fix.service &>/dev/null; then
  display_message "Disabling firefox-periodic-fix.service" "DEBUG"
  systemctl disable firefox-periodic-fix.service
fi
if [ -f "/etc/systemd/system/firefox-periodic-fix.service" ]; then
  display_message "Removing /etc/systemd/system/firefox-periodic-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/firefox-periodic-fix.service"
fi

# Var ownership fix service
if systemctl is-enabled var-ownership-fix.service &>/dev/null; then
  display_message "Disabling var-ownership-fix.service" "DEBUG"
  systemctl disable var-ownership-fix.service
fi
if [ -f "/etc/systemd/system/var-ownership-fix.service" ]; then
  display_message "Removing /etc/systemd/system/var-ownership-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/var-ownership-fix.service"
fi

# Reload systemd to apply changes
display_message "Reloading systemd daemon" "DEBUG"
systemctl daemon-reload

# 2. Remove sudoers entries
display_message "Removing sudoers entries..." "INFO"
if [ -f "/etc/sudoers.d/kiosk-firefox" ]; then
  display_message "Removing /etc/sudoers.d/kiosk-firefox" "DEBUG"
  rm -f "/etc/sudoers.d/kiosk-firefox"
fi
if [ -f "/etc/sudoers.d/kiosk-firefox-fix" ]; then
  display_message "Removing /etc/sudoers.d/kiosk-firefox-fix" "DEBUG"
  rm -f "/etc/sudoers.d/kiosk-firefox-fix"
fi

# 3. Remove scripts from /opt/kiosk
display_message "Removing kiosk scripts from $OPT_KIOSK_DIR..." "INFO"
if [ -d "$OPT_KIOSK_DIR" ]; then
  display_message "Removing $OPT_KIOSK_DIR directory" "DEBUG"
  rm -rf "$OPT_KIOSK_DIR"
fi

# 4. Remove kiosk user's autostart entries
display_message "Removing kiosk user's autostart entries..." "INFO"
AUTOSTART_DIR="$KIOSK_USER_HOME/.config/autostart"
if [ -f "$AUTOSTART_DIR/firefox-profile-fix.desktop" ]; then
  display_message "Removing $AUTOSTART_DIR/firefox-profile-fix.desktop" "DEBUG"
  rm -f "$AUTOSTART_DIR/firefox-profile-fix.desktop"
fi

# 5. Ask if the kiosk user should be removed
echo "" >&2
echo "===================================================" >&2
echo "                USER REMOVAL PROMPT               " >&2
echo "===================================================" >&2
echo "" >&2

remove_user=$(get_user_input "[PROMPT] Do you want to remove the kiosk user '$KIOSK_USERNAME'? (y/n)")

if [[ "$remove_user" =~ ^[Yy]$ ]]; then
  display_message "Removing kiosk user '$KIOSK_USERNAME'..." "INFO"
  
  # Check if the user is currently logged in
  if who | grep -q "^$KIOSK_USERNAME "; then
    display_message "User $KIOSK_USERNAME is currently logged in. Cannot remove while user is active." "WARNING"
    display_message "Please log out the user and run this script again to remove the user account." "WARNING"
  else
    # Remove any tmpfs mounts for the user's home directory
    if grep -q "$KIOSK_USER_HOME" /etc/fstab; then
      display_message "Removing tmpfs entry from /etc/fstab" "DEBUG"
      sed -i "\#$KIOSK_USER_HOME#d" /etc/fstab
    fi
    
    # Remove the user and their home directory
    display_message "Deleting user $KIOSK_USERNAME and home directory" "DEBUG"
    userdel -r "$KIOSK_USERNAME" 2>/dev/null || true
    
    # Remove any remaining home directory if userdel didn't remove it
    if [ -d "$KIOSK_USER_HOME" ]; then
      display_message "Removing $KIOSK_USER_HOME directory" "DEBUG"
      rm -rf "$KIOSK_USER_HOME"
    fi
    
    display_message "Kiosk user removed successfully." "INFO"
  fi
else
  display_message "Keeping kiosk user account." "INFO"
fi

# 6. Disable autologin if configured
display_message "Checking for autologin configurations..." "INFO"

# Check for LightDM configuration
if [ -f "/etc/lightdm/lightdm.conf" ]; then
  display_message "Checking LightDM configuration" "DEBUG"
  if grep -q "autologin-user=$KIOSK_USERNAME" "/etc/lightdm/lightdm.conf"; then
    display_message "Removing autologin from LightDM configuration" "DEBUG"
    sed -i "/autologin-user=$KIOSK_USERNAME/d" "/etc/lightdm/lightdm.conf"
    sed -i "/autologin-user-timeout=0/d" "/etc/lightdm/lightdm.conf"
  fi
fi

# Check for GDM configuration
if [ -f "/etc/gdm3/custom.conf" ]; then
  display_message "Checking GDM configuration" "DEBUG"
  if grep -q "AutomaticLoginEnable=true" "/etc/gdm3/custom.conf"; then
    display_message "Removing autologin from GDM configuration" "DEBUG"
    sed -i "s/AutomaticLoginEnable=true/AutomaticLoginEnable=false/" "/etc/gdm3/custom.conf"
    sed -i "/AutomaticLogin=$KIOSK_USERNAME/d" "/etc/gdm3/custom.conf"
  fi
fi

# Check for SDDM configuration
if [ -f "/etc/sddm.conf" ]; then
  display_message "Checking SDDM configuration" "DEBUG"
  if grep -q "User=$KIOSK_USERNAME" "/etc/sddm.conf"; then
    display_message "Removing autologin from SDDM configuration" "DEBUG"
    sed -i "/User=$KIOSK_USERNAME/d" "/etc/sddm.conf"
    sed -i "/Session=/d" "/etc/sddm.conf"
  fi
fi

# Final message with visual emphasis
echo "" >&2
echo "===================================================" >&2
echo "          UNINSTALLATION COMPLETE                " >&2
echo "===================================================" >&2
echo "" >&2

display_message "Uninstallation complete!" "INFO"
display_message "You may need to reboot your system for all changes to take effect." "INFO"
display_message "Recommended: sudo reboot" "INFO"

echo "" >&2
echo "Press Enter to return to menu..." >&2
read
Disabling firefox-periodic-fix.timer" "DEBUG"
  display_message "Checking LightDM configuration" "DEBUG"
  display_message "Removing kiosk user '$KIOSK_USERNAME'..." "INFO"
    display_message "Removing autologin from LightDM configuration" "DEBUG"
  display_message "Removing /etc/sudoers.d/kiosk-firefox" "DEBUG" " >&2
  display_message "Removing /etc/systemd/system/firefox-periodic-fix.timer" "DEBUG"
    display_message "User $KIOSK_USERNAME is currently logged in. Cannot remove while user is active." "WARNING"
    display_message "Please log out the user and run this script again to remove the user account." "WARNING"
  display_message "Removing /etc/sudoers.d/kiosk-firefox-fix" "DEBUG"setup..." "INFO"
  display_message "Disabling firefox-periodic-fix.service" "DEBUG"figurations and services." "WARNING"
display_message "You will be asked if you want to remove the kiosk user account." "WARNING"
  display_message "Checking GDM configuration" "DEBUG" from /etc/fstab" "DEBUG"
echo "Press Enter to continue or Ctrl+C to cancel..." >&2
    display_message "Removing autologin from GDM configuration" "DEBUG".." "INFO"iodic-fix.service" "DEBUG"

  display_message "Removing $OPT_KIOSK_DIR directory" "DEBUG"
    display_message "Deleting user $KIOSK_USERNAME and home directory" "DEBUG"

# Firefox ownership fix service
  display_message "Disabling var-ownership-fix.service" "DEBUG"e &>/dev/null; then
display_message "Removing kiosk user's autostart entries..." "INFO"
  display_message "Checking SDDM configuration" "DEBUG"HOME directory" "DEBUG"
fi
    display_message "Removing autologin from SDDM configuration" "DEBUG"x.desktop" "DEBUG"rvice" "DEBUG"
  echo "[DEBUG] Removing /etc/systemd/system/firefox-ownership-fix.service"
    display_message "Kiosk user removed successfully." "INFO".service"
fi

  display_message "Keeping kiosk user account." "INFO""DEBUG"r
# Final message with visual emphasis
echo "" >&2
echo "===================================================" >&2
echo "          UNINSTALLATION COMPLETE                " >&2
echo "===================================================" >&2
echo "" >&2

display_message "Uninstallation complete!" "INFO"
display_message "You may need to reboot your system for all changes to take effect." "INFO"
display_message "Recommended: sudo reboot" "INFO"

echo "" >&2
echo "Press Enter to return to menu..." >&2
readix.timer
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