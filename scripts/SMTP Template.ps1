##############################################
# Email Report
##############################################
# Turns a PowerShell array into a HTML table
$htmlSummary = ""
$htmlSummary = $summaryList | ConvertTo-Html -Fragment
$htmlSummary = [System.Web.HttpUtility]::HtmlDecode($htmlSummary) -replace "`<table`>","`<table class=`"bottomBorder`"`>"

#Email Do NOT Alter
$subject = "Summary - $($(Get-Date).ToString("yyyyMMdd - HH:mm"))"
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
        <br> <br> Please find the attached status report for $($comps.Count) computers at $($(Get-Date).ToString("yyyy MMM dd HH:mm")).
        <br> <br> The result is summarized below:
        <br> <div id="Summary"> $($htmlSummary) </div>
        <br><br> Regards, 
        <br> Company
    </body>
</html>
"@

 #Send to Internal Mailcow
 $mailParamsInt = @{
    SmtpServer                 = '192.168.1.SMTP_SERVER' #smtp.office365.com
    Port                       = '25' #587 Encryption: STARTTLS
    UseSSL                     = $false
    #Credential                 = $credential
    From                       = 'alerts@domain.com'
    To                         = 'Report@alerts.domain.com'
    #cc                         = 'john.doe@domain.com'
    Subject                    = $subject
    Body                       = $content
    BodyAsHtml                 = $true
    Attachments                = "$logPath\DCMS_result.csv"
    DeliveryNotificationOption = 'Never' #'OnFailure', 'OnSuccess','Delay'
}
 Send-MailMessage @mailParamsInt