#Requires -Version 5.1
<#
.SYNOPSIS
Manages different versions of miHoYo SDK and miHoYo registry keys for account switching.
.DESCRIPTION
This script allows users to save (export) and load (import) specific miHoYo-related registry configurations.
It helps in managing multiple game accounts that might have login or 2FA issues due to shared registry settings.
Profiles are stored in the user's home directory under HoyoRegistryManagerProfiles.
Backups of current registry keys are created before loading a profile or deleting live keys, keeping the last 10 backups per key type.
#>

#region Global Variables and Configuration
$Global:BaseDir = Join-Path $env:USERPROFILE ".HoyoRegistryManagerProfiles"
$Global:ProfileDataDir = Join-Path $Global:BaseDir "profile_data"
$Global:BackupDir = Join-Path $Global:BaseDir "backups"
$Global:ConfigFile = Join-Path $Global:BaseDir "config.json"
$Global:ProfilesFile = Join-Path $Global:BaseDir "profiles.json"

# Define the registry keys that can be managed by this script
$Global:DefaultManagedKeys = @(
    @{ Path = "HKCU\Software\miHoYoSDK"; UserFriendlyName = "miHoYo SDK (Common)"; IsIncludedByDefault = $true; FileName = "miHoYoSDK.reg" },
    # @{ Path = "HKCU\Software\miHoYo"; UserFriendlyName = "miHoYo (Genshin, ZZZ, Hi3)"; IsIncludedByDefault = $true; FileName = "miHoYo.reg" },
    # @{ Path = "HKEY_CURRENT_USER\Software\Cognosphere"; UserFriendlyName = "Cognosphere (HSR)"; IsIncludedByDefault = $true; FileName = "Cognosphere.reg" },
    @{ Path = "HKEY_CURRENT_USER\Software\miHoYo\Genshin Impact"; UserFriendlyName = "Genshin Impact"; IsIncludedByDefault = $true; FileName = "miHoYo_GenshinImpact.reg" },
    @{ Path = "HKEY_CURRENT_USER\Software\Cognosphere\Star Rail"; UserFriendlyName = "Honkai: Star Rail"; IsIncludedByDefault = $true; FileName = "Cognosphere_StarRail.reg" },
    @{ Path = "HKEY_CURRENT_USER\Software\miHoYo\ZenlessZoneZero"; UserFriendlyName = "Zenless Zone Zero"; IsIncludedByDefault = $true; FileName = "miHoYo_ZenlessZoneZero.reg" },
    @{ Path = "HKEY_CURRENT_USER\Software\miHoYo\Honkai Impact 3rd"; UserFriendlyName = "Honkai Impact 3rd"; IsIncludedByDefault = $true; FileName = "miHoYo_HonkaiImpact3rd.reg" },
    @{ Path = "HKEY_CURRENT_USER\Software\Cognosphere\HYP"; UserFriendlyName = "HoyoPlay"; IsIncludedByDefault = $false; FileName = "Cognosphere_HYP.reg" }
    # Add more keys here if needed in the future
)

$Global:MaxBackups = 10

# Default configuration structure
$Global:DefaultConfig = @{
    DefaultProfileName = "DefaultProfile"
    ManagedKeys        = @() # This will be populated from DefaultManagedKeys
}

$Global:CurrentConfig = $null
$Global:Profiles = @() # Array of [pscustomobject]
#endregion Global Variables and Configuration

#region Helper Functions
function Initialize-ScriptEnvironment {
    if (-not (Test-Path $Global:BaseDir)) {
        Write-Verbose "Creating base directory: $Global:BaseDir"
        New-Item -ItemType Directory -Path $Global:BaseDir -Force | Out-Null
    }
    if (-not (Test-Path $Global:ProfileDataDir)) {
        Write-Verbose "Creating profile data directory: $Global:ProfileDataDir"
        New-Item -ItemType Directory -Path $Global:ProfileDataDir -Force | Out-Null
    }
    if (-not (Test-Path $Global:BackupDir)) {
        Write-Verbose "Creating backup directory: $Global:BackupDir"
        New-Item -ItemType Directory -Path $Global:BackupDir -Force | Out-Null
    }

    Get-Configuration
    Get-ProfilesMetadata
}

function Get-Configuration {
    # Initialize DefaultConfig.ManagedKeys from DefaultManagedKeys
    $Global:DefaultConfig.ManagedKeys = $Global:DefaultManagedKeys | ForEach-Object {
        [pscustomobject]@{
            Path             = $_.Path
            UserFriendlyName = $_.UserFriendlyName
            IsIncluded       = $_.IsIncludedByDefault # Note: This is 'IsIncluded' for current state
            FileName         = $_.FileName
        }
    }

    if (Test-Path $Global:ConfigFile) {
        try {
            $LoadedConfig = Get-Content $Global:ConfigFile | ConvertFrom-Json -ErrorAction Stop
            $Global:CurrentConfig = $Global:DefaultConfig.Clone() # Start with default structure
            
            # Overwrite with loaded values if they exist
            if ($LoadedConfig.PSObject.Properties['DefaultProfileName']) {
                $Global:CurrentConfig.DefaultProfileName = $LoadedConfig.DefaultProfileName
            }

            # Sync ManagedKeys
            $UpdatedManagedKeys = @()
            foreach ($defaultKeyEntry in $Global:DefaultManagedKeys) {
                $loadedKeyEntry = $null
                if ($LoadedConfig.PSObject.Properties['ManagedKeys'] -and $LoadedConfig.ManagedKeys -is [array]) {
                    $loadedKeyEntry = $LoadedConfig.ManagedKeys | Where-Object { $_.Path -eq $defaultKeyEntry.Path } | Select-Object -First 1
                }

                if ($loadedKeyEntry -and $loadedKeyEntry.PSObject.Properties['IsIncluded']) {
                    $UpdatedManagedKeys += [pscustomobject]@{
                        Path             = $defaultKeyEntry.Path
                        UserFriendlyName = $defaultKeyEntry.UserFriendlyName
                        IsIncluded       = $loadedKeyEntry.IsIncluded # Use loaded inclusion status
                        FileName         = $defaultKeyEntry.FileName
                    }
                }
                else {
                    # Key not in config or malformed, use default
                    $UpdatedManagedKeys += [pscustomobject]@{
                        Path             = $defaultKeyEntry.Path
                        UserFriendlyName = $defaultKeyEntry.UserFriendlyName
                        IsIncluded       = $defaultKeyEntry.IsIncludedByDefault
                        FileName         = $defaultKeyEntry.FileName
                    }
                }
            }
            $Global:CurrentConfig.ManagedKeys = $UpdatedManagedKeys

        }
        catch {
            Write-Warning "Failed to load or parse configuration file. Using default configuration. Error: $($_.Exception.Message)"
            $Global:CurrentConfig = $Global:DefaultConfig.Clone() 
        }
    }
    else {
        Write-Verbose "Configuration file not found. Using default configuration."
        $Global:CurrentConfig = $Global:DefaultConfig.Clone()
    }
    Save-Configuration # Save to ensure file exists and has all keys correctly formatted
}

function Save-Configuration {
    try {
        $Global:CurrentConfig | ConvertTo-Json -Depth 5 | Set-Content $Global:ConfigFile -Force
        Write-Verbose "Configuration saved to $Global:ConfigFile"
    }
    catch {
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Get-ProfilesMetadata {
    if (Test-Path $Global:ProfilesFile) {
        try {
            $content = Get-Content $Global:ProfilesFile -Raw
            if ([string]::IsNullOrWhiteSpace($content)) {
                $Global:Profiles = @()
            }
            else {
                $Global:Profiles = $content | ConvertFrom-Json
                if ($null -eq $Global:Profiles) { $Global:Profiles = @() } # Handle empty or malformed JSON that results in $null
                # Ensure it's an array if a single object was stored (e.g., if profiles.json had one profile not in an array)
                if ($Global:Profiles -is [pscustomobject] -and $Global:Profiles.PSObject.Properties.Count -gt 0) {
                    $Global:Profiles = @($Global:Profiles)
                }
            }
        }
        catch {
            Write-Warning "Failed to load profiles metadata. Initializing with empty list. Error: $($_.Exception.Message)"
            $Global:Profiles = @()
        }
    }
    else {
        $Global:Profiles = @()
    }
}

function Save-ProfilesMetadata {
    try {
        # Ensure $Global:Profiles is treated as an array, even if it has one item, for consistent JSON output
        $ProfilesToSave = if ($Global:Profiles.Count -eq 1) { @($Global:Profiles[0]) } else { $Global:Profiles }
        $ProfilesToSave | ConvertTo-Json -Depth 5 | Set-Content $Global:ProfilesFile -Force
        Write-Verbose "Profiles metadata saved to $Global:ProfilesFile"
    }
    catch {
        Write-Error "Failed to save profiles metadata: $($_.Exception.Message)"
    }
}

function Test-RegistryKeyExists {
    param (
        [string]$KeyPath
    )
    return Test-Path "Registry::$KeyPath"
}

function Export-RegistryKey {
    param (
        [string]$KeyPath,
        [string]$ExportFilePath
    )
    if (-not (Test-RegistryKeyExists -KeyPath $KeyPath)) {
        Write-Warning "Registry key not found, cannot export: $KeyPath"
        return $false
    }
    try {
        $ParentDir = Split-Path -Path $ExportFilePath -Parent
        if (-not (Test-Path $ParentDir)) {
            New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
        }
        $regProcess = Start-Process -FilePath "reg.exe" -ArgumentList @("export", "`"$KeyPath`"", "`"$ExportFilePath`"", "/y") -Wait -PassThru -NoNewWindow
        if ($regProcess.ExitCode -ne 0) {
            Write-Error "Registry export failed with exit code: $($regProcess.ExitCode)"
            return $false
        }
        Write-Verbose "Successfully exported $KeyPath to $ExportFilePath"
        return $true
    }
    catch {
        Write-Error "Failed to export registry key '$KeyPath' to '$ExportFilePath': $($_.Exception.Message)"
        return $false
    }
}

function Import-RegistryKey {
    param (
        [string]$ImportFilePath
    )
    if (-not (Test-Path $ImportFilePath)) {
        Write-Warning "Registry file not found, cannot import: $ImportFilePath"
        return $false
    }
    try {
        $regProcess = Start-Process -FilePath "reg.exe" -ArgumentList @("import", "`"$ImportFilePath`"") -Wait -PassThru -NoNewWindow
        if ($regProcess.ExitCode -ne 0) {
            Write-Error "Registry import failed with exit code: $($regProcess.ExitCode)"
            return $false
        }
        Write-Verbose "Successfully imported $ImportFilePath"
        return $true
    }
    catch {
        Write-Error "Failed to import registry file '$ImportFilePath': $($_.Exception.Message)"
        return $false
    }
}

function Remove-OldBackups {
    param(
        [string]$KeyIdentifier # e.g., "miHoYoSDK" or "miHoYo" (derived from FileName without .reg)
    )
    $BackupFiles = Get-ChildItem -Path $Global:BackupDir -Filter "${KeyIdentifier}_backup_*.reg" | Sort-Object CreationTime
    $NumBackups = $BackupFiles.Count
    if ($NumBackups -gt $Global:MaxBackups) {
        $NumToDelete = $NumBackups - $Global:MaxBackups
        $FilesToDelete = $BackupFiles | Select-Object -First $NumToDelete
        foreach ($File in $FilesToDelete) {
            Write-Verbose "Deleting old backup: $($File.FullName)"
            Remove-Item $File.FullName -Force
        }
    }
}
#endregion Helper Functions

#region Menu Functions
function Show-Greeting {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    Hoyo Registry Profile Manager" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host
    Write-Host "This script helps you save and load different configurations for miHoYo game accounts by managing specific registry keys."
    Write-Host "Profiles are stored in: $Global:BaseDir"
    Write-Host
}

function Show-MainMenu {
    Write-Host "--------------------"
    Write-Host "  Main Menu"
    Write-Host "--------------------"
    Write-Host "1. Save Current Profile"
    if ($Global:Profiles.Count -eq 0) {
        Write-Host "2. Load Profile (No Profiles Saved)" -ForegroundColor Gray
        Write-Host "3. Manage Profiles (No Profiles Saved)" -ForegroundColor Gray
    }
    else {
        Write-Host "2. Load Profile"
        Write-Host "3. Manage Profiles"
    }
    Write-Host "4. Delete Current Registry Settings (Save Current Registry)"
    Write-Host "5. Delete Current Registry Settings (WITHOUT Saving Registry)"
    Write-Host "6. Options"
    Write-Host "7. Exit"
    Write-Host
}
#endregion Menu Functions

#region Core Logic Functions
function Save-Profile {
    Clear-Host
    Write-Host "--- Save Current Profile ---"

    $ProfileName = Read-Host "Enter a name for this profile (or press Enter for '$($Global:CurrentConfig.DefaultProfileName)')"
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $ProfileName = $Global:CurrentConfig.DefaultProfileName
    }
    
    $ExistingProfile = $Global:Profiles | Where-Object { $_.Name -eq $ProfileName }
    if ($ExistingProfile) {
        $ProceedOverwrite = $false # Default to not overwriting
        while ($true) {
            $ConfirmOverwriteInput = Read-Host "Profile '$ProfileName' already exists. Overwrite? (y/n)"
            if ($ConfirmOverwriteInput.ToLower() -eq 'y') {
                $ProceedOverwrite = $true
                break
            }
            elseif ($ConfirmOverwriteInput.ToLower() -eq 'n') {
                $ProceedOverwrite = $false
                break
            }
            else {
                Write-Warning "Invalid input. Please enter 'y' for yes or 'n' for no."
            }
        }

        if (-not $ProceedOverwrite) {
            Write-Host "Save cancelled."
            Read-Host "Press Enter to continue..."
            return
        }
        
        # If we reach here, user explicitly typed 'y'
        $Global:Profiles = @($Global:Profiles | Where-Object { $_.Name -ne $ProfileName })
        $OldProfileDataPath = Join-Path $Global:ProfileDataDir $ExistingProfile.FolderNameGUID
        if (Test-Path $OldProfileDataPath) {
            Write-Verbose "Removing old profile data at $OldProfileDataPath"
            Remove-Item -Recurse -Force $OldProfileDataPath
        }
    }

    $ProfileFolderGUID = [guid]::NewGuid().ToString()
    $CurrentProfileDir = Join-Path $Global:ProfileDataDir $ProfileFolderGUID
    New-Item -ItemType Directory -Path $CurrentProfileDir -Force | Out-Null

    $SaveSuccess = $true
    $IncludedKeyFiles = @() # To store filenames of keys actually included in this profile

    foreach ($KeyToManage in $Global:CurrentConfig.ManagedKeys) {
        if ($KeyToManage.IsIncluded) {
            $FilePath = Join-Path $CurrentProfileDir $KeyToManage.FileName
            if (Export-RegistryKey -KeyPath $KeyToManage.Path -ExportFilePath $FilePath) {
                Write-Host "Saved $($KeyToManage.UserFriendlyName) key for profile '$ProfileName'."
                $IncludedKeyFiles += $KeyToManage.FileName
            }
            else {
                $SaveSuccess = $false
                Write-Warning "Failed to save $($KeyToManage.UserFriendlyName) key for profile '$ProfileName'."
            }
        }
    }

    if ($SaveSuccess) {
        $NewProfile = [pscustomobject]@{
            Name             = $ProfileName
            FolderNameGUID   = $ProfileFolderGUID
            CreationDate     = (Get-Date).ToUniversalTime().ToString("o") # ISO 8601 for sortable UTC date
            IncludedKeyFiles = $IncludedKeyFiles # Store which key files are part of this profile
        }
        $Global:Profiles += $NewProfile
        Save-ProfilesMetadata
        Write-Host "Profile '$ProfileName' saved successfully." -ForegroundColor Green
    }
    else {
        Write-Warning "Profile '$ProfileName' was not saved due to errors in exporting registry keys. Please check the messages above."
    }
    Read-Host "Press Enter to continue..."
}

function Import-Profile {
    Clear-Host
    Write-Host "--- Load Profile ---"
    if ($Global:Profiles.Count -eq 0) {
        Write-Host "No profiles available to load." -ForegroundColor Yellow
        Read-Host "Press Enter to continue..."
        return
    }

    $SortedProfiles = $Global:Profiles | Sort-Object CreationDate 
    Write-Host "Available profiles (sorted by creation date, oldest first):"
    for ($i = 0; $i -lt $SortedProfiles.Count; $i++) {
        $ProfileEntry = $SortedProfiles[$i]
        try {
            $CreationDateLocal = ([datetime]::ParseExact($ProfileEntry.CreationDate, "o", [System.Globalization.CultureInfo]::InvariantCulture)).ToLocalTime()
            Write-Host ("{0}. {1} (Created: {2})" -f ($i + 1), $ProfileEntry.Name, $CreationDateLocal.ToString("yyyy-MM-dd HH:mm:ss"))
        }
        catch {
            Write-Warning "Could not parse creation date for profile $($ProfileEntry.Name)."
            Write-Host ("{0}. {1} (Created: {2})" -f ($i + 1), $ProfileEntry.Name, $ProfileEntry.CreationDate)
        }
    }
    Write-Host

    $Choice = Read-Host "Enter the number of the profile to load (or 0 to cancel)"
    if ($Choice -eq '0' -or -not ($Choice -match "^\d+$") ) { 
        Write-Host "Load cancelled."
        Read-Host "Press Enter to continue..."
        return 
    }

    $Index = [int]$Choice - 1
    if ($Index -lt 0 -or $Index -ge $SortedProfiles.Count) {
        Write-Warning "Invalid selection."
        Read-Host "Press Enter to continue..."
        return
    }

    $SelectedProfile = $SortedProfiles[$Index]
    $ProfileDirToLoad = Join-Path $Global:ProfileDataDir $SelectedProfile.FolderNameGUID

    if (-not (Test-Path $ProfileDirToLoad)) {
        Write-Error "Profile data not found for '$($SelectedProfile.Name)' at '$ProfileDirToLoad'."
        Read-Host "Press Enter to continue..."
        return
    }

    Write-Host "Loading profile '$($SelectedProfile.Name)'..."
    $Timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $LoadedAllSuccessfully = $true
    
    # Determine which files to import based on the profile's metadata if available, otherwise check all .reg files
    $FilesToAttemptImport = @()
    if ($SelectedProfile.PSObject.Properties['IncludedKeyFiles']) {
        $FilesToAttemptImport = $SelectedProfile.IncludedKeyFiles
    }
    else {
        # Fallback for older profiles that might not have IncludedKeyFiles metadata
        $FilesToAttemptImport = (Get-ChildItem -Path $ProfileDirToLoad -Filter "*.reg" | Select-Object -ExpandProperty Name)
    }

    if ($FilesToAttemptImport.Count -eq 0) {
        Write-Warning "No .reg files found or specified in profile '$($SelectedProfile.Name)'. Nothing to import."
        Read-Host "Press Enter to continue..."
        return
    }
    
    # Track which files were imported from current managed keys
    $ImportedFiles = @()
    
    foreach ($KeyToManage in $Global:CurrentConfig.ManagedKeys) {
        if ($FilesToAttemptImport -contains $KeyToManage.FileName) {
            $RegFileToImport = Join-Path $ProfileDirToLoad $KeyToManage.FileName
            if (-not (Test-Path $RegFileToImport)) {
                Write-Warning "Expected file $($KeyToManage.FileName) not found in profile '$($SelectedProfile.Name)' data folder. Skipping."
                $LoadedAllSuccessfully = $false
                continue
            }

            Write-Verbose "Profile contains data for $($KeyToManage.UserFriendlyName). Preparing to load from $($KeyToManage.FileName)..."
            
            if (Test-RegistryKeyExists -KeyPath $KeyToManage.Path) {
                Write-Verbose "Backing up current $($KeyToManage.Path) key..."
                $KeyIdentifierForBackup = $KeyToManage.FileName.Replace(".reg", "")
                $BackupFilePath = Join-Path $Global:BackupDir "${KeyIdentifierForBackup}_backup_$Timestamp.reg"
                if (Export-RegistryKey -KeyPath $KeyToManage.Path -ExportFilePath $BackupFilePath) {
                    Remove-OldBackups -KeyIdentifier $KeyIdentifierForBackup
                    Write-Verbose "Backup of $($KeyToManage.Path) successful."
                }
                else {
                    Write-Warning "Failed to backup $($KeyToManage.Path)."
                }
            }
            else {
                Write-Verbose "Current $($KeyToManage.Path) does not exist. Skipping backup for this key."
            }

            Write-Host "Importing $($KeyToManage.UserFriendlyName) settings from profile '$($SelectedProfile.Name)'..."
            if (Import-RegistryKey -ImportFilePath $RegFileToImport) {
                Write-Host "Imported $($KeyToManage.UserFriendlyName) settings successfully." -ForegroundColor Green
                $ImportedFiles += $KeyToManage.FileName
            }
            else {
                Write-Warning "Failed to import $($KeyToManage.UserFriendlyName) settings from profile."
                $LoadedAllSuccessfully = $false
            }
        }
    }
    
    # Handle orphaned registry files - files that exist in profile but aren't in current managed keys
    $AllRegFilesInProfile = Get-ChildItem -Path $ProfileDirToLoad -Filter "*.reg" | Select-Object -ExpandProperty Name
    $OrphanedFiles = $AllRegFilesInProfile | Where-Object { $_ -notin $ImportedFiles -and $_ -notin ($Global:CurrentConfig.ManagedKeys | ForEach-Object { $_.FileName }) }
    
    if ($OrphanedFiles.Count -gt 0) {
        Write-Host ""
        Write-Warning "Found registry files in profile that are not in current managed keys configuration:"
        foreach ($OrphanedFile in $OrphanedFiles) {
            Write-Host "  - $OrphanedFile" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "These files may be from an older version of this script configuration." -ForegroundColor Cyan
        $ImportOrphaned = Read-Host "Do you want to import these orphaned files anyway? (y/N)"
        
        if ($ImportOrphaned -eq 'y' -or $ImportOrphaned -eq 'Y') {
            foreach ($OrphanedFile in $OrphanedFiles) {
                $OrphanedFilePath = Join-Path $ProfileDirToLoad $OrphanedFile
                Write-Host "Importing orphaned file: $OrphanedFile..." -ForegroundColor Yellow
                if (Import-RegistryKey -ImportFilePath $OrphanedFilePath) {
                    Write-Host "Successfully imported orphaned file: $OrphanedFile" -ForegroundColor Green
                }
                else {
                    Write-Warning "Failed to import orphaned file: $OrphanedFile"
                    $LoadedAllSuccessfully = $false
                }
            }
        }
        else {
            Write-Host "Skipped importing orphaned files." -ForegroundColor Gray
        }
    }
    
    if ($LoadedAllSuccessfully) {
        Write-Host "Profile '$($SelectedProfile.Name)' loaded." -ForegroundColor Green
    }
    else {
        Write-Warning "Profile '$($SelectedProfile.Name)' load completed, but not all settings were successfully imported. Check messages above."
    }

    Read-Host "Press Enter to continue..."
}

function Show-ProfileManagementMenu {
    while ($true) {
        Clear-Host
        Write-Host "--- Manage Profiles ---"
        if ($Global:Profiles.Count -eq 0) {
            Write-Host "No profiles available to manage." -ForegroundColor Yellow
            Read-Host "Press Enter to return to the Main Menu..."
            return
        }

        $SortedProfiles = $Global:Profiles | Sort-Object CreationDate
        Write-Host "Available profiles (sorted by creation date, oldest first):"
        for ($i = 0; $i -lt $SortedProfiles.Count; $i++) {
            $ProfileEntry = $SortedProfiles[$i]
            try {
                $CreationDateLocal = ([datetime]::ParseExact($ProfileEntry.CreationDate, "o", [System.Globalization.CultureInfo]::InvariantCulture)).ToLocalTime()
                Write-Host ("{0}. {1} (Created: {2})" -f ($i + 1), $ProfileEntry.Name, $CreationDateLocal.ToString("yyyy-MM-dd HH:mm:ss"))
            }
            catch {
                Write-Warning "Could not parse creation date for profile $($ProfileEntry.Name)."
                Write-Host ("{0}. {1} (Created: {2})" -f ($i + 1), $ProfileEntry.Name, $ProfileEntry.CreationDate)
            }
        }
        Write-Host
        Write-Host "0. Back to Main Menu"
        Write-Host

        $ProfileChoice = Read-Host "Enter the number of the profile to manage (or 0 to go back)"
        if ($ProfileChoice -eq '0' -or -not ($ProfileChoice -match "^\d+$") ) {
            return # Back to Main Menu
        }

        $ProfileIndex = [int]$ProfileChoice - 1
        if ($ProfileIndex -lt 0 -or $ProfileIndex -ge $SortedProfiles.Count) {
            Write-Warning "Invalid profile selection."
            Read-Host "Press Enter to continue..."
            continue
        }

        $SelectedProfile = $SortedProfiles[$ProfileIndex]
        $OriginalProfileName = $SelectedProfile.Name # Keep for comparison

        Clear-Host
        Write-Host "--- Managing Profile: '$($SelectedProfile.Name)' ---"
        Write-Host "1. Edit Profile Name"
        Write-Host "2. Delete Profile"
        Write-Host "3. Cancel (Back to Profile List)"
        Write-Host

        $ActionChoice = Read-Host "Select an action"

        switch ($ActionChoice) {
            "1" {
                # Edit Profile Name
                $NewName = Read-Host "Enter new name for profile '$($SelectedProfile.Name)'"
                if ([string]::IsNullOrWhiteSpace($NewName)) {
                    Write-Warning "Profile name cannot be empty."
                }
                elseif ($NewName -eq $SelectedProfile.Name) {
                    Write-Warning "The new name is the same as the current name. No changes made."
                }
                elseif ($Global:Profiles | Where-Object { $_.Name -eq $NewName -and $_.FolderNameGUID -ne $SelectedProfile.FolderNameGUID }) {
                    Write-Warning "A profile with the name '$NewName' already exists. Please choose a different name."
                }
                else {
                    # Find the profile in the original $Global:Profiles array to update it
                    $ProfileToUpdate = $Global:Profiles | Where-Object { $_.FolderNameGUID -eq $SelectedProfile.FolderNameGUID } | Select-Object -First 1
                    if ($ProfileToUpdate) {
                        $ProfileToUpdate.Name = $NewName
                        Save-ProfilesMetadata
                        Write-Host "Profile name updated from '$OriginalProfileName' to '$NewName'." -ForegroundColor Green
                        # Update SelectedProfile for subsequent display if needed within this loop iteration, though we usually re-fetch or exit
                        $SelectedProfile.Name = $NewName 
                    }
                    else {
                        Write-Error "Could not find the profile in the global list to update. This should not happen."
                    }
                }
            }
            "2" {
                # Delete Profile
                $ConfirmDelete = Read-Host "Are you sure you want to delete profile '$($SelectedProfile.Name)'? This will also delete its data files. (y/n)"
                if ($ConfirmDelete.ToLower() -eq 'y') {
                    $ProfileDataPathToDelete = Join-Path $Global:ProfileDataDir $SelectedProfile.FolderNameGUID
                    
                    # Remove from $Global:Profiles
                    $Global:Profiles = @($Global:Profiles | Where-Object { $_.FolderNameGUID -ne $SelectedProfile.FolderNameGUID })
                    Save-ProfilesMetadata
                    Write-Host "Profile '$($OriginalProfileName)' removed from metadata." -ForegroundColor Green

                    # Delete data folder
                    if (Test-Path $ProfileDataPathToDelete) {
                        try {
                            Remove-Item -Recurse -Force $ProfileDataPathToDelete
                            Write-Host "Profile data folder for '$($OriginalProfileName)' deleted from '$ProfileDataPathToDelete'." -ForegroundColor Green
                        }
                        catch {
                            Write-Warning "Failed to delete profile data folder '$ProfileDataPathToDelete'. Error: $($_.Exception.Message)"
                        }
                    }
                    else {
                        Write-Warning "Profile data folder for '$($OriginalProfileName)' not found at '$ProfileDataPathToDelete'. No data deleted."
                    }
                    Write-Host "Profile '$($OriginalProfileName)' deleted successfully."
                    Read-Host "Press Enter to continue..."
                    return # Exit Show-ProfileManagementMenu as the list has changed
                }
                else {
                    Write-Host "Deletion cancelled."
                }
            }
            "3" {
                # Cancel
                Write-Host "Operation cancelled."
            }
            default {
                Write-Warning "Invalid action selection."
            }
        }
        Read-Host "Press Enter to continue..."
    }
}

function Show-Options {
    while ($true) {
        Clear-Host
        Write-Host "--- Options ---"
        Write-Host "1. Default Profile Name: $($Global:CurrentConfig.DefaultProfileName)"
        Write-Host
        Write-Host "Manage Registry Keys (Included keys will be part of NEW profiles and deletion operations):"
        
        $KeyOptions = @{}
        $OptionCounter = 2 # Start options for keys from 2
        foreach ($KeyEntry in $Global:CurrentConfig.ManagedKeys) {
            $Status = if ($KeyEntry.IsIncluded) { 'Included' } else { 'Excluded' }
            Write-Host "$($OptionCounter). Manage '$($KeyEntry.UserFriendlyName)' ($($KeyEntry.Path)) (Currently: $Status)"
            $KeyOptions[$OptionCounter.ToString()] = $KeyEntry # Store reference to the key entry
            $OptionCounter++
        }
        Write-Host
        Write-Host "$($OptionCounter). Back to Main Menu"
        Write-Host

        $Choice = Read-Host "Select an option to change"
        switch ($Choice) {
            "1" {
                $NewName = Read-Host "Enter new default profile name"
                if (-not [string]::IsNullOrWhiteSpace($NewName)) {
                    $Global:CurrentConfig.DefaultProfileName = $NewName
                    Save-Configuration
                    Write-Host "Default profile name updated to '$NewName'." -ForegroundColor Green
                }
                else { Write-Warning "Name cannot be empty." }
                Read-Host "Press Enter to continue..."
            }
            default {
                if ($KeyOptions.ContainsKey($Choice)) {
                    $SelectedKeyToToggle = $KeyOptions[$Choice]
                    $SelectedKeyToToggle.IsIncluded = -not $SelectedKeyToToggle.IsIncluded
                    Save-Configuration
                    $NewStatus = if ($SelectedKeyToToggle.IsIncluded) { 'included' } else { 'excluded' }
                    Write-Host "'$($SelectedKeyToToggle.UserFriendlyName)' will now be $NewStatus." -ForegroundColor Green
                    Read-Host "Press Enter to continue..."
                }
                elseif ($Choice -eq $OptionCounter.ToString()) {
                    # Back to Main Menu
                    return
                }
                else {
                    Write-Warning "Invalid option."
                    Read-Host "Press Enter to continue..."
                }
            }
        }
    }
}

function Invoke-LiveRegistryKeyDeletion {
    Write-Host "--- Performing Live Registry Key Deletion ---"
    $DeletionAttempted = $false
    $SomethingWasDeleted = $false
    $Timestamp = Get-Date -Format 'yyyyMMddHHmmss'

    foreach ($KeyToManage in $Global:CurrentConfig.ManagedKeys) {
        if ($KeyToManage.IsIncluded) {
            $DeletionAttempted = $true
            if (Test-RegistryKeyExists -KeyPath $KeyToManage.Path) {
                Write-Verbose "Backing up current $($KeyToManage.Path) key before deletion..."
                $KeyIdentifierForBackup = $KeyToManage.FileName.Replace(".reg", "")
                $BackupFilePath = Join-Path $Global:BackupDir "${KeyIdentifierForBackup}_backup_$Timestamp.reg"
                
                if (Export-RegistryKey -KeyPath $KeyToManage.Path -ExportFilePath $BackupFilePath) {
                    Write-Host "Successfully backed up $($KeyToManage.Path) to $BackupFilePath before deletion." -ForegroundColor Cyan
                    Remove-OldBackups -KeyIdentifier $KeyIdentifierForBackup
                }
                else {
                    Write-Warning "Failed to backup $($KeyToManage.Path) before deletion. Deletion will proceed."
                }

                Write-Host "Attempting to delete live registry key: $($KeyToManage.Path)"
                try {
                    reg.exe delete "$($KeyToManage.Path)" /f
                    Write-Host "Successfully deleted live registry key: $($KeyToManage.Path)" -ForegroundColor Green
                    $SomethingWasDeleted = $true
                }
                catch {
                    Write-Warning "Failed to delete live registry key '$($KeyToManage.Path)': $($_.Exception.Message)"
                }
            }
            else {
                Write-Host "Live registry key '$($KeyToManage.Path)' ($($KeyToManage.UserFriendlyName)) not found, no deletion needed." -ForegroundColor Yellow
            }
        }
    }

    if (-not $DeletionAttempted) {
        Write-Warning "No registry keys are currently configured for management in Options. Nothing to delete."
    }
    elseif ($SomethingWasDeleted) {
        Write-Host "Live registry key deletion process completed." -ForegroundColor Green
    }
    else {
        # Deletion was attempted, but nothing was actually deleted (e.g. keys didn't exist or reg delete failed but didn't throw terminating error)
        Write-Host "Live registry key deletion process completed. No keys were deleted (either not found or deletion failed for all attempted keys)."
    }
    
    # return $SomethingWasDeleted
}

function Remove-CurrentRegistryKeysWithSave {
    Clear-Host
    Write-Host "--- Delete Current Registry Settings (Save Current Registry) ---"

    $KeysToActuallyManage = $Global:CurrentConfig.ManagedKeys | Where-Object { $_.IsIncluded }

    if ($KeysToActuallyManage.Count -eq 0) {
        Write-Warning "No registry keys are configured for inclusion in Options (see Main Menu -> Options)."
        Write-Warning "Nothing will be deleted."
        Read-Host "Press Enter to continue..."
        return
    }

    Write-Host "This action will:"
    Write-Host "1. First save the current registry settings to a new profile"
    Write-Host "2. Then delete the following LIVE registry keys:"
    $KeysToActuallyManage | ForEach-Object { Write-Host "   - $($_.UserFriendlyName) ($($_.Path))" }
    Write-Host
    Write-Warning "This operation directly modifies your system registry and can lead to issues if done incorrectly or if the wrong keys are targeted."
    Write-Host

    $Confirm = Read-Host "Do you want to proceed? (y/n)"
    if ($Confirm.ToLower() -ne 'y') {
        Write-Host "Operation cancelled."
        Read-Host "Press Enter to continue..."
        return
    }

    Write-Host "First, the script will guide you through saving the current registry settings to a profile."
    Save-Profile 
    
    Clear-Host 
    Write-Host "--- Delete Current Registry Settings (Continued) ---"
    Write-Host "Profile saving process is complete (or was cancelled by you)."
    Write-Host "The live registry keys to be deleted are:"
    $KeysToActuallyManage | ForEach-Object { Write-Host "- $($_.UserFriendlyName) ($($_.Path))" }
    Write-Host
    
    $ConfirmDeleteAfterSave = Read-Host "Do you want to proceed with deleting these live registry keys now? (y/n)"
    if ($ConfirmDeleteAfterSave.ToLower() -eq 'y') {
        Invoke-LiveRegistryKeyDeletion
    }
    else {
        Write-Host "Deletion of live registry keys cancelled."
    }
    Read-Host "Press Enter to return to the Main Menu..."
}

function Remove-CurrentRegistryKeysWithoutSave {
    Clear-Host
    Write-Host "--- Delete Current Registry Settings (WITHOUT Saving Registry) ---"

    $KeysToActuallyManage = $Global:CurrentConfig.ManagedKeys | Where-Object { $_.IsIncluded }

    if ($KeysToActuallyManage.Count -eq 0) {
        Write-Warning "No registry keys are configured for inclusion in Options (see Main Menu -> Options)."
        Write-Warning "Nothing will be deleted."
        Read-Host "Press Enter to continue..."
        return
    }

    Write-Host "This action will delete the following LIVE registry keys WITHOUT saving them to a new profile:"
    $KeysToActuallyManage | ForEach-Object { Write-Host "- $($_.UserFriendlyName) ($($_.Path))" }
    Write-Host
    Write-Warning "This operation directly modifies your system registry and can lead to issues if done incorrectly or if the wrong keys are targeted."
    Write-Host

    $ProceedWithDeletion = $true 

    $ShowWarning = $false
    if ($Global:Profiles.Count -eq 0) {
        $ShowWarning = $true
        Write-Warning "(CRITICAL) No profiles have ever been saved with this tool."
    }
    else {
        # Check creation date of the most recent profile
        $MostRecentProfile = $Global:Profiles | Sort-Object { if ($_.CreationDate) { [datetime]$_.CreationDate } else { [datetime]::MinValue } } -Descending | Select-Object -First 1
        if ($MostRecentProfile -and $MostRecentProfile.CreationDate) {
            $LastSaveDate = [datetime]$MostRecentProfile.CreationDate # This is UTC
            $TwentyFourHoursAgo = (Get-Date).ToUniversalTime().AddHours(-24) 
            if ($LastSaveDate -lt $TwentyFourHoursAgo) {
                $ShowWarning = $true
                Write-Warning "The most recent profile ('$($MostRecentProfile.Name)') was saved more than 24 hours ago (at $($LastSaveDate.ToLocalTime()))."
            }
        }
        else {
            $ShowWarning = $true
            Write-Warning "Could not determine the age of the most recent profile."
        }
    }

    if ($ShowWarning) {
        Write-Warning "Deleting live registry keys without a current backup/profile can lead to loss of settings if these keys are important for your games."
        $ConfirmForceDelete = Read-Host "Are you absolutely sure you want to delete the live keys without saving them to a new profile now? (Type 'yes' to confirm)"
        if ($ConfirmForceDelete.ToLower() -ne "yes") { 
            $ProceedWithDeletion = $false
            Write-Host "Deletion of live registry keys cancelled."
        }
    }
    else {
        $ConfirmDelete = Read-Host "Confirm deletion of the listed live registry keys? (y/n)"
        if ($ConfirmDelete.ToLower() -ne 'y') {
            $ProceedWithDeletion = $false
            Write-Host "Deletion of live registry keys cancelled."
        }
    }
    
    if ($ProceedWithDeletion) {
        Invoke-LiveRegistryKeyDeletion
    }
    Read-Host "Press Enter to return to the Main Menu..."
}
#endregion Core Logic Functions

#region Main Script Execution
Initialize-ScriptEnvironment

while ($true) {
    Show-Greeting
    Show-MainMenu
    $Selection = Read-Host "Enter your choice"  
      
    switch ($Selection) {
        "1" { Save-Profile }
        "2" {
            if ($Global:Profiles.Count -eq 0) {
                Write-Warning "No profiles saved yet. Cannot load."
                Read-Host "Press Enter to continue..."
            }
            else {
                Import-Profile
            }
        }
        "3" { 
            if ($Global:Profiles.Count -eq 0) {
                Write-Warning "No profiles saved yet. Cannot manage."
                Read-Host "Press Enter to continue..."
            }
            else {
                Show-ProfileManagementMenu 
            }
        }
        "4" { Remove-CurrentRegistryKeysWithSave }
        "5" { Remove-CurrentRegistryKeysWithoutSave }
        "6" { Show-Options }
        "7" { Write-Host "Exiting script."; exit }
        default {
            Write-Warning "Invalid selection. Please try again."
            Read-Host "Press Enter to continue..."
        }
    }
}
#endregion Main Script Execution
