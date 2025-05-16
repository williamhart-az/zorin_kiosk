#!/bin/bash

# ZorinOS Kiosk Firefox Ownership Fix Script

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

# Define kiosk user's home directory
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"

echo "[INFO] Fixing Firefox directory ownership..."

# Create and fix ownership of .var directory and subdirectories
if [ ! -d "$KIOSK_USER_HOME/.var" ]; then
  echo "[DEBUG] Creating $KIOSK_USER_HOME/.var"
  mkdir -p "$KIOSK_USER_HOME/.var"
fi
echo "[DEBUG] Fixing ownership of $KIOSK_USER_HOME/.var"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var"
chmod 755 "$KIOSK_USER_HOME/.var"  # Use 755 to allow access but prevent modification

# Create and fix ownership of .var/app directory
if [ ! -d "$KIOSK_USER_HOME/.var/app" ]; then
  echo "[DEBUG] Creating $KIOSK_USER_HOME/.var/app"
  mkdir -p "$KIOSK_USER_HOME/.var/app"
fi
echo "[DEBUG] Fixing ownership of $KIOSK_USER_HOME/.var/app"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var/app"
chmod 755 "$KIOSK_USER_HOME/.var/app"

# Create and fix ownership of Firefox Flatpak directory
if [ ! -d "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox" ]; then
  echo "[DEBUG] Creating $KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
  mkdir -p "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
fi
echo "[DEBUG] Fixing ownership of $KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
chmod -R 700 "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"  # Use 700 for Firefox directory for privacy

# Fix ownership of .mozilla directory
if [ -d "$KIOSK_USER_HOME/.mozilla" ]; then
  echo "[DEBUG] Fixing ownership of $KIOSK_USER_HOME/.mozilla"
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.mozilla"
  chmod -R 700 "$KIOSK_USER_HOME/.mozilla"
fi

# Fix ownership of snap Firefox directory if it exists
if [ -d "$KIOSK_USER_HOME/snap/firefox" ]; then
  echo "[DEBUG] Fixing ownership of $KIOSK_USER_HOME/snap/firefox"
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/snap/firefox"
  chmod -R 700 "$KIOSK_USER_HOME/snap/firefox"
fi

echo "[INFO] Firefox directory ownership fix complete."

# Create a systemd service to fix ownership at boot
SYSTEMD_SERVICE="/etc/systemd/system/firefox-ownership-fix.service"

cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Fix Firefox Directory Ownership
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "mkdir -p /home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/.var && chmod 755 /home/$KIOSK_USERNAME/.var && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/.var/app && chmod 755 /home/$KIOSK_USERNAME/.var/app && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox && chmod -R 700 /home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/.mozilla 2>/dev/null || true && chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/snap/firefox 2>/dev/null || true"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SYSTEMD_SERVICE"
systemctl enable firefox-ownership-fix.service

echo "[INFO] Firefox ownership fix service created and enabled."