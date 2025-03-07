#!/bin/bash

# Initialize terminal
tput init
clear

# Menu items and their initial states (0 = OFF, 1 = ON)
menu_items=("Feature 1" "Feature 2" "Feature 3" "Run All ON" "Cancel")
states=(1 0 1 0 0)  # Initial states: Feature 1 ON, Feature 2 OFF, Feature 3 ON
selected=0
total_items=${#menu_items[@]}

draw_menu() {
    clear
    echo "=== Feature Control Interface ==="
    echo "Up/Down: Select item | Left/Right/Space: Toggle ON/OFF"
    echo "Enter on feature: Run only that feature (if ON) | 'Run All ON': Run all ON features | 'Cancel': Exit"
    echo "--------------------------------"
    for i in "${!menu_items[@]}"; do
        if [ $i -eq $selected ]; then
            tput setaf 2  # Green for selected item
            if [ $i -lt 3 ]; then  # Only show state for features
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
            if [ $i -lt 3 ]; then
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
    if [ $selected -lt 3 ]; then  # Only toggle features
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
        script_name=$(echo "${menu_items[$selected]}" | tr ' ' '_')
        echo "Running: ./$script_name.sh enable"
        echo "--------------------------------"
        ./$script_name.sh enable
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
    local has_on=0
    for i in {0..2}; do  # Only check features (0-2)
        if [ ${states[$i]} -eq 1 ]; then
            echo "- ${menu_items[$i]}"
            has_on=1
        fi
    done
    if [ $has_on -eq 0 ]; then
        echo "(No features are ON)"
    fi
    echo "--------------------------------"
    if [ $has_on -eq 1 ]; then
        echo "Executing now..."
        echo "--------------------------------"
        for i in {0..2}; do
            if [ ${states[$i]} -eq 1 ]; then
                script_name=$(echo "${menu_items[$i]}" | tr ' ' '_')
                echo "Running: ./$script_name.sh enable"
                ./$script_name.sh enable
                sleep 1  # Optional: delay for visibility
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
            if [ $selected -lt 3 ]; then  # Feature selected
                run_single_feature
            elif [ $selected -eq 3 ]; then  # Run All ON selected
                run_all_on
            elif [ $selected -eq 4 ]; then  # Cancel selected
                clear
                echo "=== Operation Cancelled ==="
                echo "No features were executed."
                echo "Exiting now."
                sleep 2  # Brief pause for user to read
                exit 0
            fi
            ;;
        $'\x1b') # Escape key - Also cancel
            clear
            echo "=== Operation Cancelled ==="
            echo "No features were executed."
            echo "Exiting now."
            sleep 2
            exit 0
            ;;
    esac
done