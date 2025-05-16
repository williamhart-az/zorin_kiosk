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
- Configures scheduled system reboots for maintenance
- Restricts network settings access for kiosk users

## Installation

1. Clone this repository:
```
git clone https://github.com/williamhart-az/zorin_kiosk/
cd zorin_kiosk
```

2. Copy the example configuration file and modify it to match your requirements:
```
cp .env.example .env
nano .env  # or use your preferred text editor
```

3. Run the setup script with sudo:
```
chmod 755 setup.sh
sudo ./setup.sh
```

4. Reboot your system to apply the changes:
```
sudo reboot
```

## New Feature Selection Menu

The interactive menu system (`setup.sh`) allows you to selectively enable or disable specific features:

- Create Firefox Profile Sync
- Never Sleep Screen
- Clone Admin Profile
- Use Temporary File System
- Setup WiFi
- Setup Reboot Interval
- Uninstall Kiosk Setup

The menu provides an easy-to-use interface where you can:
- Navigate through options using arrow keys
- Toggle features ON/OFF using space or left/right arrow keys
- Run a single feature or all enabled features
- Cancel and exit without making changes

Note that the core user setup feature will always run, as it's required for kiosk functionality.

## Uninstallation

To uninstall the kiosk setup:

1. Run the setup script with sudo:
```
sudo ./setup.sh
```

2. In the menu, select "Uninstall Kiosk Setup" and toggle it to ON (it will automatically set all other features to OFF).

3. Press Enter to run the uninstall process or select "Run All ON" to execute it.

4. Follow the prompts to complete the uninstallation process.

The uninstall process will:
- Disable and remove all systemd services created during installation
- Remove sudoers entries
- Remove scripts from /opt/kiosk
- Remove kiosk user's autostart entries
- Optionally remove the kiosk user account
- Disable autologin configurations

5. Reboot your system to apply the changes:
```
sudo reboot
```

## Configuration

All configuration options are stored in the `.env` file. You can customize:

- Kiosk user details (username, password, full name)
- Admin username
- Display timeout
- WiFi settings
- Browser homepage
- Wallpaper path and name
- Script directories
- Scheduled reboot time and days

### Environment Variables Reference

Below is a comprehensive list of all environment variables used in the kiosk setup scripts:

#### User Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `KIOSK_USERNAME` | The username for the kiosk user account. This is the account that will automatically log in when the system boots. | `kiosk` |
| `KIOSK_PASSWORD` | The password for the kiosk user account. This is needed for initial setup but won't be used for login as auto-login is configured. | `kiosk123` |
| `KIOSK_FULLNAME` | The full name or display name for the kiosk user account. This appears in the user interface where the user's name is displayed. | `Kiosk User` |
| `ADMIN_USERNAME` | The username of the administrative account that will be used to make persistent changes to the kiosk environment. This should be an existing user with sudo privileges. | `localadmin` |

#### Display Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `DISPLAY_TIMEOUT` | The time in seconds before the display would normally time out or go to sleep. The kiosk setup disables this timeout, but this value is used as a reference. | `3600` (1 hour) |

#### Network Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `WIFI_SSID` | The name (SSID) of the WiFi network to connect to. This is used if you want the kiosk to automatically connect to a specific wireless network. | `CompanyWiFi` |
| `WIFI_PASSWORD` | The password for the WiFi network. Make sure to enclose this in single quotes if it contains special characters. | `'P@ssw0rd!'` |

#### Browser Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `HOMEPAGE` | The URL that will be set as the homepage in Firefox. This is the page that will load when Firefox starts or when the home button is clicked. | `https://intranet.company.com` |

#### Appearance Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `WALLPAPER_NAME` | The filename of the wallpaper image to be used for the kiosk desktop. | `Company_Wallpaper.jpg` |
| `WALLPAPER_ADMIN_PATH` | The full path to the wallpaper file in the admin user's home directory. This is used as a source for copying the wallpaper. | `/home/localadmin/Company_Wallpaper.jpg` |
| `WALLPAPER_SYSTEM_PATH` | The full path where the wallpaper will be copied in the system-wide backgrounds directory. | `/usr/share/backgrounds/Company_Wallpaper.jpg` |

#### Directory Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `OPT_KIOSK_DIR` | The directory where kiosk-related scripts and files will be stored. This is a system directory that persists across reboots. | `/opt/kiosk` |
| `TEMPLATE_DIR` | The directory where template files for the kiosk user's home directory are stored. These files are copied to the kiosk user's home directory on each boot. | `/opt/kiosk/templates` |

#### Scheduled Reboot Configuration

| Variable | Description | Example |
|----------|-------------|--------|
| `REBOOT_TIME` | The time of day when the system should automatically reboot, in 24-hour format (HH:MM). Set to `-1` to disable scheduled reboots. | `03:00` (3:00 AM) |
| `REBOOT_DAYS` | The days of the week when the system should reboot. Use `all` for daily reboots, or a comma-separated list of days (0-6, where 0=Sunday). | `1,3,5` (Monday, Wednesday, Friday) |

### Scheduled Reboot Configuration

The kiosk system can be configured to automatically reboot at specified times using the following environment variables:

| Variable | Description | Example |
|----------|-------------|--------|
| `REBOOT_TIME` | The time of day when the system should automatically reboot, in 24-hour format (HH:MM). Set to `-1` to disable scheduled reboots. | `03:00` (3:00 AM) |
| `REBOOT_DAYS` | The days of the week when the system should reboot. Use `all` for daily reboots, or a comma-separated list of days (0-6, where 0=Sunday). | `1,3,5` (Monday, Wednesday, Friday) |

## How It Works

1. The script creates a kiosk user and mounts a tmpfs filesystem for their home directory
2. On boot, the system automatically logs in as the kiosk user
3. The kiosk environment is initialized with the template files
4. Firefox is configured to suppress the first-run wizard and use a specific profile
5. When the system reboots, all changes made by the kiosk user are discarded
6. If configured, the system will automatically reboot at the specified time and days

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

### Firefox Directory Structure

The kiosk setup manages Firefox profiles in several locations:

- Standard Firefox: `~/.mozilla/firefox/`
- Flatpak Firefox: `~/.var/app/org.mozilla.firefox/.mozilla/firefox/`
- Snap Firefox: `~/snap/firefox/common/.mozilla/`

The setup includes multiple scripts to ensure proper ownership and permissions of these directories:

- `firefox.sh`: Creates the initial Firefox profile structure
- `firefox_profile_fix.sh`: Fixes Firefox profile.ini files
- `firefox_ownership_fix.sh`: Ensures correct ownership of Firefox directories
- `firefox_periodic_fix.sh`: Periodically checks and fixes ownership during user sessions

## Display Management

The kiosk setup:

- Prevents screen blanking and display timeout
- Sets a custom timeout period (configurable in the .env file)
- Refreshes settings periodically to ensure they remain active

## Network Restrictions

The kiosk setup:

- Hides network settings from the kiosk user
- Disables network notifications
- Prevents the system from going to sleep

## Troubleshooting

If you encounter issues:

1. Check the log files in `/tmp/` (kiosk_init.log, firefox_profile_setup.log)
2. Verify that the display manager is properly configured for autologin
3. Ensure the Firefox profile is correctly set up
4. Check system logs: `journalctl -xe`
5. For scheduled reboot issues, check `/var/log/kiosk_reboot.log`

### Common Firefox Issues

#### Firefox Profile Ownership

If Firefox fails to start or shows permission errors, the profile directory ownership might be incorrect. To fix this:

1. Check the ownership of the Firefox directories:
   ```bash
   ls -la ~/.var/app/org.mozilla.firefox
   ```

2. If the directories are owned by root instead of the kiosk user, run the Firefox ownership fix script:
   ```bash
   sudo /opt/kiosk/periodic_firefox_fix.sh
   ```

3. Alternatively, manually fix the ownership:
   ```bash
   sudo chown -R kiosk:kiosk ~/.var
   sudo chown -R kiosk:kiosk ~/.var/app
   sudo chown -R kiosk:kiosk ~/.var/app/org.mozilla.firefox
   ```

#### Firefox Profile Not Loading

If Firefox starts with a blank profile or first-run wizard:

1. Check if the profile.ini file exists:
   ```bash
   cat ~/.mozilla/firefox/profiles.ini
   ```

2. Run the Firefox profile fix script:
   ```bash
   sudo features/firefox_profile_fix.sh
   ```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.