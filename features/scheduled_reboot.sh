#!/bin/bash

# ZorinOS Kiosk Scheduled Reboot Setup Script
# Feature: Configure scheduled system reboots

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Setup scheduled reboot
echo "Setting up scheduled system reboot..."

# Check if reboot is disabled
if [ "$REBOOT_TIME" = "-1" ]; then
  echo "Scheduled reboots are disabled. Skipping setup."
  exit 0
fi

# Validate reboot time format
if ! [[ $REBOOT_TIME =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "Error: Invalid REBOOT_TIME format. Must be HH:MM in 24-hour format or -1 to disable."
  echo "Using default value of 03:00 (3:00 AM)."
  REBOOT_TIME="03:00"
fi

# Extract hour and minute from REBOOT_TIME
HOUR=$(echo $REBOOT_TIME | cut -d: -f1)
MINUTE=$(echo $REBOOT_TIME | cut -d: -f2)

# Create the reboot script
REBOOT_SCRIPT="$OPT_KIOSK_DIR/scheduled_reboot.sh"

cat > "$REBOOT_SCRIPT" << EOF
#!/bin/bash

# Script to perform a scheduled reboot
# This script checks the current day of week against the configured reboot days

# Log file
LOGFILE="/var/log/kiosk_reboot.log"

# Get current day of week (0-6, where 0 is Sunday)
CURRENT_DAY=\$(date +%w)

# Check if today is a reboot day
if [ "$REBOOT_DAYS" = "all" ]; then
  echo "\$(date): Scheduled reboot triggered (daily schedule)." >> \$LOGFILE
  /sbin/shutdown -r now "Scheduled system reboot"
else
  # Check if current day is in the list of reboot days
  if [[ ",$REBOOT_DAYS," == *",\$CURRENT_DAY,"* ]]; then
    echo "\$(date): Scheduled reboot triggered (day \$CURRENT_DAY)." >> \$LOGFILE
    /sbin/shutdown -r now "Scheduled system reboot"
  else
    echo "\$(date): Today (day \$CURRENT_DAY) is not a scheduled reboot day." >> \$LOGFILE
  fi
fi
EOF

chmod +x "$REBOOT_SCRIPT"

# Create a systemd timer for the reboot
TIMER_SERVICE="/etc/systemd/system/kiosk-reboot.service"
TIMER_TIMER="/etc/systemd/system/kiosk-reboot.timer"

# Create the service file
cat > "$TIMER_SERVICE" << EOF
[Unit]
Description=Kiosk Scheduled Reboot Service
Documentation=https://github.com/yourusername/zorin_kiosk

[Service]
Type=oneshot
ExecStart=$REBOOT_SCRIPT
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create the timer file
cat > "$TIMER_TIMER" << EOF
[Unit]
Description=Run Kiosk Reboot Service at specified time
Documentation=https://github.com/yourusername/zorin_kiosk

[Timer]
OnCalendar=*-*-* $HOUR:$MINUTE:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable kiosk-reboot.timer
systemctl start kiosk-reboot.timer

echo "Scheduled reboot configured for $REBOOT_TIME"
if [ "$REBOOT_DAYS" = "all" ]; then
  echo "System will reboot daily at $REBOOT_TIME"
else
  echo "System will reboot at $REBOOT_TIME on days: $REBOOT_DAYS"
  echo "(0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday)"
fi