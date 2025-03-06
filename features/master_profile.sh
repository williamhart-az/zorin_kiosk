#!/bin/bash

# ZorinOS Kiosk Master Profile Setup Script
# Features: #14, 15

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

# 14. Create a script to save admin changes to the template directory
echo "Creating admin changes save script..."
SAVE_ADMIN_SCRIPT="$OPT_KIOSK_DIR/save_admin_changes.sh"

cat > "$SAVE_ADMIN_SCRIPT" << EOF
#!/bin/bash

# Script to save admin user changes to the kiosk template directory

# Log initialization
LOGFILE="/tmp/admin_save.log"
echo "\$(date): Saving admin changes to template directory..." >> "\$LOGFILE"

# Create template directories if they don't exist
mkdir -p "$TEMPLATE_DIR/Desktop"
mkdir -p "$TEMPLATE_DIR/Documents"
mkdir -p "$TEMPLATE_DIR/.config/autostart"
mkdir -p "$TEMPLATE_DIR/.local/share/applications"

# Detect Firefox installation type and save profile accordingly
# Check if Firefox is installed as a flatpak
if [ -d "/var/lib/flatpak/app/org.mozilla.firefox" ] || [ -d "/home/$ADMIN_USERNAME/.local/share/flatpak/app/org.mozilla.firefox" ]; then
  echo "\$(date): Firefox detected as flatpak, saving profile..." >> "\$LOGFILE"
  if [ -d "/home/$ADMIN_USERNAME/.var/app/org.mozilla.firefox" ]; then
    mkdir -p "$TEMPLATE_DIR/.var/app"
    rm -rf "$TEMPLATE_DIR/.var/app/org.mozilla.firefox"  # Remove existing profile
    cp -r "/home/$ADMIN_USERNAME/.var/app/org.mozilla.firefox" "$TEMPLATE_DIR/.var/app/"
    chmod -R 755 "$TEMPLATE_DIR/.var/app/org.mozilla.firefox"
  fi
# Regular Firefox installation
elif [ -d "/home/$ADMIN_USERNAME/.mozilla" ]; then
  echo "\$(date): Regular Firefox detected, saving profile..." >> "\$LOGFILE"
  rm -rf "$TEMPLATE_DIR/.mozilla"  # Remove existing profile
  cp -r "/home/$ADMIN_USERNAME/.mozilla" "$TEMPLATE_DIR/"
  chmod -R 755 "$TEMPLATE_DIR/.mozilla"
fi

# Copy desktop shortcuts
echo "\$(date): Copying desktop shortcuts to template..." >> "\$LOGFILE"
cp -r "/home/$ADMIN_USERNAME/Desktop/"* "$TEMPLATE_DIR/Desktop/" 2>/dev/null || true

# Copy documents
echo "\$(date): Copying documents to template..." >> "\$LOGFILE"
cp -r "/home/$ADMIN_USERNAME/Documents/"* "$TEMPLATE_DIR/Documents/" 2>/dev/null || true

# Set correct ownership for all template files
chown -R root:root "$TEMPLATE_DIR"
chmod -R 755 "$TEMPLATE_DIR"

echo "\$(date): Admin changes saved successfully." >> "\$LOGFILE"
EOF

chmod +x "$SAVE_ADMIN_SCRIPT"

# 15. Create a systemd service to save admin changes on logout
echo "Creating systemd service for saving admin changes..."
SYSTEMD_SERVICE="/etc/systemd/system/save-admin-changes.service"

cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Save admin changes to kiosk template directory
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=$OPT_KIOSK_DIR/save_admin_changes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable save-admin-changes.service