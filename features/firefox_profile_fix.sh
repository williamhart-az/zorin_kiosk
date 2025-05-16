#!/bin/bash

# ZorinOS Kiosk Firefox Profile.ini Fix Script

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

# Define potential base directories for Firefox profiles
FLATPAK_APP_BASE_DIR="$KIOSK_USER_HOME/.var/app"
FLATPAK_FIREFOX_PROFILE_DIR="$FLATPAK_APP_BASE_DIR/org.mozilla.firefox"
STANDARD_FIREFOX_PROFILE_PARENT_DIR="$KIOSK_USER_HOME/.mozilla"

echo "[INFO] Fixing Firefox profile.ini files..."

# Function to update profiles.ini with modern format
update_profiles_ini() {
  local profile_dir="$1"
  local profiles_ini="$profile_dir/firefox/profiles.ini"
  
  if [ -f "$profiles_ini" ]; then
    echo "[DEBUG] Found profiles.ini at $profiles_ini"
    
    # Get the profile path from the existing profiles.ini
    local profile_path=$(grep "Path=" "$profiles_ini" | head -1 | cut -d= -f2)
    
    if [ -n "$profile_path" ]; then
      echo "[DEBUG] Found profile path: $profile_path"
      
      # Create a new profiles.ini with modern format
      cat > "$profiles_ini" << EOL
[Profile0]
Name=default
IsRelative=1
Path=$profile_path
Default=1

[General]
StartWithLastProfile=1
Version=2

[Install]
DefaultProfile=$profile_path
EOL
      echo "[INFO] Updated profiles.ini at $profiles_ini"
    else
      echo "[WARNING] Could not find profile path in $profiles_ini"
    fi
  else
    echo "[WARNING] profiles.ini not found at $profiles_ini"
  fi
}

# Update profiles.ini in standard Firefox location
if [ -d "$STANDARD_FIREFOX_PROFILE_PARENT_DIR" ]; then
  update_profiles_ini "$STANDARD_FIREFOX_PROFILE_PARENT_DIR"
fi

# Update profiles.ini in Flatpak Firefox location
if [ -d "$FLATPAK_FIREFOX_PROFILE_DIR" ]; then
  update_profiles_ini "$FLATPAK_FIREFOX_PROFILE_DIR/.mozilla"
fi

# Update profiles.ini in Snap Firefox location (if it exists)
SNAP_FIREFOX_PROFILE_DIR="$KIOSK_USER_HOME/snap/firefox/common/.mozilla"
if [ -d "$SNAP_FIREFOX_PROFILE_DIR" ]; then
  update_profiles_ini "$SNAP_FIREFOX_PROFILE_DIR"
fi

echo "[INFO] Firefox profile.ini fix complete."

# Create a script to be run by the kiosk user
FIX_SCRIPT="/opt/kiosk/fix_firefox_profiles.sh"
cat > "$FIX_SCRIPT" << 'EOF'
#!/bin/bash

# Script to fix Firefox profiles.ini for the current user
set -e

USER_HOME="$HOME"
LOG_DIR="$USER_HOME/.cache/kiosk_setup"
LOGFILE="$LOG_DIR/firefox_profile_fix.log"

# Create log directory
mkdir -p "$LOG_DIR"
echo "$(date): Fixing Firefox profiles.ini..." >> "$LOGFILE"

# Function to update profiles.ini with modern format
update_profiles_ini() {
  local profile_dir="$1"
  local profiles_ini="$profile_dir/firefox/profiles.ini"
  
  if [ -f "$profiles_ini" ]; then
    echo "$(date): Found profiles.ini at $profiles_ini" >> "$LOGFILE"
    
    # Get the profile path from the existing profiles.ini
    local profile_path=$(grep "Path=" "$profiles_ini" | head -1 | cut -d= -f2)
    
    if [ -n "$profile_path" ]; then
      echo "$(date): Found profile path: $profile_path" >> "$LOGFILE"
      
      # Create a new profiles.ini with modern format
      cat > "$profiles_ini" << EOL
[Profile0]
Name=default
IsRelative=1
Path=$profile_path
Default=1

[General]
StartWithLastProfile=1
Version=2

[Install]
DefaultProfile=$profile_path
EOL
      echo "$(date): Updated profiles.ini at $profiles_ini" >> "$LOGFILE"
    else
      echo "$(date): Could not find profile path in $profiles_ini" >> "$LOGFILE"
    fi
  else
    echo "$(date): profiles.ini not found at $profiles_ini" >> "$LOGFILE"
  fi
}

# Update profiles.ini in standard Firefox location
if [ -d "$USER_HOME/.mozilla" ]; then
  update_profiles_ini "$USER_HOME/.mozilla"
fi

# Update profiles.ini in Flatpak Firefox location
if [ -d "$USER_HOME/.var/app/org.mozilla.firefox/.mozilla" ]; then
  update_profiles_ini "$USER_HOME/.var/app/org.mozilla.firefox/.mozilla"
fi

# Update profiles.ini in Snap Firefox location (if it exists)
if [ -d "$USER_HOME/snap/firefox/common/.mozilla" ]; then
  update_profiles_ini "$USER_HOME/snap/firefox/common/.mozilla"
fi

echo "$(date): Firefox profile.ini fix complete." >> "$LOGFILE"
EOF

chmod +x "$FIX_SCRIPT"

# Create a sudoers entry for the kiosk user to run the fix script
SUDOERS_FILE="/etc/sudoers.d/kiosk-firefox-fix"
cat > "$SUDOERS_FILE" << EOF
# Allow kiosk user to run Firefox profile fix script without password
$KIOSK_USERNAME ALL=(ALL) NOPASSWD: $FIX_SCRIPT
EOF
chmod 440 "$SUDOERS_FILE"

# Add the fix script to the kiosk user's autostart
AUTOSTART_DIR="$KIOSK_USER_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/firefox-profile-fix.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Firefox Profile Fix
Exec=sudo $FIX_SCRIPT
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$AUTOSTART_DIR"

echo "[INFO] Firefox profile fix setup complete."