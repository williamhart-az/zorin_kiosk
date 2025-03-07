#!/bin/bash

# Initialize terminal
tput init
clear

# Menu items
menu_items=("Use Temporay File System [ON]" "Schedule Reboot [OFF]" "WiFi Configuration [ON]" "Exit")
selected=0
total_items=${#menu_items[@]}

draw_menu() {
    clear
    for i in "${!menu_items[@]}"; do
        if [ $i -eq $selected ]; then
            tput setaf 2 # Green color
            echo "> ${menu_items[$i]}"
            tput sgr0    # Reset color
        else
            echo "  ${menu_items[$i]}"
        fi
    done
}

while true; do
    draw_menu
    
    # Read single key press
    read -rsn1 key
    
    case "$key" in
        $'\x1b') # Escape sequence for arrow keys
            read -rsn2 -t 0.1 key2
            case "$key2" in
                "[A") # Up arrow
                    ((selected--))
                    [ $selected -lt 0 ] && selected=$((total_items-1))
                    ;;
                "[B") # Down arrow
                    ((selected++))
                    [ $selected -ge $total_items ] && selected=0
                    ;;
            esac
            ;;
        "") # Enter key
            case $selected in
                0) echo "Toggling TempFS"; features/tmpfs.sh ;;
                1) echo "Toggling Daily Reboot"; features/scheduled_reboot.sh ;;
                2) echo "Toggling WiFi Setup"; features/wifi_setup.sh ;;
                3) clear; exit 0 ;;
            esac
            read -p "Press enter to continue"
            ;;
    esac
done