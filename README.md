# AWS SSM Tunnel Helper

**Bottom Line Up Front**: `ssmtunnel.ps1` creates secure SSH/RDP tunnels to AWS EC2 instances through AWS Systems Manager (SSM) with an interactive PowerShell interface. No direct internet access to instances required.

## What It Does

Creates secure tunnels to your AWS EC2 instances using AWS SSM, then:
- **For Windows instances**: Automatically launches Remote Desktop (RDP)
- **For Linux instances**: Provides SSH connection commands
- **Manages multiple tunnels**: Track, monitor, and control active connections
- **Smart port selection**: Remembers your preferences and avoids conflicts

![Demo showing profile selection and tunnel creation]

## Quick Start

```powershell
# Download and run
./ssmtunnel.ps1

# Or with a specific AWS profile
./ssmtunnel.ps1 -AWSProfile "your-profile-name"
```

**That's it!** The script will guide you through:
1. Selecting your AWS profile
2. Choosing an EC2 instance
3. Picking a local port
4. Establishing the tunnel

## How It Works

```
Your Computer ←→ AWS SSM ←→ EC2 Instance
    (port 9000)              (port 22/3389)
```

1. **Select Profile**: Choose from your configured AWS profiles
2. **Pick Instance**: GridView shows your running EC2 instances
3. **Choose Ports**: Local port (e.g., 9000) → Remote port (22 for SSH, 3389 for RDP)
4. **Connect**: Tunnel runs in background, RDP launches automatically

## Example Session

```powershell
PS> ./ssmtunnel.ps1

AWS SSM Tunnel Helper v2.0
==========================

1) SSO Profiles
   └─ Production Environment
   └─ Development Environment
2) Standard Profiles
   └─ default
   └─ personal-account

Select profile: 1

[GridView opens showing instances...]
Selected: web-server-01 (i-1234567890abcdef0)

Port Selection:
 ✓ 9001 (last used with web-server-01)
   9002 (available)
   9003 (available)

Local port: 9001
Remote port: 3389

Starting tunnel... ✓
Launching Remote Desktop...

Tunnel active on localhost:9001
Press 'q' to quit, 's' to stop, 'l' to list all tunnels
```

## Installation Requirements

**Required:**
- Windows 10/11
- PowerShell 7+ (recommended)
- AWS credentials configured

**Auto-installed if missing:**
- AWS CLI v2 (requires admin privileges)

**AWS Setup:**
```powershell
# For SSO
aws configure sso

# For standard profiles
aws configure
```

## Key Features

### Interactive Controls
While tunnels are running:
- `q` - Quit and stop tunnel
- `s` - Stop tunnel gracefully  
- `f` - Force stop tunnel
- `i` - Show tunnel details
- `l` - List all active tunnels

### Smart Port Management
- **Port History**: Remembers last 10 ports used with each instance
- **Availability Check**: Real-time scanning to avoid conflicts
- **Color Coding**: Green (available), Red (in use), Yellow (unknown)

### Profile Management
- **SSO Support**: Automatic grouping by SSO domain
- **Profile Operations**: Create, delete, rename profiles
- **Multi-Region**: Configurable default regions

### Background Processing
- **Non-blocking**: Tunnels run as PowerShell background jobs
- **Monitoring**: Real-time status updates
- **Cleanup**: Automatic cleanup of orphaned processes

## Advanced Usage

### Multiple Tunnels
```powershell
# Run multiple instances for different servers
./ssmtunnel.ps1  # Terminal 1 - connects to web server
./ssmtunnel.ps1  # Terminal 2 - connects to database server
```

### Command Line Options
```powershell
# Skip profile selection
./ssmtunnel.ps1 -AWSProfile "production"

# Debug mode (check background jobs)
Get-Job -Name "SSMTunnel*"

# View active tunnels
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -ge 8999 -and $_.LocalPort -le 9050 }
```

### Data Storage
```powershell
# Port history
~\.ssmtunnel\porthistory.json

# Instance name cache (speeds up loading)
~\.ssmtunnel\instance_names.json
```

## Troubleshooting

**Common Issues:**

| Problem | Solution |
|---------|----------|
| "No AWS CLI found" | Script will auto-install (needs admin) |
| "Profile not found" | Use profile management menu |
| "No running instances" | Check instance state and SSM agent |
| "Tunnel failed" | Verify AWS permissions and connectivity |
| "Port in use" | Check port history for alternatives |

**Advanced Debugging:**
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# View stored data
Get-Content "$env:USERPROFILE\.ssmtunnel\porthistory.json" | ConvertFrom-Json

# AWS connectivity test
aws sts get-caller-identity --profile your-profile
```

## Security & Permissions

**Required AWS Permissions:**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:StartSession",
                "ssm:TerminateSession",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

**EC2 Instance Requirements:**
- SSM Agent installed and running
- IAM role with `AmazonSSMManagedInstanceCore` policy
- Instance must be "Running" state

**Data Security:**
- All connections encrypted via AWS SSM
- No credentials stored locally (uses AWS CLI credential chain)
- Port history stored locally in user profile

## Version History

**v2.0 (Current)**
- Active tunnel detection and management
- Port history with persistence
- Instance name caching
- Interactive profile management
- Real-time monitoring controls

## License

MIT License