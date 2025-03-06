# ZorinOS Kiosk Setup

This repository contains scripts to set up a ZorinOS system as a kiosk with desktop environment access.

## Features

- Creates a dedicated kiosk user with automatic login
- Mounts a tmpfs filesystem for the kiosk user's home directory (reset on reboot)
- Configures Firefox to suppress the first-run wizard and set a custom homepage
- Prevents screen blanking and display timeout
- Sets a custom wallpaper
- Allows admin changes to be saved to a template directory
- Supports both regular and Flatpak Firefox installations
- Automatically detects and configures the display manager (LightDM, GDM, or SDDM)

## Installation

1. Clone this repository:
git clone https://github.com/williamhart-az/zorinos-kiosk-setup.git
cd zorinos-kiosk-setup
2. Review and modify the configuration in `kiosk_setup.env` to match your requirements.

3. Run the setup script with sudo:
sudo bash kiosk_setup.sh
4. Reboot your system to apply the changes:
sudo reboot
## Configuration

All configuration options are stored in the `kiosk_setup.env` file. You can customize:

- Kiosk user details (username, password, full name)
- Admin username
- Display timeout
- WiFi settings
- Browser homepage
- Wallpaper path and name
- Script directories

## How It Works

1. The script creates a kiosk user and mounts a tmpfs filesystem for their home directory
2. On boot, the system automatically logs in as the kiosk user
3. The kiosk environment is initialized with the template files
4. Firefox is configured to suppress the first-run wizard and use a specific profile
5. When the system reboots, all changes made by the kiosk user are discarded

## Admin Changes

To make persistent changes to the kiosk environment:

1. Log in as the admin user
2. Make your desired changes
3. The changes will be automatically saved to the template directory
4. Reboot the system to apply the changes to the kiosk environment

## Firefox Configuration

The script handles both regular and Flatpak Firefox installations:

- Detects the installation type automatically
- Creates a profile with appropriate settings
- Disables the first-run wizard and welcome screens
- Sets the homepage to the configured URL
- Configures privacy settings to clear data on shutdown

## Display Management

The kiosk setup:

- Prevents screen blanking and display timeout
- Sets a custom timeout period (configurable in the .env file)
- Refreshes settings periodically to ensure they remain active

## Troubleshooting

If you encounter issues:

1. Check the log files in `/tmp/` (kiosk_init.log, firefox_profile_setup.log)
2. Verify that the display manager is properly configured for autologin
3. Ensure the Firefox profile is correctly set up
4. Check system logs: `journalctl -xe`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.