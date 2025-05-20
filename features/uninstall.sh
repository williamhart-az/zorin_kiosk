#!/bin/bash

# ZorinOS Kiosk Uninstall Script
# Note: This script does NOT require user_setup.sh to run first

# Exit on any error
set -e

# Setup logging
LOG_FILE="setup.log"
ENABLE_LOGGING=true

# Process command line arguments
for arg in "$@"; do
  case $arg in
    --nolog)
      ENABLE_LOGGING=false
      shift
      ;;
    enable)
      # This parameter is passed by setup.sh, we can ignore it
      shift
      ;;
  esac
done

# Initialize log file if logging is enabled
if $ENABLE_LOGGING; then
  echo "=== Kiosk Uninstall Log $(date) ===" >> "$LOG_FILE"
  echo "Command: $0 $@" >> "$LOG_FILE"
  echo "----------------------------------------" >> "$LOG_FILE"
fi

# Function to log messages
log_message() {
  local message="$1"
  local level="${2:-INFO}"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  if $ENABLE_LOGGING; then
    echo "[$level] $timestamp - $message" >> "$LOG_FILE"
  fi
  
  # Always print to console
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
  log_message "This script must be run as root. Please use sudo." "ERROR"
  exit 1
fi

# Source the environment file
log_message "Checking for environment file" "DEBUG"
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env"
  log_message "ENV_FILE not defined, using default: $ENV_FILE" "DEBUG"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")"
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/.env"
        log_message "Looking for .env next to kiosk_setup.sh: $ENV_FILE" "DEBUG"
        break
      fi
    done
  fi
fi

log_message "Checking if environment file exists at: $ENV_FILE" "DEBUG"
if [ ! -f "$ENV_FILE" ]; then
  log_message "Environment file not found at $ENV_FILE" "ERROR"
  log_message "Please specify the correct path using the ENV_FILE variable." "ERROR"
  exit 1
fi

log_message "Sourcing environment file: $ENV_FILE" "DEBUG"
source "$ENV_FILE"
log_message "Environment file sourced successfully" "DEBUG"

# Define kiosk user's home directory
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"

# Clear screen and show header
clear
echo "===================================================" >&2
echo "           ZORIN OS KIOSK UNINSTALLER            " >&2
echo "===================================================" >&2
echo "" >&2

log_message "Starting uninstallation of ZorinOS Kiosk setup..." "INFO"
log_message "This will remove all kiosk-related configurations and services." "WARNING"
log_message "You will be asked if you want to remove the kiosk user account." "WARNING"
echo "" >&2
echo "Press Enter to continue or Ctrl+C to cancel..." >&2
read

# 1. Disable and remove systemd services
log_message "Disabling and removing systemd services..." "INFO"
# First, stop all services that might be using the kiosk user's home directory
log_message "Stopping all kiosk-related services..." "INFO"

# Firefox ownership fix service
if systemctl is-active firefox-ownership-fix.service &>/dev/null; then
  log_message "Stopping firefox-ownership-fix.service" "DEBUG"
  systemctl stop firefox-ownership-fix.service || true
fi

# Firefox periodic fix service and timer
if systemctl is-active firefox-periodic-fix.timer &>/dev/null; then
  log_message "Stopping firefox-periodic-fix.timer" "DEBUG"
  systemctl stop firefox-periodic-fix.timer || true
fi
if systemctl is-active firefox-periodic-fix.service &>/dev/null; then
  log_message "Stopping firefox-periodic-fix.service" "DEBUG"
  systemctl stop firefox-periodic-fix.service || true
fi

# Var ownership fix service
if systemctl is-active var-ownership-fix.service &>/dev/null; then
  log_message "Stopping var-ownership-fix.service" "DEBUG"
  systemctl stop var-ownership-fix.service || true
fi

# Now disable all services
log_message "Disabling all kiosk-related services..." "DEBUG"

# Firefox ownership fix service
if systemctl is-enabled firefox-ownership-fix.service &>/dev/null; then
  log_message "Disabling firefox-ownership-fix.service" "DEBUG"
  systemctl disable firefox-ownership-fix.service
fi

# Firefox periodic fix service and timer
if systemctl is-enabled firefox-periodic-fix.timer &>/dev/null; then
  log_message "Disabling firefox-periodic-fix.timer" "DEBUG"
  systemctl disable firefox-periodic-fix.timer
fi
if systemctl is-enabled firefox-periodic-fix.service &>/dev/null; then
  log_message "Disabling firefox-periodic-fix.service" "DEBUG"
  systemctl disable firefox-periodic-fix.service
fi

# Var ownership fix service
if systemctl is-enabled var-ownership-fix.service &>/dev/null; then
  log_message "Disabling var-ownership-fix.service" "DEBUG"
  systemctl disable var-ownership-fix.service
fi

# Now remove service files
log_message "Removing service files..." "DEBUG"

# Firefox periodic fix service and timer
if systemctl is-active firefox-periodic-fix.timer &>/dev/null; then
  log_message "Stopping firefox-periodic-fix.timer" "DEBUG"

systemctl stop firefox-periodic-fix.service
fi

# Var ownership fix service
if systemctl is-active var-ownership-fix.service &>/dev/null; then


# Now disable all services
log_message "Disabling all kiosk-related services..." "DEBUG"
# Firefox ownership fix service
if systemctl is-enabled firefox-ownership-fix.service &>/dev/null; then
  log_message "Disabling firefox-ownership-fix.service" "DEBUG"
  systemctl disable firefox-ownership-fix.service

log_message "Disabling firefox-periodic-fix.timer" "DEBUG"
  systemctl disable firefox-periodic-fix.timer
fi
if systemctl is-enabled firefox-periodic-fix.service &>/dev/null; then
  log_message "Disabling firefox-periodic-fix.service" "DEBUG"
  systemctl disable firefox-periodic-fix.service
fi

# Var ownership fix service
if systemctl is-enabled var-ownership-fix.service &>/dev/null; then
  log_message "Disabling var-ownership-fix.service" "DEBUG"
  systemctl disable var-ownership-fix.service
fi

# Now remove service files
log_message "Removing service files..." "DEBUG"

# Firefox ownership fix service
if [ -f "/etc/systemd/system/firefox-ownership-fix.service" ]; then
  log_message "Removing /etc/systemd/system/firefox-ownership-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/firefox-ownership-fix.service"
fi

# Firefox periodic fix service and timer
if [ -f "/etc/systemd/system/firefox-periodic-fix.timer" ]; then
  log_message "Removing /etc/systemd/system/firefox-periodic-fix.timer" "DEBUG"
  rm -f "/etc/systemd/system/firefox-periodic-fix.timer"
fi

if [ -f "/etc/systemd/system/firefox-periodic-fix.service" ]; then
  log_message "Removing /etc/systemd/system/firefox-periodic-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/firefox-periodic-fix.service"
fi

# Var ownership fix service
if [ -f "/etc/systemd/system/var-ownership-fix.service" ]; then
  log_message "Removing /etc/systemd/system/var-ownership-fix.service" "DEBUG"
  rm -f "/etc/systemd/system/var-ownership-fix.service"
fi

# Reload systemd to apply changes
log_message "Reloading systemd daemon" "DEBUG"
systemctl daemon-reload

# 2. Remove sudoers entries
log_message "Removing sudoers entries..." "INFO"
if [ -f "/etc/sudoers.d/kiosk-firefox" ]; then
  log_message "Removing /etc/sudoers.d/kiosk-firefox" "DEBUG"
  rm -f "/etc/sudoers.d/kiosk-firefox"
fi
if [ -f "/etc/sudoers.d/kiosk-firefox-fix" ]; then
  log_message "Removing /etc/sudoers.d/kiosk-firefox-fix" "DEBUG"
  rm -f "/etc/sudoers.d/kiosk-firefox-fix"
fi

# 3. Remove scripts from /opt/kiosk
log_message "Removing kiosk scripts from $OPT_KIOSK_DIR..." "INFO"
if [ -d "$OPT_KIOSK_DIR" ]; then
  log_message "Removing $OPT_KIOSK_DIR directory" "DEBUG"
  rm -rf "$OPT_KIOSK_DIR"
fi

# Ask if the .env file should be removed
remove_env=$(get_user_input "[PROMPT] Do you want to remove the .env file? (y/n)")

if [[ "$remove_env" =~ ^[Yy]$ ]]; then
  log_message "Removing .env file..." "INFO"
  if [ -f "$ENV_FILE" ]; then
    log_message "Removing $ENV_FILE" "DEBUG"
    rm -f "$ENV_FILE"
  fi
else
  log_message "Keeping .env file." "INFO"
fi

# Check if any kiosk-related files or directories still exist
remaining_issues=false

# Check if kiosk user still exists
if id "$KIOSK_USERNAME" &>/dev/null; then
  log_message "Kiosk user still exists in the system" "WARNING"
  remaining_issues=true
fi

# Check if kiosk home directory still exists
if [ -d "$KIOSK_USER_HOME" ]; then
  log_message "Kiosk user home directory still exists" "WARNING"
  remaining_issues=true
fi

# Check if any kiosk services are still running
if systemctl list-units --type=service | grep -q "firefox\|kiosk"; then
  log_message "Some kiosk-related services may still be running" "WARNING"
  remaining_issues=true
fi

if $remaining_issues; then
  log_message "Some kiosk components could not be fully removed" "WARNING"
  log_message "A system reboot is STRONGLY recommended before trying again" "WARNING"
  log_message "After reboot, run: sudo $(dirname "$0")/uninstall.sh" "INFO"
  echo "" >&2
  echo "===================================================" >&2
  echo "          REBOOT RECOMMENDED                    " >&2
  echo "===================================================" >&2
  echo "Some kiosk components could not be fully removed." >&2
  echo "Please reboot your system and run this script again" >&2
  echo "if you want to completely remove all components." >&2
else
  log_message "All kiosk components have been successfully removed" "INFO"
  log_message "You may want to reboot your system to ensure all changes take effect" "INFO"
fi

# 4. Remove autostart entries
log_message "Removing kiosk user's autostart entries..." "INFO"
AUTOSTART_DIR="$KIOSK_USER_HOME/.config/autostart"
if [ -f "$AUTOSTART_DIR/firefox-profile-fix.desktop" ]; then
  log_message "Removing $AUTOSTART_DIR/firefox-profile-fix.desktop" "DEBUG"
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
  log_message "Removing kiosk user '$KIOSK_USERNAME'..." "INFO"
  
  # Check if the user is currently logged in
  if who | grep -q "^$KIOSK_USERNAME "; then
    log_message "User $KIOSK_USERNAME is currently logged in. Cannot remove while user is active." "WARNING"
    log_message "Please log out the user and run this script again to remove the user account." "WARNING"
  else
    # Remove any tmpfs mounts for the user's home directory
    if grep -q "$KIOSK_USER_HOME" /etc/fstab; then
      log_message "Removing tmpfs entry from /etc/fstab" "DEBUG"
      sed -i "\#$KIOSK_USER_HOME#d" /etc/fstab
      
      # Unmount the tmpfs filesystem
      log_message "Unmounting tmpfs filesystem" "DEBUG"
      umount "$KIOSK_USER_HOME"
    fi
    
    # Remove the user and their home directory
    log_message "Deleting user $KIOSK_USERNAME and home directory" "DEBUG"
    userdel -r "$KIOSK_USERNAME" 2>/dev/null || true
    
    # Remove any remaining home directory if userdel didn't remove it
    if [ -d "$KIOSK_USER_HOME" ]; then
      log_message "Removing $KIOSK_USER_HOME directory" "DEBUG"
      rm -rf "$KIOSK_USER_HOME"
    fi
    
    log_message "Kiosk user removed successfully." "INFO"
  fi
else
  log_message "Keeping kiosk user account." "INFO"
fi

# 6. Disable autologin if configured
log_message "Checking for autologin configurations..." "INFO"

# Check for LightDM configuration
if [ -f "/etc/lightdm/lightdm.conf" ]; then
  log_message "Checking LightDM configuration" "DEBUG"
  if grep -q "autologin-user=$KIOSK_USERNAME" "/etc/lightdm/lightdm.conf"; then
    log_message "Removing autologin from LightDM configuration" "DEBUG"
    sed -i "/autologin-user=$KIOSK_USERNAME/d" "/etc/lightdm/lightdm.conf"
    sed -i "/autologin-user-timeout=0/d" "/etc/lightdm/lightdm.conf"
  fi
fi

# Check for GDM configuration
if [ -f "/etc/gdm3/custom.conf" ]; then
  log_message "Checking GDM configuration" "DEBUG"
  if grep -q "AutomaticLoginEnable=true" "/etc/gdm3/custom.conf"; then
    log_message "Removing autologin from GDM configuration" "DEBUG"
    sed -i "s/AutomaticLoginEnable=true/AutomaticLoginEnable=false/" "/etc/gdm3/custom.conf"
    sed -i "/AutomaticLogin=$KIOSK_USERNAME/d" "/etc/gdm3/custom.conf"
  fi
fi

# Check for SDDM configuration
if [ -f "/etc/sddm.conf" ]; then
  log_message "Checking SDDM configuration" "DEBUG"
  if grep -q "User=$KIOSK_USERNAME" "/etc/sddm.conf"; then
    log_message "Removing autologin from SDDM configuration" "DEBUG"
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

log_message "Uninstallation complete!" "INFO"
log_message "You may need to reboot your system for all changes to take effect." "INFO"
log_message "Recommended: sudo reboot" "INFO"

# Ask if the user wants to reboot the system
reboot_system=$(get_user_input "[PROMPT] Do you want to reboot the system now? (y/n)")

if [[ "$reboot_system" =~ ^[Yy]$ ]]; then
  log_message "Rebooting system..." "INFO"
  sudo reboot
else
  log_message "System reboot skipped." "INFO"
fi

# Check if we were called from setup.sh (with 'enable' parameter)
if [[ " $* " == *" enable "* ]]; then
  # We were called from setup.sh, so we should exit completely
  echo "" >&2
  echo "Press Enter to exit..." >&2
  read
  exit 0
else
  # We were called directly, so we should return to the menu
  echo "" >&2
  echo "Press Enter to return to menu..." >&2
  read
fi
