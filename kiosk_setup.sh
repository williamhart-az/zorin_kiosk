#!/bin/bash

# ZorinOS Kiosk Setup Script with Desktop Environment
# Run this script with sudo after fresh installation
# Usage: sudo bash kiosk_setup.sh [--nolog]

# Exit on any error
set -e

# Setup logging
LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/kiosk_setup.sh.log" # Changed log file path
ENABLE_LOGGING=true

# Process command line arguments
for arg in "$@"; do
  case $arg in
    --nolog)
      ENABLE_LOGGING=false
      shift
      ;;
  esac
done

# Create log directory and initialize log file if logging is enabled
if $ENABLE_LOGGING; then
  mkdir -p "$LOG_DIR" # Create log directory if it doesn't exist
  chmod 755 "$LOG_DIR" # Ensure root can write, others can read/execute
  # Ensure the log file itself is writable by root
  touch "$LOG_FILE"
  chmod 644 "$LOG_FILE" # Root r/w, others read

  echo "=== Kiosk Setup Log $(date) ===" > "$LOG_FILE" # Ensure this writes to the new LOG_FILE
  echo "Command: $0 $@" >> "$LOG_FILE"
  echo "----------------------------------------" >> "$LOG_FILE"
fi

# Function to log messages
log_message() {
  local message="$1"
  local level="${2:-INFO}" # Default level is INFO
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  if $ENABLE_LOGGING; then
    echo "[$level] $timestamp - $message" >> "$LOG_FILE"
  fi
  
  # Only print non-DEBUG messages to the console
  if [ "$level" != "DEBUG" ]; then
    echo "[$level] $message"
  fi
}

# Function to run a command with logging
run_with_logging() {
  local cmd="$1"
  local feature_name="$2"
  local script_name="$3"
  
  log_message "Installing $feature_name (using $script_name)" "INFO"
  
  if $ENABLE_LOGGING; then
    # Run the command and capture output to log file
    echo "----------------------------------------" >> "$LOG_FILE"
    echo "Running: $cmd" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
    
    # Execute command, tee output to log file, and capture exit status
    set -o pipefail
    output=$($cmd 2>&1 | tee -a "$LOG_FILE")
    exit_status=$?
    set +o pipefail
    
    echo "----------------------------------------" >> "$LOG_FILE"
    log_message "Command completed with status: $exit_status" "DEBUG"
    
    return $exit_status
  else
    # Run the command normally
    $cmd
    return $?
  fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  log_message "This script must be run as root. Please use sudo." "ERROR"
  exit 1
fi

# Load configuration from .env file
ENV_FILE="./.env"

if [ ! -f "$ENV_FILE" ]; then
  log_message "Error: Configuration file $ENV_FILE not found." "ERROR"
  log_message "Please copy .env.example to .env and customize it for your environment." "ERROR"
  exit 1
fi

# Source the environment file
source "$ENV_FILE"
log_message "Environment configuration loaded from $ENV_FILE" "DEBUG"

echo "=== ZorinOS Kiosk Setup ==="
echo "This script will configure your system for kiosk mode with desktop access."
echo "WARNING: This is meant for dedicated kiosk systems only!"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_message "Setup cancelled by user" "INFO"
  echo "Setup cancelled."
  exit 1
fi

# Check if features directory exists
if [ ! -d "features" ]; then
  log_message "Error: Features directory not found." "ERROR"
  log_message "Please make sure the 'features' directory exists in the same directory as this script." "ERROR"
  exit 1
fi

# Make all feature scripts executable
chmod +x features/*.sh
log_message "Made all feature scripts executable" "DEBUG"

# Execute feature scripts in the correct order
# Note: The order is important, especially for tmpfs setup

# First, set up the user (Features #1, 2, 8, 9, 10, 11, 12)
run_with_logging "./features/user-setup.sh" "Kiosk User" "user-setup.sh"

# Set up WiFi restrictions
run_with_logging "./features/wifi.sh" "WiFi Restrictions" "wifi.sh"

# Next, set up Firefox (Features #7, 19)
run_with_logging "./features/Firefox.sh" "Firefox Configuration" "Firefox.sh"

# Set up master profile (Features #14, 15)
run_with_logging "./features/master_profile.sh" "Master Profile" "master_profile.sh"

# Set up idle delay settings
run_with_logging "./features/idle-delay.sh" "Idle Delay Settings" "idle-delay.sh"

# Finally, set up tmpfs (Features #3, 4, 5, 6, 13, 16, 17, 18)
# This must be done last as it depends on scripts created by previous features
run_with_logging "./features/tmpfs.sh" "Temporary File System" "tmpfs.sh"

# Set up scheduled reboots
run_with_logging "./features/scheduled_reboot.sh" "Scheduled Reboots" "scheduled_reboot.sh"

log_message "All features have been installed successfully" "INFO"

echo ""
echo "=== Kiosk Setup Complete ==="
echo "Your system will now:"
echo "1. Mount a tmpfs filesystem for the kiosk user's home directory"
echo "2. Initialize the kiosk environment on login with the init_kiosk.sh script"
echo "3. Prevent the screen from turning off for $(($DISPLAY_TIMEOUT/60)) minutes"
echo "4. Set the wallpaper to $WALLPAPER_NAME"
echo "5. Autologin as the Kiosk user"
echo "6. Allow admin changes to be saved to the template directory"
echo "7. Use a systemd service to initialize the kiosk home directory after tmpfs mount"
echo "8. Automatically configure Firefox to suppress the first-run wizard"
echo "9. Restrict network settings access for the kiosk user"
if [ "$REBOOT_TIME" = "-1" ]; then
  echo "10. Scheduled reboots are disabled"
else
  if [ "$REBOOT_DAYS" = "all" ]; then
    echo "10. Automatically reboot the system daily at $REBOOT_TIME"
  else
    echo "10. Automatically reboot the system at $REBOOT_TIME on specified days"
  fi
fi

if $ENABLE_LOGGING; then
  echo ""
  echo "A detailed log of the installation has been saved to: $LOG_FILE"
fi

echo ""
echo "To test the setup, reboot your system with: sudo reboot"

log_message "Setup completed successfully" "INFO"
