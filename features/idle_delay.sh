#!/bin/bash

# ZorinOS Kiosk Idle Delay Setup Script
# Features: Disable screen blanking by setting idle-delay to zero

# Exit on any error
set -e

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/idle_delay.sh.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting idle_delay.sh script."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  log_message "Error: This script must be run as root. Please use sudo."
  echo "This script must be run as root. Please use sudo." # Keep for direct user feedback
  exit 1
fi
log_message "Running as root."

# Source the environment file
log_message "Checking for environment file..."
if [ -z "$ENV_FILE" ]; then
  # Look for the environment file next to kiosk_setup.sh
  ENV_FILE="$(dirname "$0")/../.env"
  log_message "ENV_FILE not defined, using default: $ENV_FILE"
  
  # If not found, try looking in the same directory as kiosk_setup.sh
  if [ ! -f "$ENV_FILE" ]; then
    PARENT_DIR="$(dirname "$(dirname "$0")")"
    for file in "$PARENT_DIR"/*.sh; do
      if [ -f "$file" ] && grep -q "kiosk_setup" "$file"; then
        ENV_FILE="$(dirname "$file")/.env"
        log_message "Looking for .env next to kiosk_setup.sh: $ENV_FILE"
        break
      fi
    done
  fi
fi

log_message "Checking if environment file exists at: $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  log_message "Error: Environment file not found at $ENV_FILE. Please specify the correct path using the ENV_FILE variable."
  echo "[ERROR] Environment file not found at $ENV_FILE" # Keep for direct user feedback
  echo "[ERROR] Please specify the correct path using the ENV_FILE variable." # Keep for direct user feedback
  exit 1
fi

log_message "Sourcing environment file: $ENV_FILE"
source "$ENV_FILE"
log_message "Environment file sourced successfully. TEMPLATE_DIR=${TEMPLATE_DIR}"

# Create a system-wide override for the idle-delay setting
log_message "Creating system-wide dconf override for idle-delay..."

# Create dconf profile directory
log_message "Creating dconf profile directory /etc/dconf/profile..."
mkdir -p /etc/dconf/profile

# Create a system profile
log_message "Creating system profile at /etc/dconf/profile/user..."
cat > /etc/dconf/profile/user << EOF
user-db:user
system-db:local
EOF

# Create the local database directory
log_message "Creating local database directory /etc/dconf/db/local.d..."
mkdir -p /etc/dconf/db/local.d

# Create the settings file
log_message "Creating settings file /etc/dconf/db/local.d/00-idle-delay..."
cat > /etc/dconf/db/local.d/00-idle-delay << EOF
# Kiosk mode idle-delay settings

[org/gnome/desktop/session]
idle-delay=uint32 0

[com/zorin/desktop/session]
idle-delay=uint32 0
EOF

# Create locks directory
log_message "Creating locks directory /etc/dconf/db/local.d/locks..."
mkdir -p /etc/dconf/db/local.d/locks

# Create locks file to prevent user from changing these settings
log_message "Creating locks file /etc/dconf/db/local.d/locks/idle-delay..."
cat > /etc/dconf/db/local.d/locks/idle-delay << EOF
/org/gnome/desktop/session/idle-delay
EOF

# Update the dconf database
log_message "Updating dconf database..."
dconf update
log_message "Updated dconf database with idle-delay settings."

# Create a direct override in the dconf database for site-wide settings
log_message "Creating site-wide dconf override directory /etc/dconf/db/site.d..."
mkdir -p /etc/dconf/db/site.d
log_message "Creating site-wide settings file /etc/dconf/db/site.d/00-no-idle..."
cat > /etc/dconf/db/site.d/00-no-idle << EOF
[org/gnome/desktop/session]
idle-delay=uint32 0
EOF

# Update dconf database again
log_message "Updating dconf database again for site settings..."
dconf update
log_message "Dconf database updated for site settings."

# Create a user-level systemd service to apply settings after login
# Ensure TEMPLATE_DIR is available from sourced .env
if [ -z "$TEMPLATE_DIR" ]; then
    log_message "Error: TEMPLATE_DIR is not set. Cannot create user-level systemd service for idle delay."
else
    USER_SYSTEMD_DIR="$TEMPLATE_DIR/.config/systemd/user"
    log_message "Creating user-level systemd service directory: $USER_SYSTEMD_DIR..."
    mkdir -p "$USER_SYSTEMD_DIR"
    USER_IDLE_SERVICE_FILE="$USER_SYSTEMD_DIR/kiosk-idle-delay.service"
    log_message "Creating user-level systemd service file: $USER_IDLE_SERVICE_FILE..."
    # Define the log file path for the generated service's ExecStart commands
    GENERATED_USER_IDLE_SERVICE_LOG_FILE="$LOG_DIR/kiosk-idle-delay.user.service.log"
    cat > "$USER_IDLE_SERVICE_FILE" << EOF
[Unit]
Description=Apply Kiosk Idle Delay Settings
After=graphical-session.target network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "\$(date) - kiosk-idle-delay.user.service: Applying gsettings..." >> $GENERATED_USER_IDLE_SERVICE_LOG_FILE 2>&1; gsettings set org.gnome.desktop.session idle-delay 0 >> $GENERATED_USER_IDLE_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed gsettings set" >> $GENERATED_USER_IDLE_SERVICE_LOG_FILE 2>&1; dconf write /org/gnome/desktop/session/idle-delay "uint32 0" >> $GENERATED_USER_IDLE_SERVICE_LOG_FILE 2>&1 || echo "\$(date) - Failed dconf write" >> $GENERATED_USER_IDLE_SERVICE_LOG_FILE 2>&1'
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF
    log_message "User-level systemd service for idle delay created."
fi

# Create a login script to apply idle-delay settings
log_message "Creating login script /etc/profile.d/apply-idle-delay.sh..."
mkdir -p /etc/profile.d
# Define the log file path for the generated apply-idle-delay.sh script
GENERATED_APPLY_IDLE_LOG_FILE="$LOG_DIR/apply-idle-delay.sh.log"
cat > /etc/profile.d/apply-idle-delay.sh << EOF
#!/bin/bash
# Apply idle-delay settings at login
LOGFILE="$GENERATED_APPLY_IDLE_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")"

log_apply_idle_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_apply_idle_message "apply-idle-delay.sh: Script started for user \$(whoami)."

# Only run for graphical sessions
if [ -n "\$DISPLAY" ] || [ -n "\$WAYLAND_DISPLAY" ]; then
    log_apply_idle_message "Graphical session detected. Applying idle-delay settings."
    # Set idle-delay to 0 (never)
    gsettings set org.gnome.desktop.session idle-delay 0 >> "\$LOGFILE" 2>&1 || log_apply_idle_message "Failed: gsettings set org.gnome.desktop.session idle-delay 0"
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0" >> "\$LOGFILE" 2>&1 || log_apply_idle_message "Failed: dconf write /org/gnome/desktop/session/idle-delay"
    
    # Zorin OS specific settings (if they exist)
    log_apply_idle_message "Applying Zorin OS specific idle-delay settings."
    gsettings set com.zorin.desktop.session idle-delay 0 >> "\$LOGFILE" 2>&1 || log_apply_idle_message "Note: Failed/Skipped gsettings set com.zorin.desktop.session idle-delay 0 (may not exist)"
    dconf write /com/zorin/desktop/session/idle-delay "uint32 0" >> "\$LOGFILE" 2>&1 || log_apply_idle_message "Note: Failed/Skipped dconf write /com/zorin/desktop/session (may not exist)"
    log_apply_idle_message "Idle-delay settings applied via login script."
else
    log_apply_idle_message "Not a graphical session. Skipping idle-delay settings."
fi
EOF
chmod +x /etc/profile.d/apply-idle-delay.sh
log_message "Login script /etc/profile.d/apply-idle-delay.sh created and made executable."

# Create a systemd service to apply idle-delay settings on boot
IDLE_DELAY_SERVICE_SYSTEM="/etc/systemd/system/idle-delay-settings.service" # Renamed for clarity
log_message "Creating system-level systemd service $IDLE_DELAY_SERVICE_SYSTEM..."
# Define the log file path for the generated system service's ExecStart commands
GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE="$LOG_DIR/idle-delay-settings.system.service.log"
cat > "$IDLE_DELAY_SERVICE_SYSTEM" << EOF
[Unit]
Description=Apply Idle Delay Settings for All Users at Boot
After=local-fs.target user-runtime-dir@.service # Ensure user runtime dirs are up
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo \\"\$(date) - idle-delay-settings.system.service: Starting...\\" >> $GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE 2>&1; for userhome in /home/*; do if [ -d \\"\$userhome\\" ]; then username=\$(basename \\"\$userhome\\"); if id \$username &>/dev/null; then KioskUID=\$(id -u \$username); loginctl enable-linger \$username || true; echo \\"\$(date) - Applying for user \$username (UID \$KioskUID)...\\" >> $GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE 2>&1; su - \$username -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/'\$KioskUID'/bus; gsettings set org.gnome.desktop.session idle-delay 0; dconf write /org/gnome/desktop/session/idle-delay \\"uint32 0\\"; gsettings set com.zorin.desktop.session idle-delay 0 || true; dconf write /com/zorin/desktop/session/idle-delay \\"uint32 0\\" || true' >> $GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE 2>&1 || echo \\"\$(date) - Failed for user \$username\\" >> $GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE 2>&1; fi; fi; done; echo \\"\$(date) - idle-delay-settings.system.service: Finished.\\" >> $GENERATED_SYSTEM_IDLE_SERVICE_LOG_FILE 2>&1"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
log_message "System-level systemd service definition created."

# Enable the service
log_message "Enabling system-level idle-delay-settings.service..."
systemctl enable idle-delay-settings.service
log_message "System-level idle-delay-settings.service enabled."

log_message "Idle delay settings have been configured successfully."
