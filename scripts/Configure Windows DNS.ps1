# !Attention!
# This script must be run using Powershell version 5
# This script does NOT work on Powershell 7.2 or higher

############################################
# Parameters
############################################

$pingMode = $true           # To get camera pings only, $true or $false
$checkDNSMode = $false       # To check 'MAIN' adapter DNS configurations, $true or $false
$fixDNSMode = $false        # To set 'MAIN' DNS to DC01 & DC02, $true or $false

# Surpress Warnings for waiting service 'Windows Remote Management (WS-Management) (WinRM)' to stop
$WarningPreference = "silentlyContinue"

# DNS Settings to match with the same value in specific order
$adapterName = "MAIN"
$referenceDNS = @("192.168.1.DC1", "192.168.1.DC2", "1.1.1.1")

# File Paths
$rootPath = "C:\DNS Remote Configuration"
$logPath = "${$rootPath}\logs"
$csvPath = "${$rootPath}\csv\computer_names.csv" # CSV file containing "Identifier", "Computer Name" and "IP" columns

# $pilotRaw = "computer1, computer2, computer3" #Pilot2
# $pilotList = $pilotRaw -split ','

# Create a ConcurrentDictionary
$sites = Import-Csv -Path $csvPath | ?{ $_.'SITE CODE' -in $pilotList } | select -Property `
    'Identifier'`
    'Computer Name'`
    ,'IP'`
    , @{Name="status";Expression={'unknown'} }`
    , @{Name="is_connected";Expression={$false} }`
    , @{Name="adapter_index";Expression={$null} }`
    , @{Name="currentDNS";Expression={$null} }`
    , @{Name="is_mismatchDNS";Expression={$null} }`
    | ?{$_.'Identifier' -and $_.'Computer Name' -and $_.'IP' }#Check if all columns are not null
$sites = $sites | ?{ $_.'Identifier' }

############################################
# Initialization
############################################

Start-Transcript -Path "$logPath\$($(Get-Date).ToString("yyyy-MMM-dd")).txt"

#############################################
# Check Ping & Target DNS Configurations
#############################################

if ($pingMode) {
    "INFO: Checking Target DNS Configurations..."
    $sites | Format-Table

    foreach ($site in $sites) {
        
        if (Test-Connection $site.IP -count 3 -quiet) {
            
            $site.status = "Online"
            $site.is_connected = $true
            if ($checkDNSMode) {
                try {
                    Get-Service -ComputerName $($site.'Computer Name') -Name WinRM | Set-Service -StartupType Manual -PassThru | Start-Service;
                    Get-NetAdapter -Cimsession $($site.'Computer Name') | ?{ $_.Name -eq $adapterName } | %{ $site.adapter_index += $_.ifIndex;  }
                    if ($site.adapter_index){
                        $site.status = "Found $($adapterName) adapter $($site.adapter_index)"
                        try {
                            Get-DNSClientServerAddress -CimSession $($site.'Computer Name') -interfaceIndex $site.adapter_index -AddressFamily IPv4 | select ServerAddresses | %{ $site.'currentDNS' = $_.ServerAddresses }
                        } catch {
                            throw "ERROR: Failed to get DNS address. Reason: $_."
                        }
                        if ( (Compare-Object -ReferenceObject $referenceDNS -DifferenceObject $site.currentDNS -SyncWindow 0) -eq $null ) {
                            $site.status = "DNS Setting Matches"
                        } else {
                            $site.status = "Failed to match DNS Setting"
                            $site.is_mismatchDNS = $true
                        }
                    }
                } catch {
                    throw "WARN: Failed to find Main adapter for $($site.'Computer Name'). Skipping $($site.'IP')..."
                } finally {
                    Get-Service -ComputerName $($site.'Computer Name') -Name WinRM | Stop-Service -PassThru | Set-Service -StartupType Disabled;
                }
            }
        } else {
            $site.status = "Network unreachable"
            $site.is_connected = $false
        }
    }

    # Debug
    "INFO: Finished checking all DNS configurations. Result is as follows:"
    $sites | Format-Table

}

#############################################
# Fix Target DNS Configurations
#############################################

if ($fixDNSMode) {
    "INFO: Fixing Target DNS Configurations... Sites with mismatch DNS are listed below:"
    $sites | ?{ $_.is_mismatchDNS } | Format-Table

    foreach ($site in $sites | ?{ $_.is_mismatchDNS }) {
            
            if ($site.'Computer Name' -and $site.adapter_index) {
                try {
					"INFO: Fixing DNS setting for $($site.'Computer Name') at $($site.IP)."
                    Get-Service -ComputerName $($site.'Computer Name') -Name WinRM | Set-Service -StartupType Manual -PassThru | Start-Service;
                    Set-DNSClientServerAddress -Cimsession $($site.'Computer Name') –interfaceIndex $site.adapter_index –ServerAddresses $referenceDNS;
                    $site.status = "Attempted to fix DNS"

                    # Verify DNS settings
                    try {
                        Get-DNSClientServerAddress -CimSession $($site.'Computer Name') -interfaceIndex $site.adapter_index -AddressFamily IPv4 | select ServerAddresses | %{ $site.'currentDNS' = $_.ServerAddresses }
                    } catch {
                        throw "ERROR: Failed to get DNS address for verification after attempted to fix DNS. Reason: $_."
                    }
                    if ( (Compare-Object -ReferenceObject $referenceDNS -DifferenceObject $site.currentDNS) -eq $null ) {
						"INFO: Fixed and verified DNS setting for $($site.'Computer Name') at $($site.IP)."
                        $site.status = "DNS Fixed & Verified"
                    } else {
                        $site.status = "Failed to fix DNS Setting"
                    }
                    
                } catch {
                    "WARN: Failed to set DNS address for $($site.'Computer Name') at $($site.IP). Reason: $_"
                } finally {
                    Get-Service -ComputerName $($site.'Computer Name') -Name WinRM | Stop-Service -PassThru | Set-Service -StartupType Disabled;
                }
            }
    }

    # Result
    "Completed: Finished fixing all DNS configurations. Result is as follows:"
    $sites | Format-Table

}

"INFO: Script Completed."
Stop-Transcript
Return