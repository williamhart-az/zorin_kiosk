#!/bin/bash

# Initialize terminal
tput init
clear

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
        echo "Running: $script_path enable"
        echo "--------------------------------"
        $script_path enable
        echo "--------------------------------"
        echo "Execution complete!"
    else
        echo "Feature is OFF - nothing to run."
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
    echo "Running: features/user-setup.sh enable"
    features/user-setup.sh enable
    
    if [ $has_on -eq 1 ]; then
        echo "Executing additional features..."
        echo "--------------------------------"
        for i in $(seq 0 $((feature_count-1))); do
            if [ ${states[$i]} -eq 1 ]; then
                script_path="features/${script_names[$i]}"
                echo "Running: $script_path enable"
                $script_path enable
                sleep 1  # Brief delay between feature executions
            fi
        done
        echo "--------------------------------"
        echo "Execution complete!"
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