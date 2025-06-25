# AWS SSM Tunnel Helper (`ssmtunnel.ps1`)

## Overview

`ssmtunnel.ps1` is a PowerShell script that helps you quickly establish a secure port forwarding tunnel to an AWS EC2 instance using AWS Systems Manager (SSM). It provides an interactive menu to select your AWS profile and EC2 instance, then launches an SSM port forwarding session in the background. For RDP-enabled instances, it automatically launches Remote Desktop (mstsc.exe) to connect to the forwarded port.

## Features
- Interactive AWS profile and EC2 instance selection
- Supports SSO and non-SSO AWS profiles
- Automatically launches RDP (mstsc.exe) for Windows instances
- SSH tunnel instructions for Linux instances
- Runs the SSM tunnel in a background job (non-blocking)
- Interactive controls to stop or inspect the tunnel
- Handles AWS CLI installation if missing

## Prerequisites
- **Windows 10/11**
- **PowerShell 7+** (recommended)
- **AWS CLI v2** (the script will attempt to install if missing)
- AWS credentials and profiles configured (`~/.aws/config` and `~/.aws/credentials`)
- SSM agent must be enabled on the target EC2 instance
- The instance must have the necessary IAM permissions for SSM

## Setup
1. Download or copy `ssmtunnel.ps1` to your local machine.
2. Open a PowerShell terminal as your user (not as Administrator unless needed for AWS CLI install).
3. Ensure your AWS profiles are configured (run `aws configure` or `aws configure sso` as needed).

## Usage
Run the script from PowerShell:

```powershell
# In the directory containing ssmtunnel.ps1
./ssmtunnel.ps1
```

### Steps:
1. **Profile Selection:**
   - The script lists available AWS profiles. Select by number or name.
   - You can also configure, delete, or rename profiles from the menu.
2. **SSO Login (if needed):**
   - The script will prompt to perform SSO login if required.
3. **Instance Selection:**
   - The script fetches running EC2 instances and displays them in a selection window.
4. **Port Selection:**
   - Enter the local port to forward (e.g., 9000).
   - Choose the remote port (22 for SSH, 3389 for RDP; default is 3389).
5. **Tunnel Establishment:**
   - The SSM tunnel starts in the background.
   - For RDP, mstsc.exe is launched automatically to connect to the forwarded port.
6. **Interactive Tunnel Control:**
   - While the tunnel is active, you can:
     - Press `q` to quit and stop the tunnel
     - Press `s` to stop the tunnel gracefully
     - Press `f` to force stop the tunnel
     - Press `i` to show tunnel info

## Example
```
./ssmtunnel.ps1
```
- Select your AWS profile (e.g., `prod`)
- Select the EC2 instance
- Enter local port (e.g., `9000`)
- Accept default remote port (3389 for RDP)
- RDP will launch and connect to `localhost:9000`

## Troubleshooting
- **AWS CLI not found:** The script will attempt to install AWS CLI v2 if missing.
- **No profiles found:** Run `aws configure` or `aws configure sso` to set up profiles.
- **No running instances:** Ensure your EC2 instance is running and has SSM enabled.
- **Tunnel not working:** Check your AWS permissions, SSM agent status, and network connectivity.
- **Script errors:** Ensure you are running PowerShell 7+ and have the necessary permissions.

## Notes
- The script does not require Administrator privileges unless installing AWS CLI.
- The tunnel must remain open for the RDP/SSH session to work. Closing the script or stopping the tunnel will disconnect your session.
- For SSH, use the provided instructions to connect via your forwarded port.

## License
MIT License (or specify your own) 