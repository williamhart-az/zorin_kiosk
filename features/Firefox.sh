#!/bin/bash

# ZorinOS Kiosk Firefox Setup Script
# Features: #7, 19

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
# Ensure PROFILE_BASE_DIR itself is owned by the kiosk user
if [ -d "\$PROFILE_BASE_DIR" ]; then
    chown \$KIOSK_USERNAME:\$KIOSK_USERNAME "\$PROFILE_BASE_DIR"
    chmod 700 "\$PROFILE_BASE_DIR"
    echo "\$(date): Ensured ownership and permissions (700) for \$PROFILE_BASE_DIR" >> "\$LOGFILE"
fi

chown -R $KIOSK_USERNAME:$KIOSK_USERNAME "\$PROFILE_BASE_DIR/.mozilla"
chmod -R 700 "\$PROFILE_BASE_DIR/.mozilla"

echo "\$(date): Firefox profile setup complete" >> "\$LOGFILE"
EOF

chmod +x "$FIREFOX_PROFILE_SCRIPT"

# 19. Create a sudoers entry for the kiosk user to run the Firefox profile setup script
echo "Creating sudoers entry for Firefox profile setup..."
SUDOERS_FILE="/etc/sudoers.d/kiosk-firefox"
cat > "$SUDOERS_FILE" << EOF
# Allow kiosk user to run Firefox profile setup script without password
$KIOSK_USERNAME ALL=(ALL) NOPASSWD: $OPT_KIOSK_DIR/setup_firefox_profile.sh
EOF
chmod 440 "$SUDOERS_FILE"