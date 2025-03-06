#!/bin/bash

# ZorinOS Kiosk User Setup Script
# Features: #1, 2, 8, 9, 10, 11, 12

echo "[DEBUG] Starting user-setup.sh script"
echo "[DEBUG] Script path: $(readlink -f "$0")"
echo "[DEBUG] Current directory: $(pwd)"

# Exit on any error
set -e
echo "[DEBUG] Error handling enabled with 'set -e'"

# Check if running as root
echo "[DEBUG] Checking if script is running as root"
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Please use sudo."
  exit 1
fi
echo "[DEBUG] Script is running as root, continuing"

# Source the environment file
echo "[DEBUG] Checking for environment file"
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../kiosk_setup.env"
  echo "[DEBUG] ENV_FILE not defined, using default: $ENV_FILE"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")"
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/kiosk_setup.env"
        echo "[DEBUG] Looking for kiosk_setup.env next to kiosk_setup.sh: $ENV_FILE"
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

# Print environment variables for debugging
echo "[DEBUG] KIOSK_USERNAME=$KIOSK_USERNAME"
echo "[DEBUG] KIOSK_FULLNAME=$KIOSK_FULLNAME"
echo "[DEBUG] OPT_KIOSK_DIR=$OPT_KIOSK_DIR"
echo "[DEBUG] TEMPLATE_DIR=$TEMPLATE_DIR"
echo "[DEBUG] WALLPAPER_ADMIN_PATH=$WALLPAPER_ADMIN_PATH"
echo "[DEBUG] WALLPAPER_SYSTEM_PATH=$WALLPAPER_SYSTEM_PATH"

# 1. Create kiosk user first
echo "[DEBUG] Feature #1: Creating kiosk user"
echo "[DEBUG] Checking if user $KIOSK_USERNAME already exists"
if id "$KIOSK_USERNAME" &>/dev/null; then
  echo "[DEBUG] User $KIOSK_USERNAME already exists, skipping creation"
else
  echo "[DEBUG] User $KIOSK_USERNAME does not exist, creating now"
  adduser --disabled-password --gecos "$KIOSK_FULLNAME" "$KIOSK_USERNAME"
  echo "[DEBUG] Setting password for $KIOSK_USERNAME"
  echo "$KIOSK_USERNAME:$KIOSK_PASSWORD" | chpasswd
  echo "[DEBUG] Adding $KIOSK_USERNAME to necessary groups"
  usermod -aG video,audio,plugdev,netdev,lp,lpadmin,scanner,cdrom,dialout "$KIOSK_USERNAME"
  echo "[DEBUG] User $KIOSK_USERNAME created and configured successfully"
fi

# 2. Create /opt/kiosk directory for scripts and templates
echo "[DEBUG] Feature #2: Creating kiosk directories"
echo "[DEBUG] Creating main kiosk directory at $OPT_KIOSK_DIR"
mkdir -p "$OPT_KIOSK_DIR"
echo "[DEBUG] Creating template directory at $TEMPLATE_DIR"
mkdir -p "$TEMPLATE_DIR"
echo "[DEBUG] Creating Desktop template directory"
mkdir -p "$TEMPLATE_DIR/Desktop"
echo "[DEBUG] Creating Documents template directory"
mkdir -p "$TEMPLATE_DIR/Documents"
echo "[DEBUG] Creating autostart template directory"
mkdir -p "$TEMPLATE_DIR/.config/autostart"
echo "[DEBUG] Creating applications template directory"
mkdir -p "$TEMPLATE_DIR/.local/share/applications"
echo "[DEBUG] Setting permissions on $OPT_KIOSK_DIR"
chmod 755 "$OPT_KIOSK_DIR"
echo "[DEBUG] All kiosk directories created successfully"

# 8. Create init_kiosk.sh script to initialize the kiosk environment
echo "[DEBUG] Feature #8: Creating kiosk initialization script"
INIT_SCRIPT="$OPT_KIOSK_DIR/init_kiosk.sh"
echo "[DEBUG] Initialization script will be created at: $INIT_SCRIPT"

cat > "$INIT_SCRIPT" << EOF
#!/bin/bash

# Script to initialize kiosk environment on login

# Log initialization
LOGFILE="/tmp/kiosk_init.log"
echo "\$(date): [DEBUG] Initializing kiosk environment..." >> "\$LOGFILE"

# Create necessary directories if they don't exist
echo "\$(date): [DEBUG] Creating user directories" >> "\$LOGFILE"
mkdir -p ~/Desktop
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/Pictures
mkdir -p ~/.config/autostart
mkdir -p ~/.local/share/applications
echo "\$(date): [DEBUG] User directories created" >> "\$LOGFILE"

# Copy template files to kiosk home directory
TEMPLATE_DIR="$TEMPLATE_DIR"
echo "\$(date): [DEBUG] Using template directory: \$TEMPLATE_DIR" >> "\$LOGFILE"

# Run Firefox profile setup script
echo "\$(date): [DEBUG] Running Firefox profile setup script" >> "\$LOGFILE"
sudo $OPT_KIOSK_DIR/setup_firefox_profile.sh
echo "\$(date): [DEBUG] Firefox profile setup completed" >> "\$LOGFILE"

# Copy desktop shortcuts if they exist
if [ -d "\$TEMPLATE_DIR/Desktop" ]; then
  echo "\$(date): [DEBUG] Copying desktop shortcuts from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/Desktop/"* ~/Desktop/ 2>/dev/null || true
  echo "\$(date): [DEBUG] Desktop shortcuts copied (or none found)" >> "\$LOGFILE"
fi

# Copy documents if they exist
if [ -d "\$TEMPLATE_DIR/Documents" ]; then
  echo "\$(date): [DEBUG] Copying documents from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/Documents/"* ~/Documents/ 2>/dev/null || true
  echo "\$(date): [DEBUG] Documents copied (or none found)" >> "\$LOGFILE"
fi

# Copy autostart entries if they exist
if [ -d "\$TEMPLATE_DIR/.config/autostart" ]; then
  echo "\$(date): [DEBUG] Copying autostart entries from template..." >> "\$LOGFILE"
  cp -r "\$TEMPLATE_DIR/.config/autostart/"* ~/.config/autostart/ 2>/dev/null || true
  echo "\$(date): [DEBUG] Autostart entries copied (or none found)" >> "\$LOGFILE"
fi

# Set wallpaper
echo "\$(date): [DEBUG] Setting wallpaper" >> "\$LOGFILE"
$OPT_KIOSK_DIR/set_wallpaper.sh
echo "\$(date): [DEBUG] Wallpaper set" >> "\$LOGFILE"

echo "\$(date): [DEBUG] Kiosk environment initialized successfully." >> "\$LOGFILE"
EOF

echo "[DEBUG] Writing initialization script content"
chmod +x "$INIT_SCRIPT"
echo "[DEBUG] Made initialization script executable"
echo "[DEBUG] Kiosk initialization script created successfully"

# 9. Copy the wallpaper to the system backgrounds directory
echo "[DEBUG] Feature #9: Setting up wallpaper"
echo "[DEBUG] Checking for wallpaper at $WALLPAPER_ADMIN_PATH"
if [ -f "$WALLPAPER_ADMIN_PATH" ]; then
  echo "[DEBUG] Wallpaper found, copying to $WALLPAPER_SYSTEM_PATH"
  cp "$WALLPAPER_ADMIN_PATH" "$WALLPAPER_SYSTEM_PATH"
  echo "[DEBUG] Setting permissions on wallpaper file"
  chmod 644 "$WALLPAPER_SYSTEM_PATH"
  echo "[DEBUG] Wallpaper copied to system directory successfully"
else
  echo "[WARNING] Wallpaper file not found at $WALLPAPER_ADMIN_PATH"
  echo "[DEBUG] Continuing without wallpaper"
fi

# 10. Create autostart entries in the template directory
echo "[DEBUG] Feature #10: Setting up autostart entries"
TEMPLATE_AUTOSTART_DIR="$TEMPLATE_DIR/.config/autostart"
echo "[DEBUG] Creating autostart directory at $TEMPLATE_AUTOSTART_DIR"
mkdir -p "$TEMPLATE_AUTOSTART_DIR"

# Kiosk initialization autostart entry
echo "[DEBUG] Creating kiosk initialization autostart entry"
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
echo "[DEBUG] Kiosk initialization autostart entry created"

# Screen blanking prevention autostart entry
echo "[DEBUG] Creating screen blanking prevention autostart entry"
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
echo "[DEBUG] Screen blanking prevention autostart entry created"

# Wallpaper setting autostart entry
echo "[DEBUG] Creating wallpaper setting autostart entry"
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
echo "[DEBUG] Wallpaper setting autostart entry created"
echo "[DEBUG] All autostart entries created successfully"

# 11. Configure auto-login for the Kiosk user
echo "[DEBUG] Feature #11: Configuring auto-login for the Kiosk user"
# First, create the autologin group if it doesn't exist
echo "[DEBUG] Creating autologin group if it doesn't exist"
groupadd -f autologin
echo "[DEBUG] Adding $KIOSK_USERNAME to autologin group"
usermod -aG autologin $KIOSK_USERNAME

# Detect display manager
echo "[DEBUG] Detecting display manager"
DM_SERVICE=""
if [ -f "/etc/systemd/system/display-manager.service" ]; then
  DM_SERVICE=$(readlink -f /etc/systemd/system/display-manager.service)
  echo "[DEBUG] Detected display manager service: $DM_SERVICE"
else
  echo "[DEBUG] No display manager service found at /etc/systemd/system/display-manager.service"
  # Try alternative location for Zorin OS 17
  if [ -f "/lib/systemd/system/display-manager.service" ]; then
    DM_SERVICE=$(readlink -f /lib/systemd/system/display-manager.service)
    echo "[DEBUG] Detected display manager service at alternative location: $DM_SERVICE"
  else
    echo "[DEBUG] Will try to detect display manager by directory presence"
  fi
fi

# Determine which display manager is actually running
echo "[DEBUG] Checking which display manager is running"
RUNNING_DM=""
for dm in lightdm gdm gdm3 sddm; do
  if systemctl is-active --quiet $dm.service; then
    RUNNING_DM=$dm
    echo "[DEBUG] Found running display manager: $RUNNING_DM"
    break
  fi
done

# Configure LightDM for autologin if it's being used (Zorin OS typically uses LightDM)
echo "[DEBUG] Checking for LightDM"
if [ -d "/etc/lightdm" ] || [[ "$DM_SERVICE" == *"lightdm"* ]] || [[ "$RUNNING_DM" == "lightdm" ]]; then
  echo "[DEBUG] LightDM detected, configuring for autologin"
  echo "[DEBUG] Creating /etc/lightdm directory if it doesn't exist"
  mkdir -p /etc/lightdm
  
  # Backup existing configuration if it exists
  if [ -f "/etc/lightdm/lightdm.conf" ]; then
    echo "[DEBUG] Backing up existing LightDM configuration"
    cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.bak
  fi
  
  # Check if the file already has autologin settings
  if [ -f "/etc/lightdm/lightdm.conf" ] && grep -q "\[Seat:*\]" /etc/lightdm/lightdm.conf; then
    echo "[DEBUG] Updating existing LightDM configuration"
    # Update existing configuration
    sed -i '/^\[Seat:\*\]/,/^\[/ s/^autologin-user=.*/autologin-user='$KIOSK_USERNAME'/' /etc/lightdm/lightdm.conf
    sed -i '/^\[Seat:\*\]/,/^\[/ s/^autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
    
    # Add settings if they don't exist
    if ! grep -q "autologin-user=" /etc/lightdm/lightdm.conf; then
      sed -i '/^\[Seat:\*\]/a autologin-user='$KIOSK_USERNAME'\nautologin-user-timeout=0' /etc/lightdm/lightdm.conf
    fi
  else
    echo "[DEBUG] Creating new LightDM configuration file"
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
  echo "[DEBUG] Main LightDM configuration file created/updated"

  # Create a separate autologin configuration file
  echo "[DEBUG] Creating LightDM autologin configuration directory"
  mkdir -p /etc/lightdm/lightdm.conf.d
  echo "[DEBUG] Creating LightDM autologin configuration file"
  cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << EOF
[Seat:*]
autologin-guest=false
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
EOF
  echo "[DEBUG] LightDM autologin configuration completed"
  
  # Ensure LightDM service is enabled
  echo "[DEBUG] Ensuring LightDM service is enabled"
  systemctl enable lightdm.service
else
  echo "[DEBUG] LightDM not detected"
fi

# Configure GDM for autologin if it's being used
echo "[DEBUG] Checking for GDM"
if [ -d "/etc/gdm3" ] || [[ "$DM_SERVICE" == *"gdm"* ]] || [[ "$RUNNING_DM" == "gdm"* ]]; then
  echo "[DEBUG] GDM detected, configuring for autologin"
  echo "[DEBUG] Creating /etc/gdm3 directory if it doesn't exist"
  mkdir -p /etc/gdm3
  if [ -f "/etc/gdm3/custom.conf" ]; then
    echo "[DEBUG] Existing GDM configuration found, backing up"
    cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak
    echo "[DEBUG] Backup created at /etc/gdm3/custom.conf.bak"
    
    echo "[DEBUG] Updating GDM configuration"
    # Check if [daemon] section exists
    if grep -q "^\[daemon\]" /etc/gdm3/custom.conf; then
      echo "[DEBUG] [daemon] section found, updating settings"
      sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
      sed -i '/^\[daemon\]/,/^\[/ s/^AutomaticLogin=.*/AutomaticLogin='$KIOSK_USERNAME'/' /etc/gdm3/custom.conf
      
      # Add settings if they don't exist
      if ! grep -q "AutomaticLoginEnable" /etc/gdm3/custom.conf; then
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin='$KIOSK_USERNAME'' /etc/gdm3/custom.conf
      fi
    else
      echo "[DEBUG] [daemon] section not found, adding it"
      echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$KIOSK_USERNAME" >> /etc/gdm3/custom.conf
    fi
    echo "[DEBUG] GDM configuration updated"
  else
    echo "[DEBUG] No existing GDM configuration found, creating new one"
    cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$KIOSK_USERNAME
EOF
    echo "[DEBUG] New GDM configuration created"
  fi
  echo "[DEBUG] GDM autologin configuration completed"
  
  # Ensure GDM service is enabled
  echo "[DEBUG] Ensuring GDM service is enabled"
  if [ "$RUNNING_DM" == "gdm" ]; then
    systemctl enable gdm.service
  elif [ "$RUNNING_DM" == "gdm3" ]; then
    systemctl enable gdm3.service
  fi
else
  echo "[DEBUG] GDM not detected"
fi

# Configure SDDM for autologin if it's being used
echo "[DEBUG] Checking for SDDM"
if [ -d "/etc/sddm.conf.d" ] || [[ "$DM_SERVICE" == *"sddm"* ]] || [[ "$RUNNING_DM" == "sddm" ]]; then
  echo "[DEBUG] SDDM detected, configuring for autologin"
  echo "[DEBUG] Creating SDDM configuration directory"
  mkdir -p /etc/sddm.conf.d
  echo "[DEBUG] Creating SDDM autologin configuration file"
  cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$KIOSK_USERNAME
Session=zorin
EOF
  echo "[DEBUG] SDDM autologin configuration completed"
  
  # Ensure SDDM service is enabled
  echo "[DEBUG] Ensuring SDDM service is enabled"
  systemctl enable sddm.service
else
  echo "[DEBUG] SDDM not detected"
fi

# Additional check for Zorin OS 17 specific configuration
echo "[DEBUG] Checking for Zorin OS 17 specific configuration"
if [ -f "/etc/os-release" ] && grep -q "Zorin OS" /etc/os-release; then
  ZORIN_VERSION=$(grep "VERSION_ID" /etc/os-release | cut -d= -f2 | tr -d '"')
  echo "[DEBUG] Detected Zorin OS version: $ZORIN_VERSION"
  
  # For Zorin OS 17, ensure we're using the correct session name
  if [[ "$ZORIN_VERSION" == "17"* ]]; then
    echo "[DEBUG] Applying Zorin OS 17 specific configuration"
    
    # Update LightDM configuration with correct session name if LightDM is used
    if [ -d "/etc/lightdm" ] || [[ "$DM_SERVICE" == *"lightdm"* ]] || [[ "$RUNNING_DM" == "lightdm" ]]; then
      echo "[DEBUG] Updating LightDM configuration with correct session name for Zorin OS 17"
      
      # Get the correct session name
      ZORIN_SESSION="zorin"
      if [ -d "/usr/share/xsessions" ]; then
        for session in /usr/share/xsessions/*.desktop; do
          if grep -q "Zorin" "$session"; then
            ZORIN_SESSION=$(basename "$session" .desktop)
            echo "[DEBUG] Found Zorin session: $ZORIN_SESSION"
            break
          fi
        done
      fi
      
      # Update the session name in the configuration
      sed -i "s/autologin-session=zorin/autologin-session=$ZORIN_SESSION/" /etc/lightdm/lightdm.conf
      sed -i "s/user-session=zorin/user-session=$ZORIN_SESSION/" /etc/lightdm/lightdm.conf
      
      echo "[DEBUG] LightDM configuration updated with session: $ZORIN_SESSION"
    fi
  fi
fi

# 12. Configure AccountsService for autologin
echo "[DEBUG] Feature #12: Configuring AccountsService for autologin"
echo "[DEBUG] Creating AccountsService users directory"
mkdir -p /var/lib/AccountsService/users

# Determine the correct session name for Zorin OS
ZORIN_SESSION="zorin"
if [ -d "/usr/share/xsessions" ]; then
  for session in /usr/share/xsessions/*.desktop; do
    if grep -q "Zorin" "$session"; then
      ZORIN_SESSION=$(basename "$session" .desktop)
      echo "[DEBUG] Found Zorin session for AccountsService: $ZORIN_SESSION"
      break
    fi
  done
fi

echo "[DEBUG] Creating AccountsService configuration for $KIOSK_USERNAME with session $ZORIN_SESSION"
cat > /var/lib/AccountsService/users/$KIOSK_USERNAME << EOF
[User]
Language=
XSession=$ZORIN_SESSION
SystemAccount=false
Icon=/usr/share/pixmaps/faces/user-generic.png
EOF

# Set GSettings for auto-login if available
if command -v gsettings > /dev/null; then
  echo "[DEBUG] Checking available GSettings schemas"
  
  # Create a temporary script to check available schemas and set appropriate settings
  GSETTINGS_SCRIPT="/tmp/gsettings_autologin.sh"
  cat > "$GSETTINGS_SCRIPT" << 'EOF'
#!/bin/bash
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus

# Function to safely set gsettings
safe_gsettings_set() {
  local schema="$1"
  local key="$2"
  local value="$3"
  
  # Check if schema exists
  if gsettings list-schemas | grep -q "^$schema$"; then
    # Check if key exists in schema
    if gsettings list-keys "$schema" 2>/dev/null | grep -q "^$key$"; then
      echo "[DEBUG] Setting $schema $key to $value"
      gsettings set "$schema" "$key" "$value"
      return 0
    else
      echo "[DEBUG] Key $key not found in schema $schema"
      return 1
    fi
  else
    echo "[DEBUG] Schema $schema not found"
    return 1
  fi
}

# Try different schemas and keys for auto-login settings
USERNAME="$1"

# Try GNOME login screen settings
safe_gsettings_set "org.gnome.login-screen" "enable-auto-login" "true" || echo "[DEBUG] Could not set GNOME auto-login enable"
safe_gsettings_set "org.gnome.login-screen" "auto-login-user" "$USERNAME" || echo "[DEBUG] Could not set GNOME auto-login user"

# Try Zorin OS specific settings if they exist
safe_gsettings_set "com.zorin.desktop.login-screen" "enable-auto-login" "true" || echo "[DEBUG] Could not set Zorin auto-login enable"
safe_gsettings_set "com.zorin.desktop.login-screen" "auto-login-user" "$USERNAME" || echo "[DEBUG] Could not set Zorin auto-login user"

# Try LightDM settings if they exist
safe_gsettings_set "x.dm.slick-greeter" "auto-login-user" "$USERNAME" || echo "[DEBUG] Could not set LightDM auto-login user"
safe_gsettings_set "x.dm.slick-greeter" "auto-login-enable" "true" || echo "[DEBUG] Could not set LightDM auto-login enable"

# Try alternative LightDM settings
safe_gsettings_set "org.gnome.desktop.lockdown" "disable-lock-screen" "true" || echo "[DEBUG] Could not disable lock screen"

echo "[DEBUG] GSettings configuration completed"
EOF
  chmod +x "$GSETTINGS_SCRIPT"
  
  # Run the script as the kiosk user if possible
  if id "$KIOSK_USERNAME" &>/dev/null; then
    echo "[DEBUG] Running GSettings script as $KIOSK_USERNAME"
    su - "$KIOSK_USERNAME" -c "$GSETTINGS_SCRIPT $KIOSK_USERNAME" || echo "[WARNING] Failed to run GSettings as $KIOSK_USERNAME, but continuing"
  else
    echo "[WARNING] Could not run GSettings as $KIOSK_USERNAME, user may not exist yet"
  fi
  
  # Clean up
  rm -f "$GSETTINGS_SCRIPT"
else
  echo "[DEBUG] gsettings command not available, skipping GSettings configuration"
fi

echo "[DEBUG] AccountsService configuration completed"

echo "[DEBUG] User setup script completed successfully"