#!/bin/bash

# ZorinOS Kiosk User Setup Script
# Features: #1, 2, 8, 9, 10, 11, 12

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/user_setup.sh.log"

# Ensure log directory exists (as root, this script should have permissions)
mkdir -p "$LOG_DIR"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting user_setup.sh script. Path: $(readlink -f "$0"), Current directory: $(pwd)"

# Exit on any error
set -e
log_message "Error handling enabled with 'set -e'"

# Check if running as root
log_message "Checking if script is running as root"
if [ "$(id -u)" -ne 0 ]; then
  log_message "Error: This script must be run as root. Please use sudo."
  echo "[ERROR] This script must be run as root. Please use sudo." # Keep for direct user feedback
  exit 1
fi
log_message "Script is running as root, continuing"

# Source the environment file
log_message "Checking for environment file"
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env" # Corrected path from ../a to ../.env
  log_message "ENV_FILE not defined, using default: $ENV_FILE"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")"
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/.env"
        log_message "Looking for .env next to kiosk_setup.sh: $ENV_FILE"
        break
      fi
    done
  fi
fi

log_message "Checking if environment file exists at: $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  log_message "Error: Environment file not found at $ENV_FILE. Please specify the correct path using the ENV_FILE variable."
  echo "[ERROR] Environment file not found at $ENV_FILE" # Keep for direct user feedback
  echo "[ERROR] Please specify the correct path using the ENV_FILE variable." # Keep for direct user feedback
  exit 1
fi

log_message "Sourcing environment file: $ENV_FILE"
source "$ENV_FILE"
log_message "Environment file sourced successfully"

# Print environment variables for debugging
log_message "KIOSK_USERNAME=$KIOSK_USERNAME"
log_message "KIOSK_FULLNAME=$KIOSK_FULLNAME"
log_message "OPT_KIOSK_DIR=$OPT_KIOSK_DIR"
log_message "TEMPLATE_DIR=$TEMPLATE_DIR"
log_message "WALLPAPER_ADMIN_PATH=$WALLPAPER_ADMIN_PATH"
log_message "WALLPAPER_SYSTEM_PATH=$WALLPAPER_SYSTEM_PATH"

# 1. Create kiosk user first
log_message "Feature #1: Creating kiosk user"
log_message "Checking if user $KIOSK_USERNAME already exists"
if id "$KIOSK_USERNAME" &>/dev/null; then
  log_message "User $KIOSK_USERNAME already exists, skipping creation"
else
  log_message "User $KIOSK_USERNAME does not exist, creating now"
  adduser --disabled-password --gecos "$KIOSK_FULLNAME" "$KIOSK_USERNAME"
  log_message "Setting password for $KIOSK_USERNAME"
  echo "$KIOSK_USERNAME:$KIOSK_PASSWORD" | chpasswd
  log_message "Adding $KIOSK_USERNAME to necessary groups"
  usermod -aG video,audio,plugdev,netdev,lp,lpadmin,scanner,cdrom,dialout "$KIOSK_USERNAME"
  log_message "User $KIOSK_USERNAME created and configured successfully"
fi

# 2. Create /opt/kiosk directory for scripts and templates
log_message "Feature #2: Creating kiosk directories"
log_message "Creating main kiosk directory at $OPT_KIOSK_DIR"
mkdir -p "$OPT_KIOSK_DIR"
log_message "Creating template directory at $TEMPLATE_DIR"
mkdir -p "$TEMPLATE_DIR"
log_message "Creating Desktop template directory"
mkdir -p "$TEMPLATE_DIR/Desktop"
log_message "Creating Documents template directory"
mkdir -p "$TEMPLATE_DIR/Documents"
log_message "Creating autostart template directory"
mkdir -p "$TEMPLATE_DIR/.config/autostart"
log_message "Creating applications template directory"
mkdir -p "$TEMPLATE_DIR/.local/share/applications"
log_message "Setting permissions on $OPT_KIOSK_DIR"
chmod 755 "$OPT_KIOSK_DIR"
log_message "All kiosk directories created successfully"

# 8. Create init_kiosk.sh script to initialize the kiosk environment
log_message "Feature #8: Creating kiosk initialization script"
INIT_SCRIPT="$OPT_KIOSK_DIR/init_kiosk.sh"
log_message "Initialization script will be created at: $INIT_SCRIPT"

# Define the log file path for the generated init_kiosk.sh script
GENERATED_INIT_LOG_FILE="$LOG_DIR/init_kiosk.sh.log" # Use the global LOG_DIR

cat > "$INIT_SCRIPT" << EOF
#!/bin/bash

# Script to initialize kiosk environment on login

# Log initialization
# Using the path directly from the parent script's LOG_DIR variable.
LOGFILE="$GENERATED_INIT_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

# KIOSK_USERNAME and OPT_KIOSK_DIR are expanded by user_setup.sh
# So their values will be hardcoded into this generated script.
KIOSK_USERNAME_EXPANDED="$KIOSK_USERNAME"
OPT_KIOSK_DIR_EXPANDED="$OPT_KIOSK_DIR"
TEMPLATE_DIR_EXPANDED="$TEMPLATE_DIR" # Also expand TEMPLATE_DIR

log_init_kiosk_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_init_kiosk_message "Initializing kiosk environment for user \$KIOSK_USERNAME_EXPANDED..."

# Ensure the log directory (part of OPT_KIOSK_DIR_EXPANDED if used previously) has correct permissions
# This script runs as the kiosk user, so it needs write access to its log file.
# The parent script (user_setup.sh) should ensure /var/log/kiosk is usable.
# If this script itself needs to create subdirs in /opt/kiosk, it might need sudo or correct perms.
# For now, assuming /var/log/kiosk is set up.

log_init_kiosk_message "Creating user directories..."
mkdir -p ~/Desktop
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/Pictures
mkdir -p ~/.config/autostart
mkdir -p ~/.local/share/applications
log_init_kiosk_message "User directories created/ensured."

# Copy template files to kiosk home directory
log_init_kiosk_message "Using template directory: \$TEMPLATE_DIR_EXPANDED"

# Run Firefox profile setup script
log_init_kiosk_message "Waiting a few seconds before Firefox profile setup to allow desktop to settle..."
sleep 5
log_init_kiosk_message "Running Firefox profile setup script: sudo \$OPT_KIOSK_DIR_EXPANDED/setup_firefox_profile.sh"
sudo \$OPT_KIOSK_DIR_EXPANDED/setup_firefox_profile.sh >> "\$LOGFILE" 2>&1
log_init_kiosk_message "Firefox profile setup completed."
log_init_kiosk_message "Waiting a few seconds after Firefox profile setup..."
sleep 3

# Copy desktop shortcuts if they exist
if [ -d "\$TEMPLATE_DIR_EXPANDED/Desktop" ]; then
  log_init_kiosk_message "Copying desktop shortcuts from template..."
  cp -r "\$TEMPLATE_DIR_EXPANDED/Desktop/"* ~/Desktop/ 2>/dev/null || log_init_kiosk_message "No desktop shortcuts to copy or error during copy."
  log_init_kiosk_message "Desktop shortcuts copied (or none found)."
fi

# Copy documents if they exist
if [ -d "\$TEMPLATE_DIR_EXPANDED/Documents" ]; then
  log_init_kiosk_message "Copying documents from template..."
  cp -r "\$TEMPLATE_DIR_EXPANDED/Documents/"* ~/Documents/ 2>/dev/null || log_init_kiosk_message "No documents to copy or error during copy."
  log_init_kiosk_message "Documents copied (or none found)."
fi

# Copy autostart entries if they exist
if [ -d "\$TEMPLATE_DIR_EXPANDED/.config/autostart" ]; then
  log_init_kiosk_message "Copying autostart entries from template..."
  cp -r "\$TEMPLATE_DIR_EXPANDED/.config/autostart/"* ~/.config/autostart/ 2>/dev/null || log_init_kiosk_message "No autostart entries to copy or error during copy."
  log_init_kiosk_message "Autostart entries copied (or none found)."
fi

# Set wallpaper
log_init_kiosk_message "Setting wallpaper using \$OPT_KIOSK_DIR_EXPANDED/set_wallpaper.sh"
\$OPT_KIOSK_DIR_EXPANDED/set_wallpaper.sh >> "\$LOGFILE" 2>&1
log_init_kiosk_message "Wallpaper set command executed."

log_init_kiosk_message "Kiosk environment initialized successfully."
EOF

log_message "Writing initialization script content to $INIT_SCRIPT"
chmod +x "$INIT_SCRIPT"
log_message "Made initialization script executable"
log_message "Kiosk initialization script created successfully"

# 9. Copy the wallpaper to the system backgrounds directory
log_message "Feature #9: Setting up wallpaper"
log_message "Checking for wallpaper at $WALLPAPER_ADMIN_PATH"
if [ -f "$WALLPAPER_ADMIN_PATH" ]; then
  log_message "Wallpaper found, copying to $WALLPAPER_SYSTEM_PATH"
  cp "$WALLPAPER_ADMIN_PATH" "$WALLPAPER_SYSTEM_PATH"
  log_message "Setting permissions on wallpaper file"
  chmod 644 "$WALLPAPER_SYSTEM_PATH"
  log_message "Wallpaper copied to system directory successfully"
else
  log_message "Warning: Wallpaper file not found at $WALLPAPER_ADMIN_PATH. Continuing without wallpaper."
fi

# 10. Create autostart entries in the template directory
log_message "Feature #10: Setting up autostart entries"
TEMPLATE_AUTOSTART_DIR="$TEMPLATE_DIR/.config/autostart"
log_message "Creating autostart directory at $TEMPLATE_AUTOSTART_DIR"
mkdir -p "$TEMPLATE_AUTOSTART_DIR"

# Define the log file path for the generated disable_screensaver.sh script
GENERATED_SCREENSAVER_LOG_FILE="$LOG_DIR/disable_screensaver.sh.log"

# Check if the disable_screensaver.sh script exists, create it if not
# Note: This might be created by tmpfs.sh, so we check first
if [ ! -f "$OPT_KIOSK_DIR/disable_screensaver.sh" ]; then
  log_message "Creating screen blanking prevention script at $OPT_KIOSK_DIR/disable_screensaver.sh"
  cat > "$OPT_KIOSK_DIR/disable_screensaver.sh" << EOF
#!/bin/bash

# Script to disable screen blanking and screen locking for Zorin OS 17 kiosk mode
# This script uses multiple methods to ensure screen blanking is disabled

# Log file for debugging
LOGFILE="$GENERATED_SCREENSAVER_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_screensaver_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_screensaver_message "Starting screen blanking prevention script..."

# Function to safely run xset commands with error handling
safe_xset() {
    if command -v xset &> /dev/null; then
        # Check if DISPLAY is set
        if [ -z "\$DISPLAY" ]; then # Escaped for generated script
            log_screensaver_message "DISPLAY environment variable not set, setting to :0"
            export DISPLAY=:0
        fi
        
        # Try to run xset command and capture any errors
        OUTPUT=\$(xset \$@ 2>&1) # Escaped for generated script
        if [ \$? -ne 0 ]; then # Escaped for generated script
            log_screensaver_message "xset \$@ failed: \$OUTPUT"
            return 1
        else
            log_screensaver_message "xset \$@ succeeded"
            return 0
        fi
    else
        log_screensaver_message "xset command not found"
        return 1
    fi
}

# Method 1: Use xset to disable DPMS and screen blanking with error handling
log_screensaver_message "Attempting to use xset to disable DPMS and screen blanking"

# Wait for X server to be ready (up to 30 seconds)
COUNTER=0
while [ \$COUNTER -lt 30 ]; do # Escaped for generated script
    if safe_xset q &>/dev/null; then
        log_screensaver_message "X server is ready"
        break
    fi
    log_screensaver_message "Waiting for X server to be ready (\$COUNTER/30)"
    sleep 1
    COUNTER=\$((COUNTER+1)) # Escaped for generated script
done

# Try different xset commands with error handling
safe_xset s off || log_screensaver_message "Failed to set xset s off"
safe_xset s noblank || log_screensaver_message "Failed to set xset s noblank"

# Try to disable DPMS if supported
if xset q | grep -q "DPMS"; then
    log_screensaver_message "DPMS is supported, attempting to disable"
    safe_xset -dpms || log_screensaver_message "Failed to disable DPMS with xset -dpms"
else
    log_screensaver_message "DPMS is not supported by this X server"
fi

# Method 2: Use gsettings to disable screen blanking and locking
if command -v gsettings &> /dev/null; then
    log_screensaver_message "Using gsettings to disable screen blanking and locking"
    
    # Function to safely set gsettings
    safe_gsettings_set() {
        local schema="\$1" # Escaped for generated script
        local key="\$2"   # Escaped for generated script
        local value="\$3" # Escaped for generated script
        
        # Check if schema exists
        if gsettings list-schemas 2>/dev/null | grep -q "^\$schema\$"; then # Escaped for generated script
            # Check if key exists in schema
            if gsettings list-keys "\$schema" 2>/dev/null | grep -q "^\$key\$"; then # Escaped for generated script
                log_screensaver_message "Setting \$schema \$key to \$value"
                gsettings set "\$schema" "\$key" "\$value" 2>/dev/null
                if [ \$? -eq 0 ]; then # Escaped for generated script
                    log_screensaver_message "Successfully set \$schema \$key to \$value"
                    return 0
                else
                    log_screensaver_message "Failed to set \$schema \$key to \$value"
                    return 1
                fi
            else
                log_screensaver_message "Key \$key not found in schema \$schema"
                return 1
            fi
        else
            log_screensaver_message "Schema \$schema not found"
            return 1
        fi
    }
    
    # Disable screen lock
    safe_gsettings_set "org.gnome.desktop.lockdown" "disable-lock-screen" "true"
    
    # Disable screensaver
    safe_gsettings_set "org.gnome.desktop.session" "idle-delay" "0" # uint32 0 might be needed for some
    safe_gsettings_set "org.gnome.desktop.screensaver" "lock-enabled" "false"
    safe_gsettings_set "org.gnome.desktop.screensaver" "idle-activation-enabled" "false"
    
    # Disable screen dimming
    safe_gsettings_set "org.gnome.settings-daemon.plugins.power" "idle-dim" "false"
    
    # Set power settings to never blank screen
    safe_gsettings_set "org.gnome.settings-daemon.plugins.power" "sleep-display-ac" "0"
    safe_gsettings_set "org.gnome.settings-daemon.plugins.power" "sleep-display-battery" "0"
    
    # Disable automatic suspend
    safe_gsettings_set "org.gnome.settings-daemon.plugins.power" "sleep-inactive-ac-type" "'nothing'"
    safe_gsettings_set "org.gnome.settings-daemon.plugins.power" "sleep-inactive-battery-type" "'nothing'"
    
    log_screensaver_message "gsettings commands completed"
else
    log_screensaver_message "gsettings command not found"
fi

# Method 3: Use dconf directly (for Zorin OS 17)
if command -v dconf &> /dev/null; then
    log_screensaver_message "Using dconf to disable screen blanking and locking"
    
    # Function to safely write dconf settings
    safe_dconf_write() {
        local path="\$1"  # Escaped for generated script
        local value="\$2" # Escaped for generated script
        
        log_screensaver_message "Setting dconf \$path to \$value"
        dconf write "\$path" "\$value" 2>/dev/null
        if [ \$? -eq 0 ]; then # Escaped for generated script
            log_screensaver_message "Successfully set dconf \$path to \$value"
            return 0
        else
            log_screensaver_message "Failed to set dconf \$path to \$value"
            return 1
        fi
    }
    
    # Disable screen lock
    safe_dconf_write "/org/gnome/desktop/lockdown/disable-lock-screen" "true"
    
    # Disable screensaver
    safe_dconf_write "/org/gnome/desktop/session/idle-delay" "uint32 0"
    safe_dconf_write "/org/gnome/desktop/screensaver/lock-enabled" "false"
    safe_dconf_write "/org/gnome/desktop/screensaver/idle-activation-enabled" "false"
    
    # Disable screen dimming
    safe_dconf_write "/org/gnome/settings-daemon/plugins/power/idle-dim" "false"
    
    # Set power settings to never blank screen
    safe_dconf_write "/org/gnome/settings-daemon/plugins/power/sleep-display-ac" "uint32 0"
    safe_dconf_write "/org/gnome/settings-daemon/plugins/power/sleep-display-battery" "uint32 0"
    
    # Disable automatic suspend
    safe_dconf_write "/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type" "'nothing'"
    safe_dconf_write "/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type" "'nothing'"
    
    # Zorin OS specific settings (if they exist)
    safe_dconf_write "/com/zorin/desktop/screensaver/lock-enabled" "false" 2>/dev/null || true
    safe_dconf_write "/com/zorin/desktop/session/idle-delay" "uint32 0" 2>/dev/null || true
    
    log_screensaver_message "dconf commands completed"
else
    log_screensaver_message "dconf command not found"
fi

# Method 4: Use a systemd inhibitor to prevent screen blanking
if command -v systemd-inhibit &> /dev/null; then
    log_screensaver_message "Using systemd-inhibit to prevent screen blanking"
    # Run a small sleep command that will keep the inhibitor active
    systemd-inhibit --what=idle:sleep:handle-lid-switch --who="Kiosk Mode" --why="Prevent screen blanking in kiosk mode" sleep infinity &
    INHIBIT_PID=\$! # Escaped for generated script
    log_screensaver_message "systemd-inhibit started with PID \$INHIBIT_PID"
else
    log_screensaver_message "systemd-inhibit command not found"
fi

# Method 5: Use a loop to simulate user activity (last resort)
log_screensaver_message "Starting activity simulation loop"
(
    while true; do
        # Simulate user activity every 60 seconds
        if command -v xdotool &> /dev/null; then
            # Move mouse 1 pixel right and then back
            xdotool mousemove_relative -- 1 0 2>/dev/null
            sleep 1
            xdotool mousemove_relative -- -1 0 2>/dev/null
            log_screensaver_message "Simulated mouse movement"
        else
            # If xdotool is not available, try to use DISPLAY to trigger activity
            if [ -n "\$DISPLAY" ]; then # Escaped for generated script
                # Try to use xset to reset the screensaver timer
                xset s reset 2>/dev/null || true
            fi
        fi
        sleep 60
    done
) &
ACTIVITY_PID=\$! # Escaped for generated script
log_screensaver_message "Activity simulation started with PID \$ACTIVITY_PID"

# Method 6: Use xfce4-power-manager settings if available (for Zorin OS Lite)
if command -v xfconf-query &> /dev/null; then
    log_screensaver_message "Detected xfconf-query, attempting to configure XFCE power settings"
    
    # Try to set XFCE power manager settings
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false 2>/dev/null && \
        log_screensaver_message "Disabled XFCE DPMS" || \
        log_screensaver_message "Failed to disable XFCE DPMS"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 2>/dev/null && \
        log_screensaver_message "Set XFCE blank-on-ac to 0" || \
        log_screensaver_message "Failed to set XFCE blank-on-ac"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -s 0 2>/dev/null && \
        log_screensaver_message "Set XFCE blank-on-battery to 0" || \
        log_screensaver_message "Failed to set XFCE blank-on-battery"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s 0 2>/dev/null && \
        log_screensaver_message "Set XFCE dpms-on-ac-off to 0" || \
        log_screensaver_message "Failed to set XFCE dpms-on-ac-off"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery-off -s 0 2>/dev/null && \
        log_screensaver_message "Set XFCE dpms-on-battery-off to 0" || \
        log_screensaver_message "Failed to set XFCE dpms-on-battery-off"
else
    log_screensaver_message "xfconf-query not found, skipping XFCE power settings"
fi

log_screensaver_message "Screen blanking prevention script methods applied. Script will keep running."

# Keep the script running to ensure settings persist
# This prevents the script from exiting and killing background processes
tail -f /dev/null
EOF
  chmod +x "$OPT_KIOSK_DIR/disable_screensaver.sh"
  log_message "Screen blanking prevention script created and made executable"
else
  log_message "Screen blanking prevention script $OPT_KIOSK_DIR/disable_screensaver.sh already exists, skipping creation"
fi

# Kiosk initialization autostart entry
log_message "Creating kiosk initialization autostart entry"
cat > "$TEMPLATE_AUTOSTART_DIR/kiosk-init.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Kiosk Initialization
Comment=Initializes the kiosk environment on login
Exec=$OPT_KIOSK_DIR/init_kiosk.sh
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
log_message "Kiosk initialization autostart entry created"

# Screen blanking prevention autostart entry
log_message "Creating screen blanking prevention autostart entry"
cat > "$TEMPLATE_AUTOSTART_DIR/disable-screensaver.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Disable Screensaver
Comment=Prevents the screen from blanking
Exec=$OPT_KIOSK_DIR/disable_screensaver.sh
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
log_message "Screen blanking prevention autostart entry created"

# Wallpaper setting autostart entry
log_message "Creating wallpaper setting autostart entry"
cat > "$TEMPLATE_AUTOSTART_DIR/set-wallpaper.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Set Wallpaper
Comment=Sets the desktop wallpaper
Exec=/bin/bash -c "sleep 3 && $OPT_KIOSK_DIR/set_wallpaper.sh"
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
log_message "Wallpaper setting autostart entry created"
log_message "All autostart entries created successfully"

# 11. Configure auto-login for the Kiosk user
log_message "Feature #11: Configuring auto-login for the Kiosk user"
# First, create the autologin group if it doesn't exist
log_message "Creating autologin group if it doesn't exist"
groupadd -f autologin
log_message "Adding $KIOSK_USERNAME to autologin group"
usermod -aG autologin "$KIOSK_USERNAME"

# Detect display manager
log_message "Detecting display manager"
DM_SERVICE=""
if [ -f "/etc/systemd/system/display-manager.service" ]; then
  DM_SERVICE=$(readlink -f /etc/systemd/system/display-manager.service)
  log_message "Detected display manager service: $DM_SERVICE"
else
  log_message "No display manager service found at /etc/systemd/system/display-manager.service"
  # Try alternative location for Zorin OS 17
  if [ -f "/lib/systemd/system/display-manager.service" ]; then
    DM_SERVICE=$(readlink -f /lib/systemd/system/display-manager.service)
    log_message "Detected display manager service at alternative location: $DM_SERVICE"
  else
    log_message "Will try to detect display manager by directory presence"
  fi
fi

# Determine which display manager is actually running
log_message "Checking which display manager is running"
RUNNING_DM=""
for dm in lightdm gdm gdm3 sddm; do
  if systemctl is-active --quiet $dm.service; then
    RUNNING_DM=$dm
    log_message "Found running display manager: $RUNNING_DM"
    break
  fi
done

# If no running display manager was found, try to determine from installed packages
if [ -z "$RUNNING_DM" ]; then
  log_message "No running display manager found, checking installed packages"
  if dpkg -l | grep -q "lightdm"; then
    RUNNING_DM="lightdm"
    log_message "LightDM package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "gdm3"; then
    RUNNING_DM="gdm3"
    log_message "GDM3 package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "gdm"; then
    RUNNING_DM="gdm"
    log_message "GDM package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "sddm"; then
    RUNNING_DM="sddm"
    log_message "SDDM package is installed, assuming it's the display manager"
  fi
fi

# Configure LightDM for autologin if it's being used (Zorin OS typically uses LightDM)
log_message "Checking for LightDM"
if [ -d "/etc/lightdm" ] || [[ "$DM_SERVICE" == *"lightdm"* ]] || [[ "$RUNNING_DM" == "lightdm" ]]; then
  log_message "LightDM detected, configuring for autologin"
  log_message "Creating /etc/lightdm directory if it doesn't exist"
  mkdir -p /etc/lightdm
  
  # Backup existing configuration if it exists
  if [ -f "/etc/lightdm/lightdm.conf" ]; then
    log_message "Backing up existing LightDM configuration to /etc/lightdm/lightdm.conf.bak"
    cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.bak
  fi
  
  # Check if the file already has autologin settings
  if [ -f "/etc/lightdm/lightdm.conf" ] && grep -q "\[Seat:\*\]" /etc/lightdm/lightdm.conf; then
    log_message "Updating existing LightDM configuration in /etc/lightdm/lightdm.conf"
    # Update existing configuration
    sed -i '/^\[Seat:\*\]/,/^\[/ s/^autologin-user=.*/autologin-user='$KIOSK_USERNAME'/' /etc/lightdm/lightdm.conf
    sed -i '/^\[Seat:\*\]/,/^\[/ s/^autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
    
    # Add settings if they don't exist under [Seat:*]
    if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf; then
      sed -i '/^\[Seat:\*\]/a autologin-user='$KIOSK_USERNAME'' /etc/lightdm/lightdm.conf
    fi
    if ! grep -q "^autologin-user-timeout=" /etc/lightdm/lightdm.conf; then
      sed -i '/^\[Seat:\*\]/a autologin-user-timeout=0' /etc/lightdm/lightdm.conf
    fi
  else
    log_message "Creating new LightDM configuration file /etc/lightdm/lightdm.conf"
    # Create new configuration file
    cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-guest=false
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
autologin-session=zorin
user-session=zorin
greeter-session=slick-greeter
EOF
  fi
  log_message "Main LightDM configuration file created/updated"

  # Create a separate autologin configuration file
  log_message "Creating LightDM autologin configuration directory /etc/lightdm/lightdm.conf.d"
  mkdir -p /etc/lightdm/lightdm.conf.d
  log_message "Creating LightDM autologin configuration file /etc/lightdm/lightdm.conf.d/12-autologin.conf"
  cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << EOF
[Seat:*]
autologin-guest=false
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
EOF
  
  # Create additional configuration for Zorin OS 17
  log_message "Creating additional LightDM configuration for Zorin OS 17 at /etc/lightdm/lightdm.conf.d/20-zorin-autologin.conf"
  cat > /etc/lightdm/lightdm.conf.d/20-zorin-autologin.conf << EOF
[Seat:*]
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
EOF

  # Configure slick-greeter specifically (used by Zorin OS)
  log_message "Configuring slick-greeter for autologin at /etc/lightdm/slick-greeter.conf.d/10-autologin.conf"
  mkdir -p /etc/lightdm/slick-greeter.conf.d
  cat > /etc/lightdm/slick-greeter.conf.d/10-autologin.conf << EOF
[Greeter]
automatic-login-user=$KIOSK_USERNAME
automatic-login=true
EOF

  log_message "LightDM autologin configuration completed"
  
  # Ensure LightDM service is enabled
  log_message "Ensuring LightDM service is enabled"
  systemctl enable lightdm.service
else
  log_message "LightDM not detected"
fi

# Configure GDM for autologin if it's being used
log_message "Checking for GDM"
if [ -d "/etc/gdm3" ] || [[ "$DM_SERVICE" == *"gdm"* ]] || [[ "$RUNNING_DM" == "gdm"* ]]; then
  log_message "GDM detected, configuring for autologin"
  log_message "Creating /etc/gdm3 directory if it doesn't exist"
  mkdir -p /etc/gdm3
  if [ -f "/etc/gdm3/custom.conf" ]; then
    log_message "Existing GDM configuration found at /etc/gdm3/custom.conf, backing up to /etc/gdm3/custom.conf.bak"
    cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak
    
    log_message "Updating GDM configuration in /etc/gdm3/custom.conf"
    # Check if [daemon] section exists
    if grep -q "^\[daemon\]" /etc/gdm3/custom.conf; then
      log_message "[daemon] section found, updating settings"
      sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
      sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLogin=.*/AutomaticLogin='$KIOSK_USERNAME'/' /etc/gdm3/custom.conf
      
      # Add settings if they don't exist under [daemon]
      if ! grep -q "^AutomaticLoginEnable=" /etc/gdm3/custom.conf; then
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' /etc/gdm3/custom.conf
      fi
      if ! grep -q "^AutomaticLogin=" /etc/gdm3/custom.conf; then
        sed -i '/^\[daemon\]/a AutomaticLogin='$KIOSK_USERNAME'' /etc/gdm3/custom.conf
      fi
    else
      log_message "[daemon] section not found, adding it"
      echo -e "\n[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$KIOSK_USERNAME" >> /etc/gdm3/custom.conf
    fi
    log_message "GDM configuration updated"
  else
    log_message "Creating GDM auto-login configuration file /etc/gdm3/custom.conf"
    echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$KIOSK_USERNAME" > /etc/gdm3/custom.conf
  fi
  log_message "GDM autologin configuration completed"
  
  # Ensure GDM service is enabled
  log_message "Ensuring GDM service is enabled"
  if [ "$RUNNING_DM" == "gdm" ]; then
    systemctl enable gdm.service
  elif [ "$RUNNING_DM" == "gdm3" ]; then
    systemctl enable gdm3.service
  fi
else
  log_message "GDM not detected"
fi

# Configure SDDM for autologin if it's being used
log_message "Checking for SDDM"
if [ -d "/etc/sddm.conf.d" ] || [[ "$DM_SERVICE" == *"sddm"* ]] || [[ "$RUNNING_DM" == "sddm" ]]; then
  log_message "SDDM detected, configuring for autologin"
  log_message "Creating SDDM configuration directory /etc/sddm.conf.d"
  mkdir -p /etc/sddm.conf.d
  log_message "Creating SDDM autologin configuration file /etc/sddm.conf.d/autologin.conf"
  cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$KIOSK_USERNAME
Session=zorin
EOF
  log_message "SDDM autologin configuration completed"
  
  # Ensure SDDM service is enabled
  log_message "Ensuring SDDM service is enabled"
  systemctl enable sddm.service
else
  log_message "SDDM not detected"
fi

# Additional check for Zorin OS 17 specific configuration
log_message "Checking for Zorin OS 17 specific configuration"
if [ -f "/etc/os-release" ] && grep -q "Zorin OS" /etc/os-release; then
  ZORIN_VERSION=$(grep "VERSION_ID" /etc/os-release | cut -d= -f2 | tr -d '"')
  log_message "Detected Zorin OS version: $ZORIN_VERSION"
  
  # For Zorin OS 17, ensure we're using the correct session name
  if [[ "$ZORIN_VERSION" == "17"* ]]; then
    log_message "Applying Zorin OS 17 specific configuration"
    
    # Update LightDM configuration with correct session name if LightDM is used
    if [ -d "/etc/lightdm" ] || [[ "$DM_SERVICE" == *"lightdm"* ]] || [[ "$RUNNING_DM" == "lightdm" ]]; then
      log_message "Updating LightDM configuration with correct session name for Zorin OS 17"
      
      # Get the correct session name
      ZORIN_SESSION_NAME="zorin" # Default
      if [ -d "/usr/share/xsessions" ]; then
        for session_file in /usr/share/xsessions/*.desktop; do
          if grep -q "Name=Zorin Desktop" "$session_file"; then # More specific check
            ZORIN_SESSION_NAME=$(basename "$session_file" .desktop)
            log_message "Found Zorin session: $ZORIN_SESSION_NAME from $session_file"
            break
          elif grep -q "Zorin" "$session_file"; then # Fallback check
            ZORIN_SESSION_NAME=$(basename "$session_file" .desktop)
            log_message "Found Zorin-related session (fallback): $ZORIN_SESSION_NAME from $session_file"
          fi
        done
      fi
      
      # Update the session name in the configuration
      if [ -f "/etc/lightdm/lightdm.conf" ]; then
        sed -i "s/^autologin-session=.*/autologin-session=$ZORIN_SESSION_NAME/" /etc/lightdm/lightdm.conf
        sed -i "s/^user-session=.*/user-session=$ZORIN_SESSION_NAME/" /etc/lightdm/lightdm.conf
        log_message "LightDM configuration /etc/lightdm/lightdm.conf updated with session: $ZORIN_SESSION_NAME"
      fi
      
      # Try to use Zorin OS specific tools if available
      if command -v zorin-auto-login &> /dev/null; then
        log_message "Found Zorin OS auto-login tool, using it to enable for $KIOSK_USERNAME"
        zorin-auto-login enable "$KIOSK_USERNAME" || log_message "Warning: Failed to use zorin-auto-login tool"
      fi
    fi
    
    # Try to use dconf to set auto-login (Zorin OS 17 specific)
    if command -v dconf &> /dev/null; then
      log_message "Using dconf to set auto-login for Zorin OS 17 for user $KIOSK_USERNAME"
      # Create a temporary script to run dconf as the kiosk user
      DCONF_SCRIPT="/tmp/dconf_autologin_$KIOSK_USERNAME.sh" # User-specific temp file
      # Define the log file path for the generated dconf script
      GENERATED_DCONF_LOG_FILE="$LOG_DIR/dconf_autologin_script.log"

      cat > "$DCONF_SCRIPT" << EOF
#!/bin/bash
LOGFILE="$GENERATED_DCONF_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")"

log_dconf_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_dconf_message "Starting dconf_autologin script for user \$(id -un)..."

# Wait for D-Bus session to be available (up to 30 seconds)
COUNTER=0
while [ \$COUNTER -lt 30 ]; do
    if [ -n "\$DBUS_SESSION_BUS_ADDRESS" ] && [ -e "\$(echo \$DBUS_SESSION_BUS_ADDRESS | sed 's/unix:path=//')" ]; then
        log_dconf_message "D-Bus session found at \$DBUS_SESSION_BUS_ADDRESS"
        break
    elif [ -e "/run/user/\$(id -u)/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus
        log_dconf_message "D-Bus session found at /run/user/\$(id -u)/bus, exported DBUS_SESSION_BUS_ADDRESS."
        break
    fi
    log_dconf_message "Waiting for D-Bus session (\$COUNTER/30)..."
    sleep 1
    COUNTER=\$((COUNTER+1))
done

if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ] || ! [ -e "\$(echo \$DBUS_SESSION_BUS_ADDRESS | sed 's/unix:path=//')" ]; then
    log_dconf_message "Error: D-Bus session not available. Cannot run dconf commands."
    exit 1
fi

# Function to safely write dconf settings
safe_dconf_write() {
    local path="\$1"
    local value="\$2"
    local schema="\$(echo "\$path" | cut -d'/' -f2-3)" # e.g. org/gnome
    
    log_dconf_message "Attempting to write dconf: Path=\$path, Value=\$value"
    # Check if schema exists by trying to list keys
    if dconf list "/\$schema/" &>/dev/null; then
        log_dconf_message "Schema /\$schema/ exists."
        # Check if key exists by trying to read it (value doesn't matter here)
        # dconf read "\$path" &>/dev/null # This can fail if key not set, not a reliable check for existence
        # For now, assume key exists if schema does, or dconf write will fail gracefully
        dconf write "\$path" "\$value"
        if [ \$? -eq 0 ]; then
            log_dconf_message "Successfully set dconf: \$path to \$value"
        else
            log_dconf_message "Warning: Failed to set dconf: \$path to \$value (Error code: \$?). Key might not exist or wrong value type."
        fi
    else
        log_dconf_message "Schema /\$schema/ not found, skipping dconf write for \$path"
    fi
}

# Try to set auto-login using dconf with error handling
safe_dconf_write "/org/gnome/login-screen/enable-auto-login" "true"
safe_dconf_write "/org/gnome/login-screen/auto-login-user" "'$KIOSK_USERNAME'"

# Try Zorin OS specific settings
safe_dconf_write "/com/zorin/desktop/login-screen/enable-auto-login" "true" # Zorin 16/17
safe_dconf_write "/com/zorin/desktop/login-screen/auto-login-user" "'$KIOSK_USERNAME'" # Zorin 16/17

# Try to disable screen lock
safe_dconf_write "/org/gnome/desktop/lockdown/disable-lock-screen" "true"
safe_dconf_write "/org/gnome/desktop/screensaver/lock-enabled" "false"
log_dconf_message "dconf_autologin script finished."
EOF
      chmod +x "$DCONF_SCRIPT"
      
      # Run the script as the kiosk user if possible
      if id "$KIOSK_USERNAME" &>/dev/null; then
        log_message "Running dconf script $DCONF_SCRIPT as $KIOSK_USERNAME"
        # Ensure XDG_RUNTIME_DIR is set for the su command context
        KioskUID=$(id -u "$KIOSK_USERNAME")
        export KioskUID # Make it available for su
        su - "$KIOSK_USERNAME" -c "export XDG_RUNTIME_DIR=/run/user/\$KioskUID; $DCONF_SCRIPT" || log_message "Warning: Failed to run dconf script as $KIOSK_USERNAME, but continuing"
      else
        log_message "Warning: Could not run dconf script as $KIOSK_USERNAME, user may not exist yet"
      fi
      
      # Clean up
      # rm -f "$DCONF_SCRIPT" # Keep for debugging for now
      log_message "Dconf script execution attempted. Log at $GENERATED_DCONF_LOG_FILE"
    fi
  fi
fi

# 12. Configure AccountsService for autologin
log_message "Feature #12: Configuring AccountsService for autologin"
log_message "Creating AccountsService users directory /var/lib/AccountsService/users"
mkdir -p /var/lib/AccountsService/users

# Determine the correct session name for Zorin OS
ZORIN_SESSION_FOR_AS="zorin" # Default
if [ -d "/usr/share/xsessions" ]; then
  for session_as_file in /usr/share/xsessions/*.desktop; do
    if grep -q "Name=Zorin Desktop" "$session_as_file"; then
      ZORIN_SESSION_FOR_AS=$(basename "$session_as_file" .desktop)
      log_message "Found Zorin session for AccountsService: $ZORIN_SESSION_FOR_AS from $session_as_file"
      break
    elif grep -q "Zorin" "$session_as_file"; then
      ZORIN_SESSION_FOR_AS=$(basename "$session_as_file" .desktop)
      log_message "Found Zorin-related session (fallback) for AccountsService: $ZORIN_SESSION_FOR_AS from $session_as_file"
    fi
  done
fi

log_message "Creating AccountsService configuration for $KIOSK_USERNAME with session $ZORIN_SESSION_FOR_AS at /var/lib/AccountsService/users/$KIOSK_USERNAME"
cat > /var/lib/AccountsService/users/$KIOSK_USERNAME << EOF
[User]
Language=
XSession=$ZORIN_SESSION_FOR_AS
SystemAccount=false
Icon=/usr/share/pixmaps/faces/user-generic.png
AutomaticLogin=true
EOF

# Try to use loginctl to enable auto-login
if command -v loginctl > /dev/null; then
  log_message "Using loginctl to enable linger for $KIOSK_USERNAME"
  loginctl enable-linger "$KIOSK_USERNAME" || log_message "Warning: Failed to enable linger for $KIOSK_USERNAME"
  
  # For systemd-based login managers (tty login, not graphical)
  if [ -d "/etc/systemd/system" ]; then
    log_message "Creating systemd auto-login override for tty1 at /etc/systemd/system/getty@tty1.service.d/override.conf"
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USERNAME --noclear %I \$TERM
EOF
    log_message "Reloading systemd daemon after creating getty override"
    systemctl daemon-reload
    log_message "Systemd auto-login override for tty1 created"
  fi
fi

# Set GSettings for auto-login if available (ran as root, targets system defaults or specific user if possible)
if command -v gsettings > /dev/null; then
  log_message "Attempting to set GSettings for auto-login (as root)"
  
  # Create a temporary script to check available schemas and set appropriate settings
  # This script will be run as root, so it might set system-wide defaults or need specific user context.
  GSETTINGS_ROOT_SCRIPT="/tmp/gsettings_autologin_root.sh"
  GENERATED_GSETTINGS_ROOT_LOG_FILE="$LOG_DIR/gsettings_autologin_root_script.log"

  cat > "$GSETTINGS_ROOT_SCRIPT" << EOF
#!/bin/bash
LOGFILE="$GENERATED_GSETTINGS_ROOT_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")"

log_gsettings_root_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}
log_gsettings_root_message "Starting gsettings_autologin_root script..."

# Function to safely set gsettings (for root context)
# This might not always work as expected for user-specific settings without proper DBUS env.
safe_gsettings_root_set() {
  local schema="\$1"
  local key="\$2"
  local value="\$3"
  
  log_gsettings_root_message "Attempting to set GSetting (root): Schema=\$schema, Key=\$key, Value=\$value"
  if gsettings list-schemas 2>/dev/null | grep -q "^\$schema\$"; then
    if gsettings list-keys "\$schema" 2>/dev/null | grep -q "^\$key\$"; then
      if gsettings set "\$schema" "\$key" "\$value" 2>/dev/null; then
        log_gsettings_root_message "Successfully set GSetting (root): \$schema \$key to \$value"
        return 0
      else
        log_gsettings_root_message "Warning: Failed to set GSetting (root): \$schema \$key to \$value. Error: \$?"
        return 1
      fi
    else
      log_gsettings_root_message "GSetting Key \$key not found in schema \$schema (root)"
      return 1
    fi
  else
    log_gsettings_root_message "GSetting Schema \$schema not found (root)"
    return 1
  fi
}

# Try different schemas and keys for auto-login settings
USERNAME_PARAM="$KIOSK_USERNAME" # KIOSK_USERNAME is expanded by parent script

# Try GNOME login screen settings
safe_gsettings_root_set "org.gnome.login-screen" "enable-auto-login" "true"
safe_gsettings_root_set "org.gnome.login-screen" "auto-login-user" "'\$USERNAME_PARAM'"

# Try Zorin OS specific settings if they exist
safe_gsettings_root_set "com.zorin.desktop.login-screen" "enable-auto-login" "true"
safe_gsettings_root_set "com.zorin.desktop.login-screen" "auto-login-user" "'\$USERNAME_PARAM'"

log_gsettings_root_message "GSettings configuration attempt (root) completed."
EOF
  chmod +x "$GSETTINGS_ROOT_SCRIPT"
  
  log_message "Running GSettings root script $GSETTINGS_ROOT_SCRIPT"
  bash "$GSETTINGS_ROOT_SCRIPT" || log_message "Warning: GSettings root script failed or had issues."
  # rm -f "$GSETTINGS_ROOT_SCRIPT" # Keep for debugging
  log_message "GSettings root script execution attempted. Log at $GENERATED_GSETTINGS_ROOT_LOG_FILE"
else
  log_message "gsettings command not available, skipping GSettings configuration (root attempt)"
fi

# Create a systemd user service for the kiosk user to ensure auto-login settings persist
log_message "Creating systemd user service for auto-login persistence at /home/$KIOSK_USERNAME/.config/systemd/user/kiosk-autologin.service"
mkdir -p "/home/$KIOSK_USERNAME/.config/systemd/user/" # Ensure path uses KIOSK_USERNAME var

# Define the log file path for the generated kiosk-autologin.service script
GENERATED_AUTOLOGIN_SERVICE_LOG_FILE="$LOG_DIR/kiosk-autologin.service.log"

cat > "/home/$KIOSK_USERNAME/.config/systemd/user/kiosk-autologin.service" << EOF
[Unit]
Description=Kiosk Auto-Login Settings Persistence Service
After=graphical.target network-online.target # Wait for graphical and network

[Service]
Type=oneshot
# This service runs as the kiosk user. DBUS_SESSION_BUS_ADDRESS should be available.
# Log output of these commands
ExecStart=/bin/sh -c 'echo "\$(date) - kiosk-autologin.service: Applying dconf settings..." >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
ExecStart=/bin/sh -c 'dconf write /org/gnome/desktop/lockdown/disable-lock-screen true >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed disable-lock-screen" >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
ExecStart=/bin/sh -c 'dconf write /org/gnome/desktop/screensaver/lock-enabled false >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed lock-enabled" >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
ExecStart=/bin/sh -c 'dconf write /org/gnome/login-screen/enable-auto-login true >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed enable-auto-login" >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
ExecStart=/bin/sh -c 'dconf write /org/gnome/login-screen/auto-login-user "'$KIOSK_USERNAME'" >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed auto-login-user" >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
ExecStart=/bin/sh -c 'echo "\$(date) - kiosk-autologin.service: dconf settings applied." >> $GENERATED_AUTOLOGIN_SERVICE_LOG_FILE 2>&1'
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

# Set proper ownership
log_message "Setting ownership for /home/$KIOSK_USERNAME/.config to $KIOSK_USERNAME:$KIOSK_USERNAME"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/.config/"

# Enable the service for the user
if command -v systemctl > /dev/null && id "$KIOSK_USERNAME" &>/dev/null; then
  log_message "Enabling kiosk-autologin.service for user $KIOSK_USERNAME"
  KioskUID_for_service=$(id -u "$KIOSK_USERNAME")
  su - "$KIOSK_USERNAME" -c "export XDG_RUNTIME_DIR=/run/user/$KioskUID_for_service; systemctl --user enable kiosk-autologin.service" || log_message "Warning: Failed to enable kiosk-autologin.service for user $KIOSK_USERNAME"
fi

log_message "AccountsService and related auto-login configurations completed."

# Create a script to verify and fix auto-login on each boot
log_message "Creating auto-login verification script at /usr/local/sbin/verify-autologin.sh"
# Define the log file path for the generated verify-autologin.sh script
GENERATED_VERIFY_AUTOLOGIN_LOG_FILE="$LOG_DIR/verify-autologin.sh.log"

cat > /usr/local/sbin/verify-autologin.sh << EOF
#!/bin/bash

# Script to verify and fix auto-login settings on boot
LOGFILE="$GENERATED_VERIFY_AUTOLOGIN_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")"

log_verify_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

KIOSK_USER_PARAM="\$1" # Parameter passed to the script
if [ -z "\$KIOSK_USER_PARAM" ]; then
  log_verify_message "Error: Usage: \$0 <username>. KIOSK_USER_PARAM is empty."
  exit 1
fi
log_verify_message "Starting verify-autologin.sh for user \$KIOSK_USER_PARAM"

# Check LightDM configuration
if [ -d "/etc/lightdm" ]; then
  log_verify_message "Verifying LightDM configuration..."
  # Ensure auto-login is configured in lightdm.conf
  if [ -f "/etc/lightdm/lightdm.conf" ]; then
    if ! grep -q "autologin-user=\$KIOSK_USER_PARAM" /etc/lightdm/lightdm.conf; then
      log_verify_message "Fixing LightDM auto-login in /etc/lightdm/lightdm.conf for \$KIOSK_USER_PARAM..."
      if grep -q "\[Seat:\*\]" /etc/lightdm/lightdm.conf; then
        sed -i '/^\[Seat:\*\]/a autologin-user='\$KIOSK_USER_PARAM'' /etc/lightdm/lightdm.conf
        # Ensure timeout is also set or updated
        if ! grep -q "autologin-user-timeout=0" /etc/lightdm/lightdm.conf; then
            sed -i '/^\[Seat:\*\]/a autologin-user-timeout=0' /etc/lightdm/lightdm.conf
        else
            sed -i '/^\[Seat:\*\]/,/^\[/ s/^autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
        fi
      else
        echo -e "\n[Seat:*]\nautologin-user=\$KIOSK_USER_PARAM\nautologin-user-timeout=0" >> /etc/lightdm/lightdm.conf
      fi
    else
      log_verify_message "LightDM autologin-user already set for \$KIOSK_USER_PARAM in /etc/lightdm/lightdm.conf."
    fi
  fi
  
  # Ensure auto-login is configured in lightdm.conf.d
  mkdir -p /etc/lightdm/lightdm.conf.d
  CONF_D_FILE="/etc/lightdm/lightdm.conf.d/12-autologin.conf"
  if [ ! -f "\$CONF_D_FILE" ] || ! grep -q "autologin-user=\$KIOSK_USER_PARAM" "\$CONF_D_FILE"; then
    log_verify_message "Creating/Fixing LightDM auto-login configuration file: \$CONF_D_FILE for \$KIOSK_USER_PARAM..."
    echo -e "[Seat:*]\nautologin-guest=false\nautologin-user=\$KIOSK_USER_PARAM\nautologin-user-timeout=0" > "\$CONF_D_FILE"
  else
    log_verify_message "LightDM autologin already set in \$CONF_D_FILE for \$KIOSK_USER_PARAM."
  fi
fi

# Check GDM configuration
if [ -d "/etc/gdm3" ]; then
  log_verify_message "Verifying GDM configuration..."
  GDM_CONF_FILE="/etc/gdm3/custom.conf"
  if [ -f "\$GDM_CONF_FILE" ]; then
    if ! grep -q "AutomaticLoginEnable=true" "\$GDM_CONF_FILE" || ! grep -q "AutomaticLogin=\$KIOSK_USER_PARAM" "\$GDM_CONF_FILE"; then
      log_verify_message "Fixing GDM auto-login configuration in \$GDM_CONF_FILE for \$KIOSK_USER_PARAM..."
      if grep -q "^\[daemon\]" "\$GDM_CONF_FILE"; then
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin='\$KIOSK_USER_PARAM'' "\$GDM_CONF_FILE" # This might add duplicates if one exists
        # Better: ensure they are set correctly
        sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' "\$GDM_CONF_FILE"
        sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLogin=.*/AutomaticLogin='\$KIOSK_USER_PARAM'/' "\$GDM_CONF_FILE"
        if ! grep -q "^AutomaticLoginEnable=" "\$GDM_CONF_FILE"; then sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' "\$GDM_CONF_FILE"; fi
        if ! grep -q "^AutomaticLogin=" "\$GDM_CONF_FILE"; then sed -i '/^\[daemon\]/a AutomaticLogin='\$KIOSK_USER_PARAM'' "\$GDM_CONF_FILE"; fi
      else
        echo -e "\n[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=\$KIOSK_USER_PARAM" >> "\$GDM_CONF_FILE"
      fi
    else
      log_verify_message "GDM autologin already set in \$GDM_CONF_FILE for \$KIOSK_USER_PARAM."
    fi
  else
    log_verify_message "Creating GDM auto-login configuration file \$GDM_CONF_FILE for \$KIOSK_USER_PARAM..."
    echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=\$KIOSK_USER_PARAM" > "\$GDM_CONF_FILE"
  fi
fi

# Check AccountsService configuration
ACCOUNTS_SERVICE_USER_FILE="/var/lib/AccountsService/users/\$KIOSK_USER_PARAM"
mkdir -p "/var/lib/AccountsService/users"
ZORIN_SESSION_VERIFY="zorin" # Default, should match parent script logic if possible
# Simple check for now, can be enhanced to detect session like parent script
if [ -d "/usr/share/xsessions" ]; then
  for session_verify_file in /usr/share/xsessions/*.desktop; do
    if grep -q "Name=Zorin Desktop" "\$session_verify_file"; then
      ZORIN_SESSION_VERIFY=\$(basename "\$session_verify_file" .desktop)
      break
    elif grep -q "Zorin" "\$session_verify_file"; then
      ZORIN_SESSION_VERIFY=\$(basename "\$session_verify_file" .desktop)
    fi
  done
fi
log_verify_message "Using session \$ZORIN_SESSION_VERIFY for AccountsService verification."

if [ ! -f "\$ACCOUNTS_SERVICE_USER_FILE" ] || ! grep -q "AutomaticLogin=true" "\$ACCOUNTS_SERVICE_USER_FILE"; then
  log_verify_message "Fixing AccountsService auto-login configuration in \$ACCOUNTS_SERVICE_USER_FILE for \$KIOSK_USER_PARAM..."
  echo -e "[User]\nLanguage=\nXSession=\$ZORIN_SESSION_VERIFY\nSystemAccount=false\nIcon=/usr/share/pixmaps/faces/user-generic.png\nAutomaticLogin=true" > "\$ACCOUNTS_SERVICE_USER_FILE"
else
  log_verify_message "AccountsService autologin already set in \$ACCOUNTS_SERVICE_USER_FILE for \$KIOSK_USER_PARAM."
fi

log_verify_message "Auto-login verification completed for user \$KIOSK_USER_PARAM."
EOF

chmod +x /usr/local/sbin/verify-autologin.sh
log_message "Made verify-autologin.sh executable"

# Create a systemd service to run the verification script on boot
log_message "Creating systemd service for auto-login verification at /etc/systemd/system/verify-autologin.service"
# KIOSK_USERNAME is expanded by the parent script (user_setup.sh)
cat > /etc/systemd/system/verify-autologin.service << EOF
[Unit]
Description=Verify and fix auto-login settings for $KIOSK_USERNAME
After=network.target display-manager.service accounts-daemon.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/verify-autologin.sh $KIOSK_USERNAME
RemainAfterExit=yes
StandardOutput=append:$LOG_DIR/verify-autologin.service.log
StandardError=append:$LOG_DIR/verify-autologin.service.err

[Install]
WantedBy=multi-user.target
EOF
log_message "verify-autologin.service definition created."

# Enable the service
log_message "Enabling verify-autologin.service"
systemctl enable verify-autologin.service
log_message "verify-autologin.service enabled."

log_message "User setup script completed successfully"

# Ensure script ends with a newline

</file_content>

Now that you have the latest state of the file, try the operation again with fewer, more precise SEARCH blocks. For large files especially, it may be prudent to try to limit yourself to <5 SEARCH/REPLACE blocks at a time, then wait for the user to respond with the result of the operation before following up with another replace_in_file call to make additional edits.
(If you run into this error 3 times in a row, you may use the write_to_file tool as a fallback.)
</error><environment_details>
# VSCode Visible Files
features/user_setup.sh

# VSCode Open Tabs
features/firefox.sh
setup.sh
features/user_setup.sh
features/uninstall.sh

# Actively Running Terminals
## Original command: `Remove-Item features/var_ownership_fix.sh`

# Current Time
5/20/2025, 3:09:17 PM (America/Phoenix, UTC-7:00)

# Context Window Usage
259,218 / 1,048.576K tokens used (25%)

# Current Mode
ACT MODE
</environment_details>
