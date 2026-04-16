param (
    [string[]]$Computers
)

"Running FCHF_Repair for $Computers"
$Computers = $Computers -split ","

Try {
    Get-Service -ComputerName $Computers -Name WinRM | Set-Service -StartupType Manual -PassThru | Start-Service;
    "Enabled WinRM for $Computers"
    Get-Service -ComputerName $Computers -Name FileCatalystHotFolder

    Invoke-Command -ComputerName $Computers -AsJob -ScriptBlock { 
        Start-Job { cmd /c start "C:\Users\Public\Desktop\FCHF_repair.bat"; "$(hostname) Done!"; } `
        | Wait-Job -Timeout 30 | Remove-Job -Force
    } `
    | Wait-Job -Timeout 60 | Remove-Job -Force

    "Disabled WinRM for $Computers"
    Get-Service -ComputerName $Computers -Name WinRM | Stop-Service -PassThru | Set-Service -StartupType Disabled;
} catch {
    "Failed to repair $Computers. Reason :$_"
}
