# AWS SSM Tunnel Helper (`ssmtunnel.ps1`)

## Overview

`ssmtunnel.ps1` is a comprehensive PowerShell script that provides an interactive AWS SSM port forwarding tunnel helper for Windows environments. The script establishes secure tunnels to EC2 instances using AWS Systems Manager (SSM) and automatically launches RDP or provides SSH connection instructions. It features advanced tunnel management, port history tracking, and instance name caching for an enhanced user experience.

If you ALREADY have AWS Profiles setup - just run ./ssmtunnel.ps1 - you can choose from there.

## Features

### Core Functionality
- **Interactive Profile Selection**: Multi-level menu system with SSO support and profile management
- **Instance Selection**: Out-GridView interface for EC2 instance selection with real-time AWS API queries
- **Smart Port Management**: Port history tracking, availability scanning, and conflict detection
- **Background Job Management**: Non-blocking PowerShell jobs for tunnel execution
- **Automatic Client Launch**: RDP (mstsc.exe) auto-launch for Windows instances
- **SSH Instructions**: Detailed SSH connection guidance for Linux instances

### Advanced Features
- **Active Tunnel Detection**: Scans ports 8999-9050 to identify active SSM tunnels
- **Port History**: JSON-based tracking of recently used ports with instance correlation
- **Instance Name Caching**: Reduces AWS API calls by caching instance names locally
- **Profile Management**: Create, delete, and rename AWS profiles directly from the script
- **Real-time Monitoring**: Interactive controls for tunnel status and management
- **Comprehensive Error Handling**: AWS credential expiration detection and recovery guidance

### Interactive Controls
While tunnels are active, use these keyboard shortcuts:
- `q` - Quit and stop tunnel
- `s` - Stop tunnel gracefully
- `f` - Force stop tunnel
- `i` - Show detailed tunnel information
- `l` - List all active local SSM tunnels

## Prerequisites

- **Windows 10/11**
- **PowerShell 7+** (recommended for optimal performance)
- **AWS CLI v2** (auto-installed if missing with Administrator privileges)
- AWS credentials and profiles configured (`~/.aws/config` and `~/.aws/credentials`)
- SSM-enabled EC2 instances with proper IAM permissions
- Network connectivity to AWS services

## Installation & Setup

1. Download `ssmtunnel.ps1` to your preferred directory
2. Open PowerShell 7+ (as user, not Administrator unless installing AWS CLI)
3. Configure AWS profiles:
   ```powershell
   aws configure sso  # For SSO profiles
   aws configure      # For standard profiles
   ```
4. Ensure EC2 instances have SSM agent enabled and proper IAM roles

## Usage

### Basic Usage
```powershell
# Run the script interactively
./ssmtunnel.ps1

# Run with specific profile
./ssmtunnel.ps1 -AWSProfile "your-profile-name"
```

### Workflow Steps
1. **Profile Selection**: Choose from organized SSO groups and non-SSO profiles
2. **SSO Authentication**: Optional SSO login prompt for SSO-enabled profiles
3. **Instance Selection**: GridView selection of running EC2 instances with metadata
4. **Port Configuration**: 
   - Select from port history or enter new port
   - Choose remote port (22 for SSH, 3389 for RDP)
5. **Tunnel Management**: Background job execution with real-time monitoring

### Profile Management
From the main menu, you can:
- Configure new SSO profiles
- Delete existing profiles
- Rename profiles
- List active tunnels
- Refresh instance name cache

## Data Management

### Port History
- **Location**: `~\.ssmtunnel\porthistory.json`
- **Features**: Tracks last 10 used ports with instance and profile correlation
- **Status**: Real-time availability checking with color-coded display

### Instance Name Cache
- **Location**: `~\.ssmtunnel\instance_names.json`
- **Purpose**: Reduces AWS API calls by caching instance names locally
- **Management**: Manual refresh option available from main menu

## Technical Details

### Key Functions
- `Get-ActiveLocalTunnels()`: Detects active SSM tunnels on ports 8999-9050
- `Show-ActiveLocalTunnels()`: Displays comprehensive tunnel status with job correlation
- `Get-PortHistory()` / `Save-PortHistory()`: Manages persistent port usage history
- `Get-AwsProfiles()` / `Get-ProfileGroups()`: Parses AWS configuration for profile management
- `Stop-SsmTunnel()`: Graceful tunnel cleanup with force option

### Port Management
- **Default Range**: 8999-9050 for tunnel detection
- **Conflict Detection**: Real-time port availability scanning
- **History Integration**: Port reuse with instance correlation
- **Status Indicators**: Color-coded availability display

### Error Handling
- AWS credential expiration detection
- SSO token refresh guidance
- Network connectivity validation
- Port conflict resolution
- PowerShell job lifecycle management

## Command Examples

### Development & Testing
```powershell
# Test with specific profile
./ssmtunnel.ps1 -AWSProfile "prod-profile"

# Check AWS CLI integration
aws --version
aws configure list-profiles

# Monitor background jobs
Get-Job -Name "SSMTunnel*"

# Check active ports
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -ge 8999 -and $_.LocalPort -le 9050 }
```

### Debugging
```powershell
# Verify PowerShell version
$PSVersionTable.PSVersion

# View port history
Get-Content "$env:USERPROFILE\.ssmtunnel\porthistory.json" | ConvertFrom-Json

# Check instance name cache
Get-Content "$env:USERPROFILE\.ssmtunnel\instance_names.json" | ConvertFrom-Json
```

## Configuration

### Default Settings
- **AWS Region**: `us-east-1` (configurable in script)
- **Script Version**: `2.0`
- **Port Range**: 8999-9050
- **History Limit**: 10 entries
- **Data Directory**: `~\.ssmtunnel`

### AWS Profile Support
- **SSO Profiles**: Full support with automatic grouping by SSO URL
- **Standard Profiles**: Traditional AWS credential profiles
- **Multi-Region**: Configurable default region support

## Troubleshooting

### Common Issues
- **AWS CLI Missing**: Script auto-installs with Administrator privileges
- **Profile Not Found**: Use profile management menu to configure
- **No Running Instances**: Verify instance state and SSM agent status
- **Tunnel Failures**: Check AWS permissions and network connectivity
- **Port Conflicts**: Use port history to identify available ports

### Advanced Troubleshooting
- **Credential Expiration**: Automatic detection with SSO login guidance
- **Job Management**: Built-in cleanup for orphaned PowerShell jobs
- **Cache Issues**: Manual instance name cache refresh option
- **Performance**: Instance name caching reduces API call overhead

## Security Considerations

- **Local Data**: Port history and instance cache stored locally
- **Credential Management**: Leverages AWS CLI credential chain
- **Network Security**: Uses AWS SSM secure tunneling
- **Access Control**: Respects AWS IAM permissions

## Version History

- **v2.0**: Current version with enhanced features
  - Active tunnel detection and management
  - Port history tracking with persistence
  - Instance name caching system
  - Interactive profile management
  - Comprehensive error handling
  - Real-time tunnel monitoring

## Support

For issues or feature requests, refer to the project repository or AWS SSM documentation for tunnel-related problems.

## License

MIT License 
