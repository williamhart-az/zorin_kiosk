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

# Check if the disable_screensaver.sh script exists, create it if not
# Note: This might be created by tmpfs.sh, so we check first
if [ ! -f "$OPT_KIOSK_DIR/disable_screensaver.sh" ]; then
  echo "[DEBUG] Creating screen blanking prevention script"
  cat > "$OPT_KIOSK_DIR/disable_screensaver.sh" << 'EOF'
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
  chmod +x "$OPT_KIOSK_DIR/disable_screensaver.sh"
  echo "[DEBUG] Screen blanking prevention script created and made executable"
else
  echo "[DEBUG] Screen blanking prevention script already exists, skipping creation"
fi

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

# If no running display manager was found, try to determine from installed packages
if [ -z "$RUNNING_DM" ]; then
  echo "[DEBUG] No running display manager found, checking installed packages"
  if dpkg -l | grep -q "lightdm"; then
    RUNNING_DM="lightdm"
    echo "[DEBUG] LightDM package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "gdm3"; then
    RUNNING_DM="gdm3"
    echo "[DEBUG] GDM3 package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "gdm"; then
    RUNNING_DM="gdm"
    echo "[DEBUG] GDM package is installed, assuming it's the display manager"
  elif dpkg -l | grep -q "sddm"; then
    RUNNING_DM="sddm"
    echo "[DEBUG] SDDM package is installed, assuming it's the display manager"
  fi
fi

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
  
  # Create additional configuration for Zorin OS 17
  echo "[DEBUG] Creating additional LightDM configuration for Zorin OS 17"
  cat > /etc/lightdm/lightdm.conf.d/20-zorin-autologin.conf << EOF
[Seat:*]
autologin-user=$KIOSK_USERNAME
autologin-user-timeout=0
EOF

  # Configure slick-greeter specifically (used by Zorin OS)
  echo "[DEBUG] Configuring slick-greeter for autologin"
  mkdir -p /etc/lightdm/slick-greeter.conf.d
  cat > /etc/lightdm/slick-greeter.conf.d/10-autologin.conf << EOF
[Greeter]
automatic-login-user=$KIOSK_USERNAME
automatic-login=true
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
      
      # Try to use Zorin OS specific tools if available
      if command -v zorin-auto-login &> /dev/null; then
        echo "[DEBUG] Found Zorin OS auto-login tool, using it"
        zorin-auto-login enable "$KIOSK_USERNAME" || echo "[WARNING] Failed to use zorin-auto-login tool"
      fi
    fi
    
    # Try to use dconf to set auto-login (Zorin OS 17 specific)
    if command -v dconf &> /dev/null; then
      echo "[DEBUG] Using dconf to set auto-login for Zorin OS 17"
      # Create a temporary script to run dconf as the kiosk user
      DCONF_SCRIPT="/tmp/dconf_autologin.sh"
      cat > "$DCONF_SCRIPT" << EOF
#!/bin/bash

# Wait for D-Bus session to be available (up to 30 seconds)
COUNTER=0
while [ \$COUNTER -lt 30 ]; do
    if [ -e "/run/user/\$(id -u)/bus" ]; then
        echo "[DEBUG] D-Bus session found"
        break
    fi
    echo "[DEBUG] Waiting for D-Bus session (\$COUNTER/30)"
    sleep 1
    COUNTER=\$((COUNTER+1))
done

export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus

# Function to safely write dconf settings
safe_dconf_write() {
    local path="\$1"
    local value="\$2"
    local schema="\$(echo "\$path" | cut -d'/' -f2-3)"
    
    # Check if schema exists
    if dconf list "/\$schema/" &>/dev/null; then
        dconf write "\$path" "\$value" && echo "[DEBUG] Successfully set \$path" || echo "[WARNING] Failed to set \$path"
    else
        echo "[DEBUG] Schema \$schema not found, skipping \$path"
    fi
}

# Try to set auto-login using dconf with error handling
safe_dconf_write "/org/gnome/login-screen/enable-auto-login" "true"
safe_dconf_write "/org/gnome/login-screen/auto-login-user" "'$KIOSK_USERNAME'"

# Try Zorin OS specific settings
safe_dconf_write "/com/zorin/desktop/auto-login/enabled" "true"
safe_dconf_write "/com/zorin/desktop/auto-login/user" "'$KIOSK_USERNAME'"

# Try to disable screen lock
safe_dconf_write "/org/gnome/desktop/lockdown/disable-lock-screen" "true"
safe_dconf_write "/org/gnome/desktop/screensaver/lock-enabled" "false"
EOF
      chmod +x "$DCONF_SCRIPT"
      
      # Run the script as the kiosk user if possible
      if id "$KIOSK_USERNAME" &>/dev/null; then
        echo "[DEBUG] Running dconf script as $KIOSK_USERNAME"
        su - "$KIOSK_USERNAME" -c "$DCONF_SCRIPT" || echo "[WARNING] Failed to run dconf as $KIOSK_USERNAME, but continuing"
      else
        echo "[WARNING] Could not run dconf as $KIOSK_USERNAME, user may not exist yet"
      fi
      
      # Clean up
      rm -f "$DCONF_SCRIPT"
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
AutomaticLogin=true
EOF

# Try to use loginctl to enable auto-login
if command -v loginctl > /dev/null; then
  echo "[DEBUG] Using loginctl to enable auto-login"
  loginctl enable-linger "$KIOSK_USERNAME" || echo "[WARNING] Failed to enable linger for $KIOSK_USERNAME"
  
  # For systemd-based login managers
  if [ -d "/etc/systemd/system" ]; then
    echo "[DEBUG] Creating systemd auto-login override"
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USERNAME --noclear %I \$TERM
EOF
    systemctl daemon-reload
    echo "[DEBUG] Systemd auto-login override created"
  fi
fi

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
  
  # Wait for D-Bus session to be available (up to 30 seconds)
  COUNTER=0
  while [ $COUNTER -lt 30 ]; do
    if [ -e "/run/user/$(id -u)/bus" ]; then
      echo "[DEBUG] D-Bus session found"
      break
    fi
    echo "[DEBUG] Waiting for D-Bus session ($COUNTER/30)"
    sleep 1
    COUNTER=$((COUNTER+1))
  done
  
  # Set DBUS address
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
  
  # Check if schema exists
  if gsettings list-schemas 2>/dev/null | grep -q "^$schema$"; then
    # Check if key exists in schema
    if gsettings list-keys "$schema" 2>/dev/null | grep -q "^$key$"; then
      echo "[DEBUG] Setting $schema $key to $value"
      if gsettings set "$schema" "$key" "$value" 2>/dev/null; then
        echo "[DEBUG] Successfully set $schema $key"
        return 0
      else
        echo "[WARNING] Failed to set $schema $key"
        return 1
      fi
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

# Try to disable screen lock and screensaver
safe_gsettings_set "org.gnome.desktop.screensaver" "lock-enabled" "false" || echo "[DEBUG] Could not disable screensaver lock"
safe_gsettings_set "org.gnome.desktop.screensaver" "idle-activation-enabled" "false" || echo "[DEBUG] Could not disable screensaver activation"

# Try to disable user switching
safe_gsettings_set "org.gnome.desktop.lockdown" "disable-user-switching" "true" || echo "[DEBUG] Could not disable user switching"

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

# Create a systemd user service for the kiosk user to ensure auto-login settings persist
echo "[DEBUG] Creating systemd user service for auto-login persistence"
mkdir -p /home/$KIOSK_USERNAME/.config/systemd/user/
cat > /home/$KIOSK_USERNAME/.config/systemd/user/kiosk-autologin.service << EOF
[Unit]
Description=Kiosk Auto-Login Service
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'dconf write /org/gnome/desktop/lockdown/disable-lock-screen true || true'
ExecStart=/bin/sh -c 'dconf write /org/gnome/desktop/screensaver/lock-enabled false || true'
ExecStart=/bin/sh -c 'dconf write /org/gnome/login-screen/enable-auto-login true || true'
ExecStart=/bin/sh -c 'dconf write /org/gnome/login-screen/auto-login-user "'$KIOSK_USERNAME'" || true'
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

# Set proper ownership
chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/.config/

# Enable the service for the user
if command -v systemctl > /dev/null; then
  echo "[DEBUG] Enabling kiosk-autologin service for user"
  su - $KIOSK_USERNAME -c "XDG_RUNTIME_DIR=/run/user/$(id -u $KIOSK_USERNAME) systemctl --user enable kiosk-autologin.service" || echo "[WARNING] Failed to enable kiosk-autologin service"
fi

echo "[DEBUG] AccountsService configuration completed"

# Create a script to verify and fix auto-login on each boot
echo "[DEBUG] Creating auto-login verification script"
cat > /usr/local/sbin/verify-autologin.sh << 'EOF'
#!/bin/bash

# Script to verify and fix auto-login settings on boot
KIOSK_USER="$1"
if [ -z "$KIOSK_USER" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

# Check LightDM configuration
if [ -d "/etc/lightdm" ]; then
  # Ensure auto-login is configured in lightdm.conf
  if [ -f "/etc/lightdm/lightdm.conf" ]; then
    if ! grep -q "autologin-user=$KIOSK_USER" /etc/lightdm/lightdm.conf; then
      echo "Fixing LightDM auto-login configuration..."
      if grep -q "\[Seat:\*\]" /etc/lightdm/lightdm.conf; then
        sed -i '/^\[Seat:\*\]/a autologin-user='$KIOSK_USER'\nautologin-user-timeout=0' /etc/lightdm/lightdm.conf
      else
        echo -e "[Seat:*]\nautologin-user=$KIOSK_USER\nautologin-user-timeout=0" >> /etc/lightdm/lightdm.conf
      fi
    fi
  fi
  
  # Ensure auto-login is configured in lightdm.conf.d
  mkdir -p /etc/lightdm/lightdm.conf.d
  if [ ! -f "/etc/lightdm/lightdm.conf.d/12-autologin.conf" ]; then
    echo "Creating LightDM auto-login configuration file..."
    echo -e "[Seat:*]\nautologin-user=$KIOSK_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/12-autologin.conf
  fi
fi

# Check GDM configuration
if [ -d "/etc/gdm3" ]; then
  if [ -f "/etc/gdm3/custom.conf" ]; then
    if ! grep -q "AutomaticLoginEnable=true" /etc/gdm3/custom.conf; then
      echo "Fixing GDM auto-login configuration..."
      if grep -q "^\[daemon\]" /etc/gdm3/custom.conf; then
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin='$KIOSK_USER'' /etc/gdm3/custom.conf
      else
        echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$KIOSK_USER" >> /etc/gdm3/custom.conf
      fi
    fi
  else
    echo "Creating GDM auto-login configuration file..."
    echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$KIOSK_USER" > /etc/gdm3/custom.conf
  fi
fi

# Check AccountsService configuration
mkdir -p /var/lib/AccountsService/users
if [ ! -f "/var/lib/AccountsService/users/$KIOSK_USER" ] || ! grep -q "AutomaticLogin=true" "/var/lib/AccountsService/users/$KIOSK_USER"; then
  echo "Fixing AccountsService auto-login configuration..."
  echo -e "[User]\nLanguage=\nXSession=zorin\nSystemAccount=false\nIcon=/usr/share/pixmaps/faces/user-generic.png\nAutomaticLogin=true" > "/var/lib/AccountsService/users/$KIOSK_USER"
fi

echo "Auto-login verification completed."
EOF

chmod +x /usr/local/sbin/verify-autologin.sh

# Create a systemd service to run the verification script on boot
echo "[DEBUG] Creating systemd service for auto-login verification"
cat > /etc/systemd/system/verify-autologin.service << EOF
[Unit]
Description=Verify and fix auto-login settings
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/verify-autologin.sh $KIOSK_USERNAME
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable verify-autologin.service

echo "[DEBUG] User setup script completed successfully"