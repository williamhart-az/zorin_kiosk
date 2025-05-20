#!/bin/bash

# ZorinOS Kiosk Firefox Setup Script
# Features: #7, 19

# Exit on any error
set -e

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/firefox.sh.log"

# Ensure log directory exists (as root, this script should have permissions)
mkdir -p "$LOG_DIR"
# Ownership of LOG_DIR itself should be root or a dedicated logging group if desired.
# Individual log files can be owned by the kiosk user if scripts run as kiosk.
# For this script (firefox.sh), it runs as root, so root will own its log file.

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Script started: firefox.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  log_message "Error: This script must be run as root. Please use sudo."
  echo "This script must be run as root. Please use sudo." # Keep echo for direct user feedback
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
  echo "[ERROR] Environment file not found at $ENV_FILE" # Keep echo for direct user feedback
  echo "[ERROR] Please specify the correct path using the ENV_FILE variable." # Keep echo
  exit 1
fi

log_message "Sourcing environment file: $ENV_FILE"
source "$ENV_FILE"
log_message "Environment file sourced successfully. KIOSK_USERNAME=${KIOSK_USERNAME}, OPT_KIOSK_DIR=${OPT_KIOSK_DIR}, HOMEPAGE=${HOMEPAGE}"

# Define kiosk user's home directory
KIOSK_USER_HOME="/home/$KIOSK_USERNAME"
log_message "Kiosk user home directory set to: $KIOSK_USER_HOME"

# Define potential base directories for Firefox profiles
FLATPAK_APP_BASE_DIR="$KIOSK_USER_HOME/.var/app"
FLATPAK_FIREFOX_PROFILE_DIR="$FLATPAK_APP_BASE_DIR/org.mozilla.firefox"
STANDARD_FIREFOX_PROFILE_PARENT_DIR="$KIOSK_USER_HOME/.mozilla"
SNAP_FIREFOX_PROFILE_PARENT_DIR="$KIOSK_USER_HOME/snap/firefox/common/.mozilla" # This path is relative to KIOSK_USER_HOME

log_message "Ensuring Firefox base directories are correctly permissioned for user $KIOSK_USERNAME..."

# Create and permission .var and .var/app for Flatpak
if [ ! -d "$KIOSK_USER_HOME/.var" ]; then
    mkdir -p "$KIOSK_USER_HOME/.var"
    log_message "Created $KIOSK_USER_HOME/.var"
fi
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/.var"
chmod 700 "$KIOSK_USER_HOME/.var"
log_message "Set ownership and permissions for $KIOSK_USER_HOME/.var"

if [ ! -d "$FLATPAK_APP_BASE_DIR" ]; then
    mkdir -p "$FLATPAK_APP_BASE_DIR"
    log_message "Created $FLATPAK_APP_BASE_DIR"
fi
chown "$KIOSK_USERNAME:$KIOSK_USERNAME" "$FLATPAK_APP_BASE_DIR"
chmod 700 "$FLATPAK_APP_BASE_DIR"
log_message "Set ownership and permissions for $FLATPAK_APP_BASE_DIR"

# Create and permission the Flatpak Firefox profile directory
if [ ! -d "$FLATPAK_FIREFOX_PROFILE_DIR" ]; then
    mkdir -p "$FLATPAK_FIREFOX_PROFILE_DIR"
    log_message "Created $FLATPAK_FIREFOX_PROFILE_DIR"
fi
chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$FLATPAK_FIREFOX_PROFILE_DIR"
chmod -R 700 "$FLATPAK_FIREFOX_PROFILE_DIR"
log_message "Set ownership and permissions for $FLATPAK_FIREFOX_PROFILE_DIR"

# Create and permission the standard Firefox profile parent directory
if [ ! -d "$STANDARD_FIREFOX_PROFILE_PARENT_DIR" ]; then
    mkdir -p "$STANDARD_FIREFOX_PROFILE_PARENT_DIR"
    log_message "Created $STANDARD_FIREFOX_PROFILE_PARENT_DIR"
fi
chown "$KIOSK_USERNAME:$KIOSK_USERNAME" "$STANDARD_FIREFOX_PROFILE_PARENT_DIR"
chmod 700 "$STANDARD_FIREFOX_PROFILE_PARENT_DIR"
log_message "Set ownership and permissions for $STANDARD_FIREFOX_PROFILE_PARENT_DIR"

# Create and permission the Snap Firefox profile parent directory
# Note: The actual profile is deeper, but the parent 'common' and '.mozilla' inside it need correct perms.
if [ ! -d "$SNAP_FIREFOX_PROFILE_PARENT_DIR" ]; then
    mkdir -p "$SNAP_FIREFOX_PROFILE_PARENT_DIR"
    log_message "Created Snap Firefox profile parent directory: $SNAP_FIREFOX_PROFILE_PARENT_DIR"
fi
# The snap directory itself (/home/kiosk/snap) might be managed by snapd.
# We ensure the .mozilla part is owned by the user.
# It's safer to chown only the parts we are certain about.
if [ -d "$KIOSK_USER_HOME/snap/firefox/common" ]; then
    chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "$KIOSK_USER_HOME/snap/firefox/common"
    chmod -R 700 "$KIOSK_USER_HOME/snap/firefox/common" # Restrictive permissions
    log_message "Set ownership and permissions for Snap's common directory part: $KIOSK_USER_HOME/snap/firefox/common"
fi


log_message "Base directory setup for Firefox complete."

# 7. Create Firefox profile setup script
log_message "Creating Firefox profile setup script at $OPT_KIOSK_DIR/setup_firefox_profile.sh..."
FIREFOX_PROFILE_SCRIPT="$OPT_KIOSK_DIR/setup_firefox_profile.sh"

# Define the log file path for the generated script, using the global LOG_DIR
GENERATED_SCRIPT_LOG_FILE_SETUP_PROFILE="$LOG_DIR/firefox_profile_setup.log"

cat > "$FIREFOX_PROFILE_SCRIPT" << EOF
#!/bin/bash

# Script to set up Firefox profile for kiosk user
set -e # Ensures the script will exit immediately if any command fails

# KIOSK_USERNAME is expanded by the parent firefox.sh script from the .env file
# This ensures the correct kiosk user is targeted, not 'root' if script is run via sudo.
KIOSK_USERNAME_EFFECTIVE="$KIOSK_USERNAME"

# Use the log directory defined by the parent script (firefox.sh)
# This value will be hardcoded into this generated script.
LOGFILE="$GENERATED_SCRIPT_LOG_FILE_SETUP_PROFILE"

# Ensure the directory for the log file exists
mkdir -p "$(dirname "\$LOGFILE")"
# The generated script will run as kiosk user (via sudo), so kiosk user should own its log file.
# The firefox.sh (parent) creates /var/log/kiosk, this script just writes to a file in it.
# Permissions on /var/log/kiosk should allow the kiosk user to create files if it doesn't own the dir.
# A good setup is /var/log/kiosk owned by root:kiosk_log_group with 775, and kiosk user in kiosk_log_group.
# Or, firefox.sh can `touch \$LOGFILE && chown \$KIOSK_USERNAME:\$KIOSK_USERNAME \$LOGFILE` before generating this.
# For simplicity now, assume /var/log/kiosk is writable by kiosk or this script is run as root initially.

log_setup_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_setup_message "Starting setup_firefox_profile.sh for user \$KIOSK_USERNAME_EFFECTIVE..."

KIOSK_USER_HOME_DIR="/home/\$KIOSK_USERNAME_EFFECTIVE"
# SNAP_FIREFOX_PROFILE_PARENT_DIR_GENERATED is expanded by firefox.sh
# It needs to be available inside the generated script.
# We pass the value from the parent script.
SNAP_FIREFOX_PROFILE_PARENT_DIR_IN_GENERATED_SCRIPT="$SNAP_FIREFOX_PROFILE_PARENT_DIR" # This path is already user-specific

FIREFOX_EXECUTABLE=""
FIREFOX_INSTALL_TYPE="unknown" # standard, snap, flatpak

# Check for standard Firefox installation
if command -v firefox &> /dev/null; then
  FIREFOX_EXECUTABLE="firefox"
  FIREFOX_INSTALL_TYPE="standard"
  log_setup_message "Standard Firefox detected via command -v firefox."
# Check for Snap Firefox
elif command -v /snap/bin/firefox &> /dev/null; then
  FIREFOX_EXECUTABLE="/snap/bin/firefox"
  FIREFOX_INSTALL_TYPE="snap"
  log_setup_message "Snap Firefox detected at /snap/bin/firefox."
# Check for Flatpak Firefox
elif flatpak info org.mozilla.firefox &> /dev/null; then
  # Flatpak apps are run via 'flatpak run'. The command itself isn't directly in PATH.
  # We'll note it's Flatpak and handle profile path accordingly.
  # Actual execution of Firefox isn't done by this script.
  FIREFOX_INSTALL_TYPE="flatpak"
  log_setup_message "Flatpak Firefox (org.mozilla.firefox) detected via flatpak info."
else
  log_setup_message "Error: Firefox does not appear to be installed or accessible via standard path, Snap, or Flatpak."
  echo "Error: Firefox does not appear to be installed. Please install Firefox and try again." # User feedback
  exit 1
fi
log_setup_message "Firefox installation type: \$FIREFOX_INSTALL_TYPE"

# Determine PROFILE_BASE_DIR based on installation type
if [ "\$FIREFOX_INSTALL_TYPE" = "flatpak" ]; then
  # For Flatpak, the profile is within .var/app relative to the user's home
  PROFILE_BASE_DIR="\$KIOSK_USER_HOME_DIR/.var/app/org.mozilla.firefox"
  log_setup_message "Using Flatpak profile base: \$PROFILE_BASE_DIR"
elif [ "\$FIREFOX_INSTALL_TYPE" = "snap" ]; then
  # For Snap, the profile is within snap/firefox/common relative to user's home
  # SNAP_FIREFOX_PROFILE_PARENT_DIR_IN_GENERATED_SCRIPT already points to /home/user/snap/firefox/common/.mozilla
  # So PROFILE_BASE_DIR should be its parent: /home/user/snap/firefox/common
  PROFILE_BASE_DIR="\$(dirname "\$SNAP_FIREFOX_PROFILE_PARENT_DIR_IN_GENERATED_SCRIPT")"
  log_setup_message "Using Snap profile base: \$PROFILE_BASE_DIR"
else # Standard
  PROFILE_BASE_DIR="\$KIOSK_USER_HOME_DIR" # .mozilla will be appended later
  log_setup_message "Using Standard profile base (parent of .mozilla): \$PROFILE_BASE_DIR"
fi

# Ensure the actual profile directory structure exists (e.g., $PROFILE_BASE_DIR/.mozilla/firefox)
FIREFOX_PROFILE_ROOT="\$PROFILE_BASE_DIR/.mozilla/firefox"
mkdir -p "\$FIREFOX_PROFILE_ROOT"
log_setup_message "Ensured profile directory structure exists: \$FIREFOX_PROFILE_ROOT"

# Create a default profile directory with a random name to avoid conflicts
PROFILE_NAME="kiosk-\$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
PROFILE_PATH_RELATIVE_TO_INI="\$PROFILE_NAME" # Path used in profiles.ini, relative to FIREFOX_PROFILE_ROOT
PROFILE_DIR_ABSOLUTE="\$FIREFOX_PROFILE_ROOT/\$PROFILE_NAME" # Absolute path to the profile data
mkdir -p "\$PROFILE_DIR_ABSOLUTE"
log_setup_message "Created new profile directory: \$PROFILE_DIR_ABSOLUTE"

# Create profiles.ini file with modern format
# The path to profiles.ini is always $FIREFOX_PROFILE_ROOT/profiles.ini
PROFILES_INI_PATH="\$FIREFOX_PROFILE_ROOT/profiles.ini"
log_setup_message "Creating profiles.ini at: \$PROFILES_INI_PATH"

cat > "\$PROFILES_INI_PATH" << EOL
[Profile0]
Name=default
IsRelative=1
Path=\$PROFILE_PATH_RELATIVE_TO_INI
Default=1

[General]
StartWithLastProfile=1
Version=2

[Install]
DefaultProfile=\$PROFILE_PATH_RELATIVE_TO_INI
EOL
log_setup_message "profiles.ini created with profile: \$PROFILE_NAME"

# The logic for Flatpak/Snap specific profiles.ini locations was complex and potentially redundant.
# Firefox, whether Flatpak or Snap, should look for profiles.ini within its respective
# profile root ($PROFILE_BASE_DIR/.mozilla/firefox/).
# The key is that $PROFILE_BASE_DIR is correctly set.

# HOMEPAGE is expanded by firefox.sh (parent script)
# So its value will be hardcoded into this generated script.
HOMEPAGE_EXPANDED="$HOMEPAGE"

# Create user.js file to suppress first-run wizard and set preferences
USER_JS_FILE="\$PROFILE_DIR_ABSOLUTE/user.js"
log_setup_message "Creating user.js at: \$USER_JS_FILE"
cat > "\$USER_JS_FILE" << EOL
// Set homepage
user_pref("browser.startup.homepage", "\$HOMEPAGE_EXPANDED");
user_pref("browser.startup.page", 1);

// Disable first-run wizard and welcome page
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("datareporting.policy.firstRunURL", ""); // Deprecated but good to have
user_pref("trailhead.firstrun.didSeeAboutWelcome", true); // For newer Firefox versions

// Disable default browser check
user_pref("browser.shell.checkDefaultBrowser", false);

// Disable update checks (important for kiosk stability)
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("app.update.background.enabled", false); // Ensure no background checks
user_pref("app.update.service.enabled", false); // Disable Mozilla Maintenance Service

// Disable telemetry (privacy and performance)
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.server", "data:,"); // Send to nowhere
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false); // Background Hang Reporter
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true); // Suppress notifications about data submission

// Suppress "What's New" page on updates and other popups
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.homepage_override.buildID", "20000101000000"); // Fake build ID
user_pref("browser.startup.homepage_override.mstone", "ignore");

// Privacy settings: Clear data on shutdown
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown.cache", true);        // Clear Cache
user_pref("privacy.clearOnShutdown.cookies", true);      // Clear Cookies
user_pref("privacy.clearOnShutdown.downloads", true);    // Clear Download History (not files)
user_pref("privacy.clearOnShutdown.formdata", true);     // Clear Form & Search History
user_pref("privacy.clearOnShutdown.history", true);      // Clear Browsing & Download History
user_pref("privacy.clearOnShutdown.sessions", true);     // Clear Active Logins
user_pref("privacy.clearOnShutdown.offlineApps", true);  // Clear Offline Website Data
user_pref("privacy.clearOnShutdown.siteSettings", true); // Clear Site Preferences

// Disable Pocket extension
user_pref("extensions.pocket.enabled", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
EOL
log_setup_message "Firefox preferences written to user.js."

# Set correct permissions for the profile directory
# The script setup_firefox_profile.sh is run by the kiosk user (via sudo, but effective user for file ownership should be KIOSK_USERNAME_EFFECTIVE)
# The entire .mozilla directory within $PROFILE_BASE_DIR should be owned by the kiosk user.
log_setup_message "Setting ownership of \$FIREFOX_PROFILE_ROOT and its contents to \$KIOSK_USERNAME_EFFECTIVE:\$KIOSK_USERNAME_EFFECTIVE..."
chown -R \$KIOSK_USERNAME_EFFECTIVE:\$KIOSK_USERNAME_EFFECTIVE "\$FIREFOX_PROFILE_ROOT"
log_setup_message "Setting permissions for \$FIREFOX_PROFILE_ROOT and its contents to 700 (rwx------) recursively..."
chmod -R 700 "\$FIREFOX_PROFILE_ROOT"

# If PROFILE_BASE_DIR is different from KIOSK_USER_HOME_DIR (e.g. for Flatpak/Snap), ensure its parent components are also owned by user.
# Example: /home/kiosk/.var/app/org.mozilla.firefox/.mozilla -> ensure /home/kiosk/.var and /home/kiosk/.var/app are also owned.
# This is generally handled by the parent firefox.sh script when creating these base dirs.
if [ "\$PROFILE_BASE_DIR" != "\$KIOSK_USER_HOME_DIR" ]; then
    # This ensures the containing directory (e.g. .../org.mozilla.firefox/ or .../snap/firefox/common/) is also owned by the user.
    # The .mozilla directory itself is handled by the chown/chmod above.
    # We need to ensure the parent of .mozilla (which is $PROFILE_BASE_DIR) is also correctly permissioned if it's not the home dir.
    if [ -d "\$PROFILE_BASE_DIR" ]; then # Check if PROFILE_BASE_DIR itself exists
      log_setup_message "Setting ownership of profile base \$PROFILE_BASE_DIR to \$KIOSK_USERNAME_EFFECTIVE:\$KIOSK_USERNAME_EFFECTIVE..."
      chown \$KIOSK_USERNAME_EFFECTIVE:\$KIOSK_USERNAME_EFFECTIVE "\$PROFILE_BASE_DIR" # Non-recursive for the base itself
      chmod 700 "\$PROFILE_BASE_DIR" # rwx------ for the base itself
    fi
fi


log_setup_message "Firefox profile setup complete for user \$KIOSK_USERNAME_EFFECTIVE."
EOF

chmod +x "$FIREFOX_PROFILE_SCRIPT"
log_message "Firefox profile setup script $FIREFOX_PROFILE_SCRIPT created and made executable."

# 19. Create a sudoers entry for the kiosk user to run the Firefox profile setup script
log_message "Creating sudoers entry for Firefox profile setup..."
SUDOERS_FILE="/etc/sudoers.d/kiosk-firefox"
# Ensure KIOSK_USERNAME and OPT_KIOSK_DIR are correctly expanded from the sourced .env file
if [ -z "$KIOSK_USERNAME" ] || [ -z "$OPT_KIOSK_DIR" ]; then
    log_message "Error: KIOSK_USERNAME or OPT_KIOSK_DIR is not set. Cannot create sudoers entry."
    echo "[ERROR] KIOSK_USERNAME or OPT_KIOSK_DIR is not set. Sudoers entry cannot be created." # User feedback
    # Decide if this is a fatal error for firefox.sh
else
    cat > "$SUDOERS_FILE" << EOF
# Allow kiosk user to run Firefox profile setup script without password
$KIOSK_USERNAME ALL=(ALL) NOPASSWD: $OPT_KIOSK_DIR/setup_firefox_profile.sh
EOF
    chmod 440 "$SUDOERS_FILE"
    log_message "Sudoers file $SUDOERS_FILE created with permissions 440."
fi

log_message "Script finished: firefox.sh"
