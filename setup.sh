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

# Menu items and their initial states (0 = OFF, 1 = ON)
menu_items=(
    "Create Firefox Profile Sync" 
    "Never Sleep Screen" 
    "Clone Admin Profile" 
    "Use Temporary File System" 
    "Setup WiFi" 
    "Setup Reboot Interval" 
    "Run All ON" 
    "Cancel"
)
# Script names corresponding to menu items
script_names=(
    "Firefox.sh"
    "idle-delay.sh"
    "master-profile.sh"
    "tmpfs.sh"
    "wifi.sh"
    "schedule_reboot.sh"
)
# Initial states for all features (0 = OFF, 1 = ON)
states=(1 1 1 1 1 1 0 0)  # Default all features ON
selected=0
total_items=${#menu_items[@]}
feature_count=$((total_items-2))  # Number of actual features (excluding Run All and Cancel)

draw_menu() {
    clear
    echo "=== Kiosk Setup Feature Control Interface ==="
    echo "Up/Down: Select item | Left/Right/Space: Toggle ON/OFF"
    echo "Enter on feature: Run only that feature (if ON) | 'Run All ON': Run all ON features | 'Cancel': Exit"
    echo "--------------------------------"
    echo "Note: features/user-setup.sh will always run (required for Kiosk user creation)"
    echo "--------------------------------"
    for i in "${!menu_items[@]}"; do
        if [ $i -eq $selected ]; then
            tput setaf 2  # Green for selected item
            if [ $i -lt $feature_count ]; then  # Only show state for features
                if [ "${states[$i]}" -eq 1 ]; then
                    echo "> ${menu_items[$i]} [ON]"
                else
                    echo "> ${menu_items[$i]} [OFF]"
                fi
            else
                echo "> ${menu_items[$i]}"
            fi
            tput sgr0     # Reset color
        else
            if [ $i -lt $feature_count ]; then
                if [ "${states[$i]}" -eq 1 ]; then
                    echo "  ${menu_items[$i]} [ON]"
                else
                    echo "  ${menu_items[$i]} [OFF]"
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
        fi
    fi
}

run_single_feature() {
    clear
    echo "=== Running Single Feature ==="
    echo "Selected feature: ${menu_items[$selected]}"
    echo "--------------------------------"
    if [ ${states[$selected]} -eq 1 ]; then
        script_path="features/${script_names[$selected]}"
        log_message "Running single feature: ${menu_items[$selected]}" "INFO"
        run_with_logging "$script_path enable" "${menu_items[$selected]}" "${script_names[$selected]}"
        echo "--------------------------------"
        echo "Execution complete!"
    else
        echo "Feature is OFF - nothing to run."
        log_message "Feature ${menu_items[$selected]} is OFF - nothing to run" "DEBUG"
    fi
    echo "Press Enter to return to menu"
    read
}

run_all_on() {
    clear
    echo "=== Executing All ON Features ==="
    echo "The following features are set to ON and will be executed:"
    echo "--------------------------------"
    echo "- features/user-setup.sh (always runs)"
    local has_on=0
    for i in $(seq 0 $((feature_count-1))); do  # Check all features
        if [ ${states[$i]} -eq 1 ]; then
            echo "- ${menu_items[$i]}"
            has_on=1
        fi
    done
    if [ $has_on -eq 0 ]; then
        echo "(No additional features are ON)"
    fi
    echo "--------------------------------"
    
    # Always run the user-setup.sh script
    log_message "Running required user setup" "INFO"
    run_with_logging "features/user-setup.sh enable" "User Setup" "user-setup.sh"
    
    if [ $has_on -eq 1 ]; then
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