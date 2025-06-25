param (
    [string]$AWSProfile
)

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

if (-not $AWSProfile) {
    while ($true) {
        $availableProfiles = Show-ProfileList
        if ($availableProfiles.Count -eq 0) {
            Write-Host "No AWS profiles found in $env:USERPROFILE\.aws\config or the file does not exist."
            Write-Host "Please specify a profile with -AWSProfile <profile-name>"
            exit
        }
        
        $newProfileOptionNumber = $availableProfiles.Count + 1
        $deleteProfileOptionNumber = $availableProfiles.Count + 2
        $renameProfileOptionNumber = $availableProfiles.Count + 3
        Write-Host "  $newProfileOptionNumber. Configure a new SSO profile"
        Write-Host "  $deleteProfileOptionNumber. Delete a profile"
        Write-Host "  $renameProfileOptionNumber. Rename a profile"
        
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
    Write-Host "AWS CLI is not installed. Downloading and installing AWS CLI v2..."

    $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $installerPath = "$env:TEMP\AWSCLIV2.msi"

    # Download the installer
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    } catch {
        Write-Host "Failed to download AWS CLI installer. Please check your internet connection."
        exit
    }

    # Install AWS CLI
    try {
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn"
    } catch {
        Write-Host "Failed to install AWS CLI. Please run this script as Administrator."
        exit
    }

    # Remove installer
    Remove-Item $installerPath -Force

    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # Check again
    if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
        Write-Host "AWS CLI installation failed or is not in PATH. Please restart your terminal or install manually."
        exit
    } else {
        Write-Host "AWS CLI v2 installed successfully."
    }
}

# Fetch instance details
Write-Host "Fetching EC2 instance list for profile '$AWSProfile'..."
$awsOutput = aws ec2 describe-instances --profile $AWSProfile --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name']|[0].Value,State.Name,PlatformDetails,KeyName]" --output json 2>&1

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

# Prompt for local port number
$localPort = ""
while ($true) {
    $localPort = Read-Host "Enter the local port number to forward to (e.g., 56789). This is required"
    if ($localPort -match "^\d+$") {
        $portNum = [int]$localPort
        if ($portNum -gt 0 -and $portNum -le 65535) {
            break # Valid port entered
        } else {
            Write-Warning "Port number must be between 1 and 65535."
        }
    } else {
        Write-Warning "Invalid input. Please enter a numeric port number."
    }
}

# Prompt for remote port selection
$portSelection = Read-Host "Enter remote port to forward (22 for SSH, 3389 for RDP) [default is 3389]"
$remotePort = if ($portSelection -eq "22") { 22 } else { 3389 }

# Build and execute the AWS SSM command
Write-Host "Starting port forwarding session to instance $($selectedInstance.InstanceId)..."
$jsonParams = "{`"portNumber`":[`"$remotePort`"],`"localPortNumber`":[`"$localPort`"]}"
$command = "aws ssm start-session --target $($selectedInstance.InstanceId) --document-name AWS-StartPortForwardingSession --parameters '$jsonParams' --profile $AWSProfile"

Write-Host "`nCommand to start session (for reference):"
Write-Host "$command"

# Start SSM tunnel in background job
Write-Host "`nStarting SSM tunnel in background..."
$jobName = "SSMTunnel_$(Get-Date -Format 'HHmmss')"
$job = Start-Job -ScriptBlock {
    param($command)
    Invoke-Expression $command
} -ArgumentList $command -Name $jobName

# Wait a moment for tunnel to establish
Write-Host "Waiting for tunnel to establish..."
Start-Sleep -Seconds 3

# Check if job is still running (tunnel started successfully)
if ($job.State -eq "Running") {
    Write-Host "SSM tunnel is running in background." -ForegroundColor Green
    
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
                    Write-Host "  Instance: $($selectedInstance.InstanceId)"
                    Write-Host "  Profile: $AWSProfile"
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
    
    # Clean up failed job
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    exit 1
}
