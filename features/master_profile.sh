#!/bin/bash

# Master Profile Feature Script
# This script handles cloning the master profile desktop and desktop icons to the kiosk user via the template directory

# Configuration variables - these should match your main configuration
KIOSK_USERNAME="kiosk"
ADMIN_USERNAME="alocalbox"  # Admin username

# Script directories
OPT_KIOSK_DIR="/opt/kiosk"
TEMPLATE_DIR="$OPT_KIOSK_DIR/templates"

# Create template directories if they don't exist
mkdir -p "$TEMPLATE_DIR/Desktop"
mkdir -p "$TEMPLATE_DIR/Documents"
mkdir -p "$TEMPLATE_DIR/.config/autostart"
mkdir -p "$TEMPLATE_DIR/.local/share/applications"

# Function to save admin changes to the template directory
save_admin_changes() {
  # Log initialization
  LOGFILE="/tmp/admin_save.log"
  echo "$(date): Saving admin changes to template directory..." >> "$LOGFILE"

  # Copy Firefox profile if it exists
  if [ -d "/home/$ADMIN_USERNAME/.mozilla" ]; then
    echo "$(date): Copying Firefox profile to template..." >> "$LOGFILE"
    rm -rf "$TEMPLATE_DIR/.mozilla"  # Remove existing profile
    cp -r "/home/$ADMIN_USERNAME/.mozilla" "$TEMPLATE_DIR/"
    chmod -R 755 "$TEMPLATE_DIR/.mozilla"
  fi

  # Copy desktop shortcuts
  echo "$(date): Copying desktop shortcuts to template..." >> "$LOGFILE"
  cp -r "/home/$ADMIN_USERNAME/Desktop/"* "$TEMPLATE_DIR/Desktop/" 2>/dev/null || true

  # Copy documents
  echo "$(date): Copying documents to template..." >> "$LOGFILE"
  cp -r "/home/$ADMIN_USERNAME/Documents/"* "$TEMPLATE_DIR/Documents/" 2>/dev/null || true

  # Set correct ownership for all template files
  chown -R root:root "$TEMPLATE_DIR"
  chmod -R 755 "$TEMPLATE_DIR"

  echo "$(date): Admin changes saved successfully." >> "$LOGFILE"
}

# Function to create the save admin changes script
create_save_admin_script() {
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

# Determine Firefox profile directory for $ADMIN_USERNAME
# Note: $ADMIN_USERNAME and $TEMPLATE_DIR below are expanded when master_profile.sh generates save_admin_changes.sh.
# The \$ prefixed variables are for the save_admin_changes.sh script itself when it runs.
\$FF_PROFILE_DIR_SNAP="/home/$ADMIN_USERNAME/snap/firefox/common/.mozilla"
\$FF_PROFILE_DIR_FLATPAK="/home/$ADMIN_USERNAME/.var/app/org.mozilla.firefox/.mozilla"
\$FF_PROFILE_DIR_TRADITIONAL="/home/$ADMIN_USERNAME/.mozilla" # Original path
\$FF_PROFILE_SOURCE_DIR=""

if [ -d "\$FF_PROFILE_DIR_SNAP" ]; then
  \$FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_SNAP"
  echo "\$(date): Found Firefox Snap profile at \$FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME" >> "\$LOGFILE"
elif [ -d "\$FF_PROFILE_DIR_FLATPAK" ]; then
  \$FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_FLATPAK"
  echo "\$(date): Found Firefox Flatpak profile at \$FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME" >> "\$LOGFILE"
elif [ -d "\$FF_PROFILE_DIR_TRADITIONAL" ]; then
  \$FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_TRADITIONAL"
  echo "\$(date): Found Firefox traditional profile at \$FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME" >> "\$LOGFILE"
fi

# Copy Firefox profile if a source directory was found
if [ -n "\$FF_PROFILE_SOURCE_DIR" ]; then
  echo "\$(date): Copying Firefox profile from \$FF_PROFILE_SOURCE_DIR to $TEMPLATE_DIR/.mozilla..." >> "\$LOGFILE"
  rm -rf "$TEMPLATE_DIR/.mozilla"  # Remove existing profile first
  cp -r "\$FF_PROFILE_SOURCE_DIR" "$TEMPLATE_DIR/.mozilla" # Copies the found profile dir and names the copy '.mozilla'
  chmod -R 755 "$TEMPLATE_DIR/.mozilla"
else
  echo "\$(date): Firefox profile directory not found for user $ADMIN_USERNAME. Searched Snap, Flatpak, and traditional paths." >> "\$LOGFILE"
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
}

# Function to create systemd service for saving admin changes
create_systemd_service() {
  SYSTEMD_SERVICE="/etc/systemd/system/save-admin-changes.service"

  cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Save admin changes to kiosk template directory
Before=lightdm.service

[Service]
Type=oneshot
ExecStart=$OPT_KIOSK_DIR/save_admin_changes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # Enable the service
  systemctl enable save-admin-changes.service
}

# Function to create systemd service for kiosk home initialization
create_kiosk_init_service() {
  KIOSK_INIT_SERVICE="/etc/systemd/system/kiosk-home-init.service"

  cat > "$KIOSK_INIT_SERVICE" << EOF
[Unit]
Description=Initialize Kiosk User Home Directory
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "mkdir -p /home/$KIOSK_USERNAME/.config/autostart && cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ && mkdir -p /home/$KIOSK_USERNAME/Desktop && cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ && mkdir -p /home/$KIOSK_USERNAME/Documents && cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ 2>/dev/null || true && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # Enable the service
  systemctl enable kiosk-home-init.service
}

# Function to initialize kiosk environment
create_init_kiosk_script() {
  INIT_SCRIPT="$OPT_KIOSK_DIR/init_kiosk.sh"

  cat > "$INIT_SCRIPT" << EOF
#!/bin/bash

# Script to initialize kiosk environment on login

# Log initialization
LOGFILE="/tmp/kiosk_init.log"
echo "\$(date): Initializing kiosk environment..." >> "\$LOGFILE"

# Create necessary directories if they don't exist
mkdir -p ~/Desktop
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/Pictures
mkdir -p ~/.config/autostart
mkdir -p ~/.local/share/applications

# Copy template files to kiosk home directory
TEMPLATE_DIR="$TEMPLATE_DIR"

# Copy Firefox profile if it exists
if [ -d "\$TEMPLATE_DIR/.mozilla" ]; then
  echo "\$(date): Copying Firefox profile from template..." >> "\$LOGFILE"
  rm -rf ~/.mozilla  # Remove any existing profile
  cp -r "\$TEMPLATE_DIR/.mozilla" ~/
  chmod -R 700 ~/.mozilla
fi

# Copy desktop shortcuts if they exist
if [ -d "\$TEMPLATE_DIR/Desktop" ]; then
  echo "\$(date): Copying desktop shortcuts from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/Desktop/"* ~/Desktop/ 2>/dev/null || true
fi

# Copy documents if they exist
if [ -d "\$TEMPLATE_DIR/Documents" ]; then
  echo "\$(date): Copying documents from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/Documents/"* ~/Documents/ 2>/dev/null || true
fi

# Copy autostart entries if they exist
if [ -d "\$TEMPLATE_DIR/.config/autostart" ]; then
  echo "\$(date): Copying autostart entries from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/.config/autostart/"* ~/.config/autostart/ 2>/dev/null || true
fi

echo "\$(date): Kiosk environment initialized successfully." >> "\$LOGFILE"
EOF

  chmod +x "$INIT_SCRIPT"
}

# Main execution
echo "Setting up master profile feature..."

# Create the necessary scripts
create_save_admin_script
create_init_kiosk_script

# Create the systemd services
create_systemd_service
create_kiosk_init_service

# Perform an initial save of admin changes
save_admin_changes

# Copy the autostart entries and desktop shortcut to the kiosk user's home directory if it exists
if [ -d "/home/$KIOSK_USERNAME" ]; then
  mkdir -p "/home/$KIOSK_USERNAME/.config/autostart"
  mkdir -p "/home/$KIOSK_USERNAME/Desktop"
  mkdir -p "/home/$KIOSK_USERNAME/Documents"
  
  # Copy from template to kiosk user
  if [ -d "$TEMPLATE_DIR/.config/autostart" ]; then
    cp -r "$TEMPLATE_DIR/.config/autostart/"* "/home/$KIOSK_USERNAME/.config/autostart/" 2>/dev/null || true
  fi
  
  if [ -d "$TEMPLATE_DIR/Desktop" ]; then
    cp -r "$TEMPLATE_DIR/Desktop/"* "/home/$KIOSK_USERNAME/Desktop/" 2>/dev/null || true
  fi
  
  if [ -d "$TEMPLATE_DIR/Documents" ]; then
    cp -r "$TEMPLATE_DIR/Documents/"* "/home/$KIOSK_USERNAME/Documents/" 2>/dev/null || true
  fi
  
  # Set correct ownership
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/"
fi

echo "Master profile feature setup complete."