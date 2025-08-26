# AWS SSM Tunnel Helper

**Bottom Line Up Front**: `ssmtunnel.ps1` creates secure SSH/RDP tunnels to AWS EC2 instances through AWS Systems Manager (SSM). No direct internet access required.

## Quick Start

```powershell
# Run the script
./ssmtunnel.ps1

# Or with specific profile/region
./ssmtunnel.ps1 -AWSProfile "production" -AWSRegion "us-west-2"
```

The script will guide you through:
1. Select AWS profile and region
2. Choose EC2 instance from GridView
3. Pick ports (local → remote)
4. Connect (RDP launches automatically for Windows)

## Features

- **Smart port management** - remembers your preferences, avoids conflicts
- **Interactive controls** - `q`uit, `s`top, `l`ist active tunnels while running
- **Multi-region support** - change regions from the UI
- **Profile management** - create, delete, rename AWS profiles
- **Background tunnels** - run multiple connections simultaneously

## Requirements

- Windows 10/11 with PowerShell
- AWS credentials configured (`aws configure` or `aws configure sso`)
- AWS CLI v2 (auto-installs if missing, requires admin)

## How It Works

```
Your Computer ←→ AWS SSM ←→ EC2 Instance
   (port 9000)              (port 22/3389)
```

## Required AWS Permissions

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

**EC2 Requirements:**
- SSM Agent running
- IAM role with `AmazonSSMManagedInstanceCore` 
- Instance in "Running" state

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "No AWS CLI found" | Script auto-installs (needs admin) |
| "No running instances" | Check instance state and SSM agent |
| "Tunnel failed" | Verify AWS permissions |
| "Port in use" | Use different port from history |

## License

MIT License
