# Hoyo Registry Manager

## Overview

Hoyo Registry Manager is a PowerShell script designed to manage different versions of miHoYo SDK and miHoYo registry keys. This is particularly useful for users who need to switch between multiple game accounts (e.g., for Genshin Impact, Honkai: Star Rail, Zenless Zone Zero, Honkai Impact 3rd) and encounter login or 2FA issues due to shared registry settings.

The script allows users to:
- **Save (Export)** current miHoYo-related registry configurations as named profiles.
- **Load (Import)** previously saved profiles to quickly switch account settings.
- **Manage Profiles**: Edit profile names or delete profiles.
- **Delete Live Registry Keys**: Remove current registry settings, either with or without first saving them to a new profile.
- **Configure**: Customize which registry keys are managed by the script and set a default profile name.

## Features

- **Profile Management**: Save multiple registry configurations and easily switch between them.
- **Backup System**: Automatically creates backups of current registry keys before loading a profile or deleting live keys. It keeps the last 10 backups for each key type.
- **User-Friendly Interface**: A simple command-line menu to navigate through options.
- **Configurable**: Users can choose which specific game registry keys to include in profiles.
- **Safe Deletion**: Options to delete live registry keys with or without creating a backup profile, including warnings for potentially risky operations.

## Managed Registry Keys

By default, the script is configured to manage the following registry keys:

- [x] `HKCU\\Software\\miHoYoSDK` (miHoYo SDK)
- [x] `HKEY_CURRENT_USER\\Software\\miHoYo\\Genshin Impact` (Genshin Impact)
- [x] `HKEY_CURRENT_USER\\Software\\Cognosphere\\Star Rail` (Honkai: Star Rail)
- [x] `HKEY_CURRENT_USER\\Software\\miHoYo\\ZenlessZoneZero` (Zenless Zone Zero)
- [x] `HKEY_CURRENT_USER\\Software\\miHoYo\\Honkai Impact 3rd` (Honkai Impact 3rd)
- [ ] `HKEY_CURRENT_USER\\Software\\Cognosphere\\HYP` (HoyoPlay)

Users can customize which of these keys are actively managed via the script's "Options" menu.

## Storage Location

- Profiles and configuration data are stored in the user's home directory: `%USERPROFILE%\\.HoyoRegistryManagerProfiles`
  - Profile data: `profile_data` subdirectory
  - Backups: `backups` subdirectory
  - Configuration: `config.json`
  - Profiles metadata: `profiles.json`

## Prerequisites

- Windows PowerShell 5.1 or higher.

## How to Use

1.  **Download** the `HoyoRegistryManager.ps1` script.
2.  **Open PowerShell**: Navigate to the directory where you saved the script.
3.  **Run the script**:
    ```powershell
    .\HoyoRegistryManager.ps1
    ```
4.  **Follow the on-screen menu** to:
    *   **Save Current Profile**: Exports the current state of the selected registry keys to a new profile.
    *   **Load Profile**: Imports a previously saved profile, restoring those registry settings.
    *   **Manage Profiles**: Rename or delete existing profiles.
    *   **Delete Current Registry Settings**: Removes the live registry keys (with an option to save them first). This can be useful for a "clean" login state.
    *   **Options**: Configure the default profile name and select which registry keys the script should manage.

## Quick Run from GitHub

You can also try to run the script directly from GitHub without downloading it first. Open PowerShell and run the following command:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Invoke-Expression (New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/Alb11747/HoyoRegistryManager/refs/heads/main/HoyoRegistryManager.ps1")
```

## Important Notes

-   **Registry Modification**: This script directly modifies the Windows Registry. While it includes backup mechanisms, incorrect use or modification of the script could potentially lead to issues with your game installations or other software. Use with caution.
-   **Backups**: Backups are created in the `%USERPROFILE%\\.HoyoRegistryManagerProfiles\\backups` directory. If you suspect an issue after loading a profile or deleting keys, you might be able to manually restore a `.reg` file from this location by double-clicking it.

## Disclaimer

This script is provided as-is. The author is not responsible for any damage or loss of data that may occur from its use. Always ensure you understand what the script does before running it, especially operations that modify the registry.
