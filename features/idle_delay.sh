#!/bin/bash

# ZorinOS Kiosk Idle Delay Setup Script
# Features: Disable screen blanking by setting idle-delay to zero

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

# Create a system-wide override for the idle-delay setting
echo "Creating system-wide dconf override for idle-delay..."

# Create dconf profile directory
mkdir -p /etc/dconf/profile

# Create a system profile
cat > /etc/dconf/profile/user << EOF
user-db:user
system-db:local
EOF

# Create the local database directory
mkdir -p /etc/dconf/db/local.d

# Create the settings file
cat > /etc/dconf/db/local.d/00-idle-delay << EOF
# Kiosk mode idle-delay settings

[org/gnome/desktop/session]
idle-delay=uint32 0

[com/zorin/desktop/session]
idle-delay=uint32 0
EOF

# Create locks directory
mkdir -p /etc/dconf/db/local.d/locks

# Create locks file to prevent user from changing these settings
cat > /etc/dconf/db/local.d/locks/idle-delay << EOF
/org/gnome/desktop/session/idle-delay
EOF

# Update the dconf database
dconf update
echo "Updated dconf database with idle-delay settings"

# Create a direct override in the dconf database for site-wide settings
mkdir -p /etc/dconf/db/site.d
cat > /etc/dconf/db/site.d/00-no-idle << EOF
[org/gnome/desktop/session]
idle-delay=uint32 0
EOF

# Update dconf database again
dconf update

# Create a user-level systemd service to apply settings after login
mkdir -p "$TEMPLATE_DIR/.config/systemd/user"
cat > "$TEMPLATE_DIR/.config/systemd/user/kiosk-idle-delay.service" << EOF
[Unit]
Description=Apply Kiosk Idle Delay Settings
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'gsettings set org.gnome.desktop.session idle-delay 0; dconf write /org/gnome/desktop/session/idle-delay "uint32 0"'
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF

# Create a login script to apply idle-delay settings
mkdir -p /etc/profile.d
cat > /etc/profile.d/apply-idle-delay.sh << 'EOF'
#!/bin/bash
# Apply idle-delay settings at login

# Only run for graphical sessions
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # Set idle-delay to 0 (never)
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0" 2>/dev/null || true
    
    # Zorin OS specific settings (if they exist)
    gsettings set com.zorin.desktop.session idle-delay 0 2>/dev/null || true
    dconf write /com/zorin/desktop/session/idle-delay "uint32 0" 2>/dev/null || true
fi
EOF
chmod +x /etc/profile.d/apply-idle-delay.sh

# Create a systemd service to apply idle-delay settings on boot
IDLE_DELAY_SERVICE="/etc/systemd/system/idle-delay-settings.service"

cat > "$IDLE_DELAY_SERVICE" << EOF
[Unit]
Description=Apply Idle Delay Settings for All Users
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "for user in \$(ls /home); do if id \$user &>/dev/null; then su - \$user -c 'gsettings set org.gnome.desktop.session idle-delay 0; dconf write /org/gnome/desktop/session/idle-delay \"uint32 0\"' || true; fi; done"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable idle-delay-settings.service

echo "Idle delay settings have been configured successfully."