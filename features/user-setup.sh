#!/bin/bash

# ZorinOS Kiosk User Setup Script
# Features: #1, 2, 8, 9, 10, 11, 12

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

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