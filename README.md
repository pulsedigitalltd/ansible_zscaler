# Zscaler Client Connector Automated Deployment

This repository contains Ansible playbooks and scripts for automated deployment of Zscaler Client Connector across Linux and macOS endpoints with comprehensive tamper protection.

## Features

- ✅ Automated installation/updates of Zscaler Client Connector
- ✅ Root certificate installation and trust
- ✅ Comprehensive tamper protection mechanisms
- ✅ Service monitoring and auto-restart
- ✅ File integrity monitoring
- ✅ Network bypass prevention
- ✅ Alert notifications (Email & Slack)
- ✅ Detailed logging and reporting

## Prerequisites

### Control Node (where Ansible runs)
- Ansible 2.9+ with ansible-vault
- Python 3.6+
- SSH access to target nodes
- Valid Zscaler deployment credentials

### Target Nodes
- **Linux**: Ubuntu 18.04+, RHEL/CentOS 7+, or compatible
- **macOS**: macOS 10.15+ with admin privileges
- SSH key-based authentication configured
- Sudo/admin privileges for the deployment user

## Quick Start

### 1. Clone and Setup
```bash
git clone <repository-url>
cd zscaler-deployment
mkdir -p {group_vars/all,inventory,logs}
```

### 2. Configure Inventory
Edit `inventory/hosts` with your target systems:
```ini
[linux_clients]
server1 ansible_host=192.168.1.100 ansible_user=admin
server2 ansible_host=192.168.1.101 ansible_user=admin

[macos_clients]
mac1 ansible_host=192.168.1.200 ansible_user=admin
```

### 3. Configure Vault Variables
Create `group_vars/all/vault.yml`:
```bash
ansible-vault create group_vars/all/vault.yml
```

Add the following variables (customize for your environment):
```yaml
vault_zscaler_root_cert_url: "https://your-zscaler.zscalerbeta.net/auth/cert"
vault_zscaler_user_domain: "company.com"
vault_monitoring_email: "admin@company.com"
vault_slack_webhook: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

vault_zscaler_app_profile: |
  <?xml version="1.0" encoding="UTF-8"?>
  <AppProfile>
    <ServerName>your-zscaler.zscalerbeta.net</ServerName>
    <AppServerName>your-zscaler.zscalerbeta.net</AppServerName>
    <UserDomain>company.com</UserDomain>
    <HideAppUI>true</HideAppUI>
    <DisableUninstall>true</DisableUninstall>
    <AutoConnect>true</AutoConnect>
    <PolicyToken>your-policy-token</PolicyToken>
  </AppProfile>
```

### 4. Create Vault Password File
```bash
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
```

### 5. Test Connectivity
```bash
./deploy-zscaler.sh test
```

### 6. Deploy to All Systems
```bash
./deploy-zscaler.sh all
```

## Configuration Details

### Zscaler App Profile Settings

Key settings in your app profile for security:

- `<HideAppUI>true</HideAppUI>` - Hides UI from end users
- `<DisableUninstall>true</DisableUninstall>` - Prevents uninstallation
- `<AutoConnect>true</AutoConnect>` - Automatically connects on startup
- `<StrictCertCheck>true</StrictCertCheck>` - Enforces certificate validation
- `<TrustedNetworkDetection>false</TrustedNetworkDetection>` - Always enforces tunnel

### Tamper Protection Mechanisms

#### 1. Service Protection
- **Linux**: systemd service with restart policies and timers
- **macOS**: LaunchDaemon with KeepAlive and automatic restart

#### 2. File System Protection
- Configuration files marked as immutable (Linux: `chattr +i`, macOS: `chflags uchg`)
- File integrity monitoring with checksum validation
- Automatic permission and ownership restoration

#### 3. Network Protection
- iptables rules (Linux) and pfctl rules (macOS) to prevent DNS bypass
- Monitoring for VPN applications and proxy configurations
- Network connectivity checks to Zscaler cloud

#### 4. Process Protection
- Continuous process monitoring and restart
- Detection of bypass tools (proxychains, Tor, etc.)
- System extension verification (macOS)

#### 5. Advanced Monitoring
- Real-time file system monitoring with inotify (Linux)
- Audit logging for file access and modifications
- Email and Slack alerting for security events
- Comprehensive logging with severity levels

## Deployment Modes

### Individual Platform Deployment
```bash
# Deploy to Linux systems only
./deploy-zscaler.sh linux

# Deploy to macOS systems only  
./deploy-zscaler.sh macos
```

### Testing and Validation
```bash
# Test connectivity to all hosts
./deploy-zscaler.sh test

# Generate status report
./deploy-zscaler.sh report
```

### Emergency Procedures
```bash
# Stop all Zscaler services (for maintenance)
./deploy-zscaler.sh rollback
```

## Security Considerations

### Preventing Root User Bypass

Even with root access, users will find it difficult to disable Zscaler due to:

1. **Multi-layered Protection**: Multiple monitoring scripts and services
2. **Immutable Files**: Critical config files protected at filesystem level
3. **Service Resurrection**: Services automatically restart if stopped
4. **Network Enforcement**: Firewall rules prevent direct internet access
5. **Alerting**: Any tampering attempts trigger immediate alerts
6. **File Integrity**: Changes to binaries/configs are detected and can trigger reinstall

### Additional Hardening Options

For maximum security, consider:

1. **SELinux/AppArmor**: Additional MAC policies for Zscaler processes
2. **Kernel Module Protection**: Prevent loading of kernel modules that could bypass
3. **Hardware Security**: TPM-based attestation for system integrity
4. **Centralized Logging**: Forward all logs to SIEM for analysis
5. **Regular Auditing**: Periodic compliance checks

## Troubleshooting

### Common Issues

#### 1. Installation Fails
```bash
# Check logs
tail -f /var/log/zscaler-deployment/deployment-*.log

# Verify connectivity
ansible all -i inventory/hosts -m ping --vault-password-file .vault_pass
```

#### 2. Service Won't Start
```bash
# Linux
systemctl status zscaler
journalctl -u zscaler -f

# macOS  
launchctl list | grep zscaler
log show --predicate 'subsystem == "com.zscaler"' --last 1h
```

#### 3. Certificate Issues
```bash
# Linux - verify certificate installation
update-ca-certificates --verbose

# macOS - check keychain
security find-certificate -a -c "Zscaler" /Library/Keychains/System.keychain
```

### Log Locations

- **Deployment logs**: `/var/log/zscaler-deployment/`
- **Protection logs**: `/var/log/zscaler-protection.log`
- **Service logs**: 
  - Linux: `journalctl -u zscaler`
  - macOS: Console.app or `log show --predicate 'subsystem == "com.zscaler"'`

## Updating Zscaler

To update Zscaler to a new version:

1. Update the version variable in the playbooks:
```yaml
zscaler_version: "4.3.0"  # New version
```

2. Run the deployment again:
```bash
./deploy-zscaler.sh all
```

The playbooks will automatically handle stopping the service, updating, and restarting.

## Monitoring and Alerting

### Email Alerts
Configure SMTP on your systems or use a mail relay for email notifications.

### Slack Integration
1. Create a Slack app with webhook permissions
2. Add the webhook URL to your vault variables
3. Test alerts: `curl -X POST -H 'Content-type: application/json' --data '{"text":"Test"}' YOUR_WEBHOOK_URL`

### Log Analysis
Consider implementing:
- ELK stack for log aggregation
- Splunk for advanced analysis
- Grafana for visualization
- Custom scripts for specific monitoring needs

## Compliance and Auditing

### Audit Requirements
The deployment supports various compliance frameworks:

- **SOC 2**: Continuous monitoring and alerting
- **ISO 27001**: Access controls and change management
- **PCI DSS**: Network segmentation and monitoring
- **NIST**: Comprehensive logging and incident response

### Evidence Collection
Logs and reports can be used for:
- Compliance audits
- Incident response
- Forensic analysis
- Change tracking

## Support and Maintenance

### Regular Tasks
- Monitor alert notifications
- Review deployment logs weekly
- Update Zscaler versions quarterly
- Test rollback procedures annually
- Review and update tamper protection rules

### Breaking Changes
When updating this deployment system:
1. Test in a lab environment first
2. Update documentation and procedures
3. Train administrators on changes
4. Plan rollback procedures

## License and Disclaimer

This deployment framework is provided as-is for educational and enterprise use. Ensure compliance with your organization's security policies and Zscaler's licensing terms.

## Contributing

To contribute improvements:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly in a lab environment
4. Submit a pull request with detailed documentation

---

**Note**: This deployment creates a highly secure Zscaler installation that is designed to be tamper-resistant. Ensure you have appropriate procedures for legitimate maintenance and emergency access before deploying to production systems.