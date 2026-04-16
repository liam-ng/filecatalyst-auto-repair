# !Attention!
# This script must be run using Powershell version 7.2 or higher

############################################
# Parameters
############################################

$concurrentLimit = 60          # Number of threads to run the script which should be multiple of number of vCores of 6
$authMode = $true              # To check connectivity & authentications
$checkConfigMode = $true       # To check the exported configs (.xml or .conf) against reference configs located in ./ref/ folder
$repairFCMode = $true          # To remotely execute FCHF_repair.bat on target desktop
$importConfigMode = $false     # To import reference configs to target machine
$configs = @('sites', 'hotfolders' , 'tasks' , 'bandwidth') # Case-sensitive

# File Paths
$rootPath = "C:\FileCatalyst Central at Home"
$refPath = "${$rootPath}\ref"
$csvPath = "${$rootPath}\csv\test.csv"

# Insert latest base64 encoded passwords to the leftmost item of $auths
$auths = @("password3", "password2", "password1")
$latestAuth = $auths[0]

############################################
# Initialization
############################################

Start-Transcript -Path "$rootPath\logs\$($(Get-Date).ToString("yyyy-MMM-dd")).txt"

# Reference a local csv file for list of sites
# It is possible to retrieves list of sites using REST, not shown here for brevity


$csv = Import-Csv -Path $csvPath | select -Property `
    'Identifier'`
    ,'Computer name'`
    ,'IP'`
    , @{Name="status";Expression={'unknown'} }`
    , @{Name="is_connected";Expression={$false} }`
    , @{Name="is_latest_password";Expression={$null} }`
    , @{Name="is_known_password";Expression={$null} }`
    , @{Name="currentAuth";Expression={$null} }`
    , @{Name="does_ALL_config_match";Expression={$null} }`
    , @{Name="mismatchConfigs";Expression={$null} }`
    , @{Name="importedConfigs";Expression={$null} }`
    , @{Name="serviceStatus";Expression={$null} }`
    | ?{$_.'Identifier' -and $_.'Computer name' -and $_.'IP'}

# Create a ConcurrentDictionary
$sites = [System.Collections.Concurrent.ConcurrentDictionary[string, [PSCustomObject]]]::new()

# Populate the ConcurrentDictionary, note that key is unique
foreach ($site in $csv | ?{ $_.'Identifier' } ) {
    $sites[$site.'Computer name'] = $site
}
# Debug
 #$sites.Values | Format-Table -AutoSize

#############################################
# DNS Lookup to populate IP column
#############################################

$sites.Values.'Computer name' | ForEach-Object -ThrottleLimit $concurrentLimit -Parallel {
    $cur = $using:sites
    if ($cur.ContainsKey($_)) {
        $rec = $cur[$_]
    } else { 
        throw "Failed to find $_ in sites variable. `r`nExiting parallel execution" 
    }

    if ( $dnsIP = (Resolve-DnsName -Name $rec.'Computer name').IPAddress ){
        $rec.IP = $dnsIP
    } else {
        $rec.IP = 'unresolvable'
    }
}


#############################################
# Check Authentication
# GET AuthorizationSessionRev1
#############################################

if ($authMode) {
    $sites.Values | ?{ $_.IP -ne "unresolvable" -and ($_.IP).GetType() -eq [String] } | ForEach-Object -ThrottleLimit $concurrentLimit -Parallel {
        if (Test-Connection $_.IP -count 1 -quiet) {
        
            $cur = $using:sites
            if ($cur.ContainsKey($_.'Computer name')) {
                $rec = $cur[$_.'Computer name']
            } else { 
                throw "Failed to find $($_.IP) in sites variable. `r`nExiting parallel execution" 
            }

            $rec.is_connected = $true

            ForEach ($auth in $($using:auths)) {
                #"Trying to reach http://$($_.IP):12580/rs/AuthorizationSessionRev1 with $auth"
                try {
                    $res = Invoke-WebRequest -TimeoutSec 35 -UseBasicParsing -Uri "http://$($_.IP):12580/rs/AuthorizationSessionRev1" -Method POST -ContentType "application/json" -Body "{`"authorization`":`"$auth`"}" -SkipHttpErrorCheck 
                    if ($res.StatusCode -eq 200){ 
                        "Found auth: $($_.IP) with $auth";
                        # Update the record in the ConcurrentDictionary
                        $rec.status = 'Authentication succeeded'
                        $rec.is_known_password = $true
                        $rec.currentAuth = $auth
                        if ($auth -match $using:latestAuth) { $rec.is_latest_password = $true } else { $rec.is_latest_password = $false }
                        break;
                    } else { 
                        "Failed to authenticate $($_.IP) with $auth";
                        $rec.status = 'Authentication failed'
                        $rec.is_known_password = $false
                        Start-Sleep -Seconds 3
                    }
                } Catch {
                    "Caught Exception during FileCatalyst Authentication: $($_.IP)."
                    $rec.status = 'Check FC Interface or Service'
                }
            }
        } else {
            $cur = $using:sites
            if ($cur.ContainsKey($_.'Computer name')) {
                $rec = $cur[$_.'Computer name']
                $rec.status = 'Network unreachable'
            }
        }
    }
}

#############################################
# Check Configs
# GET sites | hotfolders | tasks | bandwidth
#############################################

# Strip HotFolderIdentity, TaskID, Password from XML | Select-String -Pattern $pattern -NotMatch
# Because each target computer has a unique HotFolderIdentity, TaskID, Password
$unwantedPattern = @('Password','HotFolderIdentity','TaskID','ReferenceDate')

if ($checkConfigMode) {
    "Checking target configs..."
	$sites.Values | ?{ $_.currentAuth -ne $null } | Format-Table
	
	# Filter cameras with valid Authentication
    $sites.Values | ?{ $_.currentAuth -ne $null } | ForEach-Object -ThrottleLimit $concurrentLimit -Parallel {
		#"Start checking for site $($rec.'Identifier')!"
        
        $unmatchedConfigs = $null
        $cur = $using:sites
        if ($cur.ContainsKey($_.'Computer name')) {
            $rec = $cur[$_.'Computer name']
            $auth = $rec.currentAuth
        } else { 
            throw "Failed to find $_.IP in sites variable. `r`nExiting parallel execution" 
        }

        ForEach ($config in $($using:configs)){
            #"Trying to reach for site $($rec.'Identifier') http://$($rec.IP):12580/rs/exportData/$($config)"
			try {
				$res = Invoke-WebRequest -TimeoutSec 35 -UseBasicParsing -Uri "http://$($rec.IP):12580/rs/exportData/$($config)" -Method GET -SkipHttpErrorCheck -Headers @{ "Accept" = "application/octet-stream"; "RESTAuthorization" = "$auth"; "ContentType" = "*/*"}
            } catch { 
				throw "Caught exception when reaching for site $($rec.'Identifier') $($config). Reason: $_" 
			}
            #"Trying to get reference files from $refPath. Symlink to 172.23.14.12."
			try {
				$ref = Get-Content "$using:refPath\$(if($config -eq "tasks"){"schedule"}else{"$config"}).xml" | Select-String -NotMatch -Pattern $using:unwantedPattern
			} catch {
				throw "Caught exception when getting reference files $($rec.'Identifier') $($config). Reason: $_" 
			}
            # Parse file name and read reference config line by line
            # Removed last line with redundant `r`n
            # Filter lines with unwanted pattern
            $diff = ([System.Text.Encoding]::UTF8.GetString($res.Content) -split "`r`n") | Select-String -Pattern $using:unwantedPattern -NotMatch
            
            # Parse variables into PSObject for Compare-Object function
            $obj = @{
                ReferenceObject = $ref
                DifferenceObject = $diff[0..($diff.Length - 2)]
            }

            # Change summary table status
            # Compare-Object return null when every lines match
			#"Comparing for site $($rec.'Identifier'):  `r`n$(Compare-Object @obj)"
            if ( (Compare-Object @obj) -eq $null ) {
                #"$($rec.IP) $($config) config matches with reference."
            } else {
                "Failed to match $($rec.IP) $($config) with reference."
                $unmatchedConfigs += "$config<br style=`"mso-data-placement:same-cell;`">"
            }
			#"Done comparing site $($rec.'Identifier') http://$($rec.IP):12580/rs/exportData/$($config)"
        }
		#"Done checking for site $($rec.'Identifier')!"
        #"Start updating records for site $($rec.'Identifier')!"
        if ($unmatchedConfigs -eq $null) {
			#"site $($rec.'Identifier') all configs match: $($unmatchedConfigs)"
            $rec.status = 'Configurations match'
            $rec.does_ALL_config_match = $true

        } else {
			"site $($rec.'Identifier') has unmatch configs: $($unmatchedConfigs)"
            $rec.status = 'Mismatch Configurations'
            $rec.does_ALL_config_match = $false
            $rec.mismatchConfigs = $unmatchedConfigs
        }
		#"Done updating records for site $($rec.'Identifier')!"
    }
	#"Finished checking target configs..."
}

##############################################
# Import Configs
# POST sites | hotfolders | tasks | bandwidth
##############################################

<#
# PowerShell 5 
$exported = Get-Content -Path "$refPath\hotfolders.xml" -Encoding Byte
$fileBytes = [System.IO.File]::ReadAllBytes($FilePath);
$fileEnc = [System.Text.Encoding]::GetEncoding('UTF-8').GetString($fileBytes);
#>

# Powershell 7.2 -AsByteStream

if ($importConfigMode) {
    "Importing reference configs to target FileCatalyst HotFolder..."
	$sites.Values | ?{ $_.mismatchConfigs -ne $null } | Format-Table
    $sites.Values | ?{ $_.mismatchConfigs -ne $null } | ForEach-Object -ThrottleLimit $concurrentLimit -Parallel {
    
        $imported = $null
        $cur = $using:sites
        if ($cur.ContainsKey($_.'Computer name')) {
            $rec = $cur[$_.'Computer name']
            $auth = $rec.currentAuth
        } else { 
            throw "Failed to find $_.IP in sites variable. `r`nExiting parallel execution" 
        }

        ForEach ($config in $($rec.mismatchConfigs).split("<br style=`"mso-data-placement:same-cell;`">", [StringSplitOptions]::RemoveEmptyEntries)){
            # Parse reference XML into text stream
            $boundary = [System.Guid]::NewGuid().ToString(); 
            $LF = "`r`n";
            $fileEnc = Get-Content "$using:refPath\$(if($config -eq "tasks"){"schedule"}else{"$config"}).xml" -Raw
            $bodyLines = ( 
                "--$boundary",
                "Content-Disposition: form-data; name=`"dataFile`"; filename=`"hotfolders.xml`"",
                "Content-Type: application/octet-stream$LF",
                $fileEnc,
                "--$boundary--$LF" 
            ) -join $LF
            
            #"Trying to reach http://$($rec.IP):12580/rs/importData/$($config)"
            $res = Invoke-WebRequest -UseBasicParsing -Uri "http://$($rec.IP):12580/rs/importData/$($config)" `
                -Method POST `
				-TimeoutSec 65 `
                -SkipHttpErrorCheck `
                -Headers @{ "Accept" = "application/json"; "RESTAuthorization" = "$auth"; }`
                -ContentType "multipart/form-data; boundary=`"$boundary`"" `
                -Body ($bodyLines)
            "$res"

            # Change summary table status
            if ( $res.StatusCode -eq 200 ) {
                "Imported reference $($config) config for $($rec.IP)."
                $imported += "$config<br style=`"mso-data-placement:same-cell;`">"
            } else {
                "Failed to import reference $($config) config for $($rec.IP)."
            }
        }

        
        if ($imported -eq $null) {
            $rec.status = 'Configuration imported'
            $rec.importedConfigs = $imported
        } else {
            $rec.status = 'Import failed'
        }
    }
}

##############################################
# Repair FC
##############################################

if ($repairFCMode) {
    "Repairing target FCHF..."
    $sites.Values | ?{ ($_.status -match 'Check FC Interface or Service' -or $_.'is_latest_password' -eq $false -or $_.'mismatchConfigs') -and  $_.'Computer name' } | Format-Table

    # Filter broken FCHF
    # Append K7LX prefix and Pass value to $comps as comma separated string
    # Update dict status
    $sites.Values | ?{ ($_.status -match 'Check FC Interface or Service' -or $_.'is_latest_password' -eq $false -or $_.'mismatchConfigs') -and  $_.'Computer name' } `
	| ForEach-Object -ThrottleLimit $concurrentLimit -Parallel {
        
        $cur = $using:sites
        if ($cur.ContainsKey($_.'Computer name')) {
            $rec = $cur[$_.'Computer name']
        } else { 
            throw "Failed to find $_.IP in sites variable. `r`nExiting parallel execution" 
        }
        
	    # Run remote exec script in pwsh 5 
	    # Pass comma separated string to -Computers param which will be split into array within script
	    # $comps_param = $comps -join ","
		try {
            #& "Powershell.exe" -File  "$($rootPath)\RemoteRepair.ps1" -Computers "ComputerPC1"
			& "Powershell.exe" -File  "$($using:rootPath)\RemoteRepair.ps1" -Computers "$($_.'Computer name')"
		} catch {
			"$($rec.'Identifier') Caught exception when running repair script remotely: $_"
		}
        $rec.status = 'Attempted FCHF Repair'
        
        #& "Powershell.exe" -File  "$($rootPath)\RemoteServ.ps1" -Computers "ComputerPC1"
        $rec.serviceStatus = (& "Powershell.exe" -File "$($using:rootPath)\RemoteServ.ps1" -Computers "$($_.'Computer name')")[3]

        if ($rec.serviceStatus -match 'Running'){
            $rec.status = 'FileCatalyst is running: Possibly Repaired'
        } else {
            $rec.status = '<div style="color:red"> FCHF Repair Failed</div>'
        }
    }
}


##############################################
# Output to Log
##############################################

$Sites

##############################################
# Email Report
##############################################

$htmlTables = ""
$htmlTableBad = $sites.Values | select -Property 'Identifier', 'Computer name', 'IP', 'status', 'mismatchConfigs', 'is_latest_password' | ?{ $_.status -notmatch 'Configurations match' } | ConvertTo-Html -Fragment
$htmlTableGood = $sites.Values | select -Property 'Identifier', 'Computer name', 'IP', 'status', 'does_ALL_config_match' | ?{ $_.status -match 'Configurations match' } | ConvertTo-Html -Fragment
$htmlTables =  $htmlTableBad + "<br>" + $htmlTableGood
$htmlTables =  [System.Web.HttpUtility]::HtmlDecode($htmlTables) -replace "`<table`>","`<table class=`"bottomBorder`"`>"

#Email Do NOT Alter
$subject = "FileCatalyst Central Task Summary - $($(Get-Date).ToString("yyyyMMdd"))"
$content = @"
<html>
    <body> 
        <style>
			div #hint {     font-size: 9px; font-style: italic;    }
            table.bottomBorder {     border-collapse: collapse;   }  
            table.bottomBorder td,   table.bottomBorder th {     border-bottom: 1px solid yellowgreen;     padding: 10px;     text-align: left;  }
			div #Summary td {     padding-bottom : 0px; padding-top : 0px;    }
            div #Summary {    overflow: auto;      }
            div #Failed {    overflow: auto; max-width: 85%; max-height: 600px;     }
        </style>
        <p>Dear All,
        <br> <br> The FileCatalyst Central task has been completed for $($sites.count) sites. Please find the report below:
        <br> &emsp;Authentication mode: $authMode
        <br> &emsp;Config Verification mode: $checkConfigMode
        <br> &emsp;Config Import mode: $importConfigMode
        <br> &emsp;Repair FC mode: $repairFCMode
		<br> <br> Stages:
		<br> &emsp;Network > FC Service > Authentication > Match Configs > Import Configs > Repair FC
        <br> <br> <div id="Summary"> $($htmlTables) </div>
        <br><br> Regards, 
        <br> Company Name
    </body>
</html>
"@

 #Send to Internal Mailcow via SMTP relay
 $mailParamsInt = @{
    SmtpServer                 = '192.168.1.SMTP_SERVER' #smtp.office365.com
    Port                       = '25' #587 Encryption: STARTTLS
    UseSSL                     = $false
    #Credential                 = $credential #Credential stored at mailcow / SMTP relay
    From                       = 'alerts@domain.com'
    To                         = 'FileCatalyst_Central@alerts.domain.com'
    #cc                         = 'liam.ng@domain.com'
    Subject                    = $subject
    Body                       = $content
    BodyAsHtml                 = $true
    Attachments                = "$($csvPath+$csvName+'.csv')"
    DeliveryNotificationOption = 'Never' #'OnFailure', 'OnSuccess','Delay'
}
 Send-MailMessage @mailParamsInt
 
#Send to Outlook via SMTP relay
$mailParamsExt = @{
    SmtpServer                 = '192.168.1.SMTP_SERVER' #smtp-mail.outlook.com
    Port                       = '25' #587 Encryption: STARTTLS
    UseSSL                     = $false
    #Credential                 = $credential #Credential stored at mailcow / SMTP relay
    From                       = 'alerts@domain.com'
    To                         = 'notifications@external.email.com'
    #cc                         = 'liam.ng@external.email.com'
    Subject                    = $subject
    Body                       = $content
    BodyAsHtml                 = $true
    #Attachments                = "$($csvPath+$csvName+'.csv')"
    DeliveryNotificationOption = 'Never' #'OnFailure', 'OnSuccess','Delay'
}
Send-MailMessage @mailParamsExt

Stop-Transcript
Return