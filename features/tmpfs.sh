#!/bin/bash

# ZorinOS Kiosk tmpfs Setup Script
# Features: #3, 4, 5, 6, 13, 16, 17, 18

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

# 5. Create a script to disable screen blanking
echo "Creating screen blanking prevention script..."
SCREEN_SCRIPT="$OPT_KIOSK_DIR/disable_screensaver.sh"

# Check if the script already exists (might have been created by user-setup.sh)
if [ ! -f "$SCREEN_SCRIPT" ]; then
  cat > "$SCREEN_SCRIPT" << 'EOF'
#!/bin/bash

# Script to disable screen blanking and screen locking for Zorin OS 17 kiosk mode
# This script uses multiple methods to ensure screen blanking is disabled

# Log file for debugging
LOGFILE="/tmp/disable_screensaver.log"
echo "$(date): Starting screen blanking prevention script" > "$LOGFILE"

# Function to safely run xset commands with error handling
safe_xset() {
    if command -v xset &> /dev/null; then
        # Check if DISPLAY is set
        if [ -z "$DISPLAY" ]; then
            echo "$(date): DISPLAY environment variable not set, setting to :0" >> "$LOGFILE"
            export DISPLAY=:0
        fi
        
        # Try to run xset command and capture any errors
        OUTPUT=$(xset $@ 2>&1)
        if [ $? -ne 0 ]; then
            echo "$(date): xset $@ failed: $OUTPUT" >> "$LOGFILE"
            return 1
        else
            echo "$(date): xset $@ succeeded" >> "$LOGFILE"
            return 0
        fi
    else
        echo "$(date): xset command not found" >> "$LOGFILE"
        return 1
    fi
}

# Method 1: Use xset to disable DPMS and screen blanking with error handling
echo "$(date): Attempting to use xset to disable DPMS and screen blanking" >> "$LOGFILE"

# Wait for X server to be ready (up to 30 seconds)
COUNTER=0
while [ $COUNTER -lt 30 ]; do
    if safe_xset q &>/dev/null; then
        echo "$(date): X server is ready" >> "$LOGFILE"
        break
    fi
    echo "$(date): Waiting for X server to be ready ($COUNTER/30)" >> "$LOGFILE"
    sleep 1
    COUNTER=$((COUNTER+1))
done

# Try different xset commands with error handling
safe_xset s off || echo "$(date): Failed to set xset s off" >> "$LOGFILE"
safe_xset s noblank || echo "$(date): Failed to set xset s noblank" >> "$LOGFILE"

# Try to disable DPMS if supported
if xset q | grep -q "DPMS"; then
    echo "$(date): DPMS is supported, attempting to disable" >> "$LOGFILE"
    safe_xset -dpms || echo "$(date): Failed to disable DPMS with xset -dpms" >> "$LOGFILE"
else
    echo "$(date): DPMS is not supported by this X server" >> "$LOGFILE"
fi

# Method 2: Use gsettings to disable screen blanking and locking
if command -v gsettings &> /dev/null; then
    echo "$(date): Using gsettings to disable screen blanking and locking" >> "$LOGFILE"
    
    # Function to safely set gsettings
    safe_gsettings_set() {
        local schema="$1"
        local key="$2"
        local value="$3"
        
        # Check if schema exists
        if gsettings list-schemas 2>/dev/null | grep -q "^$schema$"; then
            # Check if key exists in schema
            if gsettings list-keys "$schema" 2>/dev/null | grep -q "^$key$"; then
                echo "$(date): Setting $schema $key to $value" >> "$LOGFILE"
                gsettings set "$schema" "$key" "$value" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "$(date): Successfully set $schema $key to $value" >> "$LOGFILE"
                    return 0
                else
                    echo "$(date): Failed to set $schema $key to $value" >> "$LOGFILE"
                    return 1
                fi
            else
                echo "$(date): Key $key not found in schema $schema" >> "$LOGFILE"
                return 1
            fi
        else
            echo "$(date): Schema $schema not found" >> "$LOGFILE"
            return 1
        fi
    }
    
    # Disable screen lock
    safe_gsettings_set "org.gnome.desktop.lockdown" "disable-lock-screen" "true"
    
    # Disable screensaver
    safe_gsettings_set "org.gnome.desktop.session" "idle-delay" "0"
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
    
    echo "$(date): gsettings commands completed" >> "$LOGFILE"
else
    echo "$(date): gsettings command not found" >> "$LOGFILE"
fi

# Method 3: Use dconf directly (for Zorin OS 17)
if command -v dconf &> /dev/null; then
    echo "$(date): Using dconf to disable screen blanking and locking" >> "$LOGFILE"
    
    # Function to safely write dconf settings
    safe_dconf_write() {
        local path="$1"
        local value="$2"
        
        echo "$(date): Setting dconf $path to $value" >> "$LOGFILE"
        dconf write "$path" "$value" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "$(date): Successfully set dconf $path to $value" >> "$LOGFILE"
            return 0
        else
            echo "$(date): Failed to set dconf $path to $value" >> "$LOGFILE"
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
    
    echo "$(date): dconf commands completed" >> "$LOGFILE"
else
    echo "$(date): dconf command not found" >> "$LOGFILE"
fi

# Method 4: Create a systemd inhibitor to prevent screen blanking
if command -v systemd-inhibit &> /dev/null; then
    echo "$(date): Using systemd-inhibit to prevent screen blanking" >> "$LOGFILE"
    # Run a small sleep command that will keep the inhibitor active
    systemd-inhibit --what=idle:sleep:handle-lid-switch --who="Kiosk Mode" --why="Prevent screen blanking in kiosk mode" sleep infinity &
    INHIBIT_PID=$!
    echo "$(date): systemd-inhibit started with PID $INHIBIT_PID" >> "$LOGFILE"
else
    echo "$(date): systemd-inhibit command not found" >> "$LOGFILE"
fi

# Method 5: Use a loop to simulate user activity (last resort)
echo "$(date): Starting activity simulation loop" >> "$LOGFILE"
(
    while true; do
        # Simulate user activity every 60 seconds
        if command -v xdotool &> /dev/null; then
            # Move mouse 1 pixel right and then back
            xdotool mousemove_relative -- 1 0 2>/dev/null
            sleep 1
            xdotool mousemove_relative -- -1 0 2>/dev/null
            echo "$(date): Simulated mouse movement" >> "$LOGFILE"
        else
            # If xdotool is not available, try to use DISPLAY to trigger activity
            if [ -n "$DISPLAY" ]; then
                # Try to use xset to reset the screensaver timer
                xset s reset 2>/dev/null || true
            fi
        fi
        sleep 60
    done
) &
ACTIVITY_PID=$!
echo "$(date): Activity simulation started with PID $ACTIVITY_PID" >> "$LOGFILE"

# Method 6: Use xfce4-power-manager settings if available (for Zorin OS Lite)
if command -v xfconf-query &> /dev/null; then
    echo "$(date): Detected xfconf-query, attempting to configure XFCE power settings" >> "$LOGFILE"
    
    # Try to set XFCE power manager settings
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false 2>/dev/null && \
        echo "$(date): Disabled XFCE DPMS" >> "$LOGFILE" || \
        echo "$(date): Failed to disable XFCE DPMS" >> "$LOGFILE"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 2>/dev/null && \
        echo "$(date): Set XFCE blank-on-ac to 0" >> "$LOGFILE" || \
        echo "$(date): Failed to set XFCE blank-on-ac" >> "$LOGFILE"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -s 0 2>/dev/null && \
        echo "$(date): Set XFCE blank-on-battery to 0" >> "$LOGFILE" || \
        echo "$(date): Failed to set XFCE blank-on-battery" >> "$LOGFILE"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s 0 2>/dev/null && \
        echo "$(date): Set XFCE dpms-on-ac-off to 0" >> "$LOGFILE" || \
        echo "$(date): Failed to set XFCE dpms-on-ac-off" >> "$LOGFILE"
        
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery-off -s 0 2>/dev/null && \
        echo "$(date): Set XFCE dpms-on-battery-off to 0" >> "$LOGFILE" || \
        echo "$(date): Failed to set XFCE dpms-on-battery-off" >> "$LOGFILE"
else
    echo "$(date): xfconf-query not found, skipping XFCE power settings" >> "$LOGFILE"
fi

echo "$(date): Screen blanking prevention script completed" >> "$LOGFILE"

# Keep the script running to ensure settings persist
# This prevents the script from exiting and killing background processes
tail -f /dev/null
EOF
  echo "Created comprehensive screen blanking prevention script for Zorin OS 17."
else
  echo "Screen blanking prevention script already exists, skipping creation."
fi

chmod +x "$SCREEN_SCRIPT"

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
ExecStart=/bin/bash -c "mkdir -p /home/$KIOSK_USERNAME/.config/autostart && cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ && mkdir -p /home/$KIOSK_USERNAME/Desktop && cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ 2>/dev/null || true && mkdir -p /home/$KIOSK_USERNAME/Documents && cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ 2>/dev/null || true && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/ && $OPT_KIOSK_DIR/setup_firefox_profile.sh"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable kiosk-home-init.service