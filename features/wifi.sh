#!/bin/bash

# ZorinOS Kiosk WiFi Setup Script
# Feature: Hide network settings from kiosk user and configure WiFi

LOG_DIR="/var/log/kiosk"
LOG_FILE="$LOG_DIR/wifi.sh.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting wifi.sh script. Path: $(readlink -f "$0"), Current directory: $(pwd)"

# Exit on any error
set -e
log_message "Error handling enabled with 'set -e'"

# Check if running as root
log_message "Checking if script is running as root"
if [ "$(id -u)" -ne 0 ]; then
  log_message "Error: This script must be run as root. Please use sudo."
  echo "[ERROR] This script must be run as root. Please use sudo." # Keep for direct user feedback
  exit 1
fi
log_message "Script is running as root, continuing"

# Source the environment file
log_message "Checking for environment file"
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
log_message "Environment file sourced successfully. WIFI_SSID=${WIFI_SSID}" # Don't log WIFI_PASSWORD

# Function to ensure required packages are installed
ensure_wifi_packages() {
  log_message "Ensuring required WiFi packages are installed"
  
  # List of required packages
  local packages="network-manager wireless-tools wpasupplicant iw net-tools uuid-runtime" # Added uuid-runtime for uuidgen
  local missing_packages=""
  
  # Check which packages are missing
  for pkg in $packages; do
    if ! dpkg -l | grep -q "ii  $pkg "; then # Added space after $pkg for exact match
      missing_packages="$missing_packages $pkg"
    fi
  done
  
  # Install missing packages if any
  if [ -n "$missing_packages" ]; then
    log_message "Installing missing packages:$missing_packages"
    # Try multiple package installation methods
    if ! apt update && apt install -y $missing_packages; then
      log_message "First attempt (apt update && apt install) failed, trying without update..."
      if ! apt install -y $missing_packages; then
        log_message "Direct install (apt install) failed, trying packages individually..."
        local install_failed=0
        for pkg_indiv in $missing_packages; do # Use different var name
          if ! apt install -y "$pkg_indiv"; then # Quote pkg_indiv
            log_message "Warning: Failed to install package: $pkg_indiv"
            install_failed=1
          fi
        done
        if [ $install_failed -eq 1 ]; then
          log_message "Warning: Some packages failed to install, but continuing..."
        fi
      fi
    fi
    log_message "Package installation attempt completed."
  else
    log_message "All required WiFi packages are already installed."
  fi
  
  return 0
}

# Hide network settings from kiosk user
log_message "Feature: Restricting network settings access"

# Check if dconf is installed
log_message "Checking if dconf is installed"
if ! command -v dconf &> /dev/null; then
  log_message "dconf not found, attempting to install dconf-cli package..."
  apt update && apt install -y dconf-cli || {
    log_message "Error: Failed to install dconf-cli. Network settings restrictions may not work properly."
    # Continue script execution despite error
  }
fi
log_message "dconf is available."

# Create a policy to hide network settings from standard users
log_message "Creating dconf profile directory /etc/dconf/profile/..."
mkdir -p /etc/dconf/profile/
log_message "Writing user profile configuration to /etc/dconf/profile/user..."
echo "user-db:user
system-db:local" > /etc/dconf/profile/user

# Create directory for dconf database files
log_message "Creating dconf database directory /etc/dconf/db/local.d/..."
mkdir -p /etc/dconf/db/local.d/

# Create network settings restrictions
log_message "Creating network settings restrictions file /etc/dconf/db/local.d/00-network..."
cat > /etc/dconf/db/local.d/00-network << EOF
[org/gnome/nm-applet]
disable-connected-notifications=true
disable-disconnected-notifications=true
suppress-wireless-networks-available=true

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF
log_message "Network settings restrictions file created."

# Create locks to prevent user from changing these settings
log_message "Creating dconf locks directory /etc/dconf/db/local.d/locks/..."
mkdir -p /etc/dconf/db/local.d/locks/
log_message "Creating network settings locks file /etc/dconf/db/local.d/locks/network..."
cat > /etc/dconf/db/local.d/locks/network << EOF
/org/gnome/nm-applet/disable-connected-notifications
/org/gnome/nm-applet/disable-disconnected-notifications
/org/gnome/nm-applet/suppress-wireless-networks-available
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF
log_message "Network settings locks file created."

# Update the dconf database
log_message "Updating dconf database..."
dconf update || {
  log_message "Error: Failed to update dconf database. Network settings restrictions may not be applied."
  # Continue script execution despite error
}
log_message "Network settings restrictions applied successfully."

# Function to configure WiFi
configure_wifi() {
  local ssid="$1"
  local password="$2"
  
  log_message "Configuring WiFi connection for SSID: $ssid"
  
  # Check if NetworkManager is installed
  log_message "Checking if NetworkManager (nmcli) is installed"
  if command -v nmcli &> /dev/null; then
    log_message "NetworkManager (nmcli) found, proceeding with configuration."
    
    # Get the WiFi interface name
    log_message "Getting WiFi interface name..."
    local wifi_interface=$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi$' | cut -d':' -f1 | head -n 1)
    if [ -z "$wifi_interface" ]; then
      log_message "Error: No WiFi interface found. Make sure WiFi hardware is enabled."
      return 1
    fi
    log_message "Found WiFi interface: $wifi_interface"
    
    # Ensure WiFi is enabled
    log_message "Ensuring WiFi is enabled via nmcli radio wifi on..."
    nmcli radio wifi on
    
    # Scan for networks to refresh the list
    log_message "Scanning for WiFi networks (nmcli device wifi rescan)..."
    nmcli device wifi rescan || log_message "Warning: nmcli device wifi rescan command failed, but continuing."
    sleep 2  # Give it time to scan
    
    # Check if connection already exists
    log_message "Checking if connection '$ssid' already exists..."
    if nmcli -t -f NAME connection show | grep -q "^${ssid}$"; then # Exact match for SSID
      log_message "WiFi connection for '$ssid' already exists, deleting it first..."
      nmcli connection delete "$ssid" || log_message "Warning: Failed to delete existing connection '$ssid'."
      log_message "Existing connection '$ssid' deleted."
    fi
    
    # Create a new connection with explicit security settings
    log_message "Creating new WiFi connection for '$ssid' using nmconnection file..."
    
    # Create a connection file instead of using the simple connect command
    local UUID
    if command -v uuidgen &>/dev/null; then
        UUID=$(uuidgen)
    else
        log_message "Warning: uuidgen not found. Generating a pseudo-random UUID."
        UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | md5sum | cut -c1-32) # Fallback
    fi
    log_message "Generated UUID for connection: $UUID"

    local CONN_FILENAME="${ssid}.nmconnection" # Use a safe filename
    local CONN_FILE_PATH="/etc/NetworkManager/system-connections/$CONN_FILENAME"
    
    log_message "Creating connection file at $CONN_FILE_PATH"
    cat > "$CONN_FILE_PATH" << EOF
[connection]
id=$ssid
uuid=$UUID
type=wifi
interface-name=$wifi_interface
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
    
    # Set proper permissions for the connection file
    log_message "Setting permissions for connection file $CONN_FILE_PATH to 600..."
    chmod 600 "$CONN_FILE_PATH"
    
    # Reload connections
    log_message "Reloading NetworkManager connections (nmcli connection reload)..."
    nmcli connection reload || log_message "Warning: nmcli connection reload failed."
    
    # Activate the connection
    log_message "Activating the WiFi connection '$ssid' (nmcli connection up)..."
    if ! nmcli connection up "$ssid"; then
      log_message "Error: Failed to activate connection '$ssid' with 'nmcli connection up'. Trying alternative method (nmcli device wifi connect)..."
      # Try alternative method with direct connect
      if ! nmcli device wifi connect "$ssid" password "$password"; then
        log_message "Error: Both 'nmcli connection up' and 'nmcli device wifi connect' failed. Trying wpa_supplicant fallback..."
        
        # Create a temporary wpa_supplicant configuration file
        local WPA_CONF="/tmp/wpa_supplicant_${ssid}.conf" # SSID in filename for uniqueness
        log_message "Creating wpa_supplicant configuration file at $WPA_CONF..."
        if wpa_passphrase "$ssid" "$password" > "$WPA_CONF"; then
          log_message "wpa_supplicant configuration file created."
          # Stop NetworkManager temporarily
          log_message "Stopping NetworkManager temporarily..."
          systemctl stop NetworkManager || log_message "Warning: Failed to stop NetworkManager."
          
          # Connect using wpa_supplicant directly
          log_message "Connecting using wpa_supplicant directly (wpa_supplicant -B -i $wifi_interface -c $WPA_CONF)..."
          if wpa_supplicant -B -i "$wifi_interface" -c "$WPA_CONF"; then
            log_message "wpa_supplicant started in background."
            # Get IP address using DHCP
            log_message "Getting IP address using DHCP (dhclient $wifi_interface)..."
            dhclient "$wifi_interface" || log_message "Warning: dhclient command failed."
            
            # Clean up
            log_message "Cleaning up temporary wpa_supplicant file $WPA_CONF..."
            rm -f "$WPA_CONF"
            
            # Restart NetworkManager
            log_message "Restarting NetworkManager..."
            systemctl start NetworkManager || log_message "Warning: Failed to start NetworkManager."
            
            # Wait for NetworkManager to start
            sleep 5
            
            # Import the connection into NetworkManager
            log_message "Importing the connection into NetworkManager..."
            nmcli connection add type wifi con-name "$ssid" ifname "$wifi_interface" ssid "$ssid" -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password" || log_message "Warning: Failed to import connection into NetworkManager."
            
            log_message "Fallback WiFi connection attempt completed."
          else
            log_message "Error: Failed to connect using wpa_supplicant."
            # Clean up and restart NetworkManager
            rm -f "$WPA_CONF"
            systemctl start NetworkManager || log_message "Warning: Failed to start NetworkManager after wpa_supplicant failure."
            return 1
          fi
        else
          log_message "Error: Failed to create wpa_supplicant configuration using wpa_passphrase."
          return 1
        fi
      else
        log_message "Successfully connected using 'nmcli device wifi connect'."
      fi
    else
      log_message "Successfully activated connection '$ssid' using 'nmcli connection up'."
    fi
    
    # Verify connection status
    log_message "Verifying connection status for '$ssid'..."
    if nmcli -t -f GENERAL.STATE connection show "$ssid" 2>/dev/null | grep -q "activated"; then
      log_message "WiFi connection '$ssid' successfully activated."
    else
      log_message "Warning: Connection '$ssid' created but not activated. It may connect automatically later."
    fi
    
    # Set connection to autoconnect
    log_message "Setting connection '$ssid' to autoconnect yes..."
    nmcli connection modify "$ssid" connection.autoconnect yes || log_message "Warning: Failed to set autoconnect for '$ssid'."
    
    # Set connection to all users
    log_message "Making connection '$ssid' available to all users (permissions='')..."
    nmcli connection modify "$ssid" connection.permissions "" || log_message "Warning: Failed to set permissions for '$ssid'."
    
    log_message "WiFi configuration for '$ssid' completed."
    return 0
  else
    log_message "NetworkManager (nmcli) not found, attempting to install..."
    if apt update && apt install -y network-manager; then
      log_message "NetworkManager installed successfully. Restarting NetworkManager service..."
      systemctl restart NetworkManager || log_message "Warning: Failed to restart NetworkManager service."
      
      # Wait for NetworkManager to start
      log_message "Waiting for NetworkManager to initialize (5 seconds)..."
      sleep 5
      
      # Verify NetworkManager is running
      log_message "Verifying NetworkManager is running..."
      if systemctl is-active --quiet NetworkManager; then
        log_message "NetworkManager is running. Re-attempting WiFi configuration for '$ssid'..."
        # Call this function again now that NetworkManager is installed
        configure_wifi "$ssid" "$password"
      else
        log_message "Error: NetworkManager service failed to start after installation. WiFi configuration skipped."
        return 1
      fi
    else
      log_message "Error: Failed to install NetworkManager. WiFi configuration skipped."
      return 1
    fi
  fi
  return 0 # Should be unreachable if nmcli not found and install fails
}

# Function to detect WiFi security type
detect_wifi_security() {
  local ssid="$1"
  log_message "Detecting security type for SSID: $ssid"
  
  # Scan for networks
  log_message "Rescanning for WiFi networks to detect security for $ssid..."
  nmcli device wifi rescan || log_message "Warning: nmcli device wifi rescan failed during security detection."
  sleep 2 # Increased sleep to allow scan to complete
  
  # Get security info
  # Using a more robust grep to handle SSIDs with special characters if any (though nmcli output is usually clean)
  local security_info=$(nmcli -t -f SSID,SECURITY device wifi list | grep "^${ssid}:" | head -n 1 | cut -d':' -f2)
  
  if [ -z "$security_info" ]; then
    log_message "Warning: Could not detect security type for '$ssid' from nmcli output. Assuming WPA/WPA2."
    echo "WPA2" # Default to WPA2 as it's common
    return
  fi
  
  log_message "Detected security string for '$ssid': $security_info"
  
  # Normalize and check security type
  if echo "$security_info" | grep -qE "WPA2"; then # Check for WPA2 first
    log_message "Interpreted security type as WPA2 for '$ssid'."
    echo "WPA2"
  elif echo "$security_info" | grep -qE "WPA"; then # Then WPA
    log_message "Interpreted security type as WPA for '$ssid'."
    echo "WPA"
  elif echo "$security_info" | grep -qE "WEP"; then # Then WEP
    log_message "Interpreted security type as WEP for '$ssid'."
    echo "WEP"
  elif [ "$security_info" = "--" ] || [ -z "$security_info" ]; then # Open network
    log_message "Interpreted security type as NONE (Open) for '$ssid'."
    echo "NONE"
  else
    log_message "Warning: Unrecognized security string '$security_info' for '$ssid'. Defaulting to WPA2."
    echo "WPA2" # Default if unsure
  fi
}

# Function to create a persistent WiFi connection
create_persistent_wifi_connection() {
  local ssid="$1"
  local password="$2"
  
  log_message "Creating persistent WiFi connection for SSID: $ssid"
  
  # Detect security type
  local security_type
  security_type=$(detect_wifi_security "$ssid")
  log_message "Using detected security type: $security_type for SSID: $ssid"
  
  # Create the NetworkManager connection directory if it doesn't exist
  log_message "Ensuring NetworkManager system connections directory exists: /etc/NetworkManager/system-connections/"
  mkdir -p /etc/NetworkManager/system-connections/
  
  # Generate a UUID for the connection
  local UUID_persistent
   if command -v uuidgen &>/dev/null; then
        UUID_persistent=$(uuidgen)
    else
        log_message "Warning: uuidgen not found for persistent connection. Generating a pseudo-random UUID."
        UUID_persistent=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | md5sum | cut -c1-32) # Fallback
    fi
  log_message "Generated UUID for persistent connection '$ssid': $UUID_persistent"
  
  # Get the WiFi interface name
  local wifi_interface_persistent=$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi$' | cut -d':' -f1 | head -n 1)
  if [ -z "$wifi_interface_persistent" ]; then
    log_message "Warning: No WiFi interface found for persistent connection '$ssid', using generic configuration (interface-name will be omitted)."
  else
    log_message "Using WiFi interface: $wifi_interface_persistent for persistent connection '$ssid'."
  fi
  
  # Create the connection file
  local CONN_FILENAME_PERSISTENT="${ssid}.nmconnection" # Use a safe filename
  local CONN_FILE_PATH_PERSISTENT="/etc/NetworkManager/system-connections/$CONN_FILENAME_PERSISTENT"
  
  log_message "Creating connection file at $CONN_FILE_PATH_PERSISTENT for persistent connection '$ssid'."
  
  # Create base connection configuration
  cat > "$CONN_FILE_PATH_PERSISTENT" << EOF
[connection]
id=$ssid
uuid=$UUID_persistent
type=wifi
EOF

  # Add interface name if available
  if [ -n "$wifi_interface_persistent" ]; then
    echo "interface-name=$wifi_interface_persistent" >> "$CONN_FILE_PATH_PERSISTENT"
  fi
  
  # Add remaining connection settings
  cat >> "$CONN_FILE_PATH_PERSISTENT" << EOF
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=$ssid
EOF

  # Add security settings based on detected type
  log_message "Applying security settings for type: $security_type to $CONN_FILE_PATH_PERSISTENT"
  case "$security_type" in
    "WPA2" | "WPA") # Combine WPA and WPA2 as they use similar config
      cat >> "$CONN_FILE_PATH_PERSISTENT" << EOF
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password
EOF
      log_message "Applied WPA/WPA2 PSK security settings for '$ssid'."
      ;;
    "WEP")
      cat >> "$CONN_FILE_PATH_PERSISTENT" << EOF
[wifi-security]
auth-alg=open
key-mgmt=none
wep-key0=$password
wep-key-type=1 # 1 for Hex/ASCII key, 2 for passphrase
EOF
      log_message "Applied WEP security settings for '$ssid'."
      ;;
    "NONE")
      # No security section needed for open networks
      log_message "Applied NONE (Open) security settings for '$ssid'."
      ;;
    *) # Should not happen if detect_wifi_security defaults to WPA2
      log_message "Warning: Unknown security type '$security_type' in case statement. Defaulting to WPA2-PSK for '$ssid'."
      cat >> "$CONN_FILE_PATH_PERSISTENT" << EOF
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password
EOF
      ;;
  esac
  
  # Add remaining settings
  cat >> "$CONN_FILE_PATH_PERSISTENT" << EOF

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
  
  # Set proper permissions for the connection file
  log_message "Setting permissions for connection file $CONN_FILE_PATH_PERSISTENT to 600..."
  chmod 600 "$CONN_FILE_PATH_PERSISTENT"
  
  # Reload connections
  log_message "Reloading NetworkManager connections (nmcli connection reload)..."
  nmcli connection reload || log_message "Warning: nmcli connection reload failed after creating persistent connection file."
  
  log_message "Persistent WiFi connection file for '$ssid' created at $CONN_FILE_PATH_PERSISTENT."
  return 0
}

# Function to verify WiFi connection
verify_wifi_connection() {
  local ssid="$1"
  log_message "Verifying WiFi connection to SSID: $ssid"
  
  # Check if the connection is active
  # Give it a few seconds to activate if it was just brought up
  sleep 3
  if nmcli -t -f GENERAL.STATE connection show "$ssid" 2>/dev/null | grep -q "activated"; then
    log_message "Connection to '$ssid' is active."
    
    # Check if we have internet connectivity
    log_message "Testing internet connectivity by pinging 8.8.8.8..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
      log_message "Internet connectivity verified for '$ssid'."
      return 0
    else
      log_message "Warning: Connected to '$ssid' but no internet connectivity (ping to 8.8.8.8 failed)."
      return 1
    fi
  else
    log_message "Warning: Connection to '$ssid' is not active."
    return 1
  fi
}

# Configure WiFi
log_message "Feature: WiFi Configuration"
log_message "Checking WiFi configuration settings..."

# Ensure required packages are installed
ensure_wifi_packages || {
  log_message "Error: Failed to ensure required WiFi packages. WiFi setup may not work properly."
  # Decide if this is fatal or a warning. For now, continue.
}

# Check if WiFi credentials are provided
log_message "Checking if WiFi credentials are provided in environment file (WIFI_SSID and WIFI_PASSWORD)..."
if [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PASSWORD" ]; then
  log_message "WiFi credentials (WIFI_SSID or WIFI_PASSWORD) not provided in environment file. Skipping WiFi setup."
else
  log_message "WiFi credentials found. SSID: $WIFI_SSID" # Password is not logged for security
  
  # Create a persistent WiFi connection first (writes the .nmconnection file)
  log_message "Creating/ensuring persistent WiFi connection file for '$WIFI_SSID'..."
  create_persistent_wifi_connection "$WIFI_SSID" "$WIFI_PASSWORD"
  
  # Call the WiFi configuration function (attempts to bring up the connection)
  log_message "Calling main WiFi configuration function for '$WIFI_SSID'..."
  configure_wifi "$WIFI_SSID" "$WIFI_PASSWORD"
  WIFI_CONFIG_STATUS=$?
  log_message "WiFi configuration function completed with status: $WIFI_CONFIG_STATUS for '$WIFI_SSID'."
  
  # Verify the connection if configuration was successful
  if [ $WIFI_CONFIG_STATUS -eq 0 ]; then
    log_message "Verifying WiFi connection for '$WIFI_SSID' after configuration attempt..."
    verify_wifi_connection "$WIFI_SSID"
    VERIFY_STATUS=$?
    
    if [ $VERIFY_STATUS -eq 0 ]; then
      log_message "WiFi connection to '$WIFI_SSID' successfully verified."
    else
      log_message "Warning: WiFi connection verification failed for '$WIFI_SSID'. The system may still connect automatically later if the persistent file is correct."
    fi
  else
    log_message "WiFi configuration function reported an error for '$WIFI_SSID'. Skipping verification."
  fi
fi

log_message "WiFi setup script (wifi.sh) completed."
