#!/bin/bash

# ZorinOS Kiosk tmpfs Setup Script
# Features: #3, 4, 6, 13, 16, 17, 18

# Exit on any error
set -e

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/tmpfs.sh.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting tmpfs.sh script."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  log_message "Error: This script must be run as root. Please use sudo."
  echo "This script must be run as root. Please use sudo." # Keep for direct user feedback
  exit 1
fi
log_message "Running as root."

# Source the environment file
log_message "Checking for environment file..."
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env"
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
log_message "Environment file sourced successfully. KIOSK_USERNAME=${KIOSK_USERNAME}, OPT_KIOSK_DIR=${OPT_KIOSK_DIR}, WALLPAPER_SYSTEM_PATH=${WALLPAPER_SYSTEM_PATH}, TEMPLATE_DIR=${TEMPLATE_DIR}"

# Ensure OPT_KIOSK_DIR is set and created
if [ -z "$OPT_KIOSK_DIR" ]; then
    log_message "Error: OPT_KIOSK_DIR is not set. Cannot proceed."
    exit 1
fi
mkdir -p "$OPT_KIOSK_DIR"
log_message "Ensured OPT_KIOSK_DIR exists: $OPT_KIOSK_DIR"

# 6. Create a script to set the wallpaper
log_message "Creating wallpaper setting script..."
WALLPAPER_SCRIPT="$OPT_KIOSK_DIR/set_wallpaper.sh"
# Define the log file path for the generated wallpaper script
GENERATED_WALLPAPER_LOG_FILE="$LOG_DIR/set_wallpaper.sh.log"
# WALLPAPER_SYSTEM_PATH is expanded by this script (tmpfs.sh)
# So its value will be hardcoded into the generated set_wallpaper.sh script.
WALLPAPER_SYSTEM_PATH_EXPANDED="$WALLPAPER_SYSTEM_PATH"


cat > "$WALLPAPER_SCRIPT" << EOF
#!/bin/bash

# Script to set the desktop wallpaper for the kiosk user
LOGFILE="$GENERATED_WALLPAPER_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_wallpaper_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_wallpaper_message "set_wallpaper.sh: Script started."

# Check if the wallpaper exists in the system path
# Use the expanded variable here
if [ -f "$WALLPAPER_SYSTEM_PATH_EXPANDED" ]; then
  log_wallpaper_message "Wallpaper found at $WALLPAPER_SYSTEM_PATH_EXPANDED. Setting wallpaper..."
  # Set the wallpaper using gsettings
  gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_SYSTEM_PATH_EXPANDED" >> "\$LOGFILE" 2>&1 || log_wallpaper_message "Failed: gsettings set picture-uri"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_SYSTEM_PATH_EXPANDED" >> "\$LOGFILE" 2>&1 || log_wallpaper_message "Failed: gsettings set picture-uri-dark"
  log_wallpaper_message "Wallpaper set to $WALLPAPER_SYSTEM_PATH_EXPANDED"
else
  log_wallpaper_message "Error: Wallpaper file not found at $WALLPAPER_SYSTEM_PATH_EXPANDED"
fi
log_wallpaper_message "set_wallpaper.sh: Script finished."
EOF

chmod +x "$WALLPAPER_SCRIPT"
log_message "Wallpaper setting script $WALLPAPER_SCRIPT created and made executable."

# 3. Mount the tmpfs for the kiosk user
log_message "Mounting tmpfs for kiosk user $KIOSK_USERNAME..."
# Unmount if already mounted
if mount | grep -q "/home/$KIOSK_USERNAME"; then
  log_message "Unmounting existing tmpfs or mount at /home/$KIOSK_USERNAME..."
  umount "/home/$KIOSK_USERNAME" || log_message "Warning: Failed to unmount /home/$KIOSK_USERNAME. It might not have been mounted."
fi

# Create the directory if it doesn't exist
log_message "Creating directory /home/$KIOSK_USERNAME if it doesn't exist..."
mkdir -p "/home/$KIOSK_USERNAME"
chmod 1777 "/home/$KIOSK_USERNAME" # Sticky bit, rwx for all
log_message "Directory /home/$KIOSK_USERNAME created/ensured with mode 1777."

# Mount the tmpfs
log_message "Mounting tmpfs at /home/$KIOSK_USERNAME with size 512M..."
mount -t tmpfs -o defaults,noatime,mode=1777,size=512M tmpfs "/home/$KIOSK_USERNAME"
log_message "tmpfs mounted successfully."

# 4. Create necessary directories for the kiosk user in the tmpfs
log_message "Creating necessary directories in tmpfs for user $KIOSK_USERNAME..."
mkdir -p "/home/$KIOSK_USERNAME/Desktop"
mkdir -p "/home/$KIOSK_USERNAME/Documents"
mkdir -p "/home/$KIOSK_USERNAME/Downloads"
mkdir -p "/home/$KIOSK_USERNAME/Pictures"
mkdir -p "/home/$KIOSK_USERNAME/.config"
mkdir -p "/home/$KIOSK_USERNAME/.config/autostart"
mkdir -p "/home/$KIOSK_USERNAME/.local/share/applications"
touch "/home/$KIOSK_USERNAME/Desktop/.keep" # To ensure Desktop directory is preserved by some tools
log_message "Standard user directories created in tmpfs."

# 13. Configure fstab for tmpfs mounting on boot
log_message "Configuring fstab for tmpfs mounting on boot..."
FSTAB_ENTRY="tmpfs /home/$KIOSK_USERNAME tmpfs defaults,noatime,mode=1777,size=512M 0 0"
# Check if the entry already exists (be more specific to avoid matching comments)
if ! grep -q "^tmpfs /home/$KIOSK_USERNAME tmpfs" /etc/fstab; then
  log_message "Adding tmpfs mount to /etc/fstab..."
  echo "# Kiosk user tmpfs mount (added by kiosk setup)" >> /etc/fstab
  echo "$FSTAB_ENTRY" >> /etc/fstab
  log_message "Added tmpfs mount to fstab."
else
  log_message "tmpfs mount for /home/$KIOSK_USERNAME already exists in fstab."
fi

# 16. Set correct ownership for all created files
log_message "Setting ownership for kiosk user files in /home/$KIOSK_USERNAME/ and scripts in $OPT_KIOSK_DIR..."
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/"
# This might be too broad if other non-script files are in OPT_KIOSK_DIR
find "$OPT_KIOSK_DIR" -name "*.sh" -type f -exec chmod 755 {} \;
log_message "Ownership and script permissions set."

# 17. Copy the autostart entries to the kiosk user's home directory
# Ensure TEMPLATE_DIR is set
if [ -z "$TEMPLATE_DIR" ]; then
    log_message "Error: TEMPLATE_DIR is not set. Cannot copy autostart entries."
else
    log_message "Copying autostart entries from $TEMPLATE_DIR/.config/autostart/ to /home/$KIOSK_USERNAME/.config/autostart/..."
    if [ -d "$TEMPLATE_DIR/.config/autostart" ]; then
        cp -r "$TEMPLATE_DIR/.config/autostart/"* "/home/$KIOSK_USERNAME/.config/autostart/" 2>/dev/null || log_message "Note: No autostart entries to copy or error during copy."
        chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/.config/autostart/"
        log_message "Autostart entries copied and ownership set."
    else
        log_message "Warning: Template autostart directory $TEMPLATE_DIR/.config/autostart not found."
    fi
fi

# Create a persistent dconf settings script
log_message "Creating persistent dconf settings script..."
PERSISTENT_DCONF_SCRIPT="$OPT_KIOSK_DIR/persistent_dconf_settings.sh"
# Define the log file path for the generated persistent_dconf_settings.sh script
GENERATED_PERSISTENT_DCONF_LOG_FILE="$LOG_DIR/persistent_dconf_settings.sh.log"

cat > "$PERSISTENT_DCONF_SCRIPT" << EOF
#!/bin/bash

# Script to apply persistent dconf settings for the kiosk user
# This script will be run on boot and after user login to ensure settings persist

# Log file for this script
LOGFILE="$GENERATED_PERSISTENT_DCONF_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_persistent_dconf_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}
log_persistent_dconf_message "persistent_dconf_settings.sh: Script started."

# Get the kiosk username from the first argument or use a default
# KIOSK_USERNAME_EXPANDED is expanded by the parent script (tmpfs.sh)
KIOSK_USERNAME_PARAM="\$1"
if [ -z "\$KIOSK_USERNAME_PARAM" ]; then
    # Fallback to the value embedded during generation if no arg given
    KIOSK_USERNAME_PARAM="$KIOSK_USERNAME" 
    log_persistent_dconf_message "No username provided as argument, using embedded value: \$KIOSK_USERNAME_PARAM"
fi

if [ -z "\$KIOSK_USERNAME_PARAM" ]; then
    log_persistent_dconf_message "Error: KIOSK_USERNAME_PARAM is empty. Exiting."
    exit 1
fi

log_persistent_dconf_message "Setting persistent dconf settings for user \$KIOSK_USERNAME_PARAM"

# Function to safely write dconf settings for a user
apply_dconf_settings() {
    local username="\$1"
    local uid=\$(id -u "\$username" 2>/dev/null)
    
    if [ -z "\$uid" ]; then
        log_persistent_dconf_message "User \$username does not exist. Cannot apply dconf settings."
        return 1
    fi
    
    # Create a temporary script to run as the user
    local tmp_script="/tmp/dconf_settings_\${username}_\$\$.sh" # Added PID for uniqueness
    # Define the log file path for the temporary inner script
    # This log might be hard to retrieve if tmp_script fails early or due to permissions
    # For critical logging, the main script's log is more reliable.
    # INNER_SCRIPT_LOG_FILE="\$LOGFILE" # Could append to same log, or a different one.
    # For simplicity, let inner script output go to main log via su redirection.

    cat > "\$tmp_script" << 'INNEREOF_APPLY_DCONF'
#!/bin/bash
# This script is run as the target user.
# Get the user's dbus address or set a default
TARGET_UID=\$(id -u)
if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$TARGET_UID/bus"
fi
if ! [ -e "\$(echo \$DBUS_SESSION_BUS_ADDRESS | sed 's/unix:path=//')" ]; then
    echo "\$(date): DBUS_SESSION_BUS_ADDRESS (\$DBUS_SESSION_BUS_ADDRESS) not valid or not found for UID \$TARGET_UID. Dconf/gsettings might fail."
    # Attempt to find a valid bus address
    # This is complex and might not always work.
    # For now, proceed with the default and log failures.
fi

# Apply critical settings using both gsettings and dconf
# Disable screen blanking
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || echo "\$(date): Failed: gsettings set org.gnome.desktop.session idle-delay 0"
dconf write /org/gnome/desktop/session/idle-delay "uint32 0" 2>/dev/null || echo "\$(date): Failed: dconf write /org/gnome/desktop/session/idle-delay"

# Disable screen lock
gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || echo "\$(date): Failed: gsettings set org.gnome.desktop.lockdown disable-lock-screen"
dconf write /org/gnome/desktop/lockdown/disable-lock-screen true 2>/dev/null || echo "\$(date): Failed: dconf write /org/gnome/desktop/lockdown/disable-lock-screen"

# Disable screensaver
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || echo "\$(date): Failed: gsettings set org.gnome.desktop.screensaver lock-enabled"
dconf write /org/gnome/desktop/screensaver/lock-enabled false 2>/dev/null || echo "\$(date): Failed: dconf write /org/gnome/desktop/screensaver/lock-enabled"
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || echo "\$(date): Failed: gsettings set org.gnome.desktop.screensaver idle-activation-enabled"
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled false 2>/dev/null || echo "\$(date): Failed: dconf write /org/gnome/desktop/screensaver/idle-activation-enabled"

# Disable screen dimming
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || echo "\$(date): Failed: gsettings set org.gnome.settings-daemon.plugins.power idle-dim"
dconf write /org/gnome/settings-daemon/plugins/power/idle-dim false 2>/dev/null || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/idle-dim"

# Set power settings to never blank screen
gsettings set org.gnome.settings-daemon.plugins.power sleep-display-ac 0 2>/dev/null || echo "\$(date): Failed: gsettings set sleep-display-ac"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac "uint32 0" 2>/dev/null || echo "\$(date): Failed: dconf write sleep-display-ac"
gsettings set org.gnome.settings-daemon.plugins.power sleep-display-battery 0 2>/dev/null || echo "\$(date): Failed: gsettings set sleep-display-battery"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery "uint32 0" 2>/dev/null || echo "\$(date): Failed: dconf write sleep-display-battery"

# Disable automatic suspend
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || echo "\$(date): Failed: gsettings set sleep-inactive-ac-type"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'" 2>/dev/null || echo "\$(date): Failed: dconf write sleep-inactive-ac-type"
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || echo "\$(date): Failed: gsettings set sleep-inactive-battery-type"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'" 2>/dev/null || echo "\$(date): Failed: dconf write sleep-inactive-battery-type"

# Zorin OS specific settings (if they exist)
gsettings set com.zorin.desktop.screensaver lock-enabled false 2>/dev/null || echo "\$(date): Note: Failed/Skipped gsettings set com.zorin.desktop.screensaver lock-enabled (may not exist)"
dconf write /com/zorin/desktop/screensaver/lock-enabled false 2>/dev/null || echo "\$(date): Note: Failed/Skipped dconf write /com/zorin/desktop/screensaver/lock-enabled (may not exist)"
gsettings set com.zorin.desktop.session idle-delay 0 2>/dev/null || echo "\$(date): Note: Failed/Skipped gsettings set com.zorin.desktop.session idle-delay (may not exist)"
dconf write /com/zorin/desktop/session/idle-delay "uint32 0" 2>/dev/null || echo "\$(date): Note: Failed/Skipped dconf write /com/zorin/desktop/session/idle-delay (may not exist)"
echo "\$(date): Inner dconf/gsettings script finished for user \$(id -un)."
INNEREOF_APPLY_DCONF
    
    chmod +x "\$tmp_script"
    
    # Run the script as the user
    log_persistent_dconf_message "Running dconf settings script \$tmp_script as \$username (UID \$uid)..."
    if [ "\$username" = "root" ]; then
        # For root, DBUS_SESSION_BUS_ADDRESS might not be relevant or available in the same way.
        # Root typically doesn't have a graphical session dconf to modify this way.
        # However, system-wide dconf changes below should cover root if needed.
        log_persistent_dconf_message "Skipping direct dconf application for root user via su; system-wide dconf changes will apply."
        # bash "\$tmp_script" >> "\$LOGFILE" 2>&1 # If needed, but usually not for root's session settings
    else
        # For regular users, set XDG_RUNTIME_DIR and run with su
        # Ensure loginctl linger is enabled for the user so their runtime dir persists
        loginctl enable-linger "\$username" >> "\$LOGFILE" 2>&1 || log_persistent_dconf_message "Warning: Failed to enable linger for \$username."
        # The su command will inherit the environment, but explicitly setting XDG_RUNTIME_DIR is safer.
        su - "\$username" -c "export XDG_RUNTIME_DIR=/run/user/\$uid; bash \$tmp_script" >> "\$LOGFILE" 2>&1
    fi
    
    # Clean up
    rm -f "\$tmp_script"
    
    log_persistent_dconf_message "Completed dconf settings application attempt for \$username."
    return 0
}

# Apply settings for the kiosk user
apply_dconf_settings "\$KIOSK_USERNAME_PARAM"

# Create a system-wide override for the idle-delay setting
log_persistent_dconf_message "Creating system-wide dconf overrides..."

# Create dconf profile directory
mkdir -p /etc/dconf/profile
log_persistent_dconf_message "Ensured dconf profile directory /etc/dconf/profile exists."

# Create a system profile
cat > /etc/dconf/profile/user << EOF_USER_PROFILE
user-db:user
system-db:local
EOF_USER_PROFILE
log_persistent_dconf_message "Created/updated dconf user profile /etc/dconf/profile/user."

# Create the local database directory
mkdir -p /etc/dconf/db/local.d
log_persistent_dconf_message "Ensured dconf local database directory /etc/dconf/db/local.d exists."

# Create the settings file
cat > /etc/dconf/db/local.d/00-kiosk-defaults << EOF_KIOSK_DEFAULTS
# Kiosk mode default settings (system-wide)
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/lockdown]
disable-lock-screen=true

[org/gnome/settings-daemon/plugins/power]
idle-dim=false
sleep-display-ac=uint32 0
sleep-display-battery=uint32 0
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[com/zorin/desktop/screensaver]
lock-enabled=false

[com/zorin/desktop/session]
idle-delay=uint32 0
EOF_KIOSK_DEFAULTS
log_persistent_dconf_message "Created dconf settings file /etc/dconf/db/local.d/00-kiosk-defaults."

# Create locks directory
mkdir -p /etc/dconf/db/local.d/locks
log_persistent_dconf_message "Ensured dconf locks directory /etc/dconf/db/local.d/locks exists."

# Create locks file to prevent user from changing these settings
cat > /etc/dconf/db/local.d/locks/00-kiosk-locks << EOF_KIOSK_LOCKS
/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/lockdown/disable-lock-screen
/org/gnome/settings-daemon/plugins/power/idle-dim
/org/gnome/settings-daemon/plugins/power/sleep-display-ac
/org/gnome/settings-daemon/plugins/power/sleep-display-battery
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
/com/zorin/desktop/screensaver/lock-enabled
/com/zorin/desktop/session/idle-delay
EOF_KIOSK_LOCKS
log_persistent_dconf_message "Created dconf locks file /etc/dconf/db/local.d/locks/00-kiosk-locks."

# Update the dconf database
dconf update
log_persistent_dconf_message "Updated dconf database with system-wide settings and locks."

log_persistent_dconf_message "persistent_dconf_settings.sh: Script completed successfully."
EOF

chmod +x "$PERSISTENT_DCONF_SCRIPT"
log_message "Persistent dconf settings script $PERSISTENT_DCONF_SCRIPT created and made executable."

# Create a direct dconf settings script for all users
log_message "Creating direct dconf settings script (not used by default, for manual run if needed)..."
DIRECT_DCONF_SCRIPT="$OPT_KIOSK_DIR/direct_dconf_settings_manual.sh" # Renamed to indicate manual use
# Define the log file path for the generated direct_dconf_settings.sh script
GENERATED_DIRECT_DCONF_LOG_FILE="$LOG_DIR/direct_dconf_settings_manual.sh.log"

cat > "$DIRECT_DCONF_SCRIPT" << EOF
#!/bin/bash

# Script to directly modify dconf settings for all users
# This is a more aggressive approach to ensure settings are applied
# INTENDED FOR MANUAL EXECUTION IF NEEDED.

# Log file
LOGFILE="$GENERATED_DIRECT_DCONF_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_direct_dconf_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}
log_direct_dconf_message "direct_dconf_settings_manual.sh: Script started."

# Function to directly modify a user's dconf database
modify_user_dconf() {
    local username="\$1"
    local uid=\$(id -u "\$username" 2>/dev/null)
    
    if [ -z "\$uid" ]; then
        log_direct_dconf_message "User \$username does not exist. Skipping."
        return 1
    fi
    
    log_direct_dconf_message "Attempting to modify dconf for user \$username (UID: \$uid)..."
    
    # Find the user's dconf directory
    local user_dconf_config_dir="/home/\$username/.config/dconf"
    if [ ! -d "\$user_dconf_config_dir" ]; then
        log_direct_dconf_message "User \$username has no .config/dconf directory (\$user_dconf_config_dir). Creating it."
        mkdir -p "\$user_dconf_config_dir"
        chown "\$username:\$username" "\$user_dconf_config_dir" # Basic ownership
        # The 'user' file within might be created by dconf itself.
    fi
    
    # Create a temporary script to run as the user
    local tmp_script_direct="/tmp/direct_dconf_inner_\${username}_\$\$.sh"

    cat > "\$tmp_script_direct" << 'INNEREOF_DIRECT_DCONF'
#!/bin/bash
# This script is run as the target user.
# Ensure DBUS is set for the current user's session
TARGET_UID_INNER=\$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$TARGET_UID_INNER/bus"

# Check if DBUS session is valid
if ! [ -e "\$(echo \$DBUS_SESSION_BUS_ADDRESS | sed 's/unix:path=//')" ]; then
    echo "\$(date): DBUS_SESSION_BUS_ADDRESS (\$DBUS_SESSION_BUS_ADDRESS) not valid for UID \$TARGET_UID_INNER. Dconf writes might fail."
    # Attempt to find a valid bus address (complex, may not always work)
    # For now, proceed and log failures.
fi

# Direct dconf writes
echo "\$(date): Applying dconf settings for user \$(id -un)..."
dconf write /org/gnome/desktop/session/idle-delay "uint32 0" || echo "\$(date): Failed: dconf write /org/gnome/desktop/session/idle-delay"
dconf write /org/gnome/desktop/screensaver/lock-enabled "false" || echo "\$(date): Failed: dconf write /org/gnome/desktop/screensaver/lock-enabled"
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled "false" || echo "\$(date): Failed: dconf write /org/gnome/desktop/screensaver/idle-activation-enabled"
dconf write /org/gnome/desktop/lockdown/disable-lock-screen "true" || echo "\$(date): Failed: dconf write /org/gnome/desktop/lockdown/disable-lock-screen"
dconf write /org/gnome/settings-daemon/plugins/power/idle-dim "false" || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/idle-dim"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac "uint32 0" || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery "uint32 0" || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'" || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'" || echo "\$(date): Failed: dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type"
# Zorin specific
dconf write /com/zorin/desktop/session/idle-delay "uint32 0" 2>/dev/null || echo "\$(date): Note: Failed/Skipped dconf write /com/zorin/desktop/session/idle-delay (may not exist)"
dconf write /com/zorin/desktop/screensaver/lock-enabled "false" 2>/dev/null || echo "\$(date): Note: Failed/Skipped dconf write /com/zorin/desktop/screensaver/lock-enabled (may not exist)"


# Verify the settings were applied (output will go to the main log via su redirection)
echo "\$(date): Verifying settings for user \$(id -un):"
echo "idle-delay: \$(dconf read /org/gnome/desktop/session/idle-delay 2>/dev/null || echo 'read_failed')"
echo "lock-enabled: \$(dconf read /org/gnome/desktop/screensaver/lock-enabled 2>/dev/null || echo 'read_failed')"
echo "idle-activation-enabled: \$(dconf read /org/gnome/desktop/screensaver/idle-activation-enabled 2>/dev/null || echo 'read_failed')"
echo "disable-lock-screen: \$(dconf read /org/gnome/desktop/lockdown/disable-lock-screen 2>/dev/null || echo 'read_failed')"
echo "\$(date): Inner dconf script finished for user \$(id -un)."
INNEREOF_DIRECT_DCONF
    
    chmod +x "\$tmp_script_direct"
    
    # Run the script as the user
    log_direct_dconf_message "Running direct dconf inner script \$tmp_script_direct as \$username (UID \$uid)..."
    if [ "\$username" = "root" ]; then
        # Root usually doesn't have a user dconf session to modify this way for GUI settings.
        log_direct_dconf_message "Skipping direct dconf application for root user via su; system-wide dconf changes should apply."
    else
        # Ensure loginctl linger is enabled for the user
        loginctl enable-linger "\$username" >> "\$LOGFILE" 2>&1 || log_direct_dconf_message "Warning: Failed to enable linger for \$username."
        su - "\$username" -c "export XDG_RUNTIME_DIR=/run/user/\$uid; bash \$tmp_script_direct" >> "\$LOGFILE" 2>&1
    fi
    
    # Clean up
    rm -f "\$tmp_script_direct"
    
    log_direct_dconf_message "Completed direct dconf modification attempt for \$username."
    return 0
}

# System-wide dconf settings (already applied by persistent_dconf_settings.sh if run)
# This script focuses on ensuring user-level settings if system-wide ones are overridden or not taking effect.
log_direct_dconf_message "Applying settings to all existing non-system users..."
for user_home_dir in /home/*; do
    if [ -d "\$user_home_dir" ]; then
        username_loop=\$(basename "\$user_home_dir")
        # Skip system users and directories that aren't actually user homes
        # Check if UID is >= 1000 (typical for regular users)
        uid_loop=\$(id -u "\$username_loop" 2>/dev/null)
        if [ -n "\$uid_loop" ] && [ "\$uid_loop" -ge 1000 ]; then
            log_direct_dconf_message "Found user: \$username_loop (UID \$uid_loop). Applying dconf settings."
            modify_user_dconf "\$username_loop"
        else
            log_direct_dconf_message "Skipping \$user_home_dir (not a regular user or user not found)."
        fi
    fi
done

# Specifically check for and modify KIOSK_USERNAME if not covered above (e.g. if home dir is not /home/KIOSK_USERNAME)
# KIOSK_USERNAME_FOR_DIRECT is expanded by the parent script (tmpfs.sh)
KIOSK_USERNAME_TARGET="$KIOSK_USERNAME" 
if id "\$KIOSK_USERNAME_TARGET" &>/dev/null && [ \$(id -u "\$KIOSK_USERNAME_TARGET") -ge 1000 ]; then
    # Check if already processed if home is under /home/
    if [[ ! "\$KIOSK_USERNAME_TARGET" == \$(basename /home/\$KIOSK_USERNAME_TARGET 2>/dev/null) ]]; then
        log_direct_dconf_message "Specifically targeting configured KIOSK_USERNAME: \$KIOSK_USERNAME_TARGET."
        modify_user_dconf "\$KIOSK_USERNAME_TARGET"
    fi
else
    log_direct_dconf_message "Configured KIOSK_USERNAME (\$KIOSK_USERNAME_TARGET) is not a regular user or does not exist. Skipping specific target."
fi

# Create a GDM configuration to apply these settings to the login screen as well
# This part is mostly for system-wide defaults affecting GDM.
if [ -d "/etc/gdm3" ] || [ -d "/etc/gdm" ]; then
    log_direct_dconf_message "Configuring GDM to use system dconf settings (ensuring profile exists)..."
    
    # Ensure GDM dconf profile exists
    mkdir -p /etc/dconf/profile
    if [ ! -f "/etc/dconf/profile/gdm" ]; then
        cat > /etc/dconf/profile/gdm << EOF_GDM_PROFILE
user-db:user
system-db:gdm
system-db:local
system-db:site
EOF_GDM_PROFILE
        log_direct_dconf_message "Created GDM dconf profile /etc/dconf/profile/gdm."
    fi
    
    # Ensure GDM specific settings directory exists
    mkdir -p /etc/dconf/db/gdm.d
    # Create a GDM settings file if it doesn't exist or is empty, to ensure GDM uses system settings.
    GDM_SETTINGS_FILE="/etc/dconf/db/gdm.d/01-kiosk-gdm-screensaver"
    if [ ! -s "\$GDM_SETTINGS_FILE" ]; then # -s checks if file exists and is not empty
        cat > "\$GDM_SETTINGS_FILE" << EOF_GDM_SETTINGS
# GDM login screen settings (kiosk defaults)
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false
EOF_GDM_SETTINGS
        log_direct_dconf_message "Created/updated GDM specific settings file \$GDM_SETTINGS_FILE."
    fi
    
    # Update dconf database to include GDM settings
    dconf update
    log_direct_dconf_message "Updated dconf database (after GDM profile/settings check)."
fi

# Create a login script to apply settings (redundancy for robustness)
log_direct_dconf_message "Ensuring login script /etc/profile.d/apply-kiosk-dconf-settings.sh exists..."
mkdir -p /etc/profile.d
# Define the log file path for the generated apply-kiosk-dconf-settings.sh script
GENERATED_APPLY_DCONF_LOGIN_LOG_FILE="$LOG_DIR/apply-kiosk-dconf-settings-login.sh.log"
cat > /etc/profile.d/apply-kiosk-dconf-settings.sh << EOF_LOGIN_SCRIPT
#!/bin/bash
# Apply critical dconf settings at login for kiosk robustness
LOGFILE_LOGIN="$GENERATED_APPLY_DCONF_LOGIN_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE_LOGIN")"

log_login_dconf_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - User \$(whoami) - \$1" >> "\$LOGFILE_LOGIN"
}
log_login_dconf_message "apply-kiosk-dconf-settings.sh: Login script started."

# Only run for graphical sessions
if [ -n "\$DISPLAY" ] || [ -n "\$WAYLAND_DISPLAY" ]; then
    log_login_dconf_message "Graphical session detected. Applying dconf settings..."
    # Set idle-delay to 0 (never)
    gsettings set org.gnome.desktop.session idle-delay 0 >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: gsettings set org.gnome.desktop.session idle-delay 0"
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0" >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: dconf write /org/gnome/desktop/session/idle-delay"
    
    # Disable screen lock
    gsettings set org.gnome.desktop.lockdown disable-lock-screen true >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: gsettings set org.gnome.desktop.lockdown disable-lock-screen"
    dconf write /org/gnome/desktop/lockdown/disable-lock-screen true >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: dconf write /org/gnome/desktop/lockdown/disable-lock-screen"
    
    # Disable screensaver
    gsettings set org.gnome.desktop.screensaver lock-enabled false >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: gsettings set org.gnome.desktop.screensaver lock-enabled"
    dconf write /org/gnome/desktop/screensaver/lock-enabled false >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: dconf write /org/gnome/desktop/screensaver/lock-enabled"
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: gsettings set org.gnome.desktop.screensaver idle-activation-enabled"
    dconf write /org/gnome/desktop/screensaver/idle-activation-enabled false >> "\$LOGFILE_LOGIN" 2>&1 || log_login_dconf_message "Failed: dconf write /org/gnome/desktop/screensaver/idle-activation-enabled"
    log_login_dconf_message "Dconf settings applied via login script."
else
    log_login_dconf_message "Not a graphical session. Skipping dconf settings."
fi
EOF_LOGIN_SCRIPT
chmod +x /etc/profile.d/apply-kiosk-dconf-settings.sh
log_direct_dconf_message "Ensured login script /etc/profile.d/apply-kiosk-dconf-settings.sh exists and is executable."

log_direct_dconf_message "direct_dconf_settings_manual.sh: Script completed successfully."
EOF

chmod +x "$DIRECT_DCONF_SCRIPT"
log_message "Created direct dconf settings script (for manual use): $DIRECT_DCONF_SCRIPT."

# Run the persistent dconf script immediately to apply system-wide and for the KIOSK_USERNAME
log_message "Running persistent dconf script for user $KIOSK_USERNAME..."
if [ -x "$PERSISTENT_DCONF_SCRIPT" ]; then
    # Pass KIOSK_USERNAME as an argument to the script
    "$PERSISTENT_DCONF_SCRIPT" "$KIOSK_USERNAME"
    log_message "Persistent dconf script executed."
else
    log_message "Error: Persistent dconf script not found or not executable at $PERSISTENT_DCONF_SCRIPT"
    # Decide if this is fatal or a warning
fi

# 18. Create a systemd service to initialize kiosk home directory after tmpfs mount
log_message "Creating systemd service for kiosk home initialization..."
KIOSK_INIT_SERVICE="/etc/systemd/system/kiosk-home-init.service"
# Define the log file path for the generated kiosk-home-init.service's ExecStart commands
GENERATED_KIOSK_INIT_SERVICE_LOG_FILE="$LOG_DIR/kiosk-home-init.service.log"

cat > "$KIOSK_INIT_SERVICE" << EOF
[Unit]
Description=Initialize Kiosk User Home Directory and Run Setup Scripts
After=local-fs.target network-online.target tmpfs-home-$KIOSK_USERNAME.mount # Ensure tmpfs is mounted
Requires=tmpfs-home-$KIOSK_USERNAME.mount # Make it a hard requirement if fstab entry is named this way
Before=display-manager.service

[Service]
Type=oneshot
# KIOSK_USERNAME, TEMPLATE_DIR, OPT_KIOSK_DIR are expanded by tmpfs.sh
ExecStart=/bin/bash -c "echo \\"\$(date) - kiosk-home-init.service: Starting initialization for $KIOSK_USERNAME...\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 mkdir -p /home/$KIOSK_USERNAME/.config/autostart >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - kiosk-home-init.service: No autostart entries to copy or error.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 mkdir -p /home/$KIOSK_USERNAME/Desktop >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - kiosk-home-init.service: No Desktop entries to copy or error.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 mkdir -p /home/$KIOSK_USERNAME/Documents >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - kiosk-home-init.service: No Documents to copy or error.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 mkdir -p /home/$KIOSK_USERNAME/.config/systemd/user >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 cp -r $TEMPLATE_DIR/.config/systemd/user/* /home/$KIOSK_USERNAME/.config/systemd/user/ >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - kiosk-home-init.service: No user systemd units to copy or error.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/ >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 echo \\"\$(date) - kiosk-home-init.service: Running setup_firefox_profile.sh...\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 su - $KIOSK_USERNAME -c 'sudo $OPT_KIOSK_DIR/setup_firefox_profile.sh' >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 echo \\"\$(date) - kiosk-home-init.service: Enabling kiosk-user-settings.service for user $KIOSK_USERNAME...\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 && \\
 su - $KIOSK_USERNAME -c 'export XDG_RUNTIME_DIR=/run/user/\$(id -u); systemctl --user enable kiosk-idle-delay.service' >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - kiosk-home-init.service: Failed to enable kiosk-idle-delay.service for user.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1; \\
 echo \\"\$(date) - kiosk-home-init.service: Initialization complete for $KIOSK_USERNAME.\\" >> $GENERATED_KIOSK_INIT_SERVICE_LOG_FILE 2>&1"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
log_message "Enabling kiosk-home-init.service..."
systemctl enable kiosk-home-init.service
log_message "kiosk-home-init.service enabled."
log_message "tmpfs.sh script finished."

# Get the kiosk username from the first argument or use a default
KIOSK_USERNAME="$1"
if [ -z "$KIOSK_USERNAME" ]; then
    echo "$(date): No username provided, exiting" >> "$LOGFILE"
    exit 1
fi

echo "$(date): Setting persistent dconf settings for user $KIOSK_USERNAME" >> "$LOGFILE"

# Function to safely write dconf settings for a user
apply_dconf_settings() {
    local username="$1"
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        echo "$(date): User $username does not exist" >> "$LOGFILE"
        return 1
    fi
    
    # Create a temporary script to run as the user
    local tmp_script="/tmp/dconf_settings_$username.sh"
    cat > "$tmp_script" << 'INNEREOF'
#!/bin/bash
# Get the user's dbus address or set a default
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# Apply critical settings using both gsettings and dconf
# Disable screen blanking
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
dconf write /org/gnome/desktop/session/idle-delay "uint32 0" 2>/dev/null || true

# Disable screen lock
gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || true
dconf write /org/gnome/desktop/lockdown/disable-lock-screen true 2>/dev/null || true

# Disable screensaver
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
dconf write /org/gnome/desktop/screensaver/lock-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled false 2>/dev/null || true

# Disable screen dimming
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
dconf write /org/gnome/settings-daemon/plugins/power/idle-dim false 2>/dev/null || true

# Set power settings to never blank screen
gsettings set org.gnome.settings-daemon.plugins.power sleep-display-ac 0 2>/dev/null || true
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac "uint32 0" 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-display-battery 0 2>/dev/null || true
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery "uint32 0" 2>/dev/null || true

# Disable automatic suspend
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'" 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'" 2>/dev/null || true

# Zorin OS specific settings (if they exist)
gsettings set com.zorin.desktop.screensaver lock-enabled false 2>/dev/null || true
dconf write /com/zorin/desktop/screensaver/lock-enabled false 2>/dev/null || true
gsettings set com.zorin.desktop.session idle-delay 0 2>/dev/null || true
dconf write /com/zorin/desktop/session/idle-delay "uint32 0" 2>/dev/null || true
INNEREOF
    
    chmod +x "$tmp_script"
    
    # Run the script as the user
    echo "$(date): Running dconf settings script as $username" >> "$LOGFILE"
    if [ "$username" = "root" ]; then
        bash "$tmp_script" >> "$LOGFILE" 2>&1
    else
        su - "$username" -c "$tmp_script" >> "$LOGFILE" 2>&1
    fi
    
    # Clean up
    rm -f "$tmp_script"
    
    echo "$(date): Completed dconf settings for $username" >> "$LOGFILE"
    return 0
}

# Apply settings for the kiosk user
apply_dconf_settings "$KIOSK_USERNAME"

# Create a system-wide override for the idle-delay setting
echo "$(date): Creating system-wide dconf override for idle-delay" >> "$LOGFILE"

# Create dconf profile directory
mkdir -p /etc/dconf/profile
echo "$(date): Created dconf profile directory" >> "$LOGFILE"

# Create a system profile
cat > /etc/dconf/profile/user << EOF
user-db:user
system-db:local
EOF
echo "$(date): Created dconf user profile" >> "$LOGFILE"

# Create the local database directory
mkdir -p /etc/dconf/db/local.d
echo "$(date): Created dconf local database directory" >> "$LOGFILE"

# Create the settings file
cat > /etc/dconf/db/local.d/00-kiosk << EOF
# Kiosk mode settings

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/lockdown]
disable-lock-screen=true

[org/gnome/settings-daemon/plugins/power]
idle-dim=false
sleep-display-ac=uint32 0
sleep-display-battery=uint32 0
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[com/zorin/desktop/screensaver]
lock-enabled=false

[com/zorin/desktop/session]
idle-delay=uint32 0
EOF
echo "$(date): Created dconf settings file" >> "$LOGFILE"

# Create locks directory
mkdir -p /etc/dconf/db/local.d/locks
echo "$(date): Created dconf locks directory" >> "$LOGFILE"

# Create locks file to prevent user from changing these settings
cat > /etc/dconf/db/local.d/locks/kiosk << EOF
/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/lockdown/disable-lock-screen
/org/gnome/settings-daemon/plugins/power/idle-dim
/org/gnome/settings-daemon/plugins/power/sleep-display-ac
/org/gnome/settings-daemon/plugins/power/sleep-display-battery
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF
echo "$(date): Created dconf locks file" >> "$LOGFILE"

# Update the dconf database
dconf update
echo "$(date): Updated dconf database" >> "$LOGFILE"

echo "$(date): Persistent dconf settings script completed successfully" >> "$LOGFILE"
EOF

chmod +x "$PERSISTENT_DCONF_SCRIPT"
echo "Created persistent dconf settings script."

# Create a direct dconf settings script for all users
echo "Creating direct dconf settings script for all users..."
DIRECT_DCONF_SCRIPT="$OPT_KIOSK_DIR/direct_dconf_settings.sh"

cat > "$DIRECT_DCONF_SCRIPT" << 'EOF'
#!/bin/bash

# Script to directly modify dconf settings for all users
# This is a more aggressive approach to ensure settings are applied

# Log file
LOGFILE="/var/log/direct-dconf-settings.log"
echo "$(date): Starting direct dconf settings script" > "$LOGFILE"

# Function to directly modify a user's dconf database
modify_user_dconf() {
    local username="$1"
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        echo "$(date): User $username does not exist" >> "$LOGFILE"
        return 1
    fi
    
    echo "$(date): Modifying dconf for user $username (UID: $uid)" >> "$LOGFILE"
    
    # Find the user's dconf database
    local user_dconf_dir="/home/$username/.config/dconf"
    if [ ! -d "$user_dconf_dir" ]; then
        echo "$(date): User $username has no dconf directory, creating one" >> "$LOGFILE"
        mkdir -p "$user_dconf_dir"
        chown "$username:$username" "$user_dconf_dir"
    fi
    
    # Create a temporary script to run as the user
    local tmp_script="/tmp/direct_dconf_$username.sh"
    cat > "$tmp_script" << 'INNEREOF'
#!/bin/bash
# Ensure DBUS is set
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Direct dconf writes
dconf write /org/gnome/desktop/session/idle-delay "uint32 0"
dconf write /org/gnome/desktop/screensaver/lock-enabled "false"
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled "false"
dconf write /org/gnome/desktop/lockdown/disable-lock-screen "true"
dconf write /org/gnome/settings-daemon/plugins/power/idle-dim "false"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac "uint32 0"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery "uint32 0"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'"

# Verify the settings were applied
echo "Verifying settings:"
echo "idle-delay: $(dconf read /org/gnome/desktop/session/idle-delay)"
echo "lock-enabled: $(dconf read /org/gnome/desktop/screensaver/lock-enabled)"
echo "idle-activation-enabled: $(dconf read /org/gnome/desktop/screensaver/idle-activation-enabled)"
echo "disable-lock-screen: $(dconf read /org/gnome/desktop/lockdown/disable-lock-screen)"
INNEREOF
    
    chmod +x "$tmp_script"
    
    # Run the script as the user
    echo "$(date): Running direct dconf script as $username" >> "$LOGFILE"
    if [ "$username" = "root" ]; then
        bash "$tmp_script" >> "$LOGFILE" 2>&1
    else
        su - "$username" -c "$tmp_script" >> "$LOGFILE" 2>&1
    fi
    
    # Clean up
    rm -f "$tmp_script"
    
    echo "$(date): Completed direct dconf modification for $username" >> "$LOGFILE"
    return 0
}

# Create system-wide dconf settings
echo "$(date): Setting up system-wide dconf settings" >> "$LOGFILE"

# Create dconf profile directory
mkdir -p /etc/dconf/profile
echo "$(date): Created dconf profile directory" >> "$LOGFILE"

# Create a system profile that applies to all users
cat > /etc/dconf/profile/user << EOF
user-db:user
system-db:local
system-db:site
EOF
echo "$(date): Created dconf user profile" >> "$LOGFILE"

# Create the local database directory
mkdir -p /etc/dconf/db/local.d
echo "$(date): Created dconf local database directory" >> "$LOGFILE"

# Create the settings file with explicit values
cat > /etc/dconf/db/local.d/00-kiosk << EOF
# Kiosk mode settings

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/lockdown]
disable-lock-screen=true

[org/gnome/settings-daemon/plugins/power]
idle-dim=false
sleep-display-ac=uint32 0
sleep-display-battery=uint32 0
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF
echo "$(date): Created dconf settings file" >> "$LOGFILE"

# Create locks directory
mkdir -p /etc/dconf/db/local.d/locks
echo "$(date): Created dconf locks directory" >> "$LOGFILE"

# Create locks file to prevent user from changing these settings
cat > /etc/dconf/db/local.d/locks/kiosk << EOF
/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/lockdown/disable-lock-screen
/org/gnome/settings-daemon/plugins/power/idle-dim
/org/gnome/settings-daemon/plugins/power/sleep-display-ac
/org/gnome/settings-daemon/plugins/power/sleep-display-battery
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF
echo "$(date): Created dconf locks file" >> "$LOGFILE"

# Create a direct override in the dconf database for site-wide settings
echo "$(date): Creating site-wide dconf settings" >> "$LOGFILE"
mkdir -p /etc/dconf/db/site.d
cat > /etc/dconf/db/site.d/00-no-idle << EOF
[org/gnome/desktop/session]
idle-delay=uint32 0
EOF

# Update dconf database
dconf update
echo "$(date): Updated dconf database" >> "$LOGFILE"

# Apply settings for all existing users
echo "$(date): Applying settings to all existing users" >> "$LOGFILE"
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        # Skip system users and directories that aren't actually user homes
        if id "$username" &>/dev/null && [ $(id -u "$username") -ge 1000 ]; then
            echo "$(date): Found user: $username" >> "$LOGFILE"
            modify_user_dconf "$username"
        fi
    fi
done

# Specifically check for and modify alocalbox user
if id "alocalbox" &>/dev/null; then
    echo "$(date): Specifically targeting alocalbox user" >> "$LOGFILE"
    modify_user_dconf "alocalbox"
fi

# Apply settings for root user as well
echo "$(date): Applying settings to root user" >> "$LOGFILE"
modify_user_dconf "root"

# Create a GDM configuration to apply these settings to the login screen as well
if [ -d "/etc/gdm3" ] || [ -d "/etc/gdm" ]; then
    echo "$(date): Configuring GDM to use system dconf settings" >> "$LOGFILE"
    
    # Create GDM dconf profile
    mkdir -p /etc/dconf/profile
    cat > /etc/dconf/profile/gdm << EOF
user-db:user
system-db:gdm
system-db:local
system-db:site
EOF
    
    # Create GDM specific settings if needed
    mkdir -p /etc/dconf/db/gdm.d
    cat > /etc/dconf/db/gdm.d/01-screensaver << EOF
# GDM login screen settings

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false
EOF
    
    # Update dconf database again
    dconf update
    echo "$(date): Updated dconf database for GDM" >> "$LOGFILE"
fi

# Create a script to be run at user login to ensure settings are applied
echo "$(date): Creating login script to apply settings" >> "$LOGFILE"
mkdir -p /etc/profile.d
cat > /etc/profile.d/apply-dconf-settings.sh << 'EOF'
#!/bin/bash
# Apply critical dconf settings at login

# Only run for graphical sessions
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # Set idle-delay to 0 (never)
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0" 2>/dev/null || true
    
    # Disable screen lock
    gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || true
    dconf write /org/gnome/desktop/lockdown/disable-lock-screen true 2>/dev/null || true
    
    # Disable screensaver
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    dconf write /org/gnome/desktop/screensaver/lock-enabled false 2>/dev/null || true
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
    dconf write /org/gnome/desktop/screensaver/idle-activation-enabled false 2>/dev/null || true
fi
EOF
chmod +x /etc/profile.d/apply-dconf-settings.sh
echo "$(date): Created login script" >> "$LOGFILE"

echo "$(date): Direct dconf settings script completed successfully" >> "$LOGFILE"
EOF

chmod +x "$DIRECT_DCONF_SCRIPT"
echo "Created direct dconf settings script."

# Run the direct dconf script immediately
echo "Running direct dconf script..."
if [ -x "$DIRECT_DCONF_SCRIPT" ]; then
    "$DIRECT_DCONF_SCRIPT"
else
    echo "Error: Direct dconf script not found or not executable at $DIRECT_DCONF_SCRIPT"
    exit 1
fi



# 18. Create a systemd service to initialize kiosk home directory after tmpfs mount
echo "Creating systemd service for kiosk home initialization..."
KIOSK_INIT_SERVICE="/etc/systemd/system/kiosk-home-init.service"

cat > "$KIOSK_INIT_SERVICE" << EOF
[Unit]
Description=Initialize Kiosk User Home Directory
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "mkdir -p /home/$KIOSK_USERNAME/.config/autostart && cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ && mkdir -p /home/$KIOSK_USERNAME/Desktop && cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ 2>/dev/null || true && mkdir -p /home/$KIOSK_USERNAME/Documents && cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ 2>/dev/null || true && mkdir -p /home/$KIOSK_USERNAME/.config/systemd/user && cp -r $TEMPLATE_DIR/.config/systemd/user/* /home/$KIOSK_USERNAME/.config/systemd/user/ 2>/dev/null || true && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/ && $OPT_KIOSK_DIR/setup_firefox_profile.sh && systemctl --user --machine=$KIOSK_USERNAME@ enable kiosk-user-settings.service"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable kiosk-home-init.service
