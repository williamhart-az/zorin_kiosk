#!/bin/bash

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/master_profile.sh.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
chown kiosk:kiosk "$LOG_DIR" # Assuming 'kiosk' user/group, adjust if needed
chmod 755 "$LOG_DIR"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

enable_feature() {
    log_message "Starting enable_feature: Cloning Firefox profile for kiosk user..."

    # Source profile location (admin user)
    SOURCE_PROFILE_DIR="$HOME/.mozilla/firefox"
    SOURCE_PROFILES_INI="$SOURCE_PROFILE_DIR/profiles.ini"
    log_message "Source profile directory: $SOURCE_PROFILE_DIR"
    log_message "Source profiles.ini: $SOURCE_PROFILES_INI"

    # Destination profile location (kiosk user)
    KIOSK_HOME="/home/kiosk" # Define KIOSK_HOME if not already defined globally
    DEST_PROFILE_DIR="$KIOSK_HOME/.mozilla/firefox"
    log_message "Destination profile directory for kiosk user: $DEST_PROFILE_DIR"

    # Create directories if they don't exist
    log_message "Creating destination directory if it doesn't exist: $DEST_PROFILE_DIR"
    mkdir -p "$DEST_PROFILE_DIR"

    # 1. First, identify the default profile from profiles.ini
    # The following logic attempts to clone a Firefox profile from $HOME/.mozilla/firefox (typically /root/.mozilla/firefox).
    # This has been identified as a point of failure if the root profile doesn't exist or is not the intended source.
    # Commenting out the problematic parts to prevent premature script exit.
    # The primary mechanism for Firefox profile setup should be the save_admin_changes and init_kiosk.sh/kiosk-home-init.service flow.

    log_message "enable_feature: Checking for source profile at $SOURCE_PROFILES_INI (typically /root/.mozilla/firefox/profiles.ini)"
    if [ -f "$SOURCE_PROFILES_INI" ]; then
        log_message "Source profiles.ini found at $SOURCE_PROFILES_INI. Original script would attempt to clone this."
        # DEFAULT_PROFILE=$(grep -A 10 "Default=1" "$SOURCE_PROFILES_INI" | grep "Path=" | head -1 | cut -d= -f2)
        # log_message "Attempted to find Default=1 profile. Result: $DEFAULT_PROFILE"

        # if [ -z "$DEFAULT_PROFILE" ]; then
        #     log_message "No Default=1 profile found. Trying to get the first profile listed."
        #     DEFAULT_PROFILE=$(grep "Path=" "$SOURCE_PROFILES_INI" | head -1 | cut -d= -f2)
        #     log_message "First profile found: $DEFAULT_PROFILE"
        # fi

        # if [ -n "$DEFAULT_PROFILE" ]; then
            # SOURCE_PROFILE_PATH="$SOURCE_PROFILE_DIR/$DEFAULT_PROFILE"
            # log_message "Identified source profile path: $SOURCE_PROFILE_PATH"
            # log_message "Original script would copy profile contents from $SOURCE_PROFILE_PATH to $DEST_PROFILE_DIR/kiosk.default"
            # log_message "This step is now SKIPPED in enable_feature to rely on template mechanism via save_admin_changes."
            # KIOSK_PROFILE_NAME="kiosk.default"
            # KIOSK_PROFILE_PATH="$DEST_PROFILE_DIR/$KIOSK_PROFILE_NAME"
            # mkdir -p "$KIOSK_PROFILE_PATH"
            # cp -r "$SOURCE_PROFILE_PATH"/* "$KIOSK_PROFILE_PATH/"
            # cat > "$DEST_PROFILE_DIR/profiles.ini" << EOF ... (omitted for brevity)
            # chown -R kiosk:kiosk "$KIOSK_HOME/.mozilla"
            # log_message "Firefox profile successfully cloned for kiosk user."
        # else
            # log_message "Error: Could not find a Firefox profile to clone from $SOURCE_PROFILE_DIR. DEFAULT_PROFILE was empty. (Original script would exit)"
            log_message "Warning: Could not find a default Firefox profile to clone from $SOURCE_PROFILE_DIR. This step in enable_feature will be skipped."
        # fi
    else
        # log_message "Error: Source profiles.ini not found at $SOURCE_PROFILES_INI. (Original script would exit)"
        log_message "Warning: Source profiles.ini not found at $SOURCE_PROFILES_INI. Cloning from root profile in enable_feature will be skipped."
    fi
    log_message "enable_feature: Finished (potentially problematic Firefox clone from root profile step has been modified/skipped)."
}

disable_feature() {
    log_message "Starting disable_feature: Removing Firefox profile for kiosk user..."
    KIOSK_HOME="/home/kiosk" # Define KIOSK_HOME if not already defined globally
    DEST_PROFILE_DIR="$KIOSK_HOME/.mozilla/firefox"
    FLATPAK_FIREFOX_PROFILE_DIR="$KIOSK_HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"

    if [ -d "$DEST_PROFILE_DIR" ]; then
        log_message "Removing Firefox profile directory: $DEST_PROFILE_DIR"
        rm -rf "$DEST_PROFILE_DIR"
        log_message "Directory $DEST_PROFILE_DIR removed."
    else
        log_message "Firefox profile directory $DEST_PROFILE_DIR not found. Nothing to remove."
    fi

    if [ -d "$FLATPAK_FIREFOX_PROFILE_DIR" ]; then
        log_message "Removing Flatpak Firefox profile directory: $FLATPAK_FIREFOX_PROFILE_DIR"
        rm -rf "$FLATPAK_FIREFOX_PROFILE_DIR"
        log_message "Directory $FLATPAK_FIREFOX_PROFILE_DIR removed."
    else
        log_message "Flatpak Firefox profile directory $FLATPAK_FIREFOX_PROFILE_DIR not found. Nothing to remove."
    fi
    log_message "Firefox profile removal complete for kiosk user."
}

case "$1" in
    enable)
        log_message "Argument 'enable' received. Calling enable_feature."
        enable_feature
        log_message "enable_feature completed."
        ;;
    disable)
        log_message "Argument 'disable' received. Calling disable_feature."
        disable_feature
        log_message "disable_feature completed."
        ;;
    *)
        log_message "Invalid argument received: $1. Usage: $0 {enable|disable}"
        echo "Usage: $0 {enable|disable}"
        exit 1
        ;;
esac

# Ensure the script continues to the main execution logic below,
# rather than exiting prematurely. The "Script finished" log and exit 0
# will be handled at the very end of the script's full execution.

# Function to save admin changes to the template directory
save_admin_changes() {
  # Log initialization
  ADMIN_SAVE_LOG_FILE="$LOG_DIR/admin_save.log" # Use the global LOG_DIR
  admin_log_message() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$ADMIN_SAVE_LOG_FILE"
  }
  admin_log_message "Saving admin changes to template directory..."

  # Ensure ADMIN_USERNAME and TEMPLATE_DIR are set (these should be sourced from .env or passed)
  if [ -z "$ADMIN_USERNAME" ] || [ -z "$TEMPLATE_DIR" ]; then
    admin_log_message "Error: ADMIN_USERNAME or TEMPLATE_DIR not set in save_admin_changes."
    return 1
  fi
  admin_log_message "ADMIN_USERNAME: $ADMIN_USERNAME, TEMPLATE_DIR: $TEMPLATE_DIR"

  # Copy Firefox profile if it exists
  # Determine Firefox profile directory for $ADMIN_USERNAME
  FF_PROFILE_DIR_SNAP="/home/$ADMIN_USERNAME/snap/firefox/common/.mozilla"
  FF_PROFILE_DIR_FLATPAK="/home/$ADMIN_USERNAME/.var/app/org.mozilla.firefox/.mozilla"
  FF_PROFILE_DIR_TRADITIONAL="/home/$ADMIN_USERNAME/.mozilla" # Original path
  FF_PROFILE_SOURCE_DIR=""

  if [ -d "$FF_PROFILE_DIR_SNAP" ]; then
    FF_PROFILE_SOURCE_DIR="$FF_PROFILE_DIR_SNAP"
    admin_log_message "Found Firefox Snap profile at $FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME"
  elif [ -d "$FF_PROFILE_DIR_FLATPAK" ]; then
    FF_PROFILE_SOURCE_DIR="$FF_PROFILE_DIR_FLATPAK"
    admin_log_message "Found Firefox Flatpak profile at $FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME"
  elif [ -d "$FF_PROFILE_DIR_TRADITIONAL" ]; then
    FF_PROFILE_SOURCE_DIR="$FF_PROFILE_DIR_TRADITIONAL"
    admin_log_message "Found Firefox traditional profile at $FF_PROFILE_SOURCE_DIR for user $ADMIN_USERNAME"
  fi

  if [ -n "$FF_PROFILE_SOURCE_DIR" ]; then
    admin_log_message "Copying Firefox profile from $FF_PROFILE_SOURCE_DIR to $TEMPLATE_DIR/.mozilla..."
    rm -rf "$TEMPLATE_DIR/.mozilla"  # Remove existing profile first
    cp -r "$FF_PROFILE_SOURCE_DIR" "$TEMPLATE_DIR/.mozilla" # Copies the found profile dir and names the copy '.mozilla'
    chmod -R 755 "$TEMPLATE_DIR/.mozilla"
    admin_log_message "Firefox profile copied to template."

    # Store the Firefox profile type for later use
    FF_PROFILE_TYPE="unknown"
    if [[ "$FF_PROFILE_SOURCE_DIR" == *"/snap/firefox/"* ]]; then
      FF_PROFILE_TYPE="snap"
    elif [[ "$FF_PROFILE_SOURCE_DIR" == *".var/app/org.mozilla.firefox"* ]]; then
      FF_PROFILE_TYPE="flatpak"
    elif [[ "$FF_PROFILE_SOURCE_DIR" == *".mozilla"* ]]; then # Check this last as it's more generic
      FF_PROFILE_TYPE="traditional"
    fi
    admin_log_message "Determined Firefox profile type as: $FF_PROFILE_TYPE"
    
    # Create a file to indicate the Firefox profile type
    echo "$FF_PROFILE_TYPE" > "$TEMPLATE_DIR/.firefox_profile_type"
    chmod 644 "$TEMPLATE_DIR/.firefox_profile_type"
    admin_log_message "Firefox profile type indicator file created at $TEMPLATE_DIR/.firefox_profile_type"
  else
    admin_log_message "Firefox profile directory not found for user $ADMIN_USERNAME. Searched Snap, Flatpak, and traditional paths."
  fi

  # Copy desktop shortcuts
  admin_log_message "Copying desktop shortcuts from /home/$ADMIN_USERNAME/Desktop/ to $TEMPLATE_DIR/Desktop/..."
  cp -r "/home/$ADMIN_USERNAME/Desktop/"* "$TEMPLATE_DIR/Desktop/" 2>/dev/null || admin_log_message "No desktop shortcuts to copy or error during copy."

  # Copy documents
  admin_log_message "Copying documents from /home/$ADMIN_USERNAME/Documents/ to $TEMPLATE_DIR/Documents/..."
  cp -r "/home/$ADMIN_USERNAME/Documents/"* "$TEMPLATE_DIR/Documents/" 2>/dev/null || admin_log_message "No documents to copy or error during copy."

  # Set correct ownership for all template files
  admin_log_message "Setting ownership of $TEMPLATE_DIR to root:root and permissions to 755 recursively..."
  chown -R root:root "$TEMPLATE_DIR"
  chmod -R 755 "$TEMPLATE_DIR"

  admin_log_message "Admin changes saved successfully."
}

# Function to create the save admin changes script
create_save_admin_script() {
  log_message "Starting create_save_admin_script..."
  # Ensure OPT_KIOSK_DIR is set
  if [ -z "$OPT_KIOSK_DIR" ]; then
    log_message "Error: OPT_KIOSK_DIR not set in create_save_admin_script."
    return 1
  fi
  SAVE_ADMIN_SCRIPT="$OPT_KIOSK_DIR/save_admin_changes.sh"
  log_message "Save admin script will be created at: $SAVE_ADMIN_SCRIPT"

  # Define the log file path for the generated script
  GENERATED_SCRIPT_LOG_FILE="$LOG_DIR/admin_save_generated_script.log" # Use the global LOG_DIR

  cat > "$SAVE_ADMIN_SCRIPT" << EOF
#!/bin/bash

# Script to save admin user changes to the kiosk template directory

# Log initialization
# Note: \$LOG_DIR will be expanded when this script (save_admin_changes.sh) runs,
# if LOG_DIR is exported or defined in its environment.
# For robustness, we hardcode it here or ensure it's passed.
# Using the path directly from the parent script's LOG_DIR variable.
LOGFILE="$GENERATED_SCRIPT_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_generated_script_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_generated_script_message "Executing save_admin_changes.sh: Saving admin changes to template directory..."

# ADMIN_USERNAME and TEMPLATE_DIR are expanded here by the master_profile.sh script
# So, their values will be hardcoded into the generated save_admin_changes.sh script.
ADMIN_USERNAME_EXPANDED="$ADMIN_USERNAME"
TEMPLATE_DIR_EXPANDED="$TEMPLATE_DIR"

log_generated_script_message "ADMIN_USERNAME for this run: \$ADMIN_USERNAME_EXPANDED"
log_generated_script_message "TEMPLATE_DIR for this run: \$TEMPLATE_DIR_EXPANDED"

# Create template directories if they don't exist
log_generated_script_message "Creating template subdirectories if they don't exist..."
mkdir -p "\$TEMPLATE_DIR_EXPANDED/Desktop"
mkdir -p "\$TEMPLATE_DIR_EXPANDED/Documents"
mkdir -p "\$TEMPLATE_DIR_EXPANDED/.config/autostart"
mkdir -p "\$TEMPLATE_DIR_EXPANDED/.local/share/applications"

# Determine Firefox profile directory for \$ADMIN_USERNAME_EXPANDED
FF_PROFILE_DIR_SNAP="/home/\$ADMIN_USERNAME_EXPANDED/snap/firefox/common/.mozilla"
FF_PROFILE_DIR_FLATPAK="/home/\$ADMIN_USERNAME_EXPANDED/.var/app/org.mozilla.firefox/.mozilla"
FF_PROFILE_DIR_TRADITIONAL="/home/\$ADMIN_USERNAME_EXPANDED/.mozilla" # Original path
FF_PROFILE_SOURCE_DIR=""

log_generated_script_message "Searching for Firefox profile for user \$ADMIN_USERNAME_EXPANDED..."
if [ -d "\$FF_PROFILE_DIR_SNAP" ]; then
  FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_SNAP"
  log_generated_script_message "Found Firefox Snap profile at \$FF_PROFILE_SOURCE_DIR"
elif [ -d "\$FF_PROFILE_DIR_FLATPAK" ]; then
  FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_FLATPAK"
  log_generated_script_message "Found Firefox Flatpak profile at \$FF_PROFILE_SOURCE_DIR"
elif [ -d "\$FF_PROFILE_DIR_TRADITIONAL" ]; then
  FF_PROFILE_SOURCE_DIR="\$FF_PROFILE_DIR_TRADITIONAL"
  log_generated_script_message "Found Firefox traditional profile at \$FF_PROFILE_SOURCE_DIR"
fi

# Copy Firefox profile if a source directory was found
if [ -n "\$FF_PROFILE_SOURCE_DIR" ]; then
  log_generated_script_message "Copying Firefox profile from \$FF_PROFILE_SOURCE_DIR to \$TEMPLATE_DIR_EXPANDED/.mozilla..."
  rm -rf "\$TEMPLATE_DIR_EXPANDED/.mozilla"  # Remove existing profile first
  cp -r "\$FF_PROFILE_SOURCE_DIR" "\$TEMPLATE_DIR_EXPANDED/.mozilla" # Copies the found profile dir and names the copy '.mozilla'
  chmod -R 755 "\$TEMPLATE_DIR_EXPANDED/.mozilla"
  log_generated_script_message "Firefox profile copied."
  
  # Store the Firefox profile type for later use
  CURRENT_FF_PROFILE_TYPE="unknown"
  if [[ "\$FF_PROFILE_SOURCE_DIR" == *"/snap/firefox/"* ]]; then
    CURRENT_FF_PROFILE_TYPE="snap"
  elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".var/app/org.mozilla.firefox"* ]]; then
    CURRENT_FF_PROFILE_TYPE="flatpak"
  elif [[ "\$FF_PROFILE_SOURCE_DIR" == *".mozilla"* ]]; then # Check this last
    CURRENT_FF_PROFILE_TYPE="traditional"
  fi
  log_generated_script_message "Determined Firefox profile type as: \$CURRENT_FF_PROFILE_TYPE"
  
  # Create a file to indicate the Firefox profile type
  echo "\$CURRENT_FF_PROFILE_TYPE" > "\$TEMPLATE_DIR_EXPANDED/.firefox_profile_type"
  chmod 644 "\$TEMPLATE_DIR_EXPANDED/.firefox_profile_type"
  log_generated_script_message "Firefox profile type indicator file created at \$TEMPLATE_DIR_EXPANDED/.firefox_profile_type"
else
  log_generated_script_message "Firefox profile directory not found for user \$ADMIN_USERNAME_EXPANDED. Searched Snap, Flatpak, and traditional paths."
fi

# Copy desktop shortcuts
log_generated_script_message "Copying desktop shortcuts from /home/\$ADMIN_USERNAME_EXPANDED/Desktop/ to \$TEMPLATE_DIR_EXPANDED/Desktop/..."
cp -r "/home/\$ADMIN_USERNAME_EXPANDED/Desktop/"* "\$TEMPLATE_DIR_EXPANDED/Desktop/" 2>/dev/null || log_generated_script_message "No desktop shortcuts to copy or error during copy."

# Copy documents
log_generated_script_message "Copying documents from /home/\$ADMIN_USERNAME_EXPANDED/Documents/ to \$TEMPLATE_DIR_EXPANDED/Documents/..."
cp -r "/home/\$ADMIN_USERNAME_EXPANDED/Documents/"* "\$TEMPLATE_DIR_EXPANDED/Documents/" 2>/dev/null || log_generated_script_message "No documents to copy or error during copy."

# Set correct ownership for all template files
log_generated_script_message "Setting ownership of \$TEMPLATE_DIR_EXPANDED to root:root and permissions to 755 recursively..."
chown -R root:root "\$TEMPLATE_DIR_EXPANDED"
chmod -R 755 "\$TEMPLATE_DIR_EXPANDED"

log_generated_script_message "Admin changes saved successfully."
EOF

  chmod +x "$SAVE_ADMIN_SCRIPT"
  log_message "save_admin_changes.sh script created and made executable."
}

# Function to create systemd service for saving admin changes
create_systemd_service() {
  log_message "Starting create_systemd_service..."
  # Ensure OPT_KIOSK_DIR is set
  if [ -z "$OPT_KIOSK_DIR" ]; then
    log_message "Error: OPT_KIOSK_DIR not set in create_systemd_service."
    return 1
  fi
  SYSTEMD_SERVICE="/etc/systemd/system/save-admin-changes.service"
  log_message "Systemd service file for saving admin changes: $SYSTEMD_SERVICE"

  cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Save admin changes to kiosk template directory
Before=lightdm.service # Or appropriate display manager service

[Service]
Type=oneshot
ExecStart=$OPT_KIOSK_DIR/save_admin_changes.sh
RemainAfterExit=yes
StandardOutput=append:$LOG_DIR/save-admin-changes.service.log
StandardError=append:$LOG_DIR/save-admin-changes.service.err

[Install]
WantedBy=multi-user.target
EOF
  log_message "Systemd service definition for save-admin-changes created."

  # Enable the service
  log_message "Enabling save-admin-changes.service..."
  systemctl enable save-admin-changes.service
  log_message "save-admin-changes.service enabled."
}

# Function to create systemd service for kiosk home initialization
create_kiosk_init_service() {
  log_message "Starting create_kiosk_init_service..."
  # Ensure KIOSK_USERNAME and TEMPLATE_DIR are set
  if [ -z "$KIOSK_USERNAME" ] || [ -z "$TEMPLATE_DIR" ]; then
    log_message "Error: KIOSK_USERNAME or TEMPLATE_DIR not set in create_kiosk_init_service."
    return 1
  fi
  KIOSK_INIT_SERVICE="/etc/systemd/system/kiosk-home-init.service"
  log_message "Systemd service file for kiosk home initialization: $KIOSK_INIT_SERVICE"

  # Define log files for the ExecStart command within the service file
  KIOSK_INIT_SERVICE_LOG="$LOG_DIR/kiosk-home-init.service.log"
  KIOSK_INIT_SERVICE_ERR="$LOG_DIR/kiosk-home-init.service.err"

  # Construct the ExecStart command with logging
  # The command is complex, so building it step-by-step for clarity
  EXEC_START_CMD="/bin/bash -c \""
  EXEC_START_CMD+="echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Starting kiosk home initialization...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="mkdir -p /home/$KIOSK_USERNAME/.config/autostart >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="cp -r $TEMPLATE_DIR/.config/autostart/* /home/$KIOSK_USERNAME/.config/autostart/ >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="mkdir -p /home/$KIOSK_USERNAME/Desktop >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="cp -r $TEMPLATE_DIR/Desktop/* /home/$KIOSK_USERNAME/Desktop/ >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="mkdir -p /home/$KIOSK_USERNAME/Documents >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="cp -r $TEMPLATE_DIR/Documents/* /home/$KIOSK_USERNAME/Documents/ 2>/dev/null || echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - No documents to copy or error during copy (Documents)\\\" >> $KIOSK_INIT_SERVICE_LOG && "
  EXEC_START_CMD+="if [ -d '$TEMPLATE_DIR/.mozilla' ]; then "
  EXEC_START_CMD+="  echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Copying .mozilla directory...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="  cp -r $TEMPLATE_DIR/.mozilla /home/$KIOSK_USERNAME/ >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="  if [ -f '$TEMPLATE_DIR/.firefox_profile_type' ] && [ \\\$(cat '$TEMPLATE_DIR/.firefox_profile_type') = 'flatpak' ]; then "
  EXEC_START_CMD+="    echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Setting up Flatpak Firefox directory structure...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="    mkdir -p /home/$KIOSK_USERNAME/.var/app/org.mozilla.firefox >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR; "
  EXEC_START_CMD+="  fi; "
  EXEC_START_CMD+="fi && "
  # Copy systemd user services
  EXEC_START_CMD+="echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Copying systemd user services...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="mkdir -p /home/$KIOSK_USERNAME/.config/systemd/user >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="if [ -d '$TEMPLATE_DIR/.config/systemd/user' ]; then "
  EXEC_START_CMD+="  cp -r $TEMPLATE_DIR/.config/systemd/user/* /home/$KIOSK_USERNAME/.config/systemd/user/ >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR || echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - No systemd user services to copy or error during copy.\\\" >> $KIOSK_INIT_SERVICE_LOG; "
  EXEC_START_CMD+="fi && "
  # Set ownership for all copied files
  EXEC_START_CMD+="echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Setting ownership for /home/$KIOSK_USERNAME...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="chown -R $KIOSK_USERNAME:$KIOSK_USERNAME /home/$KIOSK_USERNAME/ >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  # Enable kiosk-idle-delay.service for the user (requires linger to be enabled for the user)
  # Ensure KioskUID is available or fetched if needed. For system service, it might need to get UID.
  # For simplicity, assuming KIOSK_USERNAME is known and its UID can be found by systemctl.
  # This command is run by root, so it needs to specify the user.
  EXEC_START_CMD+="if [ -f \"/home/$KIOSK_USERNAME/.config/systemd/user/kiosk-idle-delay.service\" ]; then "
  EXEC_START_CMD+="  echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Enabling kiosk-idle-delay.service for user $KIOSK_USERNAME...\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && "
  EXEC_START_CMD+="  loginctl enable-linger $KIOSK_USERNAME >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR && " # Ensure linger is enabled
  EXEC_START_CMD+="  XDG_RUNTIME_DIR=/run/user/\$(id -u $KIOSK_USERNAME) systemctl --user --machine=$KIOSK_USERNAME@.host --now enable kiosk-idle-delay.service >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR || echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Failed to enable kiosk-idle-delay.service for user $KIOSK_USERNAME.\\\" >> $KIOSK_INIT_SERVICE_LOG; "
  EXEC_START_CMD+="fi && "
  EXEC_START_CMD+="echo \\\"\$(date '+%Y-%m-%d %H:%M:%S') - Kiosk home initialization complete.\\\" >> $KIOSK_INIT_SERVICE_LOG 2>> $KIOSK_INIT_SERVICE_ERR"
  EXEC_START_CMD+="\""

  cat > "$KIOSK_INIT_SERVICE" << EOF
[Unit]
Description=Initialize Kiosk User Home Directory
After=local-fs.target
Before=display-manager.service # Or appropriate display manager service

[Service]
Type=oneshot
ExecStart=$EXEC_START_CMD
RemainAfterExit=yes
# StandardOutput and StandardError are handled by redirection within ExecStart for more granular logging

[Install]
WantedBy=multi-user.target
EOF
  log_message "Systemd service definition for kiosk-home-init created."

  # Enable the service
  log_message "Enabling kiosk-home-init.service..."
  systemctl enable kiosk-home-init.service
  log_message "kiosk-home-init.service enabled."
}

# Function to initialize kiosk environment (script run on user login)
create_init_kiosk_script() {
  log_message "Starting create_init_kiosk_script..."
  # Ensure OPT_KIOSK_DIR and TEMPLATE_DIR are set
  if [ -z "$OPT_KIOSK_DIR" ] || [ -z "$TEMPLATE_DIR" ]; then
    log_message "Error: OPT_KIOSK_DIR or TEMPLATE_DIR not set in create_init_kiosk_script."
    return 1
  fi
  INIT_SCRIPT="$OPT_KIOSK_DIR/init_kiosk.sh"
  log_message "Kiosk init script will be created at: $INIT_SCRIPT"

  # Define the log file path for the generated script
  GENERATED_INIT_LOG_FILE="$LOG_DIR/kiosk_init_generated_script.log" # Use the global LOG_DIR

  cat > "$INIT_SCRIPT" << EOF
#!/bin/bash

# Script to initialize kiosk environment on login

# Log initialization
# Using the path directly from the parent script's LOG_DIR variable.
LOGFILE="$GENERATED_INIT_LOG_FILE"
mkdir -p "$(dirname "\$LOGFILE")" # Ensure directory exists when script runs

log_kiosk_init_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOGFILE"
}

log_kiosk_init_message "Executing init_kiosk.sh: Initializing kiosk environment..."

# TEMPLATE_DIR is expanded here by the master_profile.sh script
# So, its value will be hardcoded into the generated init_kiosk.sh script.
LOCAL_TEMPLATE_DIR="$TEMPLATE_DIR"
log_kiosk_init_message "TEMPLATE_DIR for this run: \$LOCAL_TEMPLATE_DIR"

# Create necessary directories if they don't exist
log_kiosk_init_message "Creating standard user directories if they don't exist..."
mkdir -p ~/Desktop
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/Pictures
mkdir -p ~/.config/autostart
mkdir -p ~/.local/share/applications

# Copy Firefox profile if it exists
if [ -d "\$LOCAL_TEMPLATE_DIR/.mozilla" ]; then
  log_kiosk_init_message "Copying Firefox profile from template \$LOCAL_TEMPLATE_DIR/.mozilla to ~/.mozilla..."
  rm -rf ~/.mozilla  # Remove any existing profile
  cp -r "\$LOCAL_TEMPLATE_DIR/.mozilla" ~/
  log_kiosk_init_message "Firefox profile copied."
  
  # Get the Firefox profile type
  LOCAL_FF_PROFILE_TYPE="unknown"
  if [ -f "\$LOCAL_TEMPLATE_DIR/.firefox_profile_type" ]; then
    LOCAL_FF_PROFILE_TYPE=\$(cat "\$LOCAL_TEMPLATE_DIR/.firefox_profile_type")
    log_kiosk_init_message "Read Firefox profile type from template: \$LOCAL_FF_PROFILE_TYPE"
  else
    log_kiosk_init_message "Firefox profile type indicator file not found in template: \$LOCAL_TEMPLATE_DIR/.firefox_profile_type"
  fi
  
  # Ensure proper ownership of Firefox profile directories
  log_kiosk_init_message "Setting permissions for ~/.mozilla to 700."
  chmod -R 700 ~/.mozilla
  
  # Handle Flatpak Firefox installation
  if [ "\$LOCAL_FF_PROFILE_TYPE" = "flatpak" ]; then
    log_kiosk_init_message "Setting up Flatpak Firefox directories in user's home as profile type is Flatpak..."
    # Create .var directory structure if it doesn't exist
    mkdir -p ~/.var/app/org.mozilla.firefox
    # Set proper ownership and permissions
    log_kiosk_init_message "Setting permissions for ~/.var to 700."
    chmod -R 700 ~/.var
  fi
else
  log_kiosk_init_message "Firefox profile directory not found in template: \$LOCAL_TEMPLATE_DIR/.mozilla. Skipping copy."
fi

# Copy desktop shortcuts if they exist
if [ -d "\$LOCAL_TEMPLATE_DIR/Desktop" ]; then
  log_kiosk_init_message "Copying desktop shortcuts from \$LOCAL_TEMPLATE_DIR/Desktop/ to ~/Desktop/..."
  cp -r "\$LOCAL_TEMPLATE_DIR/Desktop/"* ~/Desktop/ 2>/dev/null || log_kiosk_init_message "No desktop shortcuts to copy or error during copy."
fi

# Copy documents if they exist
if [ -d "\$LOCAL_TEMPLATE_DIR/Documents" ]; then
  log_kiosk_init_message "Copying documents from \$LOCAL_TEMPLATE_DIR/Documents/ to ~/Documents/..."
  cp -r "\$LOCAL_TEMPLATE_DIR/Documents/"* ~/Documents/ 2>/dev/null || log_kiosk_init_message "No documents to copy or error during copy."
fi

# Copy autostart entries if they exist
if [ -d "\$LOCAL_TEMPLATE_DIR/.config/autostart" ]; then
  log_kiosk_init_message "Copying autostart entries from \$LOCAL_TEMPLATE_DIR/.config/autostart/ to ~/.config/autostart/..."
  cp -r "\$LOCAL_TEMPLATE_DIR/.config/autostart/"* ~/.config/autostart/ 2>/dev/null || log_kiosk_init_message "No autostart entries to copy or error during copy."
fi

# Copy systemd user services if they exist
if [ -d "\$LOCAL_TEMPLATE_DIR/.config/systemd/user" ]; then
  log_kiosk_init_message "Copying systemd user services from \$LOCAL_TEMPLATE_DIR/.config/systemd/user/ to ~/.config/systemd/user/..."
  mkdir -p ~/.config/systemd/user
  cp -r "\$LOCAL_TEMPLATE_DIR/.config/systemd/user/"* ~/.config/systemd/user/ 2>/dev/null || log_kiosk_init_message "No systemd user services to copy or error during copy."
  
  # Attempt to enable kiosk-idle-delay.service if it was copied
  if [ -f ~/.config/systemd/user/kiosk-idle-delay.service ]; then
    log_kiosk_init_message "Attempting to enable kiosk-idle-delay.service for user \$(whoami)..."
    # Ensure the DBUS_SESSION_BUS_ADDRESS is available for systemctl --user
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u)/bus"
        log_kiosk_init_message "DBUS_SESSION_BUS_ADDRESS was not set. Exported to: \$DBUS_SESSION_BUS_ADDRESS"
    fi
    systemctl --user enable kiosk-idle-delay.service >> "\$LOGFILE" 2>&1 || log_kiosk_init_message "Failed to enable kiosk-idle-delay.service."
    systemctl --user start kiosk-idle-delay.service >> "\$LOGFILE" 2>&1 || log_kiosk_init_message "Failed to start kiosk-idle-delay.service."
  fi
fi

log_kiosk_init_message "Kiosk environment initialized successfully."
EOF

  chmod +x "$INIT_SCRIPT"
  log_message "init_kiosk.sh script created and made executable."
}

# Main execution
log_message "Starting main execution: Setting up master profile feature..."

# Source environment variables if they exist (e.g., .env file)
# This is important for ADMIN_USERNAME, KIOSK_USERNAME, TEMPLATE_DIR, OPT_KIOSK_DIR
# Example: if [ -f .env ]; then source .env; fi
# For now, assuming these are set in the environment or a sourced config file.
log_message "Checking required variables: ADMIN_USERNAME='${ADMIN_USERNAME}', KIOSK_USERNAME='${KIOSK_USERNAME}', TEMPLATE_DIR='${TEMPLATE_DIR}', OPT_KIOSK_DIR='${OPT_KIOSK_DIR}'"


# Create the necessary scripts
log_message "Calling create_save_admin_script..."
create_save_admin_script
log_message "Calling create_init_kiosk_script..."
create_init_kiosk_script

# Create the systemd services
log_message "Calling create_systemd_service (for save-admin-changes)..."
create_systemd_service
log_message "Calling create_kiosk_init_service..."
create_kiosk_init_service

# Perform an initial save of admin changes
log_message "Performing initial save_admin_changes..."
save_admin_changes

# Copy the autostart entries and desktop shortcut to the kiosk user's home directory if it exists
# This part might be redundant if kiosk-home-init.service runs correctly on first boot after setup.
# However, it can be useful for immediate setup if the kiosk user already exists.
if [ -n "$KIOSK_USERNAME" ] && [ -d "/home/$KIOSK_USERNAME" ]; then
  log_message "Kiosk user home directory /home/$KIOSK_USERNAME exists. Proceeding with initial content copy."
  mkdir -p "/home/$KIOSK_USERNAME/.config/autostart"
  mkdir -p "/home/$KIOSK_USERNAME/Desktop"
  mkdir -p "/home/$KIOSK_USERNAME/Documents"
  
  # Copy from template to kiosk user
  if [ -d "$TEMPLATE_DIR/.config/autostart" ]; then
    log_message "Copying $TEMPLATE_DIR/.config/autostart to /home/$KIOSK_USERNAME/.config/autostart/"
    cp -r "$TEMPLATE_DIR/.config/autostart/"* "/home/$KIOSK_USERNAME/.config/autostart/" 2>/dev/null || log_message "Error or no files copying autostart entries to kiosk user."
  fi
  
  if [ -d "$TEMPLATE_DIR/Desktop" ]; then
    log_message "Copying $TEMPLATE_DIR/Desktop to /home/$KIOSK_USERNAME/Desktop/"
    cp -r "$TEMPLATE_DIR/Desktop/"* "/home/$KIOSK_USERNAME/Desktop/" 2>/dev/null || log_message "Error or no files copying desktop entries to kiosk user."
  fi
  
  if [ -d "$TEMPLATE_DIR/Documents" ]; then
    log_message "Copying $TEMPLATE_DIR/Documents to /home/$KIOSK_USERNAME/Documents/"
    cp -r "$TEMPLATE_DIR/Documents/"* "/home/$KIOSK_USERNAME/Documents/" 2>/dev/null || log_message "Error or no files copying documents to kiosk user."
  fi
  
  # Set correct ownership
  log_message "Setting ownership for /home/$KIOSK_USERNAME to $KIOSK_USERNAME:$KIOSK_USERNAME"
  chown -R "$KIOSK_USERNAME:$KIOSK_USERNAME" "/home/$KIOSK_USERNAME/"
else
  if [ -z "$KIOSK_USERNAME" ]; then
    log_message "KIOSK_USERNAME not set. Skipping initial content copy to kiosk user home."
  else
    log_message "Kiosk user home directory /home/$KIOSK_USERNAME does not exist. Skipping initial content copy."
  fi
fi

log_message "Master profile feature setup complete."
log_message "Script finished."
exit 0
