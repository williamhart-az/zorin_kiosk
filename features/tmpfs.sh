#!/bin/bash

# ZorinOS Kiosk tmpfs Setup Script
# Features: #3, 4, 6, 13, 16, 17, 18

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

# 6. Create a script to set the wallpaper
echo "Creating wallpaper setting script..."
WALLPAPER_SCRIPT="$OPT_KIOSK_DIR/set_wallpaper.sh"

cat > "$WALLPAPER_SCRIPT" << EOF
#!/bin/bash

# Script to set the desktop wallpaper for the kiosk user

# Check if the wallpaper exists in the system path
if [ -f "$WALLPAPER_SYSTEM_PATH" ]; then
  # Set the wallpaper using gsettings
  gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_SYSTEM_PATH"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_SYSTEM_PATH"
  echo "\$(date): Wallpaper set to $WALLPAPER_SYSTEM_PATH" >> ~/wallpaper_settings.log
else
  echo "\$(date): Wallpaper file not found at $WALLPAPER_SYSTEM_PATH" >> ~/wallpaper_settings.log
fi
EOF

chmod +x "$WALLPAPER_SCRIPT"

# 3. Mount the tmpfs for the kiosk user
echo "Mounting tmpfs for kiosk user..."
# Unmount if already mounted
if mount | grep -q "/home/$KIOSK_USERNAME"; then
  umount "/home/$KIOSK_USERNAME"
fi

# Create the directory if it doesn't exist
mkdir -p "/home/$KIOSK_USERNAME"
chmod 1777 "/home/$KIOSK_USERNAME"

# Mount the tmpfs
mount -t tmpfs -o defaults,noatime,mode=1777,size=512M tmpfs "/home/$KIOSK_USERNAME"

# 4. Create necessary directories for the kiosk user in the tmpfs
echo "Creating necessary directories in tmpfs..."
mkdir -p "/home/$KIOSK_USERNAME/Desktop"
mkdir -p "/home/$KIOSK_USERNAME/Documents"
mkdir -p "/home/$KIOSK_USERNAME/Downloads"
mkdir -p "/home/$KIOSK_USERNAME/Pictures"
mkdir -p "/home/$KIOSK_USERNAME/.config"
mkdir -p "/home/$KIOSK_USERNAME/.config/autostart"
mkdir -p "/home/$KIOSK_USERNAME/.local/share/applications"
touch "/home/$KIOSK_USERNAME/Desktop/.keep"

# 13. Configure fstab for tmpfs mounting on boot
echo "Configuring fstab for tmpfs mounting on boot..."
# Check if the entry already exists
if ! grep -q "tmpfs /home/$KIOSK_USERNAME" /etc/fstab; then
  echo "# Kiosk user tmpfs mount" >> /etc/fstab
  echo "tmpfs /home/$KIOSK_USERNAME tmpfs defaults,noatime,mode=1777,size=512M 0 0" >> /etc/fstab
  echo "Added tmpfs mount to fstab."
else
  echo "tmpfs mount already exists in fstab."
fi

# 16. Set correct ownership for all created files
echo "Setting ownership for kiosk user files..."
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/"
chmod 755 "$OPT_KIOSK_DIR"/*.sh

# 17. Copy the autostart entries to the kiosk user's home directory
echo "Copying autostart entries to kiosk user's home directory..."
cp -r "$TEMPLATE_DIR/.config/autostart/"* "/home/$KIOSK_USERNAME/.config/autostart/"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/.config/autostart/"

# Create a persistent dconf settings script
echo "Creating persistent dconf settings script..."
PERSISTENT_DCONF_SCRIPT="$OPT_KIOSK_DIR/persistent_dconf_settings.sh"

cat > "$PERSISTENT_DCONF_SCRIPT" << 'EOF'
#!/bin/bash

# Script to apply persistent dconf settings for the kiosk user
# This script will be run on boot and after user login to ensure settings persist

# Log file for debugging
LOGFILE="/var/log/kiosk-dconf-settings.log"
echo "$(date): Starting persistent dconf settings script" > "$LOGFILE"

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