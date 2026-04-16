# FileCatalyst Direct Report and Monitor Scripts

Repair and report File Catalyst Direct (Client / Server) using Shell script and PowerShell 5.1 &amp; 7 Scripts.

> diagram

## Repair
`FCHF_repair_v5.bat` is a shell script that verify the local FileCatalyst HotFolder service, copy the configuration files over network, detects and remove corrupted .md5Cache and .err files due to rapid consecutive restarts.

### Repair Remotely + Report

`FileCatalyst Central at Home` uses a combination of PowerShell 5.1 &amp; 7.2 Scripts that allows parallel computing and remote Windows Management Instructments. It significantly lowered the script run time for 400+ servers from 3 hours to under 15 minutes. The script verifies the remote HotFolder service using API, verify HotFolder configurations, remotely execute the repair script that copies the latest configurations, and send out an email summary report once finished.

It is assumed that the repair script is distributed to the public desktop folder in each server, and proper security control IAM is implemented on the script.

> capture

## Grafana Monitoring Dashboard + Telegraf

`FileCatalyst.conf` configures Telegraf to run `FCnode1.sh` as a script which is a curl command to retrieve the csv report from FileCatalyst Server. The HTTP module might timeout and/or does not accept a very long json content.

> capture

## Miscellaneous / Related Scripts

- `Configure Windows DNS.ps1` - Input a list of domain computers. The PowerShell 5.1 script can ping, check the configured DNS servers on remote server and update with WMI if needed. Output the script log in a readable table. Log includes a list of computers with `Status`: Online | Network unreachable | Found adapter | DNS Setting Matches | Failed to match DNS Setting | Attempted to fix DNS | DNS Fixed & Verified | Failed to fix DNS Setting .
- `SMTP Template.ps1` - Send out an email via SMTP or STARTTLS using PowerShell. As of development, the `Send-MailMessage` cmdlet is outdated, however, there is no alternative module to send out HTML body email and allows attachment. Be aware of risk of STARTTLS. Use at own discretion.

# Disclaimer

These scripts, configurations, and instructions are provided as-is, without warranty of any kind. Use them at your own risk and discretion. Test thoroughly in a non-production environment before deploying anywhere that matters. Incorrect use may cause service disruption, misconfiguration, data loss, or other harm to systems and data. You are solely responsible for backups, validation, and any consequences of use or deployment.