# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a PowerShell script (`ssmtunnel.ps1`) that provides an interactive AWS SSM port forwarding tunnel helper for Windows environments. The script establishes secure tunnels to EC2 instances using AWS Systems Manager (SSM) and automatically launches RDP or provides SSH connection instructions.

## Key Architecture Components

### Core Functionality
- **Interactive Profile Selection**: Multi-level menu system for AWS profile selection with SSO support
- **Instance Selection**: Out-GridView interface for EC2 instance selection with real-time AWS API queries
- **Port Management**: Smart port selection with history tracking and availability scanning
- **Background Job Management**: PowerShell jobs for non-blocking tunnel execution
- **Caching System**: Instance name caching to reduce AWS API calls

### Data Management
- **Port History**: JSON-based history tracking in `~\.ssmtunnel\porthistory.json`
- **Instance Name Cache**: Cached instance names in `~\.ssmtunnel\instance_names.json`
- **Profile Management**: Direct manipulation of AWS config files (`~\.aws\config`, `~\.aws\credentials`)

### Key Functions
- `Get-ActiveLocalTunnels()`: Detects active SSM tunnels by scanning ports 8999-9050
- `Show-ActiveLocalTunnels()`: Displays comprehensive tunnel status with job correlation
- `Get-PortHistory()` / `Save-PortHistory()`: Manages port usage history
- `Get-AwsProfiles()` / `Get-ProfileGroups()`: Parses AWS config for profile management
- `Stop-SsmTunnel()`: Graceful tunnel cleanup with force option

## Development Commands

### Testing the Script
```powershell
# Run the script directly
./ssmtunnel.ps1

# Test with specific profile
./ssmtunnel.ps1 -AWSProfile "your-profile-name"

# Test AWS CLI integration
aws --version
aws configure list-profiles
```

### Debugging
```powershell
# Check PowerShell version (requires 7+)
$PSVersionTable.PSVersion

# Monitor background jobs
Get-Job -Name "SSMTunnel*"

# Check active ports
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -ge 8999 -and $_.LocalPort -le 9050 }

# View port history
Get-Content "$env:USERPROFILE\.ssmtunnel\porthistory.json" | ConvertFrom-Json
```

## Technical Requirements

- **PowerShell 7+** (recommended)
- **AWS CLI v2** (auto-installed if missing)
- **Windows 10/11**
- SSM-enabled EC2 instances with proper IAM permissions

## Key Variables and Configuration

- `$DefaultAwsRegion`: Default AWS region (currently "us-east-1")
- `$ScriptVersion`: Version tracking for the script
- `$historyDir`: User profile directory for persistent data (`~\.ssmtunnel`)
- Port range: 8999-9050 for tunnel detection and management

## Error Handling Patterns

The script implements comprehensive error handling for:
- AWS credential expiration and SSO token refresh
- Network connectivity issues
- Port conflicts and availability
- PowerShell job lifecycle management
- AWS CLI installation and PATH configuration

## Interactive Features

- Real-time tunnel status monitoring with keyboard shortcuts (q/s/f/i/l)
- Dynamic profile management (create/delete/rename)
- Port history with availability status
- Instance name caching with manual refresh option