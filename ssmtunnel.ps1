# AWS SSM Tunnel Helper Script
# Author: Michael Brown - mb@resolvetech.com
# I used robots to write this script to help with secure multi account access in AWS.
# License: MIT License

param (
    [string]$AWSProfile,
    [string]$AWSRegion = "us-east-1"
)

# Script version
$ScriptVersion = "2.0"

# AWS region for instance lookups (can be overridden with -AWSRegion parameter)
$DefaultAwsRegion = $AWSRegion

# Display version information
Write-Host "SSM Tunnel Script v$ScriptVersion" -ForegroundColor Cyan
Write-Host "================================`n"

# --- Port History and Scanning Functions ---
$historyDir = "$env:USERPROFILE\.ssmtunnel"
$historyFile = "$historyDir\porthistory.json"

# Function to get active local SSM tunnels
function Get-ActiveLocalTunnels {
    # Get all PowerShell jobs that are SSM tunnel jobs
    $ssmJobs = Get-Job -Name "SSMTunnel*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
    
    # Get active TCP connections on common SSM tunnel ports
    $activePorts = Get-ActiveTcpPorts
    $tunnelPorts = $activePorts | Where-Object { $_ -ge 8999 -and $_ -le 9050 }
    
    # Get port history to match ports with instance info
    $history = Get-PortHistory
    
    $localTunnels = @()
    
    foreach ($port in $tunnelPorts) {
        $historyEntry = $history | Where-Object { $_.LocalPort -eq $port } | Select-Object -First 1
        
        $tunnelInfo = [PSCustomObject]@{
            LocalPort = $port
            InstanceId = if ($historyEntry) { $historyEntry.InstanceId } else { "Unknown" }
            ProfileName = if ($historyEntry) { $historyEntry.ProfileName } else { "Unknown" }
            LastUsed = if ($historyEntry) { $historyEntry.LastUsed } else { "Unknown" }
            HasActiveJob = $false
            JobName = $null
            InstanceName = "Unknown"
        }
        
        # Check if there's an active job for this port
        foreach ($job in $ssmJobs) {
            if ($job.Name -like "*$port*" -or $job.Name -like "*SSMTunnel*") {
                $tunnelInfo.HasActiveJob = $true
                $tunnelInfo.JobName = $job.Name
                break
            }
        }
        
        $localTunnels += $tunnelInfo
    }
    
    return $localTunnels
}

function Get-InstanceName {
    param(
        [string]$InstanceId,
        [string]$ProfileName
    )
    
    if ($InstanceId -eq "Unknown") {
        return "Unknown"
    }
    
    try {
        # Use JSON output for more reliable parsing
        $awsOutput = aws ec2 describe-instances --instance-ids $InstanceId --profile $ProfileName --region $DefaultAwsRegion --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "(Error: AWS CLI failed)"
        }
        
        $data = $awsOutput | ConvertFrom-Json
        $instance = $data.Reservations[0].Instances[0]
        $nameTag = $instance.Tags | Where-Object { $_.Key -eq "Name" } | Select-Object -First 1
        
        if ($nameTag -and $nameTag.Value) {
            return $nameTag.Value.Trim()
        } else {
            return "(No Name)"
        }
    } catch {
        return "(Error getting name: $($_.Exception.Message))"
    }
}

function Show-ActiveLocalTunnels {
    Write-Host "`n--- Active Local SSM Tunnels ---" -ForegroundColor Yellow
    
    $tunnels = Get-ActiveLocalTunnels
    
    if ($tunnels.Count -eq 0) {
        Write-Host "  No active local SSM tunnels found." -ForegroundColor Gray
        Write-Host "  (No ports in range 8999-9050 are currently in use)" -ForegroundColor Gray
    } else {
        Write-Host "  Found $($tunnels.Count) active tunnel(s):" -ForegroundColor Green
        Write-Host ""
        
        foreach ($tunnel in $tunnels) {
            $statusColor = if ($tunnel.HasActiveJob) { "Green" } else { "Yellow" }
            $statusText = if ($tunnel.HasActiveJob) { "ACTIVE" } else { "PORT IN USE" }
            
            # Get instance name if we have a valid instance ID and profile
            $instanceName = if ($tunnel.InstanceId -ne "Unknown" -and $InstanceNameMap.ContainsKey($tunnel.InstanceId)) {
                $InstanceNameMap[$tunnel.InstanceId]
            } elseif ($tunnel.InstanceId -ne "Unknown" -and $tunnel.ProfileName -ne "Unknown") {
                # Fallback to live AWS query if not in cache
                $liveName = Get-InstanceName -InstanceId $tunnel.InstanceId -ProfileName $tunnel.ProfileName
                if ($liveName -and $liveName -ne "Unknown" -and $liveName -notmatch "Error") {
                    # Cache the result for future use
                    $global:InstanceNameMap[$tunnel.InstanceId] = $liveName
                    $liveName
                } else {
                    "Unknown"
                }
            } else {
                "Unknown"
            }
            
            Write-Host ("  Port {0}: {1}" -f $tunnel.LocalPort, $statusText) -ForegroundColor $statusColor
            Write-Host ("    Instance: {0} ({1})" -f $tunnel.InstanceId, $instanceName) -ForegroundColor White
            Write-Host ("    Profile: {0}" -f $tunnel.ProfileName) -ForegroundColor White
            Write-Host ("    Last Used: {0}" -f $tunnel.LastUsed) -ForegroundColor White
            if ($tunnel.HasActiveJob) {
                Write-Host ("    Job: {0}" -f $tunnel.JobName) -ForegroundColor Cyan
            }
            Write-Host ""
        }
    }
    
    # Also show any running SSM tunnel jobs
    $ssmJobs = Get-Job -Name "SSMTunnel*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
    if ($ssmJobs.Count -gt 0) {
        Write-Host "  Running SSM Tunnel Jobs:" -ForegroundColor Cyan
        foreach ($job in $ssmJobs) {
            Write-Host ("    {0} (ID: {1}) - {2}" -f $job.Name, $job.Id, $job.State) -ForegroundColor White
        }
        Write-Host ""
    }
    
    Write-Host "------------------------`n"
}

# Ensure the history directory exists
if (-not (Test-Path $historyDir)) {
    New-Item -Path $historyDir -ItemType Directory -Force | Out-Null
}

function Get-PortHistory {
    if (-not (Test-Path $historyFile)) {
        return @()
    }
    try {
        return Get-Content $historyFile -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Could not read or parse port history file at $historyFile"
        return @()
    }
}

function Save-PortHistory {
    param(
        [int]$LocalPort,
        [string]$InstanceId,
        [string]$ProfileName
    )
    $history = Get-PortHistory
    $now = Get-Date -Format 'u'
    
    # Remove existing entry for this port, if any
    $history = $history | Where-Object { $_.LocalPort -ne $LocalPort }
    
    # Add new entry to the top
    $newEntry = @{
        LocalPort   = $LocalPort
        InstanceId  = $InstanceId
        ProfileName = $ProfileName
        LastUsed    = $now
    }
    $history = @($newEntry) + $history
    
    # Keep only the last 10 entries
    if ($history.Count -gt 10) {
        $history = $history[0..9]
    }
    
    $history | ConvertTo-Json | Set-Content -Path $historyFile -Encoding UTF8
}

function Get-ActiveTcpPorts {
    # Get all active TCP listeners
    $tcpConnections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    if ($tcpConnections) {
        return $tcpConnections.LocalPort
    }
    return @()
}

function Show-UnavailablePorts {
    param(
        [int]$StartPort = 8999,
        [int]$EndPort = 9050
    )
    Write-Host "`n--- Used Ports ($StartPort - $EndPort) ---"
    $activePorts = Get-ActiveTcpPorts
    $history = Get-PortHistory
    $found = $false

    for ($port = $StartPort; $port -le $EndPort; $port++) {
        if ($activePorts -contains $port) {
            $historyEntry = $history | Where-Object { $_.LocalPort -eq $port } | Select-Object -First 1
            if ($historyEntry) {
                Write-Host ("  Port {0}: In Use - Last used for {1} with profile {2}" -f $port, $historyEntry.InstanceId, $historyEntry.ProfileName) -ForegroundColor Red
            } else {
                Write-Host ("  Port {0}: In Use - (No history available)" -f $port) -ForegroundColor Red
            }
            $found = $true
        }
    }

    if (-not $found) {
        Write-Host "  No used ports found in the range $StartPort - $EndPort." -ForegroundColor Cyan
    }
    Write-Host "------------------------`n"
}

# --- AWS Region Functions ---
function Get-AwsRegions {
    # Common AWS regions - you can add more as needed
    return @(
        "us-east-1",
        "us-east-2", 
        "us-west-1",
        "us-west-2",
        "eu-west-1",
        "eu-west-2",
        "eu-west-3",
        "eu-central-1",
        "eu-north-1",
        "ap-northeast-1",
        "ap-northeast-2",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-south-1",
        "ca-central-1",
        "sa-east-1"
    )
}

function Show-RegionSelection {
    $regions = Get-AwsRegions
    Write-Host "`n--- Select AWS Region ---" -ForegroundColor Yellow
    Write-Host "Current region: $DefaultAwsRegion" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $regions.Count; $i++) {
        $currentMarker = if ($regions[$i] -eq $DefaultAwsRegion) { " (current)" } else { "" }
        Write-Host ("  {0,2}. {1}{2}" -f ($i+1), $regions[$i], $currentMarker)
    }
    
    Write-Host ""
    $selection = Read-Host "Enter the number of the region to use, or press Enter to keep current"
    
    if ($selection -match "^\d+$") {
        $selectedIndex = [int]$selection - 1
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $regions.Count) {
            $script:DefaultAwsRegion = $regions[$selectedIndex]
            Write-Host "Region changed to: $DefaultAwsRegion" -ForegroundColor Green
        } else {
            Write-Host "Invalid selection." -ForegroundColor Red
        }
    }
}

# --- AWS Profile Functions ---
function Get-AwsProfiles {
    $configFile = "$env:USERPROFILE\.aws\config"
    if (-not (Test-Path $configFile)) {
        Write-Warning "AWS config file not found at $configFile"
        return @()
    }

    $profiles = Get-Content $configFile | Where-Object { $_ -match "^\[profile .*\]$" } | ForEach-Object { $_ -replace "^\[profile (.*)\]$", '$1' }
    return $profiles
}

function Get-ProfileSsoUrl {
    param(
        [string]$ProfileName
    )
    $configFile = "$env:USERPROFILE\.aws\config"
    if (-not (Test-Path $configFile)) {
        return $null
    }

    $configContent = Get-Content $configFile
    $inProfile = $false
    
    foreach ($line in $configContent) {
        if ($line -match "^\[profile $ProfileName\]$") {
            $inProfile = $true
            continue
        } elseif ($line -match "^\[profile ") {
            $inProfile = $false
        } elseif ($inProfile -and $line -match "^sso_start_url\s*=\s*(.+)") {
            return $matches[1].Trim()
        }
    }
    return $null
}

function Get-ProfileGroups {
    $profiles = Get-AwsProfiles
    $profileGroups = @{}
    $nonSsoProfiles = @()
    
    foreach ($profile in $profiles) {
        $ssoUrl = Get-ProfileSsoUrl -ProfileName $profile
        if ($ssoUrl) {
            if (-not $profileGroups.ContainsKey($ssoUrl)) {
                $profileGroups[$ssoUrl] = @()
            }
            $profileGroups[$ssoUrl] += $profile
        } else {
            $nonSsoProfiles += $profile
        }
    }
    
    return @{
        Groups = $profileGroups
        NonSsoProfiles = $nonSsoProfiles
    }
}

function Show-ProfileList {
    $profileData = Get-ProfileGroups
    $allProfiles = @()
    $profileIndex = 1
    
    # Show SSO groups first
    foreach ($ssoUrl in $profileData.Groups.Keys) {
        Write-Host "  SSO: $ssoUrl"
        foreach ($profile in $profileData.Groups[$ssoUrl]) {
            Write-Host "    $profileIndex. $profile"
            $allProfiles += $profile
            $profileIndex++
        }
        Write-Host ""
    }
    
    # Show non-SSO profiles
    if ($profileData.NonSsoProfiles.Count -gt 0) {
        Write-Host "  Non-SSO Profiles:"
        foreach ($profile in $profileData.NonSsoProfiles) {
            Write-Host "    $profileIndex. $profile"
            $allProfiles += $profile
            $profileIndex++
        }
        Write-Host ""
    }
    
    return $allProfiles
}

function Remove-AwsProfile {
    param(
        [string]$ProfileName
    )
    $configFile = "$env:USERPROFILE\.aws\config"
    $credFile = "$env:USERPROFILE\.aws\credentials"
    
    # Remove from config
    if (Test-Path $configFile) {
        $config = Get-Content $configFile -Raw
        $config = $config -replace "(?ms)^\[profile $ProfileName\][^\[]*", ''
        Set-Content $configFile $config.Trim()
    }
    # Remove from credentials
    if (Test-Path $credFile) {
        $cred = Get-Content $credFile -Raw
        $cred = $cred -replace "(?ms)^\[$ProfileName\][^\[]*", ''
        Set-Content $credFile $cred.Trim()
    }
    Write-Host "Profile '$ProfileName' deleted from config and credentials."
}

function Rename-AwsProfile {
    param(
        [string]$OldName,
        [string]$NewName
    )
    $configFile = "$env:USERPROFILE\.aws\config"
    $credFile = "$env:USERPROFILE\.aws\credentials"
    # Rename in config
    if (Test-Path $configFile) {
        $config = Get-Content $configFile -Raw
        $config = $config -replace "\[profile $OldName\]", "[profile $NewName]"
        Set-Content $configFile $config.Trim()
    }
    # Rename in credentials
    if (Test-Path $credFile) {
        $cred = Get-Content $credFile -Raw
        $cred = $cred -replace "\[$OldName\]", "[$NewName]"
        Set-Content $credFile $cred.Trim()
    }
    Write-Host "Profile '$OldName' renamed to '$NewName' in config and credentials."
}

# Instance name cache file
$InstanceNameCacheFile = "$env:USERPROFILE\.ssmtunnel\instance_names.json"
$InstanceNameMap = @{}

function Load-InstanceNameCache {
    if (Test-Path $InstanceNameCacheFile) {
        try {
            $jsonData = Get-Content $InstanceNameCacheFile -Raw | ConvertFrom-Json
            # Convert PSObject to hashtable for proper indexing
            $global:InstanceNameMap = @{}
            $jsonData.PSObject.Properties | ForEach-Object {
                $global:InstanceNameMap[$_.Name] = $_.Value
            }
            Write-Host "Loaded instance name cache from file." -ForegroundColor Cyan
        } catch {
            Write-Warning "Failed to load instance name cache. Will refresh from AWS."
            $global:InstanceNameMap = @{}
        }
    } else {
        $global:InstanceNameMap = @{}
    }
}

function Save-InstanceNameCache {
    try {
        $InstanceNameMap | ConvertTo-Json | Set-Content -Path $InstanceNameCacheFile -Encoding UTF8
        Write-Host "Saved instance name cache to file." -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to save instance name cache to file."
    }
}

function Refresh-InstanceNameCache {
    # Prompt user to select a profile for the refresh
    $profiles = Get-AwsProfiles
    if ($profiles.Count -eq 0) {
        Write-Host "No AWS profiles found. Cannot refresh instance name cache." -ForegroundColor Red
        return
    }
    Write-Host "\nSelect a profile to use for refreshing the instance name cache:"
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i+1), $profiles[$i])
    }
    $profileSelection = Read-Host "Enter the number of the profile to use"
    if ($profileSelection -match "^\d+$" -and [int]$profileSelection -ge 1 -and [int]$profileSelection -le $profiles.Count) {
        $selectedProfile = $profiles[[int]$profileSelection-1]
    } else {
        Write-Host "Invalid selection. Aborting refresh." -ForegroundColor Red
        return
    }
    Write-Host "Refreshing instance name cache from AWS using profile '$selectedProfile'..." -ForegroundColor Yellow
    $newMap = @{}
    try {
        $awsOutput = aws ec2 describe-instances --profile $selectedProfile --region $DefaultAwsRegion --output json 2>&1
        $data = $awsOutput | ConvertFrom-Json
        Write-Host "Reservations found: $($data.Reservations.Count)"
        foreach ($reservation in $data.Reservations) {
            Write-Host "Instances in reservation: $($reservation.Instances.Count)"
            foreach ($instance in $reservation.Instances) {
                $id = $instance.InstanceId
                $nameTag = $instance.Tags | Where-Object { $_.Key -eq "Name" } | Select-Object -First 1
                $name = if ($nameTag) { $nameTag.Value } else { "(No Name)" }
                $newMap[$id] = $name
            }
        }
        $global:InstanceNameMap = $newMap
        Save-InstanceNameCache
        Write-Host "Instance name cache refreshed from AWS using profile '$selectedProfile'." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to refresh instance name cache from AWS: $($_.Exception.Message)"
    }
}

# Load instance name cache at startup
Load-InstanceNameCache

if (-not $AWSProfile) {
    while ($true) {
        Write-Host "`n--- Current Settings ---" -ForegroundColor Cyan
        Write-Host "AWS Region: $DefaultAwsRegion" -ForegroundColor White
        Write-Host ""
        
        $availableProfiles = Show-ProfileList
        if ($availableProfiles.Count -eq 0) {
            Write-Host "No AWS profiles found in $env:USERPROFILE\.aws\config or the file does not exist."
            Write-Host "Please specify a profile with -AWSProfile <profile-name>"
            exit
        }
        
        $newProfileOptionNumber = $availableProfiles.Count + 1
        $deleteProfileOptionNumber = $availableProfiles.Count + 2
        $renameProfileOptionNumber = $availableProfiles.Count + 3
        $changeRegionOptionNumber = $availableProfiles.Count + 4
        $listSessionsOptionNumber = $availableProfiles.Count + 5
        $refreshCacheOptionNumber = $availableProfiles.Count + 6
        Write-Host "  $newProfileOptionNumber. Configure a new SSO profile"
        Write-Host "  $deleteProfileOptionNumber. Delete a profile"
        Write-Host "  $renameProfileOptionNumber. Rename a profile"
        Write-Host "  $changeRegionOptionNumber. Change AWS region"
        Write-Host "  $listSessionsOptionNumber. List active local SSM tunnels"
        Write-Host "  $refreshCacheOptionNumber. Refresh instance name cache from AWS"
        
        $selection = Read-Host "Select a profile number, enter a profile name, or choose an action"
        if ($selection -match "^\d+$") {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $availableProfiles.Count) {
                $AWSProfile = $availableProfiles[$selectedIndex]
            } elseif ($selectedIndex -eq ($newProfileOptionNumber - 1)) {
                Write-Host "Launching AWS SSO configuration..."
                aws configure sso
                Write-Host "AWS SSO configuration finished. Please re-run this script to use the new profile."
                exit
            } elseif ($selectedIndex -eq ($deleteProfileOptionNumber - 1)) {
                # Delete profile
                $delIdx = Read-Host "Enter the number of the profile to delete"
                if ($delIdx -match "^\d+$" -and [int]$delIdx -ge 1 -and [int]$delIdx -le $availableProfiles.Count) {
                    $profileToDelete = $availableProfiles[[int]$delIdx-1]
                    $confirm = Read-Host "Are you sure you want to delete profile '$profileToDelete'? (y/n)"
                    if ($confirm -eq 'y') {
                        Remove-AwsProfile -ProfileName $profileToDelete
                    }
                } else {
                    Write-Host "Invalid profile number."
                }
                continue # Reload menu
            } elseif ($selectedIndex -eq ($renameProfileOptionNumber - 1)) {
                # Rename profile
                $renIdx = Read-Host "Enter the number of the profile to rename"
                if ($renIdx -match "^\d+$" -and [int]$renIdx -ge 1 -and [int]$renIdx -le $availableProfiles.Count) {
                    $profileToRename = $availableProfiles[[int]$renIdx-1]
                    $newName = Read-Host "Enter the new name for profile '$profileToRename'"
                    if ($newName -and $newName -ne $profileToRename) {
                        Rename-AwsProfile -OldName $profileToRename -NewName $newName
                    } else {
                        Write-Host "Invalid or same name."
                    }
                } else {
                    Write-Host "Invalid profile number."
                }
                continue # Reload menu
            } elseif ($selectedIndex -eq ($changeRegionOptionNumber - 1)) {
                # Change region
                Show-RegionSelection
                continue # Reload menu
            } elseif ($selectedIndex -eq ($listSessionsOptionNumber - 1)) {
                # List active local tunnels
                Show-ActiveLocalTunnels
                continue # Reload menu
            } elseif ($selectedIndex -eq ($refreshCacheOptionNumber - 1)) {
                Refresh-InstanceNameCache
                continue # Reload menu
            } else {
                Write-Host "Invalid selection."
                exit
            }
        } else {
            $AWSProfile = $selection
        }
        if (-not $AWSProfile) { # Double check if a profile was actually set
            Write-Host "No profile selected or provided."
            exit
        }
        break
    }
    Write-Host "Using profile: $AWSProfile"

    $ssoLoginChoice = Read-Host "Attempt SSO login for profile '$AWSProfile'? (y/n) [n]"
    if ($ssoLoginChoice -eq 'y') {
        Write-Host "Attempting SSO login for profile '$AWSProfile'..."
        aws sso login --profile $AWSProfile
        # We don't explicitly check the outcome here, but the subsequent aws command will fail if login was unsuccessful
    }
}

# Ensure AWS CLI is available
if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
    Write-Host "AWS CLI is not installed or not in your PATH."

    # Check for Admin rights, which are required for MSI installation
    if (-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[ERROR] Administrator privileges are required to install the AWS CLI." -ForegroundColor Red
        Write-Host "Please re-run this script from a terminal with Administrator rights."
        exit
    }

    # Check PowerShell Version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Host "[WARNING] Your PowerShell version is $($PSVersionTable.PSVersion). Version 5.1 or higher is recommended."
        Write-Host "The script will attempt to continue, but may fail."
    }

    $confirmation = Read-Host "Do you want to proceed with downloading and installing AWS CLI v2? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Installation cancelled by user."
        exit
    }

    Write-Host "Downloading and installing AWS CLI v2..."
    $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $installerPath = "$env:TEMP\AWSCLIV2.msi"

    # Download the installer
    try {
        Write-Host "Downloading from $installerUrl..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Failed to download the AWS CLI installer." -ForegroundColor Red
        Write-Host "  - Check your internet connection."
        Write-Host "  - Ensure PowerShell can access the internet (check firewalls)."
        Write-Host "  - Error details: $($_.Exception.Message)"
        exit
    }

    # Install AWS CLI
    try {
        Write-Host "Installing AWS CLI... This may take a few moments."
        # Using /passive for some UI but no user interaction, /qn is fully quiet
        $msiArgs = "/i `"$installerPath`" /passive /norestart"
        $process = Start-Process msiexec.exe -Wait -ArgumentList $msiArgs -PassThru
        if ($process.ExitCode -ne 0) {
            # Throw a custom error to be caught by the catch block
            throw "MSI installer exited with code $($process.ExitCode). A common reason is needing to run as Administrator."
        }
    } catch {
        Write-Host "[ERROR] Failed to install the AWS CLI." -ForegroundColor Red
        Write-Host "  - Ensure you are running this script with Administrator privileges."
        Write-Host "  - The installer may have failed. You can try running it manually from '$installerPath'."
        Write-Host "  - Error details: $($_.Exception.Message)"
        # Don't exit here, let the user decide if they want to keep the installer
        Read-Host "Press Enter to exit."
        exit
    } finally {
        # Clean up the installer if it still exists
        if (Test-Path $installerPath) {
            Write-Host "Removing installer..."
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Refresh environment variables and add to current session
    Write-Host "Installation complete. Refreshing PATH..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Also explicitly add the default install path to the current session's PATH for good measure
    $awsCliPath = "$env:ProgramFiles\Amazon\AWSCLIV2"
    if (Test-Path $awsCliPath -and $env:Path -notlike "*$awsCliPath*") {
        $env:Path += ";$awsCliPath"
    }

    # Check again
    if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] AWS CLI was installed, but the 'aws' command is still not available." -ForegroundColor Red
        Write-Host "Please restart your terminal and try again. If the problem persists, a system restart may be required."
        exit
    } else {
        Write-Host "AWS CLI v2 installed and configured successfully." -ForegroundColor Green
    }
}

# Fetch instance details
Write-Host "Fetching EC2 instance list for profile '$AWSProfile' in region '$DefaultAwsRegion'..."
$awsOutput = aws ec2 describe-instances --profile $AWSProfile --region $DefaultAwsRegion --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name']|[0].Value,State.Name,PlatformDetails,KeyName]" --output json 2>&1

# Check for expired token or credential errors
if ($awsOutput -match "ExpiredToken|The security token included in the request is expired|Unable to locate credentials|could not be found") {
    Write-Host "`n[ERROR] AWS credentials are missing or expired."
    Write-Host "To refresh your credentials, try one of the following:"
    Write-Host "  - If you use SSO: aws sso login --profile $AWSProfile"
    Write-Host "  - If you use MFA: Run 'aws configure' or refresh your session token."
    Write-Host "  - For other cases: Ensure your credentials are valid in ~/.aws/credentials."
    exit
}

# Try to parse output as JSON, otherwise print error and exit
try {
    $instances = $awsOutput | ConvertFrom-Json
} catch {
    Write-Host "`n[ERROR] Failed to parse AWS CLI output as JSON."
    Write-Host "Raw output from AWS CLI:"
    Write-Host $awsOutput
    Write-Host "`nThis usually means there was an error with your AWS credentials, profile, or network."
    Write-Host "Please check the above error and try one of the following:"
    Write-Host "  - If you use SSO: aws sso login --profile $AWSProfile"
    Write-Host "  - If you use MFA: Run 'aws configure' or refresh your session token."
    Write-Host "  - For other cases: Ensure your credentials are valid in ~/.aws/credentials."
    exit
}

# Flatten and filter running instances
$flatInstances = @()
foreach ($reservation in $instances) {
    foreach ($instance in $reservation) {
        if ($instance[2] -eq "running") {
            $platform = $instance[3]
            if (-not $platform -or $platform -eq "" ) {
                $platform = "Linux/UNIX" # Default to Linux/UNIX if PlatformDetails is empty or null
            }
            $keyName = $instance[4] ? $instance[4] : "(No Key)" # Handle cases where KeyName might be missing
            $flatInstances += [PSCustomObject]@{
                InstanceId = $instance[0]
                Name       = $instance[1] ? $instance[1] : "(No Name)"
                State      = $instance[2]
                OS         = $platform
                KeyName    = $keyName
            }
        }
    }
}

if ($flatInstances.Count -eq 0) {
    Write-Host "No running instances found for profile '$AWSProfile'."
    exit
}

# Display selection menu
$selectedInstance = $flatInstances | Out-GridView -Title "Select an EC2 Instance (Profile: $AWSProfile)" -PassThru
if (-not $selectedInstance) {
    Write-Host "No instance selected."
    exit
}

# --- Port Selection with History ---
$localPort = ""
while ($true) {
    Show-UnavailablePorts
    Write-Host "`n--- Select a Local Port ---"
    $history = Get-PortHistory
    $activePorts = Get-ActiveTcpPorts
    $historyOptions = @{}
    $optionIndex = 1

    if ($history.Count -gt 0) {
        Write-Host "Recent Ports:"
        foreach ($entry in $history) {
            $status = if ($activePorts -contains $entry.LocalPort) { 
                [PSCustomObject]@{ Text = "In Use"; Color = "Red" }
            } else {
                [PSCustomObject]@{ Text = "Available"; Color = "Green" }
            }
            
            Write-Host ("  {0,2}. Port: {1,-5} ({2}) - Last used for {3} with profile {4}" -f $optionIndex, $entry.LocalPort, $status.Text, $entry.InstanceId, $entry.ProfileName) -ForegroundColor $status.Color
            
            $historyOptions[$optionIndex] = $entry.LocalPort
            $optionIndex++
        }
    }

    $selection = Read-Host "Select a recent port by number, or enter a new port number"

    if ($selection -match "^\d+$") {
        $portNum = [int]$selection
        
        if ($historyOptions.ContainsKey($portNum)) {
            # User selected a port from history
            $selectedPort = $historyOptions[$portNum]
            if ($activePorts -contains $selectedPort) {
                Write-Warning "Port $selectedPort is currently in use. Please choose another."
                continue
            }
            $localPort = $selectedPort
            break
        }
        
        # User entered a new port number
        if ($portNum -gt 0 -and $portNum -le 65535) {
            if ($activePorts -contains $portNum) {
                Write-Warning "Port $portNum is currently in use. Please choose another."
                continue
            }
            $localPort = $portNum
            break
        } else {
            Write-Warning "Port number must be between 1 and 65535."
        }
    } else {
        Write-Warning "Invalid input. Please enter a numeric port number or select from the list."
    }
}

# Prompt for remote port selection
$portSelection = Read-Host "Enter remote port to forward (22 for SSH, 3389 for RDP) [default is 3389]"
$remotePort = if ($portSelection -eq "22") { 22 } else { 3389 }

# Build and execute the AWS SSM command
Write-Host "Starting port forwarding session to instance $($selectedInstance.InstanceId)..."
$jsonParams = @{
    "portNumber" = @("$remotePort")
    "localPortNumber" = @("$localPort")
} | ConvertTo-Json -Compress
$command = "aws ssm start-session --target $($selectedInstance.InstanceId) --document-name AWS-StartPortForwardingSession --parameters '$jsonParams' --profile $AWSProfile --region $DefaultAwsRegion"

Write-Host "`nCommand to start session (for reference):"
Write-Host "$command"
Write-Host "JSON Parameters: $jsonParams"

# Start SSM tunnel in background job
Write-Host "`nStarting SSM tunnel in background..."
$jobName = "SSMTunnel_$(Get-Date -Format 'HHmmss')"
$job = Start-Job -ScriptBlock {
    param($command)
    # Execute the AWS command directly
    Invoke-Expression $command
} -ArgumentList $command -Name $jobName


# Wait a moment for tunnel to establish
Write-Host "Waiting for tunnel to establish..."
Start-Sleep -Seconds 3

# Check if job is still running (tunnel started successfully)
if ($job.State -eq "Running") {
    Write-Host "SSM tunnel is running in background." -ForegroundColor Green
    
    # Save the successful port to history
    Save-PortHistory -LocalPort $localPort -InstanceId $selectedInstance.InstanceId -ProfileName $AWSProfile

    # Launch RDP automatically
    if ($remotePort -eq 3389) {
        Write-Host "Launching RDP session to localhost:$localPort..."
        Start-Process "mstsc.exe" -ArgumentList "/v:localhost:$localPort"
    } elseif ($remotePort -eq 22) {
        Write-Host "SSH tunnel established. Use: ssh <username>@localhost -p $localPort"
        if ($selectedInstance.KeyName -and $selectedInstance.KeyName -ne "(No Key)") {
            Write-Host "You might need to use your SSH key: ssh -i /path/to/$($selectedInstance.KeyName).pem <username>@localhost -p $localPort"
        }
    }
    
    # Function to stop tunnel gracefully
    function Stop-SsmTunnel {
        param([switch]$Force)
        
        Write-Host "Stopping SSM tunnel..."
        
        if ($job -and $job.State -eq "Running") {
            try {
                if ($Force) {
                    Remove-Job $job -Force
                    Write-Host "Tunnel stopped forcefully." -ForegroundColor Yellow
                } else {
                    Stop-Job $job
                    Remove-Job $job
                    Write-Host "Tunnel stopped gracefully." -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Error stopping tunnel: $($_.Exception.Message)"
                # Try force removal as fallback
                try {
                    Remove-Job $job -Force
                    Write-Host "Tunnel stopped with force." -ForegroundColor Yellow
                }
                catch {
                    Write-Error "Failed to stop tunnel completely."
                }
            }
        }
        
        # Clean up any remaining jobs with similar names
        Get-Job -Name "SSMTunnel*" | Remove-Job -Force -ErrorAction SilentlyContinue
    }
    
    # Set up cleanup on script exit
    trap {
        Stop-SsmTunnel
        break
    }
    
    # Keep the job running and show status
    Write-Host "`nSSM tunnel is active. Available commands:"
    Write-Host "  Press 'q' to quit and stop tunnel"
    Write-Host "  Press 's' to stop tunnel gracefully"
    Write-Host "  Press 'f' to force stop tunnel"
    Write-Host "  Press 'i' to show tunnel info"
    Write-Host "  Press 'l' to list active local SSM tunnels"
    
    do {
        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            switch ($key.Character.ToString().ToLower()) {
                'q' { 
                    Write-Host "`nQuitting..."
                    Stop-SsmTunnel
                    break 
                }
                's' { 
                    Write-Host "`nStopping tunnel gracefully..."
                    Stop-SsmTunnel
                    break 
                }
                'f' { 
                    Write-Host "`nForce stopping tunnel..."
                    Stop-SsmTunnel -Force
                    break 
                }
                'i' {
                    Write-Host "`nTunnel Status:"
                    Write-Host "  Job Name: $($job.Name)"
                    Write-Host "  Job ID: $($job.Id)"
                    Write-Host "  State: $($job.State)"
                    Write-Host "  Local Port: $localPort"
                    Write-Host "  Remote Port: $remotePort"
                    Write-Host "  Instance: $($selectedInstance.InstanceId) ($($selectedInstance.Name))"
                    Write-Host "  Profile: $AWSProfile"
                }
                'l' {
                    Show-ActiveLocalTunnels
                }
            }
        }
        
        # Show periodic status
        if ((Get-Date).Second % 30 -eq 0) {
            Write-Host "Tunnel status: $($job.State)" -ForegroundColor Green
        }
        
        Start-Sleep -Milliseconds 100
    } while ($job.State -eq "Running")
    
    Write-Host "SSM tunnel has stopped."
} else {
    Write-Host "Failed to start SSM tunnel. Job state: $($job.State)" -ForegroundColor Red
    
    # Get job output for debugging
    if ($job.HasMoreData) {
        Write-Host "Job output:"
        Receive-Job $job
    }
    
    # Check for any error output
    if ($job.ChildJobs) {
        foreach ($childJob in $job.ChildJobs) {
            if ($childJob.HasMoreData) {
                Write-Host "Child job output:"
                Receive-Job $childJob
            }
        }
    }
    
    # Clean up failed job
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    exit 1
}
