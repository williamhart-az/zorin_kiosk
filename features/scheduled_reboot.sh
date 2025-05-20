#!/bin/bash

# ZorinOS Kiosk Scheduled Reboot Setup Script
# Feature: Configure scheduled system reboots

# Exit on any error
set -e

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/scheduled_reboot_setup.sh.log" # Specific log for this setup script

# Ensure log directory exists
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting scheduled_reboot.sh script."

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
log_message "Environment file sourced successfully. REBOOT_TIME=${REBOOT_TIME}, REBOOT_DAYS=${REBOOT_DAYS}, OPT_KIOSK_DIR=${OPT_KIOSK_DIR}"

# Setup scheduled reboot
log_message "Setting up scheduled system reboot..."

# Check if reboot is disabled
if [ "$REBOOT_TIME" = "-1" ]; then
  log_message "Scheduled reboots are disabled (REBOOT_TIME is -1). Skipping setup."
  echo "Scheduled reboots are disabled. Skipping setup." # Keep for direct user feedback
  exit 0
fi

# Validate reboot time format
if ! [[ $REBOOT_TIME =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  log_message "Error: Invalid REBOOT_TIME format ('$REBOOT_TIME'). Must be HH:MM in 24-hour format or -1 to disable. Using default 03:00."
  echo "Error: Invalid REBOOT_TIME format. Must be HH:MM in 24-hour format or -1 to disable." # Keep for direct user feedback
  echo "Using default value of 03:00 (3:00 AM)." # Keep for direct user feedback
  REBOOT_TIME="03:00"
fi

# Extract hour and minute from REBOOT_TIME
HOUR=$(echo "$REBOOT_TIME" | cut -d: -f1)
MINUTE=$(echo "$REBOOT_TIME" | cut -d: -f2)
log_message "Scheduled reboot time: Hour=$HOUR, Minute=$MINUTE"

# Create the reboot script
# Ensure OPT_KIOSK_DIR is set
if [ -z "$OPT_KIOSK_DIR" ]; then
    log_message "Error: OPT_KIOSK_DIR is not set. Cannot create reboot script."
    exit 1
fi
mkdir -p "$OPT_KIOSK_DIR" # Ensure directory exists
REBOOT_SCRIPT_PATH="$OPT_KIOSK_DIR/scheduled_reboot_action.sh" # Renamed for clarity
log_message "Creating reboot action script at: $REBOOT_SCRIPT_PATH"

# Define the log file path for the generated reboot action script
GENERATED_REBOOT_ACTION_LOG_FILE="$LOG_DIR/scheduled_reboot_action.log"

cat > "$REBOOT_SCRIPT_PATH" << EOF
#!/bin/bash

# Script to perform a scheduled reboot
# This script checks the current day of week against the configured reboot days

# Log file for this action script
ACTION_LOGFILE="$GENERATED_REBOOT_ACTION_LOG_FILE"
mkdir -p "$(dirname "\$ACTION_LOGFILE")" # Ensure directory exists when script runs

log_reboot_action_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$ACTION_LOGFILE"
}

log_reboot_action_message "scheduled_reboot_action.sh: Script started."

# REBOOT_DAYS is expanded by the parent script (scheduled_reboot.sh)
# So its value will be hardcoded into this generated script.
CONFIGURED_REBOOT_DAYS="$REBOOT_DAYS"
log_reboot_action_message "Configured reboot days: \$CONFIGURED_REBOOT_DAYS"

# Get current day of week (0-6, where 0 is Sunday)
CURRENT_DAY=\$(date +%w)
log_reboot_action_message "Current day of week: \$CURRENT_DAY (0=Sun, 6=Sat)"

# Check if today is a reboot day
if [ "\$CONFIGURED_REBOOT_DAYS" = "all" ]; then
  log_reboot_action_message "Scheduled reboot triggered (daily schedule). Initiating reboot."
  /sbin/shutdown -r now "Scheduled system reboot (daily)"
else
  # Check if current day is in the list of reboot days
  if [[ ",\$CONFIGURED_REBOOT_DAYS," == *",\$CURRENT_DAY,"* ]]; then
    log_reboot_action_message "Scheduled reboot triggered (day \$CURRENT_DAY matches configured days). Initiating reboot."
    /sbin/shutdown -r now "Scheduled system reboot (specific day)"
  else
    log_reboot_action_message "Today (day \$CURRENT_DAY) is not a scheduled reboot day. No action taken."
  fi
fi
EOF

chmod +x "$REBOOT_SCRIPT_PATH"
log_message "Reboot action script $REBOOT_SCRIPT_PATH created and made executable."

# Create a systemd timer for the reboot
TIMER_SERVICE_FILE="/etc/systemd/system/kiosk-reboot.service"
TIMER_FILE="/etc/systemd/system/kiosk-reboot.timer"
log_message "Creating systemd service file: $TIMER_SERVICE_FILE"
log_message "Creating systemd timer file: $TIMER_FILE"

# Create the service file
cat > "$TIMER_SERVICE_FILE" << EOF
[Unit]
Description=Kiosk Scheduled Reboot Service
Documentation=https://github.com/yourusername/zorin_kiosk # TODO: Update this URL if needed

[Service]
Type=oneshot
ExecStart=$REBOOT_SCRIPT_PATH
User=root
StandardOutput=append:$LOG_DIR/kiosk-reboot.service.log
StandardError=append:$LOG_DIR/kiosk-reboot.service.err

[Install]
WantedBy=multi-user.target
EOF
log_message "Systemd service file $TIMER_SERVICE_FILE created."

# Create the timer file
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run Kiosk Reboot Service at specified time
Documentation=https://github.com/yourusername/zorin_kiosk # TODO: Update this URL if needed

[Timer]
OnCalendar=*-*-* $HOUR:$MINUTE:00
Persistent=true
Unit=kiosk-reboot.service # Ensure this matches the service file name

[Install]
WantedBy=timers.target
EOF
log_message "Systemd timer file $TIMER_FILE created."

# Enable and start the timer
log_message "Reloading systemd daemon..."
systemctl daemon-reload
log_message "Enabling kiosk-reboot.timer..."
systemctl enable kiosk-reboot.timer
log_message "Starting kiosk-reboot.timer..."
systemctl start kiosk-reboot.timer

log_message "Scheduled reboot configured for $REBOOT_TIME."
echo "Scheduled reboot configured for $REBOOT_TIME" # Keep for direct user feedback
if [ "$REBOOT_DAYS" = "all" ]; then
  log_message "System will reboot daily at $REBOOT_TIME."
  echo "System will reboot daily at $REBOOT_TIME" # Keep for direct user feedback
else
  log_message "System will reboot at $REBOOT_TIME on days: $REBOOT_DAYS (0=Sun, 1=Mon,...)"
  echo "System will reboot at $REBOOT_TIME on days: $REBOOT_DAYS" # Keep for direct user feedback
  echo "(0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday)" # Keep for direct user feedback
fi
log_message "Scheduled reboot setup script finished."
