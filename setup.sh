#!/bin/bash

# Initialize terminal
tput init
clear

# Setup logging
LOG_FILE="setup.log"
ENABLE_LOGGING=true

# Process command line arguments
for arg in "$@"; do
  case $arg in
    --nolog)
      ENABLE_LOGGING=false
      shift
      ;;
  esac
done

# Initialize log file if logging is enabled
if $ENABLE_LOGGING; then
  echo "=== Kiosk Setup Log $(date) ===" > "$LOG_FILE"
  echo "Command: $0 $@" >> "$LOG_FILE"
  echo "----------------------------------------" >> "$LOG_FILE"
fi

# Function to log messages
log_message() {
  local message="$1"
  local level="${2:-INFO}"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  if $ENABLE_LOGGING; then
    echo "[$level] $timestamp - $message" >> "$LOG_FILE"
  fi
  
  # Only print non-DEBUG messages to the console
  if [ "$level" != "DEBUG" ]; then
    echo "[$level] $message"
  fi
}

# Function to run a command with logging
run_with_logging() {
  local cmd="$1"
}

echo "=== ZorinOS Kiosk Setup ==="
echo "This script will configure your system for kiosk mode with desktop access."
echo "WARNING: This is meant for dedicated kiosk systems only!"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_message "Setup cancelled by user" "INFO"
  echo "Setup cancelled."
  exit 1
fi

run_with_logging() {
  local cmd="$1"
  local feature_name="$2"
  local script_name="$3"
  
  log_message "Installing $feature_name (using $script_name)" "INFO"
  
  if $ENABLE_LOGGING; then
    # Run the command and capture output to log file
    echo "----------------------------------------" >> "$LOG_FILE"
    echo "Running: $cmd" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
    
    # Execute command, tee output to log file, and capture exit status
    set -o pipefail
    output=$($cmd 2>&1 | tee -a "$LOG_FILE")
    exit_status=$?
    set +o pipefail
    
    echo "----------------------------------------" >> "$LOG_FILE"
    log_message "Command completed with status: $exit_status" "DEBUG"
    
    return $exit_status
  else
    # Run the command normally
    $cmd
    return $?
  fi
}

# Function to ensure all scripts have execution permissions
ensure_script_permissions() {
  log_message "Checking and setting execution permissions for all scripts" "INFO"
  
  # Make kiosk_setup.sh executable
  if [ -f "./kiosk_setup.sh" ]; then
    chmod 755 ./kiosk_setup.sh
    log_message "Set execution permission for kiosk_setup.sh" "DEBUG"
  else
    log_message "Warning: kiosk_setup.sh not found" "WARN"
  fi
  
  # Check if features directory exists
  if [ ! -d "./features" ]; then
    log_message "Error: Features directory not found" "ERROR"
    echo "[ERROR] Features directory not found. Please ensure you're running this script from the correct location."
    exit 1
  fi
  
  # Make all scripts in features directory executable
  log_message "Setting execution permissions for all scripts in features directory" "DEBUG"
  find ./features -name "*.sh" -type f -exec chmod 755 {} \;
  
  # Verify permissions were set correctly
  local failed_scripts=()
  
  # Check kiosk_setup.sh
  if [ -f "./kiosk_setup.sh" ] && [ ! -x "./kiosk_setup.sh" ]; then
    failed_scripts+=("kiosk_setup.sh")
  fi
  
  # Check all scripts in features directory
  for script in ./features/*.sh; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
      failed_scripts+=("$script")
    fi
  done
  
  # Report any failures
  if [ ${#failed_scripts[@]} -gt 0 ]; then
    log_message "Failed to set execution permissions for some scripts" "ERROR"
    echo "[ERROR] Failed to set execution permissions for the following scripts:"
    for script in "${failed_scripts[@]}"; do
      echo "  - $script"
    done
    echo "Please ensure you have sufficient permissions to modify these files."
    exit 1
  fi
  
  log_message "All scripts now have proper execution permissions" "INFO"
}

# Menu items and their initial states (0 = OFF, 1 = ON)

# First, ensure all scripts have proper execution permissions
ensure_script_permissions

menu_items=(
    "Setup WiFi"
    "Create Firefox Profile Sync"
    "Clone Admin Profile"
    "Never Sleep Screen"   
    "Use Temporary File System"
    "Reboot Interval"
    "Uninstall Kiosk Setup"
    "Run All ON" 
    "Cancel"
)
# Script names corresponding to menu items
script_names=(
    "wifi.sh"
    "firefox.sh"

    "master_profile.sh"
    "idle_delay.sh"
    "tmpfs.sh"
    "scheduled_reboot.sh"
    "uninstall.sh"
)
# Initial states for all features (0 = OFF, 1 = ON)
states=(1 1 1 1 1 1 1 1 1 1 0 0 0)  # Default all features ON, uninstall OFF
selected=0
total_items=${#menu_items[@]}
feature_count=$((total_items-2))  # Number of actual features (excluding Run All and Cancel)

draw_menu() {
    clear
    echo "=== Kiosk Setup Feature Control Interface ==="
    echo "Up/Down: Select item | Left/Right/Space: Toggle ON/OFF"
    echo "Enter on feature: Run only that feature (if ON) | 'Run All ON': Run all ON features | 'Cancel': Exit"
    echo "--------------------------------"
    echo "Note: features/user_setup.sh will always run (required for Kiosk user creation) unless Uninstall is ON"
    echo "--------------------------------"
    for i in "${!menu_items[@]}"; do
        if [ $i -eq $selected ]; then
            tput setaf 2  # Green for selected item
            if [ $i -lt $feature_count ]; then  # Only show state for features
                if [ $i -eq 10 ]; then  # Uninstall option
                    if [ "${states[$i]}" -eq 1 ]; then
                        tput setaf 1  # Red for uninstall when ON
                        echo "> ${menu_items[$i]} [ON]"
                    else
                        echo "> ${menu_items[$i]} [OFF]"
                    fi
                else
                    if [ "${states[$i]}" -eq 1 ]; then
                        echo "> ${menu_items[$i]} [ON]"
                    else
                        echo "> ${menu_items[$i]} [OFF]"
                    fi
                fi
            else
                echo "> ${menu_items[$i]}"
            fi
            tput sgr0     # Reset color
        else
            if [ $i -lt $feature_count ]; then
                if [ $i -eq 10 ]; then  # Uninstall option
                    if [ "${states[$i]}" -eq 1 ]; then
                        tput setaf 1  # Red for uninstall when ON
                        echo "  ${menu_items[$i]} [ON]"
                        tput sgr0     # Reset color
                    else
                        echo "  ${menu_items[$i]} [OFF]"
                    fi
                else
                    if [ "${states[$i]}" -eq 1 ]; then
                        echo "  ${menu_items[$i]} [ON]"
                    else
                        echo "  ${menu_items[$i]} [OFF]"
                    fi
                fi
            else
                echo "  ${menu_items[$i]}"
            fi
        fi
    done
    echo "--------------------------------"
}

toggle_state() {
    if [ $selected -lt $feature_count ]; then  # Only toggle features
        if [ ${states[$selected]} -eq 1 ]; then
            states[$selected]=0
        else
            states[$selected]=1
            
            # If uninstall is being turned ON, turn all other features OFF
            if [ $selected -eq 6 ]; then  # Uninstall is at index 6
                for i in $(seq 0 5); do # Indices 0 to 5 are the features before uninstall
                    states[$i]=0
                done
            fi
        fi
    fi
}

run_single_feature() {
    clear
    echo "=== Running Single Feature ==="
    echo "Selected feature: ${menu_items[$selected]}"
    echo "--------------------------------"
    
    # Special handling for uninstall feature
    if [ $selected -eq 10 ]; then  # Uninstall is at index 10
        if [ ${states[$selected]} -eq 1 ]; then
            script_path="features/${script_names[$selected]}"
            log_message "Running uninstall: ${menu_items[$selected]}" "INFO"
            log_message "Handing control to uninstall script..." "INFO"
            echo "--------------------------------"
            echo "Handing control to uninstall script. Setup will exit."
            
            # Execute uninstall directly (not as a subprocess)
            if $ENABLE_LOGGING; then
                exec "$script_path" enable
            else
                exec "$script_path" enable --nolog
            fi
            # Note: exec replaces the current process, so the code below won't run
            # unless the exec fails
            echo "Error: Failed to execute uninstall script."
            exit 1
        else
            echo "Feature is OFF - nothing to run."
            log_message "Feature ${menu_items[$selected]} is OFF - nothing to run" "DEBUG"
        fi
    else
        # For non-uninstall features
        if [ ${states[$selected]} -eq 1 ]; then
            # Run user_setup.sh first if this is not the uninstall feature
            log_message "Running required user setup" "INFO"
            run_with_logging "features/user_setup.sh enable" "User Setup" "user_setup.sh"
            
            # Then run the selected feature
            script_path="features/${script_names[$selected]}"
            log_message "Running single feature: ${menu_items[$selected]}" "INFO"
            run_with_logging "$script_path enable" "${menu_items[$selected]}" "${script_names[$selected]}"
            echo "--------------------------------"
            echo "Execution complete!"
        else
            echo "Feature is OFF - nothing to run."
            log_message "Feature ${menu_items[$selected]} is OFF - nothing to run" "DEBUG"
        fi
    fi
    
    echo "Press Enter to return to menu"
    read
}

run_all_on() {
    clear
    echo "=== Executing All ON Features ==="
    echo "The following features are set to ON and will be executed:"
    echo "--------------------------------"
    
    # Check if uninstall is ON
    local uninstall_on=0
    if [ ${states[6]} -eq 1 ]; then  # Uninstall is at index 6
        uninstall_on=1
        echo "- Uninstall Kiosk Setup"
    else
        echo "- features/user-setup.sh (always runs)"
    fi
    
    local has_on=0
    for i in $(seq 0 $((feature_count-1))); do  # Check all features
        # Skip uninstall in this loop as we've already handled it
        if [ $i -eq 6 ]; then
            continue
        fi
        
        if [ ${states[$i]} -eq 1 ]; then
            echo "- ${menu_items[$i]}"
            has_on=1
        fi
    done
    if [ $has_on -eq 0 ] && [ $uninstall_on -eq 0 ]; then
        echo "(No additional features are ON)"
    fi
    echo "--------------------------------"
    
    # If uninstall is ON, don't run user_setup.sh
    if [ $uninstall_on -eq 0 ]; then
        # Always run the user_setup.sh script
        log_message "Running required user setup" "INFO"
        run_with_logging "features/user_setup.sh enable" "User Setup" "user_setup.sh"
    fi
    
    # Special handling if uninstall is ON
    if [ $uninstall_on -eq 1 ]; then
        log_message "Uninstall is ON - handing control to uninstall script" "INFO"
        echo "Uninstall is ON - handing control to uninstall script"
        echo "--------------------------------"
        echo "Handing control to uninstall script. Setup will exit."
        
        # Execute uninstall directly (not as a subprocess)
        if $ENABLE_LOGGING; then
            exec "features/uninstall.sh" enable
        else
            exec "features/uninstall.sh" enable --nolog
        fi
        # Note: exec replaces the current process, so the code below won't run
        # unless the exec fails
        echo "Error: Failed to execute uninstall script."
        exit 1
    elif [ $has_on -eq 1 ]; then
        log_message "Executing additional features..." "DEBUG"
        echo "Executing additional features..."
        echo "--------------------------------"
        for i in $(seq 0 $((feature_count-1))); do
            if [ ${states[$i]} -eq 1 ]; then
                script_path="features/${script_names[$i]}"
                run_with_logging "$script_path enable" "${menu_items[$i]}" "${script_names[$i]}"
                sleep 1  # Brief delay between feature executions
            fi
        done
        echo "--------------------------------"
        echo "Execution complete!"
        log_message "All features execution complete" "DEBUG"
    fi
    echo "Press Enter to return to menu"
    read
}

while true; do
    draw_menu
    
    # Read single key press
    read -rsn1 key
    
    case "$key" in
        $'\x1b') # Escape sequence for arrow keys
            read -rsn2 -t 0.1 key2
            case "$key2" in
                "[A") # Up arrow - Move up
                    ((selected--))
                    [ $selected -lt 0 ] && selected=$((total_items-1))
                    ;;
                "[B") # Down arrow - Move down
                    ((selected++))
                    [ $selected -ge $total_items ] && selected=0
                    ;;
                "[D") # Left arrow - Toggle
                    toggle_state
                    ;;
                "[C") # Right arrow - Toggle
                    toggle_state
                    ;;
            esac
            ;;
        " ") # Space key - Toggle
            toggle_state
            ;;
        "") # Enter key
            if [ $selected -lt $feature_count ]; then  # Feature selected
                run_single_feature
            elif [ $selected -eq $feature_count ]; then  # Run All ON selected
                run_all_on
            elif [ $selected -eq $((feature_count+1)) ]; then  # Cancel selected
                clear
                echo "=== Operation Cancelled ==="
                echo "No features were executed."
                echo "Exiting now."
                sleep 2  # Brief pause for user to read
                exit 0
            fi
            ;;
        "q") # q key - Also cancel
            clear
            echo "=== Operation Cancelled ==="
            echo "No features were executed."
            echo "Exiting now."
            sleep 2
            exit 0
            ;;
    esac
done
