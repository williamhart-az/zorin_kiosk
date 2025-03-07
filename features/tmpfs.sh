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

# Method 1: Use xset to disable DPMS and screen blanking
if command -v xset &> /dev/null; then
    echo "$(date): Using xset to disable DPMS and screen blanking" >> "$LOGFILE"
    xset s off -dpms
    xset s noblank
    xset -dpms
    echo "$(date): xset commands executed" >> "$LOGFILE"
else
    echo "$(date): xset command not found" >> "$LOGFILE"
fi

# Method 2: Use gsettings to disable screen blanking and locking
if command -v gsettings &> /dev/null; then
    echo "$(date): Using gsettings to disable screen blanking and locking" >> "$LOGFILE"
    
    # Disable screen lock
    gsettings set org.gnome.desktop.lockdown disable-lock-screen true
    
    # Disable screensaver
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set org.gnome.desktop.screensaver lock-enabled false
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
    
    # Disable screen dimming
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
    
    # Set power settings to never blank screen
    gsettings set org.gnome.settings-daemon.plugins.power sleep-display-ac 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-display-battery 0
    
    # Disable automatic suspend
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    
    echo "$(date): gsettings commands executed" >> "$LOGFILE"
else
    echo "$(date): gsettings command not found" >> "$LOGFILE"
fi

# Method 3: Use dconf directly (for Zorin OS 17)
if command -v dconf &> /dev/null; then
    echo "$(date): Using dconf to disable screen blanking and locking" >> "$LOGFILE"
    
    # Disable screen lock
    dconf write /org/gnome/desktop/lockdown/disable-lock-screen true
    
    # Disable screensaver
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0"
    dconf write /org/gnome/desktop/screensaver/lock-enabled false
    dconf write /org/gnome/desktop/screensaver/idle-activation-enabled false
    
    # Disable screen dimming
    dconf write /org/gnome/settings-daemon/plugins/power/idle-dim false
    
    # Set power settings to never blank screen
    dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-ac "uint32 0"
    dconf write /org/gnome/settings-daemon/plugins/power/sleep-display-battery "uint32 0"
    
    # Disable automatic suspend
    dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'"
    dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'"
    
    # Zorin OS specific settings (if they exist)
    dconf write /com/zorin/desktop/screensaver/lock-enabled false 2>/dev/null || true
    dconf write /com/zorin/desktop/session/idle-delay "uint32 0" 2>/dev/null || true
    
    echo "$(date): dconf commands executed" >> "$LOGFILE"
else
    echo "$(date): dconf command not found" >> "$LOGFILE"
fi

# Method 4: Create a systemd inhibitor to prevent screen blanking
if command -v systemd-inhibit &> /dev/null; then
    echo "$(date): Using systemd-inhibit to prevent screen blanking" >> "$LOGFILE"
    # Run a small sleep command that will keep the inhibitor active
    systemd-inhibit --what=idle:sleep:handle-lid-switch --who="Kiosk Mode" --why="Prevent screen blanking in kiosk mode" sleep infinity &
    echo "$(date): systemd-inhibit started with PID $!" >> "$LOGFILE"
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
            xdotool mousemove_relative -- 1 0
            sleep 1
            xdotool mousemove_relative -- -1 0
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

echo "$(date): Screen blanking prevention script completed" >> "$LOGFILE"
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