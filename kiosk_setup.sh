#!/bin/bash

# ZorinOS Kiosk Setup Script with Desktop Environment
# Run this script with sudo after fresh installation
# Usage: sudo bash kiosk_setup.sh

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Load configuration from .env file
ENV_FILE="./.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: Configuration file $ENV_FILE not found."
  echo "Please copy .env.example to .env and customize it for your environment."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

echo "=== ZorinOS Kiosk Setup ==="
echo "This script will configure your system for kiosk mode with desktop access."
echo "WARNING: This is meant for dedicated kiosk systems only!"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Setup cancelled."
  exit 1
fi

# Check if features directory exists
if [ ! -d "features" ]; then
  echo "Error: Features directory not found."
  echo "Please make sure the 'features' directory exists in the same directory as this script."
  exit 1
fi

# Make all feature scripts executable
chmod +x features/*.sh

# Execute feature scripts in the correct order
# Note: The order is important, especially for tmpfs setup

# First, set up the user (Features #1, 2, 8, 9, 10, 11, 12)
echo "Setting up kiosk user..."
./features/user-setup.sh

# Set up WiFi restrictions
echo "Setting up WiFi restrictions..."
./features/wifi.sh

# Next, set up Firefox (Features #7, 19)
echo "Setting up Firefox..."
./features/Firefox.sh

# Set up master profile (Features #14, 15)
echo "Setting up master profile..."
./features/master_profile.sh

# Set up idle delay settings
echo "Setting up idle delay settings..."
./features/idle-delay.sh

# Finally, set up tmpfs (Features #3, 4, 5, 6, 13, 16, 17, 18)
# This must be done last as it depends on scripts created by previous features
echo "Setting up tmpfs..."
./features/tmpfs.sh

# Set up scheduled reboots
echo "Setting up scheduled reboots..."
./features/scheduled_reboot.sh

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
echo ""
echo "To test the setup, reboot your system with: sudo reboot"