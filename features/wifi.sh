#!/bin/bash

# ZorinOS Kiosk WiFi Setup Script
# Feature: Hide network settings from kiosk user and configure WiFi

echo "[DEBUG] Starting wifi.sh script"
echo "[DEBUG] Script path: $(readlink -f "$0")"
echo "[DEBUG] Current directory: $(pwd)"

# Exit on any error
set -e
echo "[DEBUG] Error handling enabled with 'set -e'"

# Check if running as root
echo "[DEBUG] Checking if script is running as root"
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Please use sudo."
  exit 1
fi
echo "[DEBUG] Script is running as root, continuing"

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

# Function to ensure required packages are installed
ensure_wifi_packages() {
  echo "[DEBUG] Ensuring required WiFi packages are installed"
  
  # List of required packages
  local packages="network-manager wireless-tools wpasupplicant iw net-tools"
  local missing_packages=""
  
  # Check which packages are missing
  for pkg in $packages; do
    if ! dpkg -l | grep -q "ii  $pkg "; then
      missing_packages="$missing_packages $pkg"
    fi
  done
  
  # Install missing packages if any
  if [ -n "$missing_packages" ]; then
    echo "[DEBUG] Installing missing packages:$missing_packages"
    apt update && apt install -y $missing_packages || {
      echo "[ERROR] Failed to install required packages"
      return 1
    }
    echo "[DEBUG] Required packages installed successfully"
  else
    echo "[DEBUG] All required packages are already installed"
  fi
  
  return 0
}

# Hide network settings from kiosk user
echo "[DEBUG] Feature: Restricting network settings access"

# Check if dconf is installed
echo "[DEBUG] Checking if dconf is installed"
if ! command -v dconf &> /dev/null; then
  echo "[DEBUG] dconf not found, installing dconf-cli package"
  apt update && apt install -y dconf-cli || {
    echo "[ERROR] Failed to install dconf-cli. Network settings restrictions may not work properly."
    # Continue script execution despite error
  }
fi
echo "[DEBUG] dconf is available"

# Create a policy to hide network settings from standard users
echo "[DEBUG] Creating dconf profile directory"
mkdir -p /etc/dconf/profile/
echo "[DEBUG] Writing user profile configuration"
echo "user-db:user
system-db:local" > /etc/dconf/profile/user

# Create directory for dconf database files
echo "[DEBUG] Creating dconf database directory"
mkdir -p /etc/dconf/db/local.d/

# Create network settings restrictions
echo "[DEBUG] Creating network settings restrictions file"
cat > /etc/dconf/db/local.d/00-network << EOF
[org/gnome/nm-applet]
disable-connected-notifications=true
disable-disconnected-notifications=true
suppress-wireless-networks-available=true

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF
echo "[DEBUG] Network settings restrictions file created"

# Create locks to prevent user from changing these settings
echo "[DEBUG] Creating dconf locks directory"
mkdir -p /etc/dconf/db/local.d/locks/
echo "[DEBUG] Creating network settings locks file"
cat > /etc/dconf/db/local.d/locks/network << EOF
/org/gnome/nm-applet/disable-connected-notifications
/org/gnome/nm-applet/disable-disconnected-notifications
/org/gnome/nm-applet/suppress-wireless-networks-available
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
EOF
echo "[DEBUG] Network settings locks file created"

# Update the dconf database
echo "[DEBUG] Updating dconf database"
dconf update || {
  echo "[ERROR] Failed to update dconf database. Network settings restrictions may not be applied."
  # Continue script execution despite error
}

echo "[DEBUG] Network settings restrictions applied successfully"

# Function to configure WiFi
configure_wifi() {
  local ssid="$1"
  local password="$2"
  
  echo "[DEBUG] Configuring WiFi connection for SSID: $ssid"
  
  # Check if NetworkManager is installed
  echo "[DEBUG] Checking if NetworkManager is installed"
  if command -v nmcli &> /dev/null; then
    echo "[DEBUG] NetworkManager found, proceeding with configuration"
    
    # Get the WiFi interface name
    echo "[DEBUG] Getting WiFi interface name"
    local wifi_interface=$(nmcli device status | grep wifi | awk '{print $1}' | head -n 1)
    if [ -z "$wifi_interface" ]; then
      echo "[ERROR] No WiFi interface found. Make sure WiFi hardware is enabled."
      return 1
    fi
    echo "[DEBUG] Found WiFi interface: $wifi_interface"
    
    # Ensure WiFi is enabled
    echo "[DEBUG] Ensuring WiFi is enabled"
    nmcli radio wifi on
    
    # Scan for networks to refresh the list
    echo "[DEBUG] Scanning for WiFi networks"
    nmcli device wifi rescan
    sleep 2  # Give it time to scan
    
    # Check if connection already exists
    echo "[DEBUG] Checking if connection already exists"
    if nmcli -t -f NAME connection show | grep -q "^${ssid}$"; then
      echo "[DEBUG] WiFi connection for $ssid already exists, deleting it first"
      nmcli connection delete "$ssid"
      echo "[DEBUG] Existing connection deleted"
    fi
    
    # Create a new connection with explicit security settings
    echo "[DEBUG] Creating new WiFi connection for $ssid with explicit security settings"
    
    # Create a connection file instead of using the simple connect command
    local UUID=$(uuidgen)
    local CONN_FILE="/etc/NetworkManager/system-connections/${ssid}.nmconnection"
    
    echo "[DEBUG] Creating connection file at $CONN_FILE"
    cat > "$CONN_FILE" << EOF
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
    echo "[DEBUG] Setting permissions for connection file"
    chmod 600 "$CONN_FILE"
    
    # Reload connections
    echo "[DEBUG] Reloading NetworkManager connections"
    nmcli connection reload
    
    # Activate the connection
    echo "[DEBUG] Activating the WiFi connection"
    nmcli connection up "$ssid" || {
      echo "[ERROR] Failed to activate connection. Trying alternative method..."
      # Try alternative method with direct connect
      nmcli device wifi connect "$ssid" password "$password" || {
        echo "[ERROR] Both connection methods failed. Trying fallback method..."
        
        # Create a temporary wpa_supplicant configuration file
        local WPA_CONF="/tmp/wpa_supplicant.conf"
        echo "[DEBUG] Creating wpa_supplicant configuration file"
        wpa_passphrase "$ssid" "$password" > "$WPA_CONF"
        
        if [ $? -eq 0 ]; then
          # Stop NetworkManager temporarily
          echo "[DEBUG] Stopping NetworkManager temporarily"
          systemctl stop NetworkManager
          
          # Connect using wpa_supplicant directly
          echo "[DEBUG] Connecting using wpa_supplicant directly"
          wpa_supplicant -B -i "$wifi_interface" -c "$WPA_CONF"
          
          if [ $? -eq 0 ]; then
            # Get IP address using DHCP
            echo "[DEBUG] Getting IP address using DHCP"
            dhclient "$wifi_interface"
            
            # Clean up
            echo "[DEBUG] Cleaning up temporary files"
            rm -f "$WPA_CONF"
            
            # Restart NetworkManager
            echo "[DEBUG] Restarting NetworkManager"
            systemctl start NetworkManager
            
            # Wait for NetworkManager to start
            sleep 5
            
            # Import the connection into NetworkManager
            echo "[DEBUG] Importing the connection into NetworkManager"
            nmcli connection add type wifi con-name "$ssid" ifname "$wifi_interface" ssid "$ssid" -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
            
            echo "[DEBUG] Fallback WiFi connection created"
          else
            echo "[ERROR] Failed to connect using wpa_supplicant"
            # Clean up and restart NetworkManager
            rm -f "$WPA_CONF"
            systemctl start NetworkManager
            return 1
          fi
        else
          echo "[ERROR] Failed to create wpa_supplicant configuration"
          return 1
        fi
      }
    }
    
    # Verify connection status
    echo "[DEBUG] Verifying connection status"
    if nmcli -t -f GENERAL.STATE connection show "$ssid" 2>/dev/null | grep -q "activated"; then
      echo "[DEBUG] WiFi connection successfully activated"
    else
      echo "[WARNING] Connection created but not activated. It may connect automatically later."
    fi
    
    # Set connection to autoconnect
    echo "[DEBUG] Setting connection to autoconnect"
    nmcli connection modify "$ssid" connection.autoconnect yes
    
    # Set connection to all users
    echo "[DEBUG] Making connection available to all users"
    nmcli connection modify "$ssid" connection.permissions ""
    
    echo "[DEBUG] WiFi configuration completed successfully"
    return 0
  else
    echo "[DEBUG] NetworkManager not found, attempting to install"
    if apt update && apt install -y network-manager; then
      echo "[DEBUG] NetworkManager installed, restarting service"
      systemctl restart NetworkManager
      
      # Wait for NetworkManager to start
      echo "[DEBUG] Waiting for NetworkManager to initialize"
      sleep 5
      
      # Verify NetworkManager is running
      echo "[DEBUG] Verifying NetworkManager is running"
      if systemctl is-active --quiet NetworkManager; then
        echo "[DEBUG] NetworkManager is running, configuring WiFi"
        # Call this function again now that NetworkManager is installed
        configure_wifi "$ssid" "$password"
      else
        echo "[ERROR] NetworkManager service failed to start. WiFi configuration skipped."
        return 1
      fi
    else
      echo "[ERROR] Failed to install NetworkManager. WiFi configuration skipped."
      return 1
    fi
  fi
  return 0
}

# Function to detect WiFi security type
detect_wifi_security() {
  local ssid="$1"
  echo "[DEBUG] Detecting security type for SSID: $ssid"
  
  # Scan for networks
  nmcli device wifi rescan
  sleep 2
  
  # Get security info
  local security_info=$(nmcli -t -f SSID,SECURITY device wifi list | grep "^${ssid}:" | cut -d':' -f2)
  
  if [ -z "$security_info" ]; then
    echo "[WARNING] Could not detect security type for $ssid, assuming WPA"
    echo "WPA"
    return
  fi
  
  echo "[DEBUG] Detected security: $security_info"
  
  if [[ "$security_info" == *"WPA2"* ]]; then
    echo "WPA2"
  elif [[ "$security_info" == *"WPA"* ]]; then
    echo "WPA"
  elif [[ "$security_info" == *"WEP"* ]]; then
    echo "WEP"
  else
    echo "NONE"
  fi
}

# Function to create a persistent WiFi connection
create_persistent_wifi_connection() {
  local ssid="$1"
  local password="$2"
  
  echo "[DEBUG] Creating persistent WiFi connection for $ssid"
  
  # Detect security type
  local security_type=$(detect_wifi_security "$ssid")
  echo "[DEBUG] Using security type: $security_type"
  
  # Create the NetworkManager connection directory if it doesn't exist
  mkdir -p /etc/NetworkManager/system-connections/
  
  # Generate a UUID for the connection
  local UUID=$(uuidgen)
  
  # Get the WiFi interface name
  local wifi_interface=$(nmcli device status | grep wifi | awk '{print $1}' | head -n 1)
  if [ -z "$wifi_interface" ]; then
    echo "[WARNING] No WiFi interface found, using generic configuration"
  else
    echo "[DEBUG] Using WiFi interface: $wifi_interface"
  fi
  
  # Create the connection file
  local CONN_FILE="/etc/NetworkManager/system-connections/${ssid}.nmconnection"
  
  echo "[DEBUG] Creating connection file at $CONN_FILE"
  
  # Create base connection configuration
  cat > "$CONN_FILE" << EOF
[connection]
id=$ssid
uuid=$UUID
type=wifi
EOF

  # Add interface name if available
  if [ -n "$wifi_interface" ]; then
    echo "interface-name=$wifi_interface" >> "$CONN_FILE"
  fi
  
  # Add remaining connection settings
  cat >> "$CONN_FILE" << EOF
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=$ssid

EOF

  # Add security settings based on detected type
  case "$security_type" in
    "WPA2")
      cat >> "$CONN_FILE" << EOF
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password
EOF
      ;;
    "WPA")
      cat >> "$CONN_FILE" << EOF
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password
EOF
      ;;
    "WEP")
      cat >> "$CONN_FILE" << EOF
[wifi-security]
auth-alg=open
key-mgmt=none
wep-key0=$password
wep-key-type=1
EOF
      ;;
    "NONE")
      # No security section needed
      ;;
    *)
      # Default to WPA/WPA2
      cat >> "$CONN_FILE" << EOF
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password
EOF
      ;;
  esac
  
  # Add remaining settings
  cat >> "$CONN_FILE" << EOF

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
  
  # Set proper permissions for the connection file
  echo "[DEBUG] Setting permissions for connection file"
  chmod 600 "$CONN_FILE"
  
  # Reload connections
  echo "[DEBUG] Reloading NetworkManager connections"
  nmcli connection reload
  
  echo "[DEBUG] Persistent WiFi connection created"
  return 0
}

# Function to verify WiFi connection
verify_wifi_connection() {
  local ssid="$1"
  echo "[DEBUG] Verifying WiFi connection to $ssid"
  
  # Check if the connection is active
  if nmcli -t -f GENERAL.STATE connection show "$ssid" 2>/dev/null | grep -q "activated"; then
    echo "[DEBUG] Connection to $ssid is active"
    
    # Check if we have internet connectivity
    echo "[DEBUG] Testing internet connectivity"
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
      echo "[DEBUG] Internet connectivity verified"
      return 0
    else
      echo "[WARNING] Connected to $ssid but no internet connectivity"
      return 1
    fi
  else
    echo "[WARNING] Connection to $ssid is not active"
    return 1
  fi
}

# Configure WiFi
echo "[DEBUG] Feature: WiFi Configuration"
echo "[DEBUG] Checking WiFi configuration settings"

# Ensure required packages are installed
ensure_wifi_packages || {
  echo "[ERROR] Failed to ensure required WiFi packages. WiFi setup may not work properly."
}

# Check if WiFi credentials are provided
echo "[DEBUG] Checking if WiFi credentials are provided in environment file"
if [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PASSWORD" ]; then
  echo "[DEBUG] WiFi credentials not provided in environment file, skipping WiFi setup"
else
  echo "[DEBUG] WiFi credentials found, SSID: $WIFI_SSID"
  # Print environment variables for debugging
  echo "[DEBUG] WIFI_SSID=$WIFI_SSID"
  # Don't print the actual password for security reasons
  echo "[DEBUG] WIFI_PASSWORD=********"
  
  # Create a persistent WiFi connection first
  echo "[DEBUG] Creating persistent WiFi connection"
  create_persistent_wifi_connection "$WIFI_SSID" "$WIFI_PASSWORD"
  
  # Call the WiFi configuration function
  echo "[DEBUG] Calling WiFi configuration function"
  configure_wifi "$WIFI_SSID" "$WIFI_PASSWORD"
  WIFI_CONFIG_STATUS=$?
  echo "[DEBUG] WiFi configuration function completed with status: $WIFI_CONFIG_STATUS"
  
  # Verify the connection if configuration was successful
  if [ $WIFI_CONFIG_STATUS -eq 0 ]; then
    echo "[DEBUG] Verifying WiFi connection"
    verify_wifi_connection "$WIFI_SSID"
    VERIFY_STATUS=$?
    
    if [ $VERIFY_STATUS -eq 0 ]; then
      echo "[DEBUG] WiFi connection successfully verified"
    else
      echo "[WARNING] WiFi connection verification failed. The system may still connect automatically later."
    fi
  fi
fi

echo "[DEBUG] WiFi setup script completed"