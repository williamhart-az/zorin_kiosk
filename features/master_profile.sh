#!/bin/bash

enable_feature() {
    echo "Cloning Firefox profile for kiosk user..."

    # Source profile location (admin user)
    SOURCE_PROFILE_DIR="$HOME/.mozilla/firefox"
    SOURCE_PROFILES_INI="$SOURCE_PROFILE_DIR/profiles.ini"

    # Destination profile location (kiosk user)
    KIOSK_HOME="/home/kiosk"
    DEST_PROFILE_DIR="$KIOSK_HOME/.mozilla/firefox"

    # Create directories if they don't exist
    mkdir -p "$DEST_PROFILE_DIR"

    # 1. First, identify the default profile from profiles.ini
    if [ -f "$SOURCE_PROFILES_INI" ]; then
        # Extract the default profile path
        DEFAULT_PROFILE=$(grep -A 10 "Default=1" "$SOURCE_PROFILES_INI" | grep "Path=" | head -1 | cut -d= -f2)

        if [ -z "$DEFAULT_PROFILE" ]; then
            # If no default profile found, try to get the first profile
            DEFAULT_PROFILE=$(grep "Path=" "$SOURCE_PROFILES_INI" | head -1 | cut -d= -f2)
        fi

        if [ -n "$DEFAULT_PROFILE" ]; then
            SOURCE_PROFILE_PATH="$SOURCE_PROFILE_DIR/$DEFAULT_PROFILE"
            echo "Found source profile: $SOURCE_PROFILE_PATH"

            # 2. Create a new profile for kiosk
            KIOSK_PROFILE_NAME="kiosk.default"
            KIOSK_PROFILE_PATH="$DEST_PROFILE_DIR/$KIOSK_PROFILE_NAME"

            # Create the profile directory
            mkdir -p "$KIOSK_PROFILE_PATH"

            # 3. Copy profile contents
            echo "Copying profile contents..."
            cp -r "$SOURCE_PROFILE_PATH"/* "$KIOSK_PROFILE_PATH/"

            # 4. Create/update profiles.ini for kiosk user with modern format
            cat > "$DEST_PROFILE_DIR/profiles.ini" << EOF
[Profile0]
Name=default
IsRelative=1
Path=$KIOSK_PROFILE_NAME
Default=1

[General]
StartWithLastProfile=1
Version=2

[Install]
DefaultProfile=$KIOSK_PROFILE_NAME
EOF

            # Also create profiles.ini in Flatpak location if needed
            if [ -d "$KIOSK_HOME/.var/app/org.mozilla.firefox" ]; then
                mkdir -p "$KIOSK_HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
                cat > "$KIOSK_HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini" << EOF
[Profile0]
Name=default
IsRelative=1
Path=$KIOSK_PROFILE_NAME
Default=1

[General]
StartWithLastProfile=1
Version=2

[Install]
DefaultProfile=$KIOSK_PROFILE_NAME
EOF
            fi

            # 5. Ensure user.js is in the profile directory
            if [ -f "/opt/kiosk/user.js" ]; then
                echo "Copying user.js to profile..."
                cp "/opt/kiosk/user.js" "$KIOSK_PROFILE_PATH/user.js"
            else
                echo "Warning: user.js not found in /opt/kiosk/"
            fi

            # 6. Set proper ownership
            chown -R kiosk:kiosk "$KIOSK_HOME/.mozilla"

            echo "Firefox profile successfully cloned for kiosk user"
        else
            echo "Error: Could not find a Firefox profile to clone"
            exit 1
        fi
    else
        echo "Error: Source profiles.ini not found at $SOURCE_PROFILES_INI"
        exit 1
    fi
}

disable_feature() {
    echo "Removing Firefox profile for kiosk user..."
    rm -rf "/home/kiosk/.mozilla/firefox"
}

case "$1" in
    enable)
        enable_feature
        ;;
    disable)
        disable_feature
        ;;
    *)
        echo "Usage: $0 {enable|disable}"
        exit 1
        ;;
esac

exit 0

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
  
  # Store the Firefox profile type for later use
  FF_PROFILE_TYPE="unknown"
  if [[ "\$FF_PROFILE_SOURCE_DIR" == *"/snap/firefox/"* ]]; then
    FF_PROFILE_TYPE="snap"
  elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".var/app/org.mozilla.firefox"* ]]; then
    FF_PROFILE_TYPE="flatpak"
  elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".mozilla"* ]]; then
    FF_PROFILE_TYPE="traditional"
  fi
  
  # Create a file to indicate the Firefox profile type
  echo "\$FF_PROFILE_TYPE" > "$TEMPLATE_DIR/.firefox_profile_type"
  chmod 644 "$TEMPLATE_DIR/.firefox_profile_type"
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
ExecStart=/bin/bash -c "mkdir -p /home/$KIOSK_USERNAME/.config/autostart && cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ && mkdir -p /home/$KIOSK_USERNAME/Desktop && cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ && mkdir -p /home/$KIOSK_USERNAME/Documents && cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ 2>/dev/null || true && if [ -d '$TEMPLATE_DIR/.mozilla' ]; then cp -r $TEMPLATE_DIR/.mozilla /home/$KIOSK_USERNAME/ && if [ -f '$TEMPLATE_DIR/.firefox_profile_type' ] && [ \\$(cat '$TEMPLATE_DIR/.firefox_profile_type') = 'flatpak' ]; then mkdir -p /home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox; fi; fi && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/"
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

# Store the Firefox profile source type for later use
FF_PROFILE_TYPE="unknown"
if [[ "\$FF_PROFILE_SOURCE_DIR" == *"/snap/firefox/"* ]]; then
  FF_PROFILE_TYPE="snap"
elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".var/app/org.mozilla.firefox"* ]]; then
  FF_PROFILE_TYPE="flatpak"
elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".mozilla"* ]]; then
  FF_PROFILE_TYPE="traditional"
fi

# Create a file to indicate the Firefox profile type
echo "\$FF_PROFILE_TYPE" > "\$TEMPLATE_DIR/.firefox_profile_type"

# Copy Firefox profile if it exists
if [ -d "\$TEMPLATE_DIR/.mozilla" ]; then
  echo "\$(date): Copying Firefox profile from template..." >> "\$LOGFILE"
  rm -rf ~/.mozilla  # Remove any existing profile
  cp -r "\$TEMPLATE_DIR/.mozilla" ~/
  
  # Get the Firefox profile type
  FF_PROFILE_TYPE="unknown"
  if [ -f "\$TEMPLATE_DIR/.firefox_profile_type" ]; then
    FF_PROFILE_TYPE=\$(cat "\$TEMPLATE_DIR/.firefox_profile_type")
  fi
  
  # Ensure proper ownership of Firefox profile directories
  chmod -R 700 ~/.mozilla
  
  # Handle Flatpak Firefox installation
  if [ "\$FF_PROFILE_TYPE" = "flatpak" ]; then
    echo "\$(date): Setting up Flatpak Firefox directories..." >> "\$LOGFILE"
    # Create .var directory structure if it doesn't exist
    mkdir -p ~/.var/app/org.mozilla.firefox
    # Set proper ownership and permissions
    chmod -R 700 ~/.var
  fi
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