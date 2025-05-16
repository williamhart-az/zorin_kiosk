#!/bin/bash

# ZorinOS Kiosk Firefox Periodic Ownership Fix Script

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

echo "[INFO] Setting up periodic Firefox directory ownership fix..."

# Create the periodic fix script
PERIODIC_FIX_SCRIPT="/opt/kiosk/periodic_firefox_fix.sh"

cat > "$PERIODIC_FIX_SCRIPT" << EOF
#!/bin/bash

# Periodic script to fix Firefox directory ownership
KIOSK_USERNAME="$KIOSK_USERNAME"
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"
LOG_FILE="/var/log/kiosk_firefox_fix.log"

echo "$(date): Running periodic Firefox ownership fix" >> "$LOG_FILE"

# Fix ownership of Firefox directories
mkdir -p "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var/app"
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"
chmod -R 700 "$KIOSK_USER_HOME/.var/app/org.mozilla.firefox"

# Also fix .mozilla directory if it exists
if [ -d "$KIOSK_USER_HOME/.mozilla" ]; then
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.mozilla"
  chmod -R 700 "$KIOSK_USER_HOME/.mozilla"
fi

# Fix snap Firefox directory if it exists
if [ -d "$KIOSK_USER_HOME/snap/firefox" ]; then
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/snap/firefox"
  chmod -R 700 "$KIOSK_USER_HOME/snap/firefox"
fi

echo "$(date): Periodic Firefox ownership fix completed" >> "$LOG_FILE"
EOF

chmod 755 "$PERIODIC_FIX_SCRIPT"

# Create a systemd timer to run the script periodically
SYSTEMD_SERVICE="/etc/systemd/system/firefox-periodic-fix.service"
SYSTEMD_TIMER="/etc/systemd/system/firefox-periodic-fix.timer"

cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Periodic Firefox Directory Ownership Fix

[Service]
Type=oneshot
ExecStart=$PERIODIC_FIX_SCRIPT
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > "$SYSTEMD_TIMER" << EOF
[Unit]
Description=Run Firefox Directory Ownership Fix Periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

chmod 644 "$SYSTEMD_SERVICE"
chmod 644 "$SYSTEMD_TIMER"

# Enable and start the timer
systemctl enable firefox-periodic-fix.timer
systemctl start firefox-periodic-fix.timer

echo "[INFO] Periodic Firefox ownership fix has been set up to run every 10 minutes."