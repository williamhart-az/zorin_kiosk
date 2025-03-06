#!/bin/bash

# ZorinOS Kiosk Setup Script with Desktop Environment
# Run this script with sudo after fresh installation
# Usage: sudo bash kiosk_setup.sh

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Load configuration from .env file
ENV_FILE="./kiosk_setup.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: Configuration file $ENV_FILE not found."
  echo "Please make sure the file exists in the same directory as this script."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

echo "=== ZorinOS Kiosk Setup ==="
echo "This script will configure your system for kiosk mode with desktop access."
echo "WARNING: This is meant for dedicated kiosk systems only!"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Setup cancelled."
  exit 1
fi

# 1. Create kiosk user first
echo "Creating kiosk user..."
if id "$KIOSK_USERNAME" &>/dev/null; then
  echo "User $KIOSK_USERNAME already exists."
else
  adduser --disabled-password --gecos "$KIOSK_FULLNAME" "$KIOSK_USERNAME"
  echo "$KIOSK_USERNAME:$KIOSK_PASSWORD" | chpasswd
  # Add to necessary groups for printing and USB access
  usermod -aG video,audio,plugdev,netdev,lp,lpadmin,scanner,cdrom,dialout "$KIOSK_USERNAME"
fi

# 2. Create /opt/kiosk directory for scripts and templates
echo "Creating /opt/kiosk directory..."
mkdir -p "$OPT_KIOSK_DIR"
mkdir -p "$TEMPLATE_DIR"
mkdir -p "$TEMPLATE_DIR/Desktop"
mkdir -p "$TEMPLATE_DIR/Documents"
mkdir -p "$TEMPLATE_DIR/.config/autostart"
mkdir -p "$TEMPLATE_DIR/.local/share/applications"
chmod 755 "$OPT_KIOSK_DIR"

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

# 7. Create Firefox profile setup script
echo "Creating Firefox profile setup script..."
FIREFOX_PROFILE_SCRIPT="$OPT_KIOSK_DIR/setup_firefox_profile.sh"

cat > "$FIREFOX_PROFILE_SCRIPT" << EOF
#!/bin/bash

# Script to set up Firefox profile for kiosk user
LOGFILE="/tmp/firefox_profile_setup.log"
echo "\$(date): Setting up Firefox profile..." >> "\$LOGFILE"

# Detect Firefox installation type
FIREFOX_FLATPAK=false

# Check if Firefox is installed as flatpak
if [ -d "/var/lib/flatpak/app/org.mozilla.firefox" ] || [ -d "/home/$KIOSK_USERNAME/.local/share/flatpak/app/org.mozilla.firefox" ]; then
  FIREFOX_FLATPAK=true
  PROFILE_BASE_DIR="/home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox"
  echo "\$(date): Firefox flatpak detected" >> "\$LOGFILE"
else
  PROFILE_BASE_DIR="/home/$KIOSK_USERNAME"
  echo "\$(date): Standard Firefox detected" >> "\$LOGFILE"
fi

# Create profile directories
mkdir -p "\$PROFILE_BASE_DIR/.mozilla/firefox"

# Create a default profile directory with a random name
PROFILE_NAME="default-\$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
PROFILE_DIR="\$PROFILE_BASE_DIR/.mozilla/firefox/\$PROFILE_NAME"
mkdir -p "\$PROFILE_DIR"

# Create profiles.ini file
cat > "\$PROFILE_BASE_DIR/.mozilla/firefox/profiles.ini" << EOL
[Profile0]
Name=default
IsRelative=1
Path=$PROFILE_NAME
Default=1

[General]
StartWithLastProfile=1
Version=2
EOL

echo "\$(date): Created profile: \$PROFILE_NAME" >> "\$LOGFILE"

# Create user.js file to suppress first-run wizard and set preferences
cat > "\$PROFILE_DIR/user.js" << EOL
// Set homepage
user_pref("browser.startup.homepage", "$HOMEPAGE");
user_pref("browser.startup.page", 1);

// Disable first-run wizard and welcome page
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);

// Disable default browser check
user_pref("browser.shell.checkDefaultBrowser", false);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable telemetry
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.firstRunTime", 0);

// Privacy settings
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.downloads", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.history", true);
user_pref("privacy.clearOnShutdown.sessions", true);
EOL

echo "\$(date): Created Firefox preferences" >> "\$LOGFILE"

# Set correct permissions
chown -R $KIOSK_USERNAME:$KIOSK_USERNAME "\$PROFILE_BASE_DIR/.mozilla"
chmod -R 700 "\$PROFILE_BASE_DIR/.mozilla"

echo "\$(date): Firefox profile setup complete" >> "\$LOGFILE"
EOF

chmod +x "$FIREFOX_PROFILE_SCRIPT"

# 8. Create init_kiosk.sh script to initialize the kiosk environment
echo "Creating kiosk initialization script..."
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

# Run Firefox profile setup script
sudo $OPT_KIOSK_DIR/setup_firefox_profile.sh

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

# Set wallpaper
$OPT_KIOSK_DIR/set_wallpaper.sh

echo "\$(date): Kiosk environment initialized successfully." >> "\$LOGFILE"
EOF

chmod +x "$INIT_SCRIPT"

# 9. Copy the wallpaper to the system backgrounds directory
echo "Setting up wallpaper..."
if [ -f "$WALLPAPER_ADMIN_PATH" ]; then
  cp "$WALLPAPER_ADMIN_PATH" "$WALLPAPER_SYSTEM_PATH"
  chmod 644 "$WALLPAPER_SYSTEM_PATH"
  echo "Wallpaper copied to system directory."
else
  echo "Warning: Wallpaper file not found at $WALLPAPER_ADMIN_PATH"
fi

# 10. Create autostart entries in the template directory
echo "Setting up autostart entries in template directory..."
TEMPLATE_AUTOSTART_DIR="$TEMPLATE_DIR/.config/autostart"
mkdir -p "$TEMPLATE_AUTOSTART_DIR"

# Kiosk initialization autostart entry
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

# Screen blanking prevention autostart entry
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

# Wallpaper setting autostart entry
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

# 11. Configure auto-login for the Kiosk user
echo "Configuring auto-login for the Kiosk user..."
# First, create the autologin group if it doesn't exist
groupadd -f autologin
usermod -aG autologin $KIOSK_USERNAME

# Detect display manager
DM_SERVICE=""
if [ -f "/etc/systemd/system/display-manager.service" ]; then
  DM_SERVICE=$(readlink -f /etc/systemd/system/display-manager.service)
  echo "Detected display manager service: $DM_SERVICE"
fi

# Configure LightDM for autologin if it's being used
if [ -d "/etc/lightdm" ] || [[ "$DM_SERVICE" == *"lightdm"* ]]; then
  echo "Configuring LightDM for autologin..."
  mkdir -p /etc/lightdm
  cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-guest=false
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
autologin-session=zorin
user-session=zorin
greeter-session=slick-greeter
EOF

  # Create a separate autologin configuration file
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << EOF
[Seat:*]
autologin-guest=false
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
autologin-session=zorin
user-session=zorin
greeter-session=slick-greeter
EOF
fi

# Configure GDM for autologin if it's being used
if [ -d "/etc/gdm3" ] || [[ "$DM_SERVICE" == *"gdm"* ]]; then
  echo "Configuring GDM for autologin..."
  mkdir -p /etc/gdm3
  if [ -f "/etc/gdm3/custom.conf" ]; then
    # Backup the original file
    cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak
    
    # Update the configuration
    sed -i '/\[daemon\]/,/^\[/ s/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
    sed -i '/\[daemon\]/,/^\[/ s/^AutomaticLogin=.*/AutomaticLogin='$KIOSK_USERNAME'/' /etc/gdm3/custom.conf
    
    # If the settings don't exist, add them
    if ! grep -q "AutomaticLoginEnable" /etc/gdm3/custom.conf; then
      sed -i '/\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin='$KIOSK_USERNAME'' /etc/gdm3/custom.conf
    fi
  else
    # Create a new configuration file
    cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$KIOSK_USERNAME
EOF
  fi
fi

# Configure SDDM for autologin if it's being used
if [ -d "/etc/sddm.conf.d" ] || [[ "$DM_SERVICE" == *"sddm"* ]]; then
  echo "Configuring SDDM for autologin..."
  mkdir -p /etc/sddm.conf.d
  cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$KIOSK_USERNAME
Session=zorin
EOF
fi

# 12. Configure AccountsService for autologin
echo "Configuring AccountsService for autologin..."
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/$KIOSK_USERNAME << EOF
[User]
Language=
XSession=zorin
SystemAccount=false
Icon=/usr/share/pixmaps/faces/user-generic.png
EOF

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

# 16. Set correct ownership for all created files
echo "Setting ownership for kiosk user files..."
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/"
chmod 755 "$OPT_KIOSK_DIR"/*.sh

# 17. Copy the autostart entries to the kiosk user's home directory
echo "Copying autostart entries to kiosk user's home directory..."
cp -r "$TEMPLATE_AUTOSTART_DIR/"* "/home/$KIOSK_USERNAME/.config/autostart/"
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

# 19. Create a sudoers entry for the kiosk user to run the Firefox profile setup script
echo "Creating sudoers entry for Firefox profile setup..."
SUDOERS_FILE="/etc/sudoers.d/kiosk-firefox"
cat > "$SUDOERS_FILE" << EOF
# Allow kiosk user to run Firefox profile setup script without password
$KIOSK_USERNAME ALL=(ALL) NOPASSWD: $OPT_KIOSK_DIR/setup_firefox_profile.sh
EOF
chmod 440 "$SUDOERS_FILE"

echo ""
echo "=== Kiosk Setup Complete ==="
echo "Your system will now:"
echo "1. Mount a tmpfs filesystem for the kiosk user's home directory"
echo "2. Initialize the kiosk environment on login with the init_kiosk.sh script"
echo "3. Prevent the screen from turning off for $(($DISPLAY_TIMEOUT/60)) minutes"
echo "4. Set the wallpaper to $WALLPAPER_NAME"
echo "5. Autologin as the Kiosk user"
echo "6. Allow admin changes to be saved to the template directory"
echo "7. Use a systemd service to initialize the kiosk home directory after tmpfs mount"
echo "8. Automatically configure Firefox to suppress the first-run wizard"
echo ""
echo "To test the setup, reboot your system with: sudo reboot"