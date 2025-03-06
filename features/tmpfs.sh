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
source "$ENV_FILE"

# 5. Create a script to disable screen blanking
echo "Creating screen blanking prevention script..."
SCREEN_SCRIPT="$OPT_KIOSK_DIR/disable_screensaver.sh"

cat > "$SCREEN_SCRIPT" << EOF
#!/bin/bash

# Script to disable screen blanking and prevent display from turning off
# Display timeout set to $DISPLAY_TIMEOUT seconds ($(($DISPLAY_TIMEOUT/60)) minutes)

# Disable DPMS (Energy Star) features
xset -dpms

# Disable screen saver
xset s off

# Set screen timeout (using the variable from the main script)
xset s $DISPLAY_TIMEOUT $DISPLAY_TIMEOUT

# Disable screen blanking
xset s noexpose
xset s noblank

# Log that the script has run
echo "\$(date): Screen blanking disabled, timeout set to $(($DISPLAY_TIMEOUT/60)) minutes." >> ~/screen_settings.log

# Keep the script running to maintain settings
while true; do
  # Refresh settings every 5 minutes to ensure they stay active
  sleep 300
  xset -dpms
  xset s off
  xset s $DISPLAY_TIMEOUT $DISPLAY_TIMEOUT
  xset s noexpose
  xset s noblank
done
EOF

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